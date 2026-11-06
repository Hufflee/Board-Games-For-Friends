extends SceneTree
## Разовая проверка (06.11): карты, у которых выбор цели не первый шаг плана.
const CardAutomation := preload("res://games/four_souls/logic/fs_card_automation.gd")
const Packet26 := preload("res://games/four_souls/logic/fs_packet26_cards.gd")
const TARGETING := ["players", "other_players", "damage_targets", "items", "rolls", "own_destroy", "all_destroyable", "steal_or_shop", "living_others17", "nonactive26"]
func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/manifest.json"))
	var out: Array = []
	for card in data.cards:
		var id: int = int(card.id)
		var kind: String = str(card.kind)
		var contexts: Array = [""]
		if kind == "loot":
			if not CardAutomation.handles({"kind": "loot", "card": id}):
				continue
		elif kind in ["treasure", "eternal"]:
			if not CardAutomation.handles({"kind": "item", "card": id}) and not CardAutomation.handles({"kind": "item", "card": id, "automation_context": ""}):
				continue
			for mode in Packet26.PAID.get(id, {}):
				contexts.append(mode)
		else:
			continue
		for context in contexts:
			var plan: Array = CardAutomation.plan(id, context)
			for i in plan.size():
				var step: Dictionary = plan[i]
				if step.has("targets"):
					if i > 0:
						out.append("%d %s [%s] шаг %d: %s → %s" % [id, str(card.name).split("/")[0], context, i, str(plan.slice(0, i).map(func(s): return s.op)), str(step.targets)])
					break
	var f := FileAccess.open("res://build/logs/late_targets28.txt", FileAccess.WRITE)
	for line in out:
		f.store_line(line)
	f.close()
	print("LATE ", out.size())
	quit()
