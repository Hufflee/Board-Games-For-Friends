extends "res://games/four_souls/logic/fs_packet25_automation.gd"
## Стартовые предметы, выборы, оплата и срабатывания группы 26.
func _tap_item14(id: int) -> bool:
	return id in CardAutomation.Packet26.TAP or id in CardAutomation.Packet27.TAP or super._tap_item14(id)

func _end_battle() -> void:
	super._end_battle()
	_sibling_reward26.clear()

func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"void_modes26":
			out.append(_choice26("Заменить свою руку", "void_mode26", "hand"))
			if _has_discard_target26():
				out.append(_choice26("Сбросить монстра или предмет магазина", "void_mode26", "table"))
		"void_table26", "glitch_shop26":
			for slot in shop.size():
				if int(shop[slot]) >= 0:
					var op := "glitch_copy26" if step.targets == "glitch_shop26" else "discard_shop"
					out.append({"label": FSData.title(int(shop[slot])), "arg": {"op": op, "item": slot}})
			if step.targets == "void_table26":
				for slot in monsters.size():
					if _can_discard_monster26(slot):
						out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": "discard_monster", "item": slot}})
		"gimpy26":
			out.append(_choice26("Получить 2¢", "gimpy26", "coins"))
			out.append(_choice26("Взять и сбросить добычу", "gimpy26", "loot"))
			out.append(_choice26("Получить +2 атаки до конца хода", "gimpy26", "attack"))
		"pink_eggs26", "blood_targets26":
			for seat in players.size():
				if not dead[seat]:
					_add_combat_choice26(out, step, "player", seat, name_of(seat))
			for slot in monsters.size():
				if not monsters[slot].has("virtual_zone15") and int(monsters[slot].hp) > 0:
					_add_combat_choice26(out, step, "monster", slot, FSData.title(int(monsters[slot].id)))
		"nonactive26":
			for seat in players.size():
				if seat != current and not dead[seat] and int(hp[seat]) > 0:
					out.append({"label": name_of(seat), "arg": {"op": "sibling26", "target": seat}})
		"ready_chars26":
			for seat in players.size():
				if not character_ready[seat]:
					out.append({"label": name_of(seat), "arg": {"op": "ready_character", "target": seat}})
		"ibs_modes26":
			out.append(_choice26("Получить 3¢", "ibs_small26", "coins"))
			if _own_monster_attack26(owner):
				out.append(_choice26("Отменить свою атаку", "ibs_small26", "attack"))
		"cancel_ibs26":
			for index in stack.size():
				if _ibs_can_cancel26(stack[index]):
					out.append({"label": FSData.title(int(stack[index].card)), "arg": {"op": "cancel_selected", "index": index}})
		"capricious_modes26":
			out.append(_choice26("Разыграть дополнительную добычу", "capricious26", "loot"))
			if shop.any(func(id): return int(id) >= 0):
				out.append(_choice26("Сбросить предмет магазина", "capricious26", "shop"))
	if step.op in ["soulbond26", "holy_save26"]:
		out = out.filter(func(choice): return not dead[int(choice.arg.target)] and (step.op != "soulbond26" or int(hp[int(choice.arg.target)]) > 0))
	return out

func _choice26(label: String, op: String, mode: String) -> Dictionary:
	return {"label": label, "arg": {"op": op, "mode": mode}}

func _can_discard_monster26(slot: int) -> bool:
	return slot != battle and not monsters[slot].has("virtual_zone15") and not bool(monsters[slot].get("death_pending", false))

func _has_discard_target26() -> bool:
	for slot in monsters.size():
		if _can_discard_monster26(slot):
			return true
	return shop.any(func(id): return int(id) >= 0)

