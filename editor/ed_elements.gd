extends RefCounted
## Операции таблицы карт: типизированные колонки без скрытой потери данных и удаление строк через undo.

var document: RefCounted

func _init(doc: RefCounted) -> void:
	document = doc

func add_column(deck_index: int, name_value: String, type: String) -> String:
	var id := name_value.strip_edges()
	if id.is_empty() or id.length() > 128 or id == "copies" or type not in ["text", "number", "bool", "image"]:
		return "Введите имя свойства и допустимый тип. «copies» зарезервировано для копий."
	if deck_index < 0 or deck_index >= document.data.elements.decks.size():
		return "Колода не найдена."
	var copy: Dictionary = document.data.duplicate(true)
	var deck: Dictionary = copy.elements.decks[deck_index]
	var columns: Array = deck.get("columns", [])
	if columns.size() >= 64 or columns.any(func(column: Dictionary): return column.id == id):
		return "Такое свойство уже есть или достигнут лимит 64 колонок."
	columns.append({"id": id, "type": type})
	deck.columns = columns
	for row: Dictionary in deck.rows:
		if not row.has(id):
			row[id] = 0 if type == "number" else (false if type == "bool" else "")
	document.replace(copy, "Добавить свойство карты")
	return ""

func remove_column(deck_index: int, index: int) -> bool:
	if deck_index < 0 or deck_index >= document.data.elements.decks.size():
		return false
	var copy: Dictionary = document.data.duplicate(true)
	var deck: Dictionary = copy.elements.decks[deck_index]
	if index < 0 or index >= deck.get("columns", []).size():
		return false
	var id := str(deck.columns[index].id)
	deck.columns.remove_at(index)
	for row: Dictionary in deck.rows:
		row.erase(id)
	document.replace(copy, "Удалить свойство карты")
	return true

func remove_row(deck_index: int, index: int) -> bool:
	if deck_index < 0 or deck_index >= document.data.elements.decks.size():
		return false
	var copy: Dictionary = document.data.duplicate(true)
	var rows: Array = copy.elements.decks[deck_index].rows
	if index < 0 or index >= rows.size():
		return false
	rows.remove_at(index)
	return document.replace(copy, "Удалить карту")

func set_owner(deck_index: int, owner: String) -> bool:
	if owner not in ["shared", "player", "team"] or deck_index < 0 or deck_index >= document.data.elements.decks.size():
		return false
	var copy: Dictionary = document.data.duplicate(true)
	var zone := ""
	var ids: Array = []
	for screen: Dictionary in copy.layout.screens:
		for item: Dictionary in screen.get("items", []):
			ids.append(str(item.get("id", "")))
			if item.get("kind") == "zone" and item.get("owner", "shared") == owner and zone.is_empty():
				zone = str(item.id)
	if zone.is_empty():
		var number := 1
		zone = "deck_zone_%d" % number
		while ids.has(zone):
			number += 1
			zone = "deck_zone_%d" % number
		if copy.layout.screens.is_empty():
			copy.layout.screens.append({"id": "main", "items": []})
		copy.layout.screens[0].items.append({"kind": "zone", "id": zone, "title": "Колода команды" if owner == "team" else "Колода", "owner": owner, "view": "pile", "free": true, "rect": [32, 160, 224, 224]})
	copy.elements.decks[deck_index]["owner"] = owner
	copy.elements.decks[deck_index]["zone"] = zone
	return document.replace(copy, "Владелец колоды и начальная зона")

func change_column_type(deck_index: int, column_index: int, type: String) -> String:
	if type not in ["text", "number", "bool", "image"] or deck_index < 0 or deck_index >= document.data.elements.decks.size():
		return "Неверный тип или колода."
	var copy: Dictionary = document.data.duplicate(true)
	var deck: Dictionary = copy.elements.decks[deck_index]
	if column_index < 0 or column_index >= deck.get("columns", []).size():
		return "Свойство не найдено."
	var id := str(deck.columns[column_index].id)
	for index in deck.rows.size():
		var row: Dictionary = deck.rows[index]
		var value: Variant = row.get(id, "")
		match type:
			"number":
				if value is bool:
					value = 1 if value else 0
				elif value is String and value.is_valid_float():
					value = float(value)
				if not preload("res://games/custom/logic/cg_def.gd")._number(value):
					return "Строка %d: «%s» нельзя преобразовать в число." % [index + 1, str(value)]
			"bool":
				if not value is bool:
					var normalized := str(value).strip_edges().to_lower()
					if normalized in ["да", "true", "1"]:
						value = true
					elif normalized in ["нет", "false", "0"]:
						value = false
					else:
						return "Строка %d: нужен флаг да/нет или 1/0." % (index + 1)
			"image":
				if not value is String or (not value.is_empty() and (not copy.get("assets", {}).has(value) or not str(copy.assets[value].get("path", "")).begins_with("assets/img/"))):
					return "Строка %d: выберите импортированный рисунок." % (index + 1)
			"text":
				value = "да" if value is bool and value else ("нет" if value is bool else str(value))
		row[id] = value
	deck.columns[column_index].type = type
	document.replace(copy, "Тип свойства карты")
	return ""
