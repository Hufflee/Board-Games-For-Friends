extends "res://games/four_souls/logic/fs_rooms24_automation.gd"
## Игровые комнаты, обязательные дополнительные атаки и стартовые предметы.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var owner: int = int(resolving.get("owner", current))
	match str(step.get("targets", "")):
		"mirror_accept25":
			if int(hp[owner]) > 1:
				out.append({"label": "Заплатить %d здоровья" % (int(hp[owner]) - 1), "arg": {"op": "mirror_pay25"}})
		"glitch_monsters25":
			for slot in monsters.size():
				if slot != battle and not monsters[slot].has("virtual_zone15"):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "glitch_replace25", "item": slot}})
		"blue_modes25":
			if coins.any(func(amount): return int(amount) > 0):
				out.append({"label": "Украсть 1¢", "arg": {"op": "blue_modes25", "mode": "coin"}})
			out.append({"label": "Посмотреть верх колоды", "arg": {"op": "blue_modes25", "mode": "peek"}})
			if not hands[owner].is_empty():
				out.append({"label": "Сбросить добычу и взять 1 добычу", "arg": {"op": "blue_modes25", "mode": "cycle"}})
		"blue_others25":
			for seat in players.size():
				if seat != owner and int(coins[seat]) > 0 and not _protected20(seat, owner):
					out.append({"label": name_of(seat), "arg": {"op": "blue_steal25", "target": seat}})
		"incubus_modes25":
			out.append({"label": "Посмотреть чужую руку и предложить обмен", "arg": {"op": "incubus_modes25", "mode": "swap"}})
			out.append({"label": "Взять добычу и вернуть карту наверх", "arg": {"op": "incubus_modes25", "mode": "top"}})
		"incubus_cards25":
			for index in hands[int(resolving.incubus_target25)].size():
				var card: int = int(hands[int(resolving.incubus_target25)][index])
				out.append({"label": FSData.title(card), "arg": {"op": "incubus_swap25", "item": index, "card": card}})
	return out

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var id: int = int(resolving.card)
	match str(step.op):
		"room_loot_cost25":
			var card: int = int(hands[owner].pop_at(int(step.item)))
			discards.loot.append(card)
			var keys: bool = str(FSData.card(card).get("key", "")).contains("key")
			resolving["room_tries25"] = 3 if id == 785 and keys else 1
			_room_activations[owner] = int(_room_activations.get(owner, 0)) + 1
			_insert_card_steps([{"op": "auto_roll"}, {"op": "room_table25"}])
		"room_table25":
			_room_table25(id, owner, int(resolving.get("automation_roll", 1)))
		"room_partner25":
			if int(resolving.get("automation_roll", 0)) >= 4 and owner not in _coop_partners20:
				_coop_partners20.append(owner)
		"mirror_pay25":
			hp[owner] = 1
			_mirror_turn25 = turn_serial
		"dice_room25":
			if id in [786, 788, 791]:
				_reroll_each25(owner if id == 791 else -1)
			if id in [786, 789]:
				_flush_shop25()
			if id in [786, 790]:
				for seat in players.size():
					_reset_hand25(seat)
			if id in [786, 787]:
				_flush_monsters24(false)
		"discard_room25":
			_discard_native_room24(resolving.source)
		"glitch_replace25":
			var slot: int = int(step.item)
			var old: Dictionary = monsters[slot]
			_put_monster20(old, "discard")
			_eggs_monsters.erase(int(old.id))
			var replacement := _draw("monster")
			if replacement < 0:
				monsters.remove_at(slot)
			elif FSData.card(replacement).get("kind", "") == "event":
				_push({"kind": "event", "card": replacement, "owner": current}, "effect")
				if old.has("under"):
					monsters[slot] = old.under
				else:
					monsters.remove_at(slot)
				resolving["refill_monsters"] = true
			else:
				var fresh := {"id": replacement, "hp": _monster_hp(replacement), "dc": FSData.stat(replacement, "dc", 4), "at": FSData.stat(replacement, "at", 1)}
				if old.has("under"):
					fresh["under"] = old.under
				monsters[slot] = fresh
				_monster_entered15(fresh)
		"glitch_hand25":
			_reset_hand25(owner)
		"blue_modes25":
			match str(step.mode):
				"coin": _insert_card_steps([{"op": "blue_steal25", "targets": "blue_others25"}])
				"peek": _insert_card_steps([{"op": "peek_deck", "targets": "decks", "amount": 1}, {"op": "read_peek"}])
				"cycle": _insert_card_steps([{"op": "blue_cycle25", "targets": "own_hand"}])
		"blue_steal25":
			_transfer_coins(int(step.target), owner, 1)
		"blue_cycle25":
			discards.loot.append(int(hands[owner].pop_at(int(step.item))))
			_draw_loot(owner, 1)
		"pit_cancel25":
			if _cancel_attack25():
				attack_left += 1
				attacked = false
		"incubus_modes25":
			if str(step.mode) == "top":
				_draw_loot(owner, 1)
				_insert_card_steps([{"op": "incubus_top25", "targets": "own_hand"}])
			else:
				_insert_card_steps([{"op": "incubus_peek25", "targets": "other_players"}])
		"incubus_top25":
			decks.loot.append(int(hands[owner].pop_at(int(step.item))))
		"incubus_peek25":
			var target: int = int(step.target)
			resolving["incubus_target25"] = target
			peek = {"owner": owner, "deck": "hand", "cards": hands[target].duplicate(), "target": target}
			if hands[owner].is_empty() or hands[target].is_empty():
				_insert_card_steps([{"op": "read_peek"}])
			else:
				_insert_card_steps([{"op": "incubus_give25", "targets": "own_hand", "optional": true}, {"op": "incubus_finish25"}])
		"incubus_give25":
			resolving["incubus_own25"] = int(step.item)
			_insert_card_steps([{"op": "incubus_swap25", "targets": "incubus_cards25"}])
		"incubus_swap25":
			var target: int = int(resolving.incubus_target25)
			var own: int = int(resolving.incubus_own25)
			var card: int = int(hands[owner][own])
			hands[owner][own] = int(hands[target][int(step.item)])
			hands[target][int(step.item)] = card
		"incubus_finish25":
			peek = {}
		"bone_roll25":
			var index: int = int(step.roll_index)
			_change_pending12(_roll_token(stack[index]), int(stack[index].value) + 1, false)
		"bone_soul25":
			_bone_soul25(resolving.source, owner)
		_:
			super._apply_card_step(step)

