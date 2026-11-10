extends "res://games/four_souls/logic/fs_monster18_automation.gd"
## Пассивные условия409–451, случайная закрытая кража и выбор места Утопца.
func _card_choices() -> Array:
	var out := super._card_choices()
	var step := _card_step()
	if step.is_empty():
		return out
	var owner: int = int(resolving.owner)
	match str(step.get("targets", "")):
		"other_hands19":
			for seat in active_seats():
				if seat != owner and not hands[seat].is_empty():
					out.append({"label": name_of(seat), "arg": {"op": "random_loot19", "target": seat}})
		"bloat_slots19":
			for slot: int in _bloat_slots19():
				out.append({"label": "Слот монстров %d" % (slot + 1), "arg": {"op": "bloat_place19", "item": slot}})
	return out

func _bloat_slots19() -> Array:
	var slots := []
	for slot in mini(maxi(monster_slots, monsters.size()), monsters.size() + 1):
		if slot == battle:
			continue
		if slot >= monsters.size() or (int(monsters[slot].hp) > 0 and int(monsters[slot].id) not in [272, 279, 299, 312, 913, 914] and not _untargetable(int(monsters[slot].id))):
			slots.append(slot)
	return slots


func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	match str(step.op):
		"random_loot19":
			var victim: int = int(step.target)
			if not hands[victim].is_empty():
				var index := _rng.randi_range(0, hands[victim].size() - 1)
				hands[owner].append(hands[victim].pop_at(index))
		"roller_damage19":
			_damage_player(int(resolving.automation_data.get("seat", owner)), int(step.amount), {"monster": int(resolving.card)})
		"roller_coins19":
			_gain_coins(owner, int(step.amount))
		"roller_heal19":
			if not dead[owner] and int(hp[owner]) > 0:
				hp[owner] = mini(int(max_hp[owner]), int(hp[owner]) + 1)
		"recharge_all":
			var corrected := step.duplicate()
			if int(corrected.target) == -1:
				corrected.target = owner
			super._apply_card_step(corrected)
		"bloat_prepare19":
			var found := -1
			for id: int in decks.monster:
				if FSData.card(id).get("key", "") == "bloat":
					found = id
					break
			if found >= 0 and not _bloat_slots19().is_empty():
				resolving["bloat_id19"] = found
				_insert_card_steps([{"op": "bloat_place19", "targets": "bloat_slots19"}])
			else:
				_shuffle(decks.monster)
		"bloat_place19":
			var id: int = int(resolving.bloat_id19)
			if id in decks.monster:
				decks.monster.erase(id)
				_place_encounter_monster(id, int(step.item))
				_shuffle(decks.monster)
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var own_attack: bool = battle >= 0 and battle < monsters.size() and is_same(monsters[battle], source)
		var own_death: bool = event == "monster_death" and _same_monster20(source, data)
		var face: int = int(data.get("value", 0))
		var trigger := false
		var receiver := current
		match id:
			410:
				trigger = own_attack and event == "attack_roll" and face == 3
				receiver = int(data.get("seat", current))
			416, 418, 429, 432, 442:
				trigger = own_death
			419:
				trigger = own_attack and event == "attack_roll" and face == 6
			421:
				if event == "damage" and _same_damage_source20(source, data):
					source.hp = mini(_monster_max15(source), int(source.hp) + 1)
			433:
				trigger = event == "combat_monster_damage" and _same_monster20(source, data)
				receiver = int(data.get("seat", current))
			434:
				if event == "monster_damage" and _same_monster20(source, data):
					if int(source.get("damage_turn19", -1)) != turn_serial:
						source["damage_turn19"] = turn_serial
						source["damage_count19"] = 0
					source.damage_count19 = int(source.damage_count19) + 1
					if int(source.damage_count19) % 2 == 0:
						source.dc = int(source.dc) + 1
						source["temporary_dc"] = int(source.get("temporary_dc", 0)) + 1
			435, 439, 440, 445, 446, 447, 448, 449:
				var required: int = {435: 1, 439: 5, 440: 2, 445: 4, 446: 6, 447: 1, 448: 2, 449: 5}[id]
				trigger = event == "roll" and face == required
				receiver = int(data.get("seat", current))
			436:
				trigger = event == "roll" and face == 6 and int(data.get("seat", -1)) == current
			437:
				if event == "roll" and face == 4:
					for monster: Dictionary in monsters:
						if monster.has("virtual_zone15"):
							continue
						monster.at = int(monster.at) + 1
						monster["temporary_at"] = int(monster.get("temporary_at", 0)) + 1
			438:
				trigger = event == "activate"
				receiver = int(data.get("seat", current))
			443, 444:
				trigger = own_attack and event == "attack_roll" and face == (5 if id == 443 else 6)
				receiver = int(data.get("seat", current))
		if trigger:
			_queue_packet15(receiver, id, source, event, data)

func _apply_combat(effect: Dictionary) -> void:
	if _card_automation_enabled():
		var id: int = int(effect.get("card", -1))
		if bool(effect.hit) and id == 411 and int(effect.value) in [4, 5]:
			effect.damage = 0
		if not bool(effect.hit) and id == 416 and int(effect.value) == 1:
			effect.damage = int(effect.damage) * 2
	super._apply_combat(effect)

func _monster_evasion(monster: Dictionary) -> int:
	return super._monster_evasion(monster) + (1 if _card_automation_enabled() and int(monster.id) == 413 and int(monster.hp) <= 2 else 0)

func _printed_monster_reward(id: int) -> Dictionary:
	var reward := super._printed_monster_reward(id)
	if _card_automation_enabled() and id in CardAutomation.Monster19.IDS:
		reward = reward.duplicate()
		reward.erase("manual_death")
	return reward
