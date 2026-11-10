extends "res://games/four_souls/logic/fs_packet15_automation.gd"
## Автоматические события40монстров, замещения урона и обязательный чужой выбор.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	for choice: Dictionary in out:
		if step.has("amount") and not choice.arg.has("amount") and str(choice.arg.get("op", "")) == str(step.op):
			choice.arg["amount"] = int(step.amount)
	var category: String = str(step.get("targets", ""))
	match category:
		"other_monsters16", "other_slots16":
			for slot in monsters.size():
				if not is_same(monsters[slot], resolving.source) and not monsters[slot].has("virtual_zone15"):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": str(step.op), "item": slot}})
		"living_players16", "kill_three16":
			for seat in active_seats():
				if not dead[seat] and int(hp[seat]) > 0 and (category != "kill_three16" or seat != current):
					out.append({"label": name_of(seat), "arg": {"op": str(step.op), "target": seat}})
			if category == "kill_three16":
				out.append({"label": "Закончить выбор", "arg": {"op": "stop_kills16"}})
		"split_damage16":
			for seat in active_seats():
				if not dead[seat] and int(hp[seat]) > 0:
					out.append({"label": name_of(seat), "arg": {"op": "split_damage16", "target": seat, "zone": "player"}})
			for slot in monsters.size():
				if int(monsters[slot].hp) > 0:
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "split_damage16", "target": slot, "zone": "monster"}})
		"victim_hand16":
			var seat := _card_choice_owner()
			if _item_count(seat, 523) > 0:
				return out
			for index in hands[seat].size():
				out.append({"label": FSData.title(int(hands[seat][index])), "arg": {"op": "discard_victim_card16", "target": seat, "item": index, "card": int(hands[seat][index])}})
		"victim_items16":
			var seat := _card_choice_owner()
			for index in items[seat].size():
				out.append({"label": FSData.title(int(items[seat][index].id)), "arg": {"op": "recharge", "target": seat, "item": index}})
		"whip_votes16":
			for whip in [true, false]:
				out.append({"label": "Хлыст" if whip else "Свист", "arg": {"op": "whip_vote16", "whip": whip}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"damage":
			if int(resolving.card) == 319:
				_damage_player(int(step.target), int(step.get("amount", 1)), {"attacker": owner})
			else:
				super._apply_card_step(step)
		"random_damage15":
			if int(resolving.card) in [284, 291]:
				_damage_player(_rng.randi_range(0, players.size() - 1), int(step.amount), {"attacker": current})
			else:
				super._apply_card_step(step)
		"random_nonactive16":
			var targets: Array = []
			for seat in players.size():
				if seat != current and not dead[seat] and int(hp[seat]) > 0:
					targets.append(seat)
			if not targets.is_empty():
				_damage_player(int(targets[_rng.randi_range(0, targets.size() - 1)]), int(step.amount))
		"bottom_source16":
			_bottom_monster16(source)
		"kill_other16":
			monsters[int(step.item)].hp = 0
			monsters[int(step.item)]["slayer"] = owner
		"kill_player16":
			hp[int(step.target)] = 0
		"kill_others16":
			for monster: Dictionary in monsters:
				if not is_same(monster, source):
					monster.hp = 0
					monster["slayer"] = owner
		"kill_players16":
			for seat in players.size():
				hp[seat] = 0
		"give_soul16":
			var soul: Dictionary = resolving.automation_data.pending_soul16
			resolving.automation_data.erase("pending_soul16")
			super._gain_soul_card(int(step.target), soul, bool(resolving.automation_data.gained))
		"gut_result16":
			if value <= 2:
				_gut_tokens16[current] = true
		"portal_result16":
			if value <= 4:
				_insert_card_steps([{"op": "clear_slot16" if value <= 2 else "cover_slot16", "targets": "other_slots16"}])
			else:
				for monster: Dictionary in monsters:
					monster.dc = int(monster.dc) + 1
					monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) + 1
		"clear_slot16":
			_clear_slot16(int(step.item))
		"cover_slot16":
			var id := _draw("monster")
			if id >= 0:
				if FSData.card(id).kind == "event":
					_push({"kind": "event", "card": id, "owner": current}, "effect")
				else:
					_place_encounter_monster(id, int(step.item))
		"expand16":
			monster_slots += int(step.get("amount", 1))
			resolving["refill_monsters"] = true
		"expand_roll16":
			_insert_card_steps([{"op": "expand16", "amount": (value + 1) / 2}])
		"required_attack16":
			attack_left += 1
			attacked = false
			_forced_regular16 += 1
			# 09.11 (владелец): «должен атаковать» — ход не закончить, пока атака не объявлена (Зависть 404, Портал 432…).
			_mandatory_attacks25 += 1
		"spider_split_prepare16":
			resolving["split_left16"] = int(source.get("counters", 0))
			if int(resolving.split_left16) > 0:
				_insert_card_steps([{"op": "split_damage16", "targets": "split_damage16"}])
		"split_damage16":
			resolving.split_left16 = int(resolving.split_left16) - 1
			if int(resolving.split_left16) > 0:
				_insert_card_steps([{"op": "split_damage16", "targets": "split_damage16"}])
			if str(step.zone) == "player":
				_damage_player(int(step.target), 1, {"attacker": owner})
			else:
				_effect({"op": "monster_damage", "item": int(step.target), "amount": 1})
		"hurt_other_players16":
			for seat in players.size():
				if seat != int(resolving.automation_data.get("seat", owner)):
					_damage_player(seat, 1)
		"discard_others16":
			var originals: Array = monsters.duplicate()
			for monster: Dictionary in originals:
				if not is_same(monster, source):
					var slot := monsters.find(monster)
					if slot >= 0:
						_clear_slot16(slot)
		"rider16":
			if not _physical_in_play16(913) and not _physical_in_play16(914):
				_remove_from_piles16(913)
				_remove_from_piles16(914)
				_place_encounter_monster(913, monsters.size())
		"rider_death16":
			var treasure := _draw("treasure")
			if treasure >= 0:
				_gain_item(current, treasure)
			_end_battle()
			if int(source.get("counters", 0)) >= 4:
				source.id = 914
				source.hp = _monster_hp(914)
				source.dc = 4
				source.at = 2
				_queue_packet15(current, 914, source, "flip")
		"beast_rolls16":
			resolving["beast_faces16"] = {}
			resolving["beast_seats16"] = []
			for offset in players.size():
				var seat := (current + offset) % players.size()
				if not dead[seat] and int(hp[seat]) > 0:
					resolving.beast_seats16.append(seat)
			_insert_card_steps([{"op": "beast_next16"}])
		"beast_next16":
			if not resolving.beast_seats16.is_empty():
				resolving["choice_owner"] = int(resolving.beast_seats16.pop_front())
				resolving.erase("automation_roll")
				_insert_card_steps([{"op": "auto_roll"}, {"op": "beast_collect16"}, {"op": "beast_next16"}])
			else:
				resolving.erase("choice_owner")
				if not resolving.beast_faces16.is_empty():
					var lowest: int = int(resolving.beast_faces16.values().min())
					for seat in resolving.beast_faces16:
						if int(resolving.beast_faces16[seat]) == lowest:
							hp[int(seat)] = 0
		"beast_collect16":
			resolving.beast_faces16[_card_choice_owner()] = value
		"last_alive16":
			if not dead[current] and int(hp[current]) > 0 and _player_attack_targets().is_empty():
				winner = current
				phase = "game_over"
		"kill_three_prepare16":
			resolving["kills_left16"] = 3
			_insert_card_steps([{"op": "kill_next16", "targets": "kill_three16"}])
		"kill_next16":
			hp[int(step.target)] = 0
			resolving.kills_left16 = int(resolving.kills_left16) - 1
			if int(resolving.kills_left16) > 0:
				_insert_card_steps([{"op": "kill_next16", "targets": "kill_three16"}])
		"stop_kills16":
			pass
		"discard_others_hands16":
			for offset in range(players.size() - 1, 0, -1):
				var seat := (current + offset) % players.size()
				_queue_packet15(seat, 313, source, "discard16", {"seat": seat})
		"discard_victim16":
			resolving["choice_owner"] = int(resolving.automation_data.get("seat", owner))
			_insert_card_steps([{"op": "discard_victim_card16", "targets": "victim_hand16"}])
		"discard_victim_card16":
			discards.loot.append(int(hands[int(step.target)].pop_at(int(step.item))))
		"recharge_owner16":
			resolving["choice_owner"] = int(step.target)
			_insert_card_steps([{"op": "recharge", "targets": "victim_items16"}])
		"roll_gift16":
			resolving["gift_target16"] = int(step.target)
			resolving["choice_owner"] = int(step.target)
		"coins_result16":
			_gain_coins(int(resolving.gift_target16), value)
		"curse_slot16":
			var options: Array = decks.monster.filter(func(id): return FSData.card(int(id)).lua.get("type", "") == "curse")
			if not options.is_empty():
				var id: int = int(options[_rng.randi_range(0, options.size() - 1)])
				decks.monster.erase(id)
				monsters.append({"id": id, "hp": 1, "dc": 7, "at": 0, "curse_slot16": true})
				monster_slots = maxi(monster_slots, monsters.size())
			_shuffle(decks.monster)
		"soul_damage16":
			if value == 1:
				resolving.automation_data.pending.damage = 0
		"whip_prepare16":
			resolving["voters16"] = []
			for offset in players.size():
				var seat := (current + offset) % players.size()
				if not dead[seat] and int(hp[seat]) > 0:
					resolving.voters16.append(seat)
			resolving["whips16"] = 0
			resolving["votes16"] = 0
			if not resolving.voters16.is_empty():
				resolving["choice_owner"] = int(resolving.voters16[0])
				_insert_card_steps([{"op": "whip_vote16", "targets": "whip_votes16"}])
		"whip_vote16":
			resolving.whips16 = int(resolving.whips16) + (1 if bool(step.whip) else 0)
			resolving.votes16 = int(resolving.votes16) + 1
			if int(resolving.votes16) < resolving.voters16.size():
				resolving.choice_owner = int(resolving.voters16[int(resolving.votes16)])
				_insert_card_steps([{"op": "whip_vote16", "targets": "whip_votes16"}])
			else:
				resolving.erase("choice_owner")
				if int(resolving.whips16) * 2 > resolving.voters16.size():
					resolving.automation_data.pending.damage = 0
					for seat in players.size():
						if seat != current:
							_damage_player(seat, 1)
				else:
					_draw_loot(current, 1)
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "attack_declared" and _forced_regular16 > 0:
		_forced_regular16 -= 1
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var own_damage: bool = event == "monster_damage" and _same_monster20(source, data)
		var own_death: bool = event == "monster_death" and _same_monster20(source, data)
		var own_attack: bool = battle >= 0 and battle < monsters.size() and is_same(monsters[battle], source)
		var declared: bool = event == "attack_declared" and int(data.get("slot", -1)) >= 0 and int(data.slot) < monsters.size() and is_same(monsters[int(data.slot)], source)
		if id == 314 and event == "attack_roll" and own_attack:
			source["throws16"] = int(source.get("throws16", 0)) + 1
		var trigger := false
		var receiver := current
		match id:
			913:
				if event == "turn_start":
					_forced_monsters14.append(913)
			914:
				trigger = declared
			287, 308:
				trigger = own_damage
			288, 290, 300, 301, 303, 307, 309, 313, 325:
				trigger = own_death
				if id == 300 and own_damage:
					source["counters"] = int(source.get("counters", 0)) + 1
				if id == 313 and declared:
					trigger = true
				if id == 325 and event == "roll" and int(data.get("value", 0)) == 1:
					trigger = true
					receiver = int(data.get("seat", current))
			289:
				trigger = event == "attack_miss" and own_attack
			291:
				trigger = event == "turn_start" or (event == "damage" and bool(data.get("combat", false)) and _same_damage_source20(source, data))
			292, 296:
				trigger = event == "turn_start"
			295:
				trigger = own_death or (event == "attack_roll" and own_attack and int(data.get("value", 0)) == 1)
			298:
				trigger = event == "attack_roll" and own_attack and int(data.get("value", 0)) == 1
			302, 311:
				if own_damage:
					var change := -1 if id == 302 else 1
					source.dc = int(source.dc) + change
					source["temporary_dc"] = int(source.get("temporary_dc", 0)) + change
				trigger = id == 311 and own_death
			305:
				trigger = event == "damage" and bool(data.get("combat", false)) and _same_damage_source20(source, data)
			306:
				trigger = own_death or declared
			312:
				trigger = event == "turn_end"
			317:
				if event == "attack_miss" and own_attack:
					source.hp = mini(_monster_max15(source), int(source.hp) + 1)
			319:
				trigger = event == "attack_roll" and own_attack and int(data.get("value", 0)) == 6
			322, 323:
				if event == "damage" and _same_damage_source20(source, data):
					if id == 322:
						_queue_packet15(int(data.seat), id, source, "damaged_player16", data)
					else:
						_gain_coins(int(data.seat), -2)
			326:
				trigger = event == "monster_death"
		if trigger:
			_queue_packet15(receiver, id, source, "discard16" if id == 313 and event == "discard16" else event, data)

func _monster_entered15(entry: Dictionary) -> void:
	var fresh := not bool(entry.get("entered15", false))
	super._monster_entered15(entry)
	if fresh and _card_automation_enabled() and not _setting_up and int(entry.id) == 288:
		_queue_packet15(current, 288, entry, "enter")

func _after_auto_reward16(effect: Dictionary) -> void:
	if _card_automation_enabled() and int(effect.card) in [315, 316, 317, 318, 319, 321, 322, 323]:
		_push({"kind": "passive", "owner": int(effect.owner), "card": int(effect.card), "source": {}, "operations": [{"op": "trinket_automation", "amount": 1, "context": "post_reward16", "data": {}}]}, _after_stack)

func _encounter_must_attack() -> bool:
	return super._encounter_must_attack() or (_forced_regular16 > 0 and not attacked and attack_left > 0 and int(coins[current]) >= _attack_tax(current))

func _bottom_monster16(source: Dictionary) -> void:
	var slot := monsters.find(source)
	if slot < 0:
		return
	if battle == slot:
		_end_battle()
	var under: Dictionary = source.get("under", {})
	_put_monster20(source, "bottom")
	_eggs_monsters.erase(int(source.id))
	if under.is_empty():
		monsters.remove_at(slot)
	else:
		monsters[slot] = under
	resolving["refill_monsters"] = true

func _clear_slot16(slot: int) -> void:
	if slot < 0 or slot >= monsters.size():
		return
	if battle == slot:
		_end_battle()
	var card: Dictionary = monsters[slot]
	while not card.is_empty():
		_put_monster20(card, "discard")
		_eggs_monsters.erase(int(card.id))
		card = card.get("under", {})
	monsters.remove_at(slot)
	for effect: Dictionary in stack:
		if effect.kind == "attack" and int(effect.slot) >= slot:
			effect.slot = int(effect.slot) - 1 if int(effect.slot) > slot else -2
	if battle > slot:
		battle -= 1
	if not resolving.is_empty():
		resolving["refill_monsters"] = true

func _physical_in_play16(id: int) -> bool:
	for inventory: Array in items:
		if inventory.any(func(item): return int(item.get("physical_id13", item.id)) == id):
			return true
	for cards: Array in soul_cards:
		if cards.any(func(card): return int(card.id) == id):
			return true
	return monsters.any(func(monster): return int(monster.id) == id)

func _remove_from_piles16(id: int) -> void:
	for pile: Array in decks.values():
		pile.erase(id)
	for pile: Array in discards.values():
		pile.erase(id)

func _intercept_damage16(pending: Dictionary) -> bool:
	if not _card_automation_enabled() or int(pending.damage) <= 0:
		return false
	var attacker: int = int(pending.owner)
	var card := -1
	var source: Dictionary = {}
	if not bool(pending.get("soul_checked16", false)) and attacker >= 0 and attacker < players.size():
		for soul: Dictionary in soul_cards[attacker]:
			if int(soul.id) == 293:
				card = 293
				source = soul
				break
		pending["soul_checked16"] = true
	if card < 0 and not bool(pending.get("whip_checked16", false)) and str(pending.get("zone", "monster")) == "monster" and int(pending.get("card", -1)) == 324:
		card = 324
		pending["whip_checked16"] = true
		for monster: Dictionary in monsters:
			if int(monster.id) == 324:
				source = monster
	if card < 0:
		return false
	_push(pending, _after_stack if phase == "priority" else phase)
	_begin_resolving({"kind": "item", "card": card, "owner": attacker if card == 293 else current, "source": source, "conditional": true, "automation_context": "damage16", "automation_data": {"pending": pending}})
	_advance_card_automation()
	return true

func _apply_combat(effect: Dictionary) -> void:
	if _card_automation_enabled() and battle >= 0 and battle < monsters.size():
		var monster: Dictionary = monsters[battle]
		if bool(effect.hit):
			if int(monster.id) == 304 and int(effect.value) != 2:
				effect.damage = 0
			if int(monster.id) == 314:
				if int(monster.get("throws16", 0)) % 2 == 0:
					effect.damage = 0
			if _intercept_damage16(effect):
				return
		var cancel: bool = int(monster.id) == 304 and int(_turn_attack_rolls.get(int(effect.owner), 0)) == 2
		super._apply_combat(effect)
		if cancel and battle >= 0:
			_end_battle()
	else:
		super._apply_combat(effect)

func _damage_player(seat: int, amount: int, context: Dictionary = {}) -> void:
	var default_attacker: int = -1 if context.has("monster") or FSData.card(int(resolving.get("card", -1))).get("kind", "") == "monster" else int(resolving.get("owner", current))
	var attacker: int = int(context.get("attacker", default_attacker))
	var pending := {"kind": "damage16", "owner": attacker, "zone": "player", "target": seat, "damage": amount, "context": context, "soul_checked16": bool(context.get("soul_checked16", false))}
	if _intercept_damage16(pending):
		return
	super._damage_player(seat, amount, context)

func _intercept_effect_damage16(a: Dictionary) -> bool:
	if str(a.get("op", "")) == "monster_damage" and not bool(a.get("checked16", false)):
		var slot: int = int(a.get("item", -1))
		if slot >= 0 and slot < monsters.size():
			var pending := {"kind": "damage16", "owner": _damage_owner18(), "zone": "monster", "card": int(monsters[slot].id), "damage": int(a.get("amount", 1)), "arg": a}
			if _intercept_damage16(pending):
				pending.arg["history_seq"] = int(resolving.get("history_seq", 0))
				return true
	return false

func _resolve_damage16(effect: Dictionary) -> void:
	if _intercept_damage16(effect):
		return
	if int(effect.damage) > 0:
		if str(effect.zone) == "player":
			var context: Dictionary = effect.context.duplicate()
			context["soul_checked16"] = true
			_damage_player(int(effect.target), int(effect.damage), context)
		else:
			for slot in monsters.size():
				if int(monsters[slot].id) == int(effect.card):
					var arg: Dictionary = effect.arg.duplicate()
					arg["checked16"] = true
					arg["item"] = slot
					arg["amount"] = int(effect.damage)
					var original: Dictionary = resolving
					resolving = {"owner": int(effect.owner) if int(effect.owner) >= 0 else current, "card": -1, "damage_owner18": int(effect.owner)}
					_effect(arg)
					resolving = original
					break
	_continue_stack()

func _death_item16(seat: int, proposed: int) -> int:
	if _card_automation_enabled() and soul_cards[seat].any(func(card): return int(card.id) == 294):
		var choices: Array = []
		for index in items[seat].size():
			if not bool(items[seat][index].eternal):
				choices.append(index)
		return int(choices[_rng.randi_range(0, choices.size() - 1)]) if not choices.is_empty() else -1
	return proposed

func _pvp_defense16(target: int) -> int:
	return 3 if _gut_tokens16.has(target) else 4

func _permitted_player_attack_targets() -> Array:
	var out := super._permitted_player_attack_targets()
	if _card_automation_enabled() and not attacked and attack_left > 0 and _lust_pending.is_empty():
		for seat in players.size():
			if seat != current and not dead[seat] and int(hp[seat]) > 0 and (_gut_tokens16.has(seat) or monsters.any(func(monster): return int(monster.id) == 312 and int(monster.hp) > 0)) and seat not in out:
				out.append(seat)
	return out

func _replace_monster_death(slot: int) -> bool:
	var source: Dictionary = monsters[slot]
	if _card_automation_enabled() and int(source.id) == 913:
		source["counters"] = int(source.get("counters", 0)) + 1
		source.hp = _monster_max15(source)
		source["death_pending"] = false
		_queue_packet15(current, 913, source, "prevented_death")
		return true
	return super._replace_monster_death(slot)

func _printed_monster_reward(id: int) -> Dictionary:
	if id == 914:
		return {"treasure": 1, "loot": 6, "souls": 2}
	return super._printed_monster_reward(id)

func _end_battle() -> void:
	super._end_battle()
	_resolving_base = mini(_resolving_base, stack.size())
	if not resolving.is_empty() and str(resolving.get("_resume", "")) == "battle_roll":
		resolving["_resume"] = "turn"

func _gain_soul_card(seat: int, card: Dictionary, gained: bool = true) -> void:
	if _card_automation_enabled() and int(card.id) == 320 and seat == current and not _room_has20(779) and not curses[seat].has(744) and not (resolving.get("kind", "") == "reward" and int(resolving.get("card", -1)) == 320):
		_begin_resolving({"kind": "item", "card": 320, "owner": current, "source": {}, "conditional": true, "automation_context": "soul_transfer16", "automation_data": {"pending_soul16": card, "gained": gained}})
		_advance_card_automation()
		return
	super._gain_soul_card(seat, card, gained)
