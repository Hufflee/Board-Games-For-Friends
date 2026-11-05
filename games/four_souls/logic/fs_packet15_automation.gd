extends "res://games/four_souls/logic/fs_treasure14_automation.gd"
## Сорок текстов246–286: жетоны монстров, штрафы, голоса и обязательные действия.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	var category: String = str(step.get("targets", ""))
	match category:
		"leaders15":
			for seat in players.size():
				if int(souls[seat]) == int(souls.max()):
					out.append({"label": name_of(seat), "arg": {"op": "winner15", "target": seat}})
		"faces15", "unique_faces15", "neighbor_faces15":
			for face in range(1, 7):
				if category == "unique_faces15" and face in resolving.get("chosen_faces15", {}).values():
					continue
				out.append({"label": str(face), "arg": {"op": str(step.op), "face": face}})
		"penalty_items15", "eternal_items15", "other_player_items15":
			for seat in players.size():
				if category == "penalty_items15" and seat != int(resolving.automation_data.seat):
					continue
				if category == "other_player_items15" and seat == owner:
					continue
				for index in items[seat].size():
					var item: Dictionary = items[seat][index]
					if bool(item.eternal):
						continue
					out.append({"label": name_of(seat) + " · " + FSData.title(int(item.id)), "arg": {"op": str(step.op), "target": seat, "item": index}})
			if category == "eternal_items15":
				for index in shop.size():
					if int(shop[index]) >= 0:
						out.append({"label": "Магазин · " + FSData.title(int(shop[index])), "arg": {"op": "eternal_shop15", "item": index}})
		"kill_targets15":
			for seat in players.size():
				if int(resolving.card) != 257 and not dead[seat] and int(hp[seat]) > 0:
					out.append({"label": name_of(seat), "arg": {"op": "kill15", "target": seat, "zone": "player"}})
			for slot in monsters.size():
				if int(monsters[slot].hp) > 0:
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "kill15", "target": slot, "zone": "monster"}})
		"other_monsters15":
			for slot in monsters.size():
				if not is_same(monsters[slot], resolving.source):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "discard_other15", "item": slot}})
		"other_slots15":
			for slot in range(maxi(monster_slots, monsters.size())):
				if slot >= monsters.size() or not is_same(monsters[slot], resolving.source):
					out.append({"label": "Слот монстров %d" % (slot + 1), "arg": {"op": "move_monster15", "item": slot}})
		"votes15":
			for naughty in [true, false]:
				out.append({"label": "Озорной" if naughty else "Послушный", "arg": {"op": "vote15", "naughty": naughty}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"winner15":
			winner = int(step.target)
			phase = "game_over"
			_note("Сердце Мамы: победитель — " + name_of(winner))
		"exchange_prepare15":
			_team_source15 = source
			_team_queue15.clear()
		"neighbors_prepare15":
			resolving["neighbor_offset15"] = 0
			resolving["neighbor_faces15"] = []
			resolving["choice_owner"] = posmod(current - 1, players.size())
			_insert_card_steps([{"op": "neighbor_face15", "targets": "neighbor_faces15"}])
		"neighbor_face15":
			resolving.neighbor_faces15.append(int(step.face))
			resolving.neighbor_offset15 = int(resolving.neighbor_offset15) + 1
			if int(resolving.neighbor_offset15) == 1:
				resolving["choice_owner"] = (current + 1) % players.size()
				_insert_card_steps([{"op": "neighbor_face15", "targets": "neighbor_faces15"}])
			else:
				_neighbor_faces15 = resolving.neighbor_faces15.duplicate()
				resolving.erase("choice_owner")
				_insert_card_steps([{"op": "declared_roll15"}])
		"declared_roll15":
			var roller := _battle_roller15()
			last_roll = _card_die(roller, true)
			roll_no += 1
			stats_rolls.append({"seat": roller, "faces": [last_roll]})
			_push({"kind": "roll", "value": last_roll, "owner": roller, "multi_bonus12": _multi_raw_bonus, "neighbor_faces15": _neighbor_faces15.duplicate()}, "battle_roll")
		"min_prepare15":
			resolving["min_faces15"] = [int(resolving.automation_data.value)]
			resolving["min_left15"] = int(souls[owner])
			_insert_card_steps([{"op": "min_next15"}])
		"min_next15":
			if int(resolving.min_left15) > 0:
				resolving.min_left15 = int(resolving.min_left15) - 1
				resolving.erase("automation_roll")
				_insert_card_steps([{"op": "auto_roll"}, {"op": "min_collect15"}, {"op": "min_next15"}])
			else:
				var token: int = int(resolving.automation_data.token)
				var face: int = int(resolving.min_faces15.min()) + int(resolving.automation_data.bonus)
				if _era_left > 0:
					_era_left -= 1
					face = _era_face
				_change_pending12(token, clampi(face, 1, 6), false)
		"min_collect15":
			resolving.min_faces15.append(value)
		"bum_result15":
			_insert_card_steps([{"op": "coins", "amount": 3}] if value <= 2 else [{"op": "loot"}] if value <= 4 else [{"op": "damage"}])
		"steal_coins":
			_transfer_coins(int(step.target), owner, int(step.get("amount", 3)))
		"shadow_item15":
			_shadow_penalty15[int(step.target)] = {"receiver": owner, "item": items[int(step.target)][int(step.item)]}
		"source_counter15":
			if _source_item_in_play(source):
				source.counters = int(source.counters) + 1
		"kill15":
			if str(step.zone) == "player":
				hp[int(step.target)] = 0
			else:
				var monster: Dictionary = monsters[int(step.target)]
				monster.hp = 0
				monster["slayer"] = owner
				monster["lethal_attack_roll"] = 0
		"rotate_hands15":
			var previous := hands.duplicate()
			for seat in players.size():
				hands[posmod(seat + int(step.direction), players.size())] = previous[seat]
		"crystal_face15":
			_crystal_predictions15.append({"owner": owner, "face": int(step.face)})
		"reflect_shield15":
			_next_hit_shields.append({"zone": "player", "target": owner, "amount": 1, "reflect15": owner})
		"box_destroy15":
			resolving["box_physical15"] = int(source.get("physical_id13", source.get("id", -1)))
			var destroyed := false
			for index in items[owner].size():
				if is_same(items[owner][index], source) and not bool(source.eternal):
					_destroy_item(owner, index)
					destroyed = not _source_item_in_play(source)
					break
			if not destroyed:
				resolving.automation_step = resolving.automation_steps.size()
		"box_result15":
			match value:
				1, 2, 5:
					_gain_coins(owner, {1: 1, 2: 6, 5: 9}[value])
				3:
					_insert_card_steps([{"op": "kill15", "targets": "kill_targets15"}])
				4:
					_draw_loot(owner, 3)
				6:
					var id: int = int(resolving.box_physical15)
					if id in discards.treasure:
						discards.treasure.erase(id)
						_gain_soul_card(owner, {"id": id, "value": 1})
		"trapper_result15":
			if value >= 4:
				_forced_monsters14.append(int(source.id))
			else:
				var options: Array = monsters.filter(func(m): return not is_same(m, source))
				if not options.is_empty():
					var chosen: Dictionary = options[_rng.randi_range(0, options.size() - 1)]
					_discard_monster15(monsters.find(chosen))
		"random_tokens15":
			if not monsters.is_empty():
				var health: Dictionary = monsters[_rng.randi_range(0, monsters.size() - 1)]
				health["health_tokens15"] = int(health.get("health_tokens15", 0)) + 1
				health.hp = int(health.hp) + 1
				var attack_target: Dictionary = monsters[_rng.randi_range(0, monsters.size() - 1)]
				attack_target["attack_tokens15"] = int(attack_target.get("attack_tokens15", 0)) + 1
		"random_attack_token15":
			var options: Array = monsters.filter(func(m): return not is_same(m, source))
			if not options.is_empty():
				var chosen: Dictionary = options[_rng.randi_range(0, options.size() - 1)]
				chosen["attack_tokens15"] = int(chosen.get("attack_tokens15", 0)) + 1
		"spiders_prepare15":
			var target := _rng.randi_range(0, players.size() - 1)
			_spider_tokens15[target] = int(_spider_tokens15.get(target, 0)) + 1
			var steps: Array = []
			for index in int(_spider_tokens15.get(current, 0)):
				steps.append({"op": "spider_roll15"})
			_insert_card_steps(steps)
		"spider_roll15":
			resolving.erase("automation_roll")
			_insert_card_steps([{"op": "auto_roll"}, {"op": "spider_damage15"}])
		"spider_damage15":
			if value <= 3:
				_damage_player(owner, 1)
		"monster_age15":
			if monsters.any(func(m): return is_same(m, source)):
				source["counters"] = int(source.get("counters", 0)) + 1
				source.hp = int(source.hp) - 1
		"switch_result15":
			match value:
				1, 2:
					_damage_player(owner, 3 if value == 1 else 2)
				3, 5:
					_gain_coins(owner, 1 if value == 3 else 5)
				4:
					_draw_loot(owner, 1)
				6:
					_insert_card_steps([{"op": "treasure"}])
		"eternal_token15":
			items[int(step.target)][int(step.item)].eternal = true
		"eternal_shop15":
			_eternal_shop15[int(shop[int(step.item)])] = true
		"discard_other15":
			_discard_monster15(int(step.item))
		"numbers_prepare15":
			resolving["chosen_faces15"] = {}
			resolving["choice_owner"] = current
			resolving["number_offset15"] = 0
			_insert_card_steps([{"op": "number15", "targets": "unique_faces15"}])
		"number15":
			resolving.chosen_faces15[_card_choice_owner()] = int(step.face)
			resolving.number_offset15 = int(resolving.number_offset15) + 1
			if int(resolving.number_offset15) < players.size():
				resolving["choice_owner"] = (current + int(resolving.number_offset15)) % players.size()
				_insert_card_steps([{"op": "number15", "targets": "unique_faces15"}])
			else:
				_roll_punishments15.append(resolving.chosen_faces15.duplicate())
				resolving.erase("choice_owner")
		"vote_prepare15":
			resolving["vote_offset15"] = 0
			resolving["naughty15"] = 0
			resolving["choice_owner"] = current
			_insert_card_steps([{"op": "vote15", "targets": "votes15"}])
		"vote15":
			resolving.naughty15 = int(resolving.naughty15) + (1 if bool(step.naughty) else 0)
			resolving.vote_offset15 = int(resolving.vote_offset15) + 1
			if int(resolving.vote_offset15) < players.size():
				resolving["choice_owner"] = (current + int(resolving.vote_offset15)) % players.size()
				_insert_card_steps([{"op": "vote15", "targets": "votes15"}])
			else:
				if int(resolving.naughty15) * 2 > players.size():
					_forced_monsters14.append(int(source.id))
				resolving.erase("choice_owner")
		"other_monster_damage15":
			var steps: Array = []
			for slot in monsters.size():
				if not is_same(monsters[slot], source) and not is_same(monsters[slot].get("virtual_ref15", {}), source):
					steps.append({"op": "monster_byid15", "card": int(monsters[slot].id)})
			_insert_card_steps(steps)
		"monster_byid15":
			for slot in monsters.size():
				if int(monsters[slot].id) == int(step.card):
					_effect({"op": "monster_damage", "item": slot, "amount": 1})
					break
		"cancel_source_attack15":
			if battle >= 0 and battle < monsters.size() and is_same(monsters[battle], source):
				_end_battle()
		"move_monster15":
			var old := -1
			for slot in monsters.size():
				if is_same(monsters[slot], source):
					old = slot
			if old >= 0:
				var destination: int = int(step.item)
				var under: Dictionary = source.get("under", {})
				source.erase("under")
				source.erase("death_pending")
				if under.is_empty():
					monsters.remove_at(old)
					if destination > old:
						destination -= 1
				else:
					monsters[old] = under
				if destination < monsters.size():
					source["under"] = monsters[destination]
					monsters[destination] = source
				else:
					monsters.append(source)
		"hand_health15":
			if monsters.any(func(m): return is_same(m, source)):
				var count: int = hands[current].size()
				source.hp = int(source.hp) + count
				source["temporary_hp15"] = int(source.get("temporary_hp15", 0)) + count
		"find_curse15":
			var others: Array = []
			var found := -1
			for index in decks.monster.size():
				var id := _draw("monster")
				if FSData.card(id).lua.get("type", "") == "curse":
					found = id
					break
				others.append(id)
			_shuffle(others)
			for id in others:
				decks.monster.push_front(id)
			if found >= 0:
				_note("Проклятие открыто: " + FSData.title(found))
				curses[current].append(found)
		"item_health15":
			var item: Dictionary = items[int(step.target)][int(step.item)]
			item["health_tokens15"] = int(item.get("health_tokens15", 0)) + 1
			_refresh_passive_stats()
		"cancel_attack15":
			_end_battle()
		"random_damage15":
			_damage_player(_rng.randi_range(0, players.size() - 1), int(step.amount))
		"damage_all":
			for seat in players.size():
				_damage_player(seat, int(step.get("amount", 1)))
		_:
			super._apply_card_step(step)

func _discard_monster15(slot: int) -> void:
	if slot < 0 or slot >= monsters.size():
		return
	if battle == slot:
		_end_battle()
	var source: Dictionary = monsters[slot]
	_put_monster20(source, "discard")
	_eggs_monsters.erase(int(source.id))
	if source.get("under", {}).is_empty():
		monsters.remove_at(slot)
		if battle > slot:
			battle -= 1
		_fill_monster()
	else:
		monsters[slot] = source.under

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "roll":
		var predictions: Array = _crystal_predictions15.duplicate()
		_crystal_predictions15.clear()
		for prediction: Dictionary in predictions:
			if int(prediction.face) == int(data.get("value", 0)):
				_queue_passive(int(prediction.owner), 252, {}, [{"op": "loot", "amount": 3}])
		for punishments: Dictionary in _roll_punishments15:
			for seat in punishments:
				if int(punishments[seat]) == int(data.get("value", 0)):
					_queue_passive(int(seat), 269, {}, [{"op": "damage", "amount": 1}])
	for owner in players.size():
		for entry: Dictionary in items[owner]:
			if int(entry.id) == 246 and event == "turn_start" and current == owner:
				_queue_packet15(owner, 246, entry, event, data)
			if int(entry.id) == 275 and event == "damage" and int(data.get("seat", -1)) == owner:
				_queue_packet15(owner, 275, entry, event, data)
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var trigger := false
		var receiver := current
		match id:
			259:
				trigger = event == "turn_start" or (event == "monster_damage" and _same_monster20(source, data))
			260:
				trigger = event == "monster_damage" and _same_monster20(source, data) and int(source.hp) == 1
			261, 263, 269:
				trigger = event == "turn_start"
			262:
				trigger = event == "turn_start" or (event == "attack_roll" and int(data.get("value", 0)) == 1)
			265:
				trigger = event == "monster_damage" and _same_monster20(source, data) and int(data.get("seat", -1)) == current
			266:
				trigger = (event == "monster_damage" and _same_monster20(source, data) and int(data.get("seat", -1)) >= 0) or (event == "attack_declared" and int(data.get("slot", -1)) >= 0 and is_same(monsters[int(data.slot)], source))
				if event == "monster_damage":
					receiver = int(data.get("seat", current))
			267:
				trigger = (event == "roll" and int(data.get("value", 0)) == 6) or (event == "monster_death" and _same_monster20(source, data))
			271:
				trigger = event == "turn_start"
				if event == "attack_roll" and battle >= 0 and is_same(monsters[battle], source):
					trigger = int(source.get("last_turn15", -1)) == turn_serial and int(source.get("last_face15", -1)) == int(data.value)
					source["last_turn15"] = turn_serial
					source["last_face15"] = int(data.value)
			274:
				trigger = event == "monster_damage" and _same_monster20(source, data)
			275:
				trigger = event == "damage" and int(data.get("seat", -1)) == current and battle >= 0 and is_same(monsters[battle], source) and not (source.has("virtual_zone15") and int(source.virtual_owner15) == current)
			276, 277:
				trigger = event == "attack_declared" and int(data.get("slot", -1)) >= 0 and is_same(monsters[int(data.slot)], source)
			279:
				if event == "purchase" and int(data.get("slot", -1)) >= 0:
					source["counters"] = int(source.get("counters", 0)) + int(data.get("cost", 0))
			280:
				if event == "loot_play":
					source["counters"] = int(source.get("counters", 0)) + 1
			282:
				trigger = event == "monster_death"
			283:
				trigger = event == "monster_death" and _same_monster20(source, data)
			286:
				if event == "death":
					source["counters"] = int(source.get("counters", 0)) + 1
				if event == "turn_start" and int(source.get("counters", 0)) >= 6:
					_forced_monsters14.append(id)
		if trigger:
			_queue_packet15(receiver, id, source, event, data)

func _queue_packet15(owner: int, id: int, source: Dictionary, context: String, data: Dictionary = {}) -> void:
	_queue_passive(owner, id, source, [{"op": "trinket_automation", "amount": 1, "context": context, "data": data.duplicate(true)}])

func _absorb_next_hit(zone: String, target: int, amount: int) -> int:
	if _card_automation_enabled() and zone == "monster" and amount > 0:
		for monster: Dictionary in monsters:
			if int(monster.id) == target and target == 280 and int(monster.get("counters", 0)) > 0:
				monster.counters = int(monster.counters) - 1
				_queue_passive(current, 280, monster, [{"op": "loot", "amount": 1}])
				return 0
	var reflectors: Array = _next_hit_shields.filter(func(shield): return str(shield.zone) == zone and int(shield.target) == target and shield.has("reflect15"))
	var remaining := super._absorb_next_hit(zone, target, amount)
	if remaining < amount:
		for reflector: Dictionary in reflectors:
			_queue_packet15(int(reflector.reflect15), 255, {}, "prevented")
	return remaining

func _monster_entered15(entry: Dictionary) -> void:
	if not _card_automation_enabled() or bool(entry.get("entered15", false)):
		return
	entry["entered15"] = true
	if int(entry.id) == 270 and not _setting_up:
		_queue_packet15(current, 270, entry, "enter")

func _battle_roller15() -> int:
	if battle < 0 or battle >= monsters.size() or not is_same(monsters[battle], _team_source15):
		_team_queue15.clear()
		return current
	while not _team_queue15.is_empty() and (dead[int(_team_queue15[0])] or int(hp[int(_team_queue15[0])]) <= 0):
		_team_queue15.pop_front()
	return int(_team_queue15[0]) if not _team_queue15.is_empty() else current

func _team_after_combat15(roller: int) -> void:
	if battle < 0 or battle >= monsters.size() or not is_same(monsters[battle], _team_source15):
		_team_queue15.clear()
		return
	if roller == current:
		_team_queue15.clear()
		for offset in range(1, players.size()):
			var seat: int = (current + offset) % players.size()
			if not dead[seat] and int(hp[seat]) > 0:
				_team_queue15.append(seat)
	elif not _team_queue15.is_empty() and int(_team_queue15[0]) == roller:
		_team_queue15.pop_front()

func _intercept_roll12(effect: Dictionary, attack_roll: bool) -> bool:
	if _card_automation_enabled() and (attack_roll or _rerolls_attack(effect)) and battle >= 0 and battle < monsters.size() and int(monsters[battle].id) == 258 and not bool(effect.get("minimum_done15", false)):
		effect["minimum_done15"] = true
		var token := _roll_token(effect)
		stack.append(effect)
		_begin_resolving({"kind": "item", "card": 258, "owner": int(effect.owner), "source": monsters[battle], "conditional": true, "automation_context": "minimum", "automation_data": {"token": token, "value": int(effect.value), "bonus": int(effect.get("multi_bonus12", 0))}})
		return true
	return super._intercept_roll12(effect, attack_roll)

func _prepare_neighbors15() -> bool:
	if not _card_automation_enabled() or battle < 0 or battle >= monsters.size() or int(monsters[battle].id) != 273:
		return false
	_begin_resolving({"kind": "item", "card": 273, "owner": current, "source": monsters[battle], "conditional": true, "automation_context": "before_roll", "_resume": "battle_roll"})
	_advance_card_automation()
	return true

func _prepare_penalty15(dying: int) -> bool:
	if not _card_automation_enabled() or _shadow_penalty15.has(dying):
		return false
	for seat in players.size():
		for entry: Dictionary in items[seat]:
			if seat != dying and int(entry.id) == 247:
				_shadow_penalty15[dying] = {"receiver": seat, "item": {}}
				if items[dying].any(func(item): return not bool(item.eternal)):
					_begin_resolving({"kind": "item", "card": 247, "owner": seat, "source": entry, "conditional": true, "automation_context": "penalty", "automation_data": {"seat": dying}, "_resume": "death"})
					_advance_card_automation()
					return true
	return false

func _replace_item_destroy15(seat: int, source: Dictionary) -> bool:
	if not _card_automation_enabled() or int(source.id) != 275 or resolving.is_empty() or int(resolving.get("owner", seat)) == seat:
		return false
	var receiver: int = int(resolving.owner)
	for index in items[seat].size():
		if is_same(items[seat][index], source):
			items[receiver].append(_remove_item(seat, index))
			return true
	return false

func _monster_max15(monster: Dictionary) -> int:
	return maxi(0, _monster_hp(int(monster.id)) + int(monster.get("health_tokens15", 0)) + int(monster.get("temporary_hp15", 0)) - (int(monster.get("counters", 0)) if int(monster.id) == 262 else 0))

func _familiar_targets15() -> Array:
	var out: Array = []
	for seat in players.size():
		for index in items[seat].size():
			if int(items[seat][index].id) == 275:
				out.append({"zone": "item", "seat": seat, "index": index, "card": 275})
		for index in soul_cards[seat].size():
			if int(soul_cards[seat][index].id) == 278:
				out.append({"zone": "soul", "seat": seat, "index": index, "card": 278})
	return out

func _attack_familiar15(seat: int, index: int) -> bool:
	var targets := _familiar_targets15()
	if not _card_automation_enabled() or phase != "turn" or seat != current or dead[seat] or attacked or battle >= 0 or battle_player >= 0 or index < 0 or index >= targets.size() or not _forced_slots14().is_empty() or _forced_deck_remaining() > 0 or _required_player_remaining() > 0:
		return false
	if not _pay_attack_tax(seat):
		return false
	var target: Dictionary = targets[index]
	var source: Dictionary
	if str(target.zone) == "room20":
		source = _extra_rooms20[int(target.index)]
	elif str(target.zone) == "item":
		source = items[int(target.seat)][int(target.index)]
	else:
		source = soul_cards[int(target.seat)][int(target.index)]
	var id: int = int(target.card)
	var entry := {"id": id, "hp": int(source.get("familiar_hp15", _monster_hp(id))), "dc": FSData.stat(id, "dc", 4) + (1 if str(target.zone) == "soul" else 0), "at": FSData.stat(id, "at", 1), "virtual_zone15": str(target.zone), "virtual_ref15": source, "virtual_owner15": int(target.seat)}
	monsters.append(entry)
	attack_left -= 1
	attacked = attack_left <= 0
	_next_attack_token += 1
	_push({"kind": "attack", "owner": seat, "slot": monsters.size() - 1, "attack_token": _next_attack_token}, "turn")
	_emit_passives("attack_declared", {"seat": seat, "slot": monsters.size() - 1, "token": _next_attack_token})
	return true

func _end_battle() -> void:
	super._end_battle()
	_team_queue15.clear()
	_team_source15 = {}
	for index in range(monsters.size() - 1, -1, -1):
		var entry: Dictionary = monsters[index]
		if entry.has("virtual_zone15"):
			entry.virtual_ref15["familiar_hp15"] = maxi(0, int(entry.hp))
			monsters.remove_at(index)

func _replace_monster_death(slot: int) -> bool:
	var monster: Dictionary = monsters[slot]
	if _card_automation_enabled() and monster.has("virtual_zone15"):
		var source: Dictionary = monster.virtual_ref15
		var holder: int = int(monster.virtual_owner15)
		var killer: int = int(monster.get("slayer", current))
		if str(monster.virtual_zone15) == "soul":
			var index: int = soul_cards[holder].find(source)
			if index >= 0:
				soul_cards[holder].remove_at(index)
				souls[holder] = int(souls[holder]) - int(source.value)
				_gain_soul_card(killer, source, false)
			_queue_passive(current, 278, {}, [{"op": "treasure", "amount": reward_boost}])
		else:
			var index: int = items[holder].find(source)
			if index >= 0:
				if killer != holder:
					items[killer].append(_remove_item(holder, index))
				else:
					_destroy_item(holder, index)
		monsters.remove_at(slot)
		_end_battle()
		return true
	if _card_automation_enabled() and int(monster.id) == 284 and int(monster.get("counters", 0)) < 2:
		monster["counters"] = int(monster.get("counters", 0)) + 1
		monster.hp = _monster_max15(monster)
		monster["death_pending"] = false
		monster.erase("lethal_attack_roll")
		_queue_passive(current, 284, {}, [{"op": "treasure", "amount": reward_boost}])
		_queue_packet15(current, 284, monster, "prevented_death")
		return true
	return super._replace_monster_death(slot)

## Вне награды карта285 также завершает партию при получении контроля над душой.
func _gain_soul_card(seat: int, card: Dictionary, gained: bool = true) -> void:
	super._gain_soul_card(seat, card, gained)
	if _card_automation_enabled() and int(card.id) == 285 and card in soul_cards[seat] and not (resolving.get("kind", "") == "reward" and int(resolving.get("card", -1)) == 285):
		_queue_packet15(seat, 285, card, "soul_gain")

func _check_win() -> void:
	if _card_automation_enabled() and phase != "game_over":
		if int(resolving.get("card", -1)) == 285 or stack.any(func(effect): return int(effect.get("card", -1)) == 285):
			return
	super._check_win()
