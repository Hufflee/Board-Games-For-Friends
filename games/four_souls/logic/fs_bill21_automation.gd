extends "res://games/four_souls/logic/fs_packet21_automation.gd"
## Трёхдолларовая банкнота: отдельный бросок до нанесения каждого события урона.
func _intercept_damage16(pending: Dictionary) -> bool:
	if _card_automation_enabled() and int(pending.get("damage", 0)) > 0:
		var owner: int = int(pending.get("owner", -1))
		var checked: Array = pending.get("bill_checked21", pending.get("context", {}).get("bill_checked21", pending.get("arg", {}).get("bill_checked21", [])))
		if owner >= 0 and owner < players.size():
			for source: Dictionary in _ability_items20(owner):
				var physical: int = int(source.get("physical_id13", source.id))
				if int(source.id) != 37 or physical in checked:
					continue
				if battle >= 0 and battle < monsters.size() and str(pending.get("kind", "")) == "combat" and monsters[battle].has("virtual_zone15"):
					continue
				checked.append(physical)
				pending["bill_checked21"] = checked
				if pending.has("context"):
					pending.context["bill_checked21"] = checked
				if pending.has("arg"):
					pending.arg["bill_checked21"] = checked
				_push(pending, _after_stack if phase == "priority" else phase)
				_begin_resolving({"kind": "item", "card": 37, "owner": owner, "source": source, "automation_context": "damage21", "automation_data": {"pending": pending}})
				_advance_card_automation()
				return true
	return super._intercept_damage16(pending)

func _apply_card_step(step: Dictionary) -> void:
	if str(step.op) == "bill_result21":
		var value: int = int(resolving.get("automation_roll", 0))
		var pending: Dictionary = resolving.automation_data.pending
		if value in [4, 5]:
			var owner: int = int(resolving.owner)
			hp[owner] = mini(int(max_hp[owner]), int(hp[owner]) + 1)
		elif value == 6:
			pending.damage = int(pending.damage) + 1
	else:
		super._apply_card_step(step)
