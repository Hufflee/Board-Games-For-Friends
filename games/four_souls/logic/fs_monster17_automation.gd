extends "res://games/four_souls/logic/fs_monster16_automation.gd"
## Условия сорока карт, выбранный напарник, яйца и следующий бросок атаки.

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	match str(step.get("targets", "")):
		"accept17":
			out.append({"label": "Применить", "arg": {"op": str(step.op), "target": int(resolving.owner), "amount": int(step.get("amount", 1))}})
		"living_others17":
			for seat in active_seats():
				if seat != current and not dead[seat] and int(hp[seat]) > 0:
					out.append({"label": name_of(seat), "arg": {"op": str(step.op), "target": seat}})
		"double_faces17":
			for index in resolving.double_faces17.size():
				out.append({"label": "Кубик %d · %d" % [index + 1, int(resolving.double_faces17[index])], "arg": {"op": "double_choose17", "item": index}})
		"spawn_slots17":
			for slot in maxi(monster_slots, monsters.size()):
				if slot != battle and (slot >= monsters.size() or int(monsters[slot].id) not in [272, 279, 299, 312, 913, 914]):
					out.append({"label": "Слот монстров %d" % (slot + 1), "arg": {"op": "egg_spawn17", "item": slot}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	var value: int = int(resolving.get("automation_roll", 0))
	match str(step.op):
		"nonactive_damage17":
			for seat in players.size():
				if seat != current:
					_damage_player(seat, 1, {"monster": int(resolving.card)})
		"double_prepare17":
			resolving["double_faces17"] = [int(resolving.automation_data.first)]
		"double_collect17":
			resolving.double_faces17.append(value)
			resolving["choice_owner"] = (owner + 1) % players.size()
		"double_choose17":
			var face: int = int(resolving.double_faces17[int(step.item)]) + int(resolving.automation_data.bonus)
			if _era_left > 0:
				_era_left -= 1
				face = _era_face
			_change_pending12(int(resolving.automation_data.token), clampi(face, 1, 6), false)
			resolving.erase("choice_owner")
		"partner17":
			_team_source15 = source
			_team_queue15.clear()
			source["partner17"] = int(step.target)
		"partner_gift17":
			var id := _draw("treasure")
			if id >= 0:
				_gain_item(int(source.partner17), id)
		"neighbor_damage17":
			var target := owner if value <= 2 else (owner + 1) % players.size() if value <= 4 else posmod(owner - 1, players.size())
			_damage_player(target, 1, {"monster": int(resolving.card)})
		"declaration_damage17":
			if value <= 2:
				_damage_player(int(resolving.automation_data.get("seat", current)), 1, {"monster": 340})
		"kill_knots17":
			source.hp = 0
			source["slayer"] = current
			hp[current] = 0
		"egg_counter17":
			_eggs_respawn17[current] = true
		"egg_spawn17":
			if 343 in discards.monster:
				discards.monster.erase(343)
				_place_encounter_monster(343, int(step.item))
				monster_slots = maxi(monster_slots, monsters.size())
		"extra_blind17":
			_optional_blind17 += 1
			attack_left += 1
			attacked = false
		"end_unresolved17":
			_cancel_unresolved()
			_resolving_base = 0
			resolving["end_turn_after"] = true
		"one_health17":
			if value <= 4:
				_damage_source17(source, 1)
			else:
				source.hp = mini(_monster_max15(source), int(source.hp) + 2)
		"brown_result17":
			if value <= 2:
				_damage_player(owner, 1, {"monster": 366})
			elif value <= 4:
				for seat in players.size():
					_damage_player(seat, 1, {"monster": 366})
			else:
				_damage_source17(source, 1)
		"damage":
			if bool(step.get("target_roller17", false)):
				_damage_player(int(resolving.automation_data.seat), int(step.amount), {"monster": int(resolving.card)})
			else:
				super._apply_card_step(step)
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "attack_declared" and int(data.get("slot", -2)) == -1 and _optional_blind17 > 0:
		_optional_blind17 -= 1
	if event == "death" and _eggs_respawn17.has(int(data.seat)) and 343 in discards.monster:
		_eggs_respawn17.erase(int(data.seat))
		_queue_packet15(current, 343, {}, "respawn17", data)
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var own_damage: bool = event == "monster_damage" and _same_monster20(source, data)
		var own_death: bool = event == "monster_death" and _same_monster20(source, data)
		var own_attack: bool = battle >= 0 and battle < monsters.size() and is_same(monsters[battle], source)
		var declared: bool = event == "attack_declared" and int(data.get("slot", -1)) >= 0 and int(data.slot) < monsters.size() and is_same(monsters[int(data.slot)], source)
		var trigger := false
		var context := event
		match id:
			327, 337, 365:
				trigger = own_damage
			329, 331, 333:
				trigger = event == "monster_death"
			332:
				if event == "roll" and int(data.get("value", 0)) == 3:
					for monster: Dictionary in monsters:
						if monster.has("virtual_zone15"):
							continue
						monster.dc = int(monster.dc) - 1
						monster["temporary_dc"] = int(monster.get("temporary_dc", 0)) - 1
			334:
				trigger = event == "turn_end"
			335:
				trigger = declared or (own_death and own_attack and source.has("partner17"))
			338, 343, 360:
				trigger = own_death
			339:
				trigger = declared
			340:
				trigger = event == "attack_declared"
			341:
				if event == "turn_start":
					_forced_monsters14.append(341)
				trigger = own_death
			342:
				if event == "attack_declared":
					source["counters"] = int(source.get("counters", 0)) + 1
				trigger = event == "turn_start" and int(source.get("counters", 0)) >= 6
			344:
				if event == "attack_roll" and own_attack and int(data.get("value", 0)) == 3:
					source.dc = int(source.dc) + 1
					source["temporary_dc"] = int(source.get("temporary_dc", 0)) + 1
			347:
				trigger = own_death and int(source.get("lethal_attack_roll", 0)) == 6
			349:
				if event == "damage" and bool(data.get("combat", false)) and _same_damage_source20(source, data):
					var seat: int = int(data.seat)
					_next_attack_bonus17[seat] = int(_next_attack_bonus17.get(seat, 0)) + 1
			350:
				if event == "combat_monster_damage" and _same_monster20(source, data):
					var seat: int = int(data.seat)
					_next_attack_bonus17[seat] = int(_next_attack_bonus17.get(seat, 0)) - 1
			351:
				if event == "damage" and _same_damage_source20(source, data):
					source.hp = mini(_monster_max15(source), int(source.hp) + 1)
			353:
				if own_damage:
					_next_any_attack_bonus17 -= 2
			356:
				if event == "attack_roll" and own_attack and int(data.get("value", 0)) in [2, 6]:
					trigger = true
					context = "two17" if int(data.value) == 2 else "six17"
			359:
				if own_damage:
					source.dc = int(source.dc) + 1
					source["temporary_dc"] = int(source.get("temporary_dc", 0)) + 1
			363:
				trigger = own_damage and int(source.hp) == 1
			366:
				trigger = own_damage and int(data.get("seat", -1)) == current
		if trigger:
			_queue_packet15(current, id, source, context, data)

func _damage_source17(source: Dictionary, amount: int) -> void:
	if not monsters.any(func(monster): return is_same(monster, source)):
		return
	var damage := _absorb_next_hit("monster", int(source.id), amount)
	source.hp = int(source.hp) - damage
	if damage > 0:
		_emit_passives("monster_damage", {"seat": -1, "card": int(source.id), "amount": damage, "physical_id20": int(source.get("physical_id20", source.id))})
	if int(source.hp) <= 0:
		source["slayer"] = current
		source["lethal_attack_roll"] = 0

func _intercept_roll12(effect: Dictionary, attack_roll: bool) -> bool:
	if _card_automation_enabled() and not bool(effect.get("double_done17", false)) and monsters.any(func(monster): return int(monster.id) == 328 and int(monster.hp) > 0):
		effect["double_done17"] = true
		var token := _roll_token(effect)
		stack.append(effect)
		_begin_resolving({"kind": "item", "card": 328, "owner": int(effect.owner), "source": {}, "conditional": true, "automation_context": "double17", "automation_data": {"token": token, "first": int(effect.value), "bonus": int(effect.get("multi_bonus12", 0))}})
		return true
	if super._intercept_roll12(effect, attack_roll):
		return true
	if _card_automation_enabled() and attack_roll and not bool(effect.get("bonus_applied17", false)):
		if not effect.has("next_bonus17"):
			var owner: int = int(effect.owner)
			effect["next_bonus17"] = int(_next_attack_bonus17.get(owner, 0)) + _next_any_attack_bonus17
			_next_attack_bonus17.erase(owner)
			_next_any_attack_bonus17 = 0
		effect.value = clampi(int(effect.value) + int(effect.next_bonus17), 1, 6)
		effect["bonus_applied17"] = true
	return false

func _team_after_combat15(roller: int) -> void:
	if battle >= 0 and battle < monsters.size() and is_same(monsters[battle], _team_source15) and int(_team_source15.id) == 335:
		if roller == current:
			_team_queue15.clear()
			var partner: int = int(_team_source15.get("partner17", -1))
			if partner >= 0 and not dead[partner] and int(hp[partner]) > 0:
				_team_queue15.append(partner)
		elif not _team_queue15.is_empty():
			_team_queue15.pop_front()
		return
	super._team_after_combat15(roller)

func _apply_combat(effect: Dictionary) -> void:
	if _card_automation_enabled() and battle >= 0 and battle < monsters.size() and not bool(effect.hit) and int(monsters[battle].id) == 330:
		effect.damage = 0
		_queue_packet15(current, 330, monsters[battle], "prevented")
	if _card_automation_enabled() and bool(effect.hit) and int(effect.get("card", -1)) == 364 and int(effect.value) == 6:
		effect.damage = 0
	super._apply_combat(effect)

func _monster_evasion(monster: Dictionary) -> int:
	return super._monster_evasion(monster) + (int(monster.get("counters", 0)) if _card_automation_enabled() and int(monster.id) == 342 else 0)

func _monster_attack(monster: Dictionary) -> int:
	return super._monster_attack(monster) + (int(monster.get("counters", 0)) if _card_automation_enabled() and int(monster.id) == 342 else 0)

func _permitted_player_attack_targets() -> Array:
	var out := super._permitted_player_attack_targets()
	if _card_automation_enabled() and attack_left <= _optional_blind17 and required_player_attacks <= 0 and _lust_pending.is_empty():
		return []
	if _card_automation_enabled() and not attacked and attack_left > 0 and _lust_pending.is_empty() and monsters.any(func(monster): return int(monster.id) == 336 and int(monster.hp) > 0):
		for seat in _player_attack_targets():
			if seat not in out:
				out.append(seat)
	return out

func _attack_familiar15(seat: int, index: int) -> bool:
	if _card_automation_enabled() and attack_left <= _optional_blind17:
		return false
	return super._attack_familiar15(seat, index)

func _player_defenses17() -> Dictionary:
	var out: Dictionary = {}
	for target in _player_attack_targets():
		out[target] = _pvp_defense16(int(target))
	return out
