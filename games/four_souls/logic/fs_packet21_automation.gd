extends "res://games/four_souls/logic/fs_rooms20_automation.gd"
## Группа21 в работе: проверки только после реализации всех40карт.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	var category: String = str(step.get("targets", ""))
	var owner: int = int(resolving.get("owner", current))
	match category:
		"shield_monsters21", "shield_targets21":
			if category == "shield_targets21":
				for seat in players.size():
					if not dead[seat]:
						out.append({"label": name_of(seat), "arg": {"op": str(step.op), "zone": "player", "target": seat}})
			for slot in monsters.size():
				if not monsters[slot].has("virtual_zone15") and not bool(monsters[slot].get("ambush_event20", false)):
					out.append({"label": FSData.title(int(monsters[slot].id)), "arg": {"op": str(step.op), "zone": "monster", "target": int(monsters[slot].id), "physical_id20": int(monsters[slot].get("physical_id20", monsters[slot].id))}})
		"bag_counters21":
			for amount in range(1, int(resolving.source.counters) + 1):
				out.append({"label": "Сбросить %d жетонов → %s" % [amount, "1 урона монстру" if amount >= 4 else "1 добыча"], "arg": {"op": "bag_spend21", "amount": amount}})
		"battery_items21":
			for seat in players.size():
				for index in items[seat].size():
					var source: Dictionary = items[seat][index]
					if bool(source.tapped) and int(source.id) != 44 and not is_same(source, resolving.source):
						out.append({"label": name_of(seat) + " · " + FSData.title(int(source.id)), "arg": {"op": "battery_item21", "target": seat, "item": index}})
			if out.all(func(choice): return str(choice.arg.op) == "skip_choice"):
				out.clear()
		"discard_monsters21":
			for id in discards.monster:
				if FSData.card(int(id)).get("kind", "") == "monster":
					out.append({"label": FSData.title(int(id)), "arg": {"op": "raise_monster21", "card": int(id)}})
		"peek_monsters21":
			for id in peek.get("cards", []):
				out.append({"label": FSData.title(int(id)), "arg": {"op": "peek_monster21", "card": int(id)}})
		"place_monster21":
			for slot in mini(maxi(monster_slots, monsters.size()), monsters.size() + 1):
				if slot != battle and (slot >= monsters.size() or int(monsters[slot].id) not in [272, 279, 299, 312, 913, 914]):
					out.append({"label": "Слот монстров %d" % (slot + 1), "arg": {"op": str(step.op), "item": slot}})
		"give_loot21":
			for index in hands[owner].size():
				out.append({"label": FSData.title(int(hands[owner][index])), "arg": {"op": "give_loot21", "item": index}})
		"offer_loot21":
			out.append({"label": "Взять добычу и отдать карту", "arg": {"op": "offer_loot_accept21"}})
		"counter_items21":
			out.append({"label": "Получить 1¢", "arg": {"op": "coins", "target": owner, "amount": 1}})
			for seat in players.size():
				for index in items[seat].size():
					var source: Dictionary = items[seat][index]
					if not bool(source.eternal):
						for change in [-1, 1]:
							if change > 0 or int(source.counters) > 0:
								out.append({"label": name_of(seat) + " · " + FSData.title(int(source.id)) + (" · +1 жетон" if change > 0 else " · −1 жетон"), "arg": {"op": "counter_item21", "target": seat, "item": index, "amount": change}})
	if int(resolving.get("card", -1)) == 43:
		var damaged: int = int(resolving.get("automation_data", {}).get("physical_id20", resolving.get("automation_data", {}).get("card", -1)))
		out = out.filter(func(choice): return str(choice.arg.get("op", "")) != "monster_damage" or int(monsters[int(choice.arg.item)].get("physical_id20", monsters[int(choice.arg.item)].id)) != damaged)
	return out.filter(func(choice): return _choice_target20(choice.arg, _card_choice_owner() if _card_automation_active() else current))

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	match str(step.op):
		"shield_event21", "shield_one21":
			var shield := {"zone": str(step.zone), "target": int(step.target), "amount": 1, "turn": turn_serial}
			if str(step.op) == "shield_event21":
				shield["cap"] = 0
			_next_hit_shields.append(shield)
		"splash21":
			var steps: Array = []
			for seat in players.size():
				if not bool(step.get("exclude_owner", false)) or seat != owner:
					steps.append({"op": "damage", "target": seat, "amount": int(step.amount)})
			for slot in monsters.size():
				if not monsters[slot].has("virtual_zone15") and not bool(monsters[slot].get("ambush_event20", false)):
					steps.append({"op": "monster_damage", "item": slot, "amount": int(step.amount)})
			_insert_card_steps(steps)
		"abel_result21":
			if int(resolving.get("automation_roll", 0)) >= 4:
				_insert_card_steps([{"op": "damage", "targets": "damage_targets"}])
		"battery_prepare21":
			resolving["recharges21"] = 3
			_insert_card_steps([{"op": "battery_item21", "targets": "battery_items21", "optional": true}])
		"battery_item21":
			items[int(step.target)][int(step.item)].tapped = false
			resolving.recharges21 = int(resolving.recharges21) - 1
			if int(resolving.recharges21) > 0:
				_insert_card_steps([{"op": "battery_item21", "targets": "battery_items21", "optional": true}])
		"battery_self21":
			if _source_item_in_play(source):
				source.tapped = false
		"bag_spend21":
			source.counters = int(source.counters) - int(step.amount)
			_insert_card_steps([{"op": "monster_damage", "targets": "monsters"}] if int(step.amount) >= 4 else [{"op": "loot"}])
		"low_rolls21":
			_low_rolls21 = turn_serial
		"give_source21":
			for holder in players.size():
				for index in items[holder].size():
					if is_same(items[holder][index], source):
						items[int(step.target)].append(_remove_item(holder, index))
						_refresh_passive_stats()
						return
		"pandora_result21":
			if int(resolving.get("automation_roll", 0)) < int(source.counters):
				for index in range(items[owner].size() - 1, -1, -1):
					if not bool(items[owner][index].eternal):
						_destroy_item(owner, index)
		"raise_monster21", "peek_monster21":
			resolving["placing_monster21"] = int(step.card)
			_insert_card_steps([{"op": "place_monster21", "targets": "place_monster21"}])
		"place_monster21":
			var id: int = int(resolving.placing_monster21)
			if str(peek.get("deck", "")) == "monster" and id in peek.get("cards", []):
				decks.monster.erase(id)
				peek.cards.erase(id)
				if peek.cards.is_empty():
					peek = {}
			else:
				discards.monster.erase(id)
			if FSData.card(id).get("kind", "") == "event":
				_push({"kind": "event", "owner": current, "card": id}, "effect")
			else:
				_place_encounter_monster(id, int(step.item))
		"level_start21":
			var steps: Array = []
			if int(source.counters) >= 8:
				steps.append({"op": "damage", "targets": "damage_targets"})
			if int(source.counters) >= 10:
				steps.append_array([{"op": "auto_roll"}, {"op": "level_death21"}])
			_insert_card_steps(steps)
		"level_death21":
			if int(resolving.get("automation_roll", 0)) <= 3:
				hp[owner] = 0
		"six_soul21":
			if int(source.counters) >= 6:
				if bool(source.get("room_item20", false)):
					_destroy_room20(source, current, true)
				else:
					for holder in players.size():
						for index in items[holder].size():
							if is_same(items[holder][index], source):
								var converted := _remove_item(holder, index, true)
								_gain_soul_card(holder, {"id": int(converted.id), "value": 1})
		"gift_soul21":
			resolving["given_to"] = int(step.target)
			if not bool(resolving.get("loot_copy14", false)):
				_gain_soul_card(int(step.target), {"id": int(resolving.card), "value": 1})
		"counter_item21":
			var chosen: Dictionary = items[int(step.target)][int(step.item)]
			chosen.counters = maxi(0, int(chosen.counters) + int(step.amount))
			_refresh_passive_stats()
		"give_loot_prepare21":
			if not hands[owner].is_empty():
				_insert_card_steps([{"op": "give_loot_target21", "targets": "other_players"}, {"op": "give_loot21", "targets": "give_loot21"}])
		"give_loot_target21":
			resolving["recipient21"] = int(step.target)
		"give_loot21":
			hands[int(resolving.recipient21)].append(int(hands[owner].pop_at(int(step.item))))
		"offer_loot_prepare21":
			for offset in range(players.size() - 1, 0, -1):
				var recipient := (owner + offset) % players.size()
				_queue_packet15(recipient, 73, source, "offer21", {"giver": owner})
		"offer_loot_accept21":
			_draw_loot(owner, 1)
			resolving["recipient21"] = int(resolving.automation_data.giver)
			_insert_card_steps([{"op": "give_loot21", "targets": "give_loot21"}])
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for owner in players.size():
		for source: Dictionary in _ability_items20(owner).duplicate():
			var id: int = int(source.id)
			var trigger := false
			if id == 43:
				trigger = event == "combat_monster_damage" and int(data.get("seat", -1)) == owner and int(data.get("amount", 0)) > 0
			if id in [51, 59, 78, 82]:
				trigger = event == "turn_start" and owner == current
			if id in [57, 82] and event == "turn_end" and owner == current:
				trigger = true
			if id in [52, 57] and event == "death" and int(data.get("seat", -1)) == owner:
				trigger = true
			if id == 64:
				if event == "death":
					_queue_passive(owner, id, source, [PassiveRules.operation("counter")])
				trigger = event == "turn_start" and owner == current and int(source.counters) >= 8
			if id == 81:
				trigger = event == "death" and int(data.get("killer", -1)) == owner and int(data.get("seat", -1)) != owner
			if trigger:
				_queue_packet15(owner, id, source, event, data)

func _card_die(seat: int, attack_roll: bool = false) -> int:
	var value := super._card_die(seat, attack_roll)
	return 1 if _card_automation_enabled() and _low_rolls21 == turn_serial and value in [2, 3] else value

func _permitted_player_attack_targets() -> Array:
	var out := super._permitted_player_attack_targets()
	if _card_automation_enabled() and _item_count(current, 81) > 0 and not attacked and attack_left > _optional_blind17 and _forced_deck_remaining() <= 0:
		for target in players.size():
			if target != current and not dead[target] and int(hp[target]) > 0 and int(souls[target]) > int(souls[current]) and target not in out:
				out.append(target)
	return out

func _pvp_defense16(target: int) -> int:
	if _card_automation_enabled() and _item_count(current, 81) > 0 and int(souls[target]) > int(souls[current]):
		return 3
	return super._pvp_defense16(target)