func _add_combat_choice26(out: Array, step: Dictionary, zone: String, index: int, label: String) -> void:
	if step.op == "pink_egg26":
		var id: int = index if zone == "player" else int(monsters[index].id)
		out.append({"label": "Положить яйцо · " + label, "arg": {"op": "pink_egg26", "zone": zone, "target": index, "remove": false}})
		if _egg_count(zone, id) > 0:
			out.append({"label": "Убрать яйцо · " + label, "arg": {"op": "pink_egg26", "zone": zone, "target": index, "remove": true}})
	else:
		var selected: Variant = resolving.get("blood_first26")
		var source: Variant = index if zone == "player" else monsters[index]
		if not is_same(selected, source):
			out.append({"label": label, "arg": {"op": "blood_damage26", "zone": zone, "target": index}})

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"nickel_target26":
			resolving["nickel_target26"] = int(step.target)
		"nickel_coins26":
			_gain_coins(int(resolving.nickel_target26), int(resolving.automation_roll))
		"void_mode26":
			if step.mode == "hand":
				if _item_count(owner, 523) == 0:
					var count: int = hands[owner].size()
					discards.loot.append_array(hands[owner])
					hands[owner].clear()
					_draw_loot(owner, count)
			else:
				_insert_card_steps([{"op": "discard_monster", "targets": "void_table26"}])
		"holy_save26":
			_holy_saves[int(step.target)] = int(step.target)
		"gimpy26":
			match str(step.mode):
				"coins": _gain_coins(owner, 2)
				"loot": _insert_card_steps([{"op": "loot"}, {"op": "discard_loot", "targets": "own_hand"}])
				"attack": super._apply_card_step({"op": "temporary_attack", "amount": 2})
		"pink_egg26":
			_pink_egg26(step)
		"book_damage26":
			if int(resolving.automation_roll) >= 5:
				_insert_card_steps([{"op": "damage", "targets": "damage_targets"}])
		"book_loot26":
			_draw_loot(owner, 1)
			_draw_loot(int(step.target), 1)
		"sibling26":
			_sibling_pending26.append(int(step.target))
		"loot_cost26":
			discards.loot.append(int(hands[owner].pop_at(int(step.item))))
			if int(resolving.get("loot_cost_left26", 1)) > 1:
				resolving.loot_cost_left26 = int(resolving.loot_cost_left26) - 1
				_insert_card_steps([{"op": "loot_cost26", "targets": "own_hand", "required": true}])
		"paid_effect26":
			resolving["paid_effect26"] = {"kind": "item", "card": int(resolving.card), "owner": owner, "source": resolving.source,
				"automation_context": str(resolving.automation_context).get_slice("/", 1), "activation26": true}
		"ibs_small26":
			if step.mode == "coins":
				_gain_coins(owner, 3)
			elif _own_monster_attack26(owner):
				_cancel_attack25()
		"blood_at26":
			var monster: Dictionary = monsters[int(step.item)]
			monster.at = 1
			monster.erase("temporary_at")
		"blood_damage26":
			var index: int = int(step.target)
			var zone: String = str(step.zone)
			if not resolving.has("blood_first26"):
				resolving["blood_first26"] = index if zone == "player" else monsters[index]
				_insert_card_steps([{"op": "blood_damage26", "targets": "blood_targets26", "optional": true}])
			super._apply_card_step({"op": "damage", "target": index} if zone == "player" else {"op": "monster_damage", "item": index})
		"flip26":
			if int(chars[owner]) == 880:
				_enigma_back26[owner] = not bool(_enigma_back26.get(owner, false))
				_refresh_passive_stats()
			character_ready[owner] = true
			_reset_hand25(owner)
		"capricious26":
			if step.mode == "loot":
				_bonus_loot_plays[owner] = int(_bonus_loot_plays[owner]) + 1
			else:
				_insert_card_steps([{"op": "discard_shop", "targets": "shop_items"}])
		"glitch_copy26":
			var source: Dictionary = resolving.source
			var end := str(resolving.automation_context) == "turn_end"
			if _source_item_in_play(source):
				_copy_item14(int(shop[int(step.item)]), end)
				if end:
					source["copy_until_owner21"] = owner
					source["copy_until_turn21"] = turn_serial
		"glitch_recharge26":
			if str(resolving.automation_context) == "turn_end":
				resolving.source.tapped = false
		"soulbond26":
			var target: int = int(step.target)
			hp[target] = 0
			_last_player_killer[target] = owner
			if not _death_queue.is_empty() and target not in _death_queue:
				_death_queue.append(target)
		_:
			super._apply_card_step(step)

func _own_monster_attack26(seat: int) -> bool:
	return seat == current and battle_player < 0 and (battle >= 0 or stack.any(func(entry): return entry.kind == "attack"))

func _ibs_can_cancel26(effect: Dictionary) -> bool:
	return effect.kind == "loot" or (effect.kind == "item" and not bool(effect.get("conditional", false)) and FSData.card(int(effect.card)).get("kind", "") != "character")

func _activate_starter26(seat: int, source: Dictionary, mode: String) -> bool:
	var id: int = int(source.id)
	var resume := _after_stack if phase == "priority" else phase
	var effect := {"kind": "item", "card": id, "owner": seat, "source": source, "activation26": true}
	if mode.is_empty():
		var price := _tap_price24()
		if (id not in CardAutomation.Packet26.TAP and id not in CardAutomation.Packet27.TAP) or (price == 0 and bool(source.tapped)) or int(coins[seat]) < price:
			return false
		if id == 887 and (battle < 0 or monsters[battle].has("virtual_zone15")):
			return false
		if price > 0:
			coins[seat] = int(coins[seat]) - price
			bank += price
		else:
			source.tapped = true
	else:
		var modes: Dictionary = CardAutomation.Packet26.PAID.get(id, {})
		if not modes.has(mode):
			return false
		var cost: Array = modes[mode]
		if int(coins[seat]) < int(cost[0]) or int(source.counters) < int(cost[1]) or hands[seat].size() < int(cost[2]):
			return false
		if (int(cost[2]) > 0 and _item_count(seat, 523) > 0) or (mode == "ibs_cancel26" and not stack.any(_ibs_can_cancel26)):
			return false
		coins[seat] = int(coins[seat]) - int(cost[0])
		bank += int(cost[0])
		source.counters = int(source.counters) - int(cost[1])
		effect["automation_context"] = mode
		if int(cost[2]) > 0:
			effect["automation_context"] = "loot_cost26/" + mode
			effect["loot_cost_left26"] = int(cost[2])
			effect["_resume"] = resume
			_begin_resolving(effect)
			_advance_card_automation()
		else:
			_push_starter26(effect, resume)
	if mode.is_empty():
		_push_starter26(effect, resume)
	_refresh_passive_stats()
	revision += 1
	_check_bonuses()
	_check_win()
	return true

