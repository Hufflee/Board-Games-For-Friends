extends "res://games/four_souls/logic/fs_treasure20_automation.gd"
## Прототип: три столбца настоящего текста. Передача не является новым получением.
const PROTOTYPE_COLUMNS20 := [
	["В начале своего хода", "Когда игрок выбрасывает3", "Поворот и заплати3¢"],
	["Возьми2добычи", "+1здоровья до конца хода", "Получи6¢", "Получи1урона"],
	["Отдай это другому игроку", "Получи1урона", "Сбрось карту добычи"]
]

func _card_choices() -> Array:
	var out := super._card_choices()
	var category: String = str(_card_step().get("targets", ""))
	for column in 3:
		if category == "prototype_column%d_20" % column:
			for index in PROTOTYPE_COLUMNS20[column].size():
				out.append({"label": str(PROTOTYPE_COLUMNS20[column][index]), "arg": {"op": "prototype_column20", "column": column, "value": index}})
	if category == "prototype_paid20":
		var texts: Array = _prototype_texts21()
		for index in texts.size():
			var text: Dictionary = texts[index]
			if int(text.begin) == 2:
				out.append({"label": str(PROTOTYPE_COLUMNS20[1][int(text.effect)]) + "; " + str(PROTOTYPE_COLUMNS20[2][int(text.tail)]), "arg": {"op": "prototype_run20", "index": index}})
	if category == "prototype_receivers20" and not bool(resolving.source.get("eternal", false)):
		for seat in active_seats():
			if seat != int(resolving.owner):
				out.append({"label": name_of(seat), "arg": {"op": "prototype_give20", "target": seat}})
	var chooser := _card_choice_owner() if _card_automation_active() else current
	return out.filter(func(choice): return _choice_target20(choice.arg, chooser))

func _apply_card_step(step: Dictionary) -> void:
	var owner: int = int(resolving.owner)
	var source: Dictionary = resolving.get("source", {})
	match str(step.op):
		"prototype_column20":
			if not resolving.has("prototype_pending20"):
				resolving["prototype_pending20"] = {}
			resolving.prototype_pending20[["begin", "effect", "tail"][int(step.column)]] = int(step.value)
		"prototype_commit20":
			if _source_item_in_play(source):
				if not source.has("prototype_texts20"):
					source["prototype_texts20"] = []
				source.prototype_texts20.append(resolving.prototype_pending20.duplicate())
		"prototype_run20":
			var text: Dictionary = resolving.get("automation_data", {}).get("prototype20", {})
			if text.is_empty():
				var index: int = int(step.get("index", -1))
				var templates := _prototype_texts21()
				if index < 0 or index >= templates.size():
					return
				text = templates[index]
			var effects: Array = [{"op": "loot", "amount": 2}, {"op": "prototype_health20"}, {"op": "coins", "amount": 6}, {"op": "damage", "target": owner, "amount": 1}]
			var tails: Array = [{"op": "prototype_give20", "targets": "prototype_receivers20"}, {"op": "damage", "target": owner, "amount": 1}, {"op": "prototype_discard20"}]
			_insert_card_steps([effects[int(text.effect)], tails[int(text.tail)]])
		"prototype_health20":
			_grant_temporary_health(owner, 1)
		"prototype_discard20":
			resolving["choice_owner"] = owner
			_insert_card_steps([{"op": "discard_victim_card16", "targets": "victim_hand16"}])
		"prototype_give20":
			var index: int = items[owner].find(source)
			if index >= 0 and not bool(source.eternal):
				items[int(step.target)].append(_remove_item(owner, index))
		_:
			super._apply_card_step(step)

func _gain_item(seat: int, id: int, eternal: bool = false) -> void:
	super._gain_item(seat, id, eternal)
	if _card_automation_enabled() and id == 1:
		var source: Dictionary = items[seat].back()
		_queue_packet15(seat, 1, source, "gain_item")

func _treasure12_passives(event: String, data: Dictionary) -> void:
	super._treasure12_passives(event, data)
	if not _card_automation_enabled():
		return
	for owner in players.size():
		for source: Dictionary in _ability_items20(owner).duplicate():
			if int(source.id) != 1:
				continue
			for text: Dictionary in source.get("prototype_texts20", []):
				if (int(text.begin) == 0 and event == "turn_start" and owner == current) or (int(text.begin) == 1 and event == "roll" and int(data.get("value", 0)) == 3):
					_queue_packet15(owner, 1, source, "generated20", {"prototype20": text.duplicate()})

func _prototype_texts21() -> Array:
	return resolving.get("prototype_texts21", resolving.get("source", {}).get("prototype_texts20", []))

func _item_kind20(item: Dictionary) -> String:
	if int(item.id) == 1:
		return "tap" if item.get("prototype_texts20", []).any(func(text): return int(text.begin) == 2) else "passive"
	return super._item_kind20(item)

