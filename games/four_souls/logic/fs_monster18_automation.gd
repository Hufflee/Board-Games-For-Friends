extends "res://games/four_souls/logic/fs_monster17_automation.gd"
## Пассивы монстров, чужой выбор души и адресные триггеры раскрытого противника.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	match str(step.get("targets", "")):
		"soul_owners18":
			for seat in players.size():
				if soul_cards[seat].any(func(card): return FSData.card(int(card.id)).get("kind", "") != "character"):
					out.append({"label": name_of(seat), "arg": {"op": "soul_giver18", "target": seat}})
		"owned_souls18":
			var owner := _card_choice_owner()
			for index in soul_cards[owner].size():
				var card: Dictionary = soul_cards[owner][index]
				if FSData.card(int(card.id)).get("kind", "") != "character":
					out.append({"label": FSData.title(int(card.id)), "arg": {"op": str(step.op), "target": owner, "item": index, "card": int(card.id)}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"other_damage18":
			for monster: Dictionary in monsters.duplicate():
				if not is_same(monster, source):
					_monster_damage18(monster, 1)
		"roller_damage18":
			_damage_player(int(resolving.automation_data.get("seat", current)), 1, {"monster": int(resolving.card)})
		"neighbor_result18":
			var target := posmod(current - 1, players.size()) if value <= 3 else (current + 1) % players.size()
			_damage_player(target, 1, {"attacker": current})
		"damage_all18":
			for seat in players.size():
				_damage_player(seat, int(step.get("amount", 1)), {"monster": int(resolving.card)})
		"heal_all18":
			for monster: Dictionary in monsters:
				if not monster.has("virtual_zone15"):
					monster.hp = mini(_monster_max15(monster), int(monster.hp) + 2)
		"winner_prepare18":
			if souls.count(souls.max()) == 1:
				winner = souls.find(souls.max())
				phase = "game_over"
			else:
				_insert_card_steps([{"op": "winner15", "targets": "leaders15"}])
		"soul_giver18", "soul_destroyer18":
			resolving["choice_owner"] = int(step.target)
			_insert_card_steps([{"op": "give_owned_soul18" if str(step.op) == "soul_giver18" else "destroy_soul", "targets": "owned_souls18"}])
		"give_owned_soul18":
			var giver: int = int(step.target)
			if giver != owner:
				var soul: Dictionary = soul_cards[giver].pop_at(int(step.item))
				souls[giver] = int(souls[giver]) - int(soul.value)
				_gain_soul_card(owner, soul, false)
		"lose_coins_all18":
			for seat in players.size():
				_gain_coins(seat, -int(step.amount))
		"player_damage18":
			_damage_player(int(step.target), int(step.amount), {"attacker": owner})
		"death_result18":
			_insert_card_steps([{"op": "damage_all18", "amount": 1 if value <= 3 else 2}])
		"lose_victim_coins18":
			_gain_coins(int(resolving.automation_data.seat), -2)
		"discard_target18":
			resolving["choice_owner"] = int(step.target)
			_insert_card_steps([{"op": "discard_victim_card16", "targets": "victim_hand16"}, {"op": "discard_victim_card16", "targets": "victim_hand16"}])
		"mirror_damage18":
			var target := posmod(current - 1, players.size()) if int(resolving.card) == 399 else (current + 1) % players.size()
			_damage_player(target, int(resolving.automation_data.amount), {"monster": int(resolving.card)})
		_:
			super._apply_card_step(step)

func _monster_damage18(monster: Dictionary, amount: int) -> void:
	if monster.has("virtual_zone15") or not monsters.any(func(entry): return is_same(entry, monster)):
		return
	var damage := _absorb_next_hit("monster", int(monster.id), amount)
	monster.hp = int(monster.hp) - damage
	if damage > 0:
		_emit_passives("monster_damage", {"seat": -1, "card": int(monster.id), "amount": damage, "physical_id20": int(monster.get("physical_id20", monster.id))})
	if int(monster.hp) <= 0:
		monster["slayer"] = current
		monster["lethal_attack_roll"] = 0

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var own_damage: bool = event == "monster_damage" and _same_monster20(source, data)
		var own_death: bool = event == "monster_death" and _same_monster20(source, data)
		var own_attack: bool = battle >= 0 and battle < monsters.size() and is_same(monsters[battle], source)
		var declared: bool = event == "attack_declared" and int(data.get("slot", -1)) >= 0 and int(data.slot) < monsters.size() and is_same(monsters[int(data.slot)], source)
		var trigger := false
		var receiver := current
		match id:
			367:
				if event == "attack_roll" and own_attack and int(data.get("value", 0)) == 1:
					source.at = int(source.at) + 2
					source["temporary_at"] = int(source.get("temporary_at", 0)) + 2
			368:
				if event == "turn_start":
					_forced_monsters14.append(368)
			370, 372:
				trigger = event == "damage" and bool(data.get("combat", false)) and _same_damage_source20(source, data)
			371:
				trigger = event == "attack_roll" and own_attack and int(data.get("value", 0)) == 6
			374, 399, 406:
				trigger = own_damage
			375, 378, 380, 382, 386, 387, 388, 389, 390, 393, 403, 404, 405:
				trigger = own_death
			376:
				trigger = event == "roll" and int(data.get("value", 0)) == 4
			377:
				trigger = event == "roll" and int(data.get("value", 0)) == 3
			379:
				trigger = event == "roll" and int(data.get("value", 0)) == 6
				receiver = int(data.get("seat", current))
			383, 394:
				trigger = event == "damage" and _same_damage_source20(source, data)
			391:
				if own_damage:
					source.at = int(source.at) + 1
					source["temporary_at"] = int(source.get("temporary_at", 0)) + 1
			396:
				trigger = declared
			397:
				trigger = event == "activate" and own_attack and int(data.get("seat", -1)) == current
			401:
				if event == "attack_roll" and own_attack and int(data.get("value", 0)) == 1:
					for monster: Dictionary in monsters:
						if monster.has("virtual_zone15"):
							continue
						monster.dc = int(monster.dc) + 1
						monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) + 1
		if trigger:
			_queue_packet15(receiver, id, source, event, data)

func _intercept_damage16(pending: Dictionary) -> bool:
	if super._intercept_damage16(pending):
		return true
	if _card_automation_enabled() and int(pending.damage) > 0 and str(pending.get("zone", "monster")) == "monster" and int(pending.get("card", -1)) == 392 and not bool(pending.get("fly_checked18", false)):
		pending["fly_checked18"] = true
		_push(pending, _after_stack if phase == "priority" else phase)
		_begin_resolving({"kind": "item", "card": 392, "owner": current, "source": {}, "conditional": true, "automation_context": "damage18", "automation_data": {"pending": pending}})
		_advance_card_automation()
		return true
	return false

func _attack_target18(source: Dictionary, token: int) -> void:
	# Глобальное объявление уже отправлено один раз при выборе атаки колоды.
	if _card_automation_enabled() and int(source.id) in [266, 276, 277, 306, 335, 339, 396, 914]:
		_queue_packet15(current, int(source.id), source, "attack_declared", {"seat": current, "slot": monsters.find(source), "token": token})

func _monster_evasion(monster: Dictionary) -> int:
	var aura := 0
	if _card_automation_enabled():
		for source: Dictionary in monsters:
			if int(source.id) == 400 and int(source.hp) > 0 and not is_same(source, monster):
				aura += 1
	return super._monster_evasion(monster) + aura

func _gain_soul_card(seat: int, card: Dictionary, gained: bool = true) -> void:
	super._gain_soul_card(seat, card, gained)
	if _card_automation_enabled() and int(card.id) == 381 and card in soul_cards[seat] and not (resolving.get("kind", "") == "reward" and int(resolving.get("card", -1)) == 381):
		_queue_packet15(seat, 381, card, "soul_gain")

func _check_win() -> void:
	if _card_automation_enabled() and phase != "game_over" and (int(resolving.get("card", -1)) == 381 or stack.any(func(effect): return int(effect.get("card", -1)) == 381)):
		return
	super._check_win()

func _damage_owner18() -> int:
	if resolving.has("damage_owner18"):
		return int(resolving.damage_owner18)
	var owner: int = int(resolving.get("owner", current))
	if not _card_automation_enabled():
		return owner
	if FSData.card(int(resolving.get("card", -1))).get("kind", "") in ["monster", "outside"] and not _source_item_in_play(resolving.get("source", {})):
		return owner if int(resolving.card) == 300 else -1
	return owner