func _push_starter26(effect: Dictionary, resume: String) -> void:
	var seat: int = int(effect.owner)
	_push(effect, resume)
	_room_activations[seat] = int(_room_activations.get(seat, 0)) + 1
	_emit_passives("activate", {"seat": seat, "card": int(effect.card)})

func _pink_egg26(step: Dictionary) -> void:
	var zone: String = str(step.zone)
	var target: int = int(step.target)
	if zone == "monster":
		target = int(monsters[target].id)
	if not bool(step.remove):
		_place_egg(zone, target, "white")
		return
	var eggs: Dictionary = _eggs_players[target] if zone == "player" else _eggs_monsters[target]
	for color in ["white", "red", "black"]:
		if int(eggs.get(color, 0)) > 0:
			eggs[color] = int(eggs[color]) - 1
			break
	_refresh_passive_stats()

func _egg_death(zone: String, target: int, killer: int) -> void:
	if _card_automation_enabled() and target >= 0:
		var count := _egg_count(zone, target)
		if count > 0:
			for owner in players.size():
				for source: Dictionary in _ability_items20(owner):
					if int(source.id) != 859:
						continue
					for recipient in players.size():
						if _egg_count("player", recipient) == 0:
							_queue_passive(recipient, 859, source, [PassiveRules.operation("loot", count)])
	super._egg_death(zone, target, killer)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	var seat: int = int(data.get("seat", -1))
	match event:
		"turn_end":
			if int(chars[current]) == 848 and false in character_ready:
				_queue_packet15(current, 848, {}, event)
			for source: Dictionary in _ability_items20(current):
				if int(source.id) == 871 or int(source.get("physical_id13", source.id)) == 883:
					_queue_packet15(current, 883 if int(source.get("physical_id13", source.id)) == 883 else 871, source, event)
			_sibling_pending26.clear()
		"turn_start":
			for source: Dictionary in _ability_items20(current):
				if int(source.id) == 883:
					_queue_packet15(current, 883, source, event)
		"attack_declared":
			_sibling_reward26 = _sibling_pending26.duplicate()
			_sibling_pending26.clear()
			for partner in _sibling_reward26:
				if partner not in _coop_partners20:
					_coop_partners20.append(partner)
		"damage":
			if seat >= 0:
				for source: Dictionary in _ability_items20(seat):
					if int(source.id) == 855:
						_queue_packet15(seat, 855, source, event)
					elif int(source.id) == 875:
						_queue_passive(seat, 875, source, [PassiveRules.operation("counter")])
			if bool(data.get("combat", false)):
				_book_combat26(int(data.get("attacker", -1)))
		"combat_monster_damage":
			_book_combat26(seat)
		"monster_death":
			if seat >= 0:
				for source: Dictionary in _ability_items20(seat):
					if int(source.id) in [861, 871, 877]:
						_queue_packet15(seat, int(source.id), source, event)
		"death", "after_death":
			if seat >= 0:
				for source: Dictionary in _ability_items20(seat):
					if (int(source.id) == 885 and event == "death") or (int(source.id) == 881 and event == "after_death"):
						_queue_packet15(seat, int(source.id), source, event)

func _book_combat26(seat: int) -> void:
	if seat >= 0:
		for source: Dictionary in _ability_items20(seat):
			if int(source.id) == 861:
				_queue_packet15(seat, 861, source, "book_damage26")

func _refresh_passive_stats() -> void:
	if _card_automation_enabled():
		for seat in chars.size():
			if int(chars[seat]) != 880:
				_enigma_back26.erase(seat)
			var enigma: int = int(bool(_enigma_back26.get(seat, false)))
			var change: int = enigma - int(_enigma_applied26.get(seat, 0))
			if change != 0:
				_enigma_applied26[seat] = enigma
				attack[seat] = maxi(0, int(attack[seat]) + change)
				max_hp[seat] = maxi(1, int(max_hp[seat]) - change)
			var souls_on_character: int = soul_cards[seat].find_custom(func(entry): return bool(entry.get("character_soul26", false)))
			if int(chars[seat]) == 848 and souls_on_character < 0:
				soul_cards[seat].append({"id": 848, "value": 1, "character_soul26": true})
				souls[seat] = int(souls[seat]) + 1
			elif int(chars[seat]) != 848 and souls_on_character >= 0:
				soul_cards[seat].remove_at(souls_on_character)
				souls[seat] = int(souls[seat]) - 1
	super._refresh_passive_stats()