func _room_table25(id: int, owner: int, face: int) -> void:
	match id:
		776:
			if face == 6:
				_give_treasures21(owner, 1)
				_draw_loot(owner, 1)
			elif face >= 3:
				_gain_coins(owner, 4 if face == 3 else 7)
		780:
			if face == 6:
				_damage_player(owner, 1, {"attacker": -1})
			else:
				_draw_loot(owner, 2 if face <= 2 else 1)
		784:
			_gain_coins(owner, int([0, 1, 2, 5, 7, 15][face - 1]))
			if face == 6:
				_discard_native_room24(resolving.source)
		785:
			if face >= 5:
				_give_treasures21(owner, 1)
			resolving["room_tries25"] = int(resolving.get("room_tries25", 1)) - 1
			resolving.erase("automation_roll")
			if int(resolving.room_tries25) > 0:
				_insert_card_steps([{"op": "auto_roll"}, {"op": "room_table25"}])
		792:
			if face >= 4:
				attack_left += 1
				_mandatory_attacks25 += 1
				attacked = false
		801, 805:
			if face == 6:
				_give_treasures21(owner, 1)
				_discard_native_room24(resolving.source)
			elif id == 801:
				if face in [3, 5]:
					_gain_coins(owner, 1 if face == 3 else 5)
				elif face == 4:
					_draw_loot(owner, 1)
			elif face in [3, 4]:
				_gain_coins(owner, 2)
			elif face == 5:
				_draw_loot(owner, 2)
		820:
			var steps: Array = []
			if face in [1, 2, 6]:
				steps.append({"op": "glitch_replace25", "targets": "glitch_monsters25"})
			if face in [3, 4, 6]:
				steps.append({"op": "reroll_item", "targets": "room_owned24"})
			if face >= 5:
				steps.append({"op": "glitch_hand25"})
			_insert_card_steps(steps)

func _reset_hand25(seat: int) -> void:
	if _item_count(seat, 523) == 0:
		discards.loot.append_array(hands[seat])
		hands[seat].clear()
	_draw_loot(seat, 3)

func _reroll_each25(owner: int) -> void:
	for seat in players.size():
		if owner >= 0 and seat != owner:
			continue
		for source: Dictionary in items[seat].duplicate():
			var index: int = items[seat].find(source)
			if index >= 0 and not bool(source.eternal):
				# Пакет28: у _effect нет операции reroll_item — переигрываем общим шагом автоматизации.
				_apply_card_step({"op": "reroll_item", "target": seat, "item": index, "shop": false})

func _flush_shop25() -> void:
	for index in shop.size():
		var id: int = int(shop[index])
		if id >= 0 and not bool(_eternal_shop15.get(id, false)):
			_discard_item(id)
			_shop_counters20.erase(id)
			shop[index] = -1
	_refill_shop24()

