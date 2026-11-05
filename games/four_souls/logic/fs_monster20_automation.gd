extends "res://games/four_souls/logic/fs_monster19_automation.gd"
## Конец ряда монстров: собственный источник урона, штрафы и распределение двух единиц.
func _apply_card_step(step: Dictionary) -> void:
	var data: Dictionary = resolving.get("automation_data", {})
	match str(step.op):
		"slayer_damage20":
			var slayer: int = int(data.get("seat", current))
			if slayer >= 0 and slayer < players.size():
				_damage_player(slayer, 1, {"monster": 463})
		"left_damage20":
			_damage_player((current + 1) % players.size(), 1, {"attacker": current})
		"left_mirror20":
			_damage_player((current + 1) % players.size(), int(data.amount), {"monster": 466})
		"split_prepare20":
			resolving["split_left16"] = 2
			_insert_card_steps([{"op": "split_damage16", "targets": "split_damage16"}])
		_:
			super._apply_card_step(step)

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for source: Dictionary in monsters.duplicate():
		var id: int = int(source.id)
		var own_death: bool = event == "monster_death" and _same_monster20(source, data)
		var trigger := false
		var receiver := current
		match id:
			453:
				trigger = event == "damage" and _same_damage_source20(source, data)
				receiver = int(data.get("seat", current))
			454, 455, 463, 465:
				trigger = own_death
			456:
				if event == "monster_damage" and _same_monster20(source, data):
					source.at = int(source.at) + 1
					source["temporary_at"] = int(source.get("temporary_at", 0)) + 1
			460:
				trigger = event == "damage" and bool(data.get("combat", false)) and _same_damage_source20(source, data)
			464:
				trigger = event == "combat_monster_damage" and _same_monster20(source, data) and int(data.get("value", 0)) == 6
			466:
				trigger = event == "damage" and _same_damage_source20(source, data) and int(data.get("seat", -1)) == current
		if trigger:
			_queue_packet15(receiver, id, source, event, data)

func _apply_combat(effect: Dictionary) -> void:
	if _card_automation_enabled() and int(effect.get("card", -1)) == 461 and not bool(effect.hit) and int(effect.value) == 2:
		effect.damage = int(effect.damage) + 1
	super._apply_combat(effect)

func _printed_monster_reward(id: int) -> Dictionary:
	var reward := super._printed_monster_reward(id)
	if _card_automation_enabled() and id in preload("res://games/four_souls/logic/fs_monster20_cards.gd").IDS:
		reward = reward.duplicate()
		reward.erase("manual_death")
	return reward

func _damage_owner18() -> int:
	if _card_automation_enabled() and int(resolving.get("card", -1)) == 465:
		return int(resolving.owner)
	return super._damage_owner18()