func _cancel_attack25() -> bool:
	var found := battle >= 0 or battle_player >= 0
	for index in range(stack.size() - 1, -1, -1):
		if stack[index].kind in ["attack", "player_attack"]:
			stack.remove_at(index)
			found = true
	if found:
		_resolving_base = mini(_resolving_base, stack.size())
		_end_battle()
		resolving["_resume"] = "turn"
		# 09.11: приостановленные эффекты боя (способность монстра ждёт броска) продолжат обычный ход,
		# а не «бросок атаки» без боя — иначе партия вставала (Повелитель ямы 836).
		for paused: Dictionary in paused_effects:
			if str(paused.get("resume", "")) == "battle_roll":
				paused["resume"] = "turn"
			if (paused.get("effect", {}) as Dictionary).get("_resume", "") == "battle_roll":
				paused.effect["_resume"] = "turn"
		for entry: Dictionary in stack:
			if str(entry.kind) == "resume_effect":
				var previous: Dictionary = entry.get("previous", {})
				if str(previous.get("resume", "")) == "battle_roll":
					previous["resume"] = "turn"
	return found

func _bone_soul25(source: Dictionary, owner: int) -> void:
	if bool(source.get("room_item20", false)):
		_destroy_room20(source, current, true)
		return
	for holder in players.size():
		for index in items[holder].size():
			if is_same(source, items[holder][index]):
				var physical := _remove_item(holder, index, true)
				_gain_soul_card(owner, {"id": int(physical.id), "value": 1})
				return

func _refresh_passive_stats() -> void:
	super._refresh_passive_stats()
	if not _card_automation_enabled() or _setting_up:
		return
	for index in range(-1, _extra_rooms20.size()):
		var source := _native_room_source24(index)
		if int(source.get("id", -1)) in CardAutomation.Packet25.DICE_ROOMS and not bool(source.get("entered25", false)):
			source["entered25"] = true
			_queue_packet15(current, int(source.id), source, "room_enter25")

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	if event == "turn_start":
		if _room_has20(783) and int(hp[current]) > 1:
			_queue_packet15(current, 783, {}, event, data)
		if _room_has20(820):
			_queue_packet15(current, 820, {}, event, data)
	if event == "turn_end":
		for index in range(-1, _extra_rooms20.size()):
			var source := _native_room_source24(index)
			if int(source.get("id", -1)) in CardAutomation.Packet25.DICE_ROOMS:
				_queue_packet15(current, int(source.id), source, "room_end25")
	if event == "monster_death":
		if _mirror_turn25 == turn_serial:
			_queue_passive(current, 783, {}, [PassiveRules.operation("treasure")])
		if _room_has20(792):
			_queue_packet15(current, 792, {}, event, data)
	if event == "roll" and _room_has20(819) and int(data.get("value", 0)) == 1 and int(data.get("seat", -1)) >= 0:
		_queue_passive(int(data.seat), 819, {}, [PassiveRules.operation("damage")])
	if event == "attack_declared":
		_mandatory_attacks25 = maxi(0, _mandatory_attacks25 - 1)
		var slot: int = int(data.get("slot", -1))
		if slot >= 0 and slot < monsters.size() and int(monsters[slot].id) == 778 and str(monsters[slot].get("virtual_zone15", "")) == "native_room24":
			for offset in range(players.size() - 1, 0, -1):
				_queue_packet15((current + offset) % players.size(), 778, monsters[slot].virtual_ref15, "partner25")
	if event == "damage" and int(data.get("seat", -1)) >= 0:
		var target: int = int(data.seat)
		for source: Dictionary in _ability_items20(target):
			if int(source.id) == 830:
				_queue_passive(target, 830, source, [PassiveRules.operation("recharge")])

func _must_attack() -> bool:
	if super._must_attack():
		return true
	if not _card_automation_enabled() or _mandatory_attacks25 <= 0 or attack_left <= 0 or attacked or int(coins[current]) < _attack_tax(current):
		return false
	return not decks.monster.is_empty() or not discards.monster.is_empty() or monsters.any(func(entry): return not _untargetable(int(entry.id))) or not _permitted_player_attack_targets().is_empty()

func _room_pvp25() -> int:
	if not _card_automation_enabled():
		return -1
	for id in [793, 794, 795]:
		if _room_has20(id):
			return id
	return -1

func _pvp_defense16(target: int) -> int:
	var id := _room_pvp25()
	return 798 - id if id >= 0 else super._pvp_defense16(target)

func _permitted_player_attack_targets() -> Array:
	var out := super._permitted_player_attack_targets()
	if _room_pvp25() >= 0 and not attacked and attack_left > _optional_blind17 and _forced_deck_remaining() == 0 and _lust_pending.is_empty():
		for seat in _player_attack_targets():
			if seat not in out:
				out.append(seat)
	return out
