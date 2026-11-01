class_name CGDef
extends RefCounted
## Проверка JSON-схемы пользовательской игры до запуска. Только данные, без загрузки ресурсов.

const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
const MAX_COMPONENTS := 300
const CARD_SIZES := [Vector2i(88, 136), Vector2i(114, 178), Vector2i(126, 176), Vector2i(140, 220), Vector2i(160, 240), Vector2i(140, 140), Vector2i(200, 200), Vector2i(120, 120), Vector2i(90, 90)]

static func validate(def: Dictionary) -> Dictionary:
	var result := {"errors": [], "warnings": []}
	if not _json_only(def, 0):
		result.errors.append("Игра содержит недопустимые значения или слишком глубокое вложение.")
		return result
	if def.get("format") != 1:
		result.errors.append("Поддерживается формат игры 1.")
	for key in ["meta", "elements", "layout", "rules"]:
		if not def.get(key) is Dictionary:
			result.errors.append("Нет раздела «%s»." % key)
	if not result.errors.is_empty():
		return result
	if def.layout.has("custom") and not def.layout.custom is bool:
		result.errors.append("Признак собственного стола должен быть логическим.")
	var assets: Variant = def.get("assets", {})
	if not assets is Dictionary or assets.size() > 1000:
		result.errors.append("Ассеты должны быть словарём до 1000 файлов.")
	else:
		for key: Variant in assets:
			var asset: Variant = assets[key]
			if not key is String or not _hash(str(key)) or not asset is Dictionary or not asset.get("path") is String:
				result.errors.append("Неверное описание ассета.")
				continue
			var path := str(asset.path)
			var extension := path.get_extension()
			var directory := "fonts" if extension in ["ttf", "otf"] else "img"
			if extension not in ["png", "jpg", "webp", "ttf", "otf"] or path != "assets/" + directory + "/" + str(key) + "." + extension:
				result.errors.append("Недопустимый путь ассета.")
	if str(def.meta.get("title", "")).strip_edges().is_empty():
		result.errors.append("Введите название игры.")
	for field: String in ["title", "author", "time", "description", "color"]:
		if def.meta.has(field) and (not def.meta[field] is String or str(def.meta[field]).length() > 4096):
			result.errors.append("Поле %s должно быть текстом до 4096 символов." % field)
	for field: String in ["phase_titles", "action_titles"]:
		if def.meta.has(field):
			if not def.meta[field] is Dictionary:
				result.errors.append("Названия фаз/действий должны быть словарём.")
			else:
				for title: Variant in def.meta[field].values():
					if not title is String:
						result.errors.append("Название фазы/действия должно быть текстом.")
	if def.has("box"):
		if not def.box is Dictionary:
			result.errors.append("Описание коробки должно быть объектом.")
		elif not _number(def.box.get("thickness", 0.06)) or def.box.get("template", "square") not in ["square", "tall", "wide", "small"]:
			result.errors.append("Неверная форма или толщина коробки.")
		elif not box_valid(def.box):
			result.errors.append("Неверные грани или слои коробки.")
	var seats: Variant = def.meta.get("players", [2, 8])
	if not seats is Array or seats.size() != 2:
		result.errors.append("Укажите минимальное и максимальное число игроков.")
	elif not _number(seats[0]) or not _number(seats[1]) or seats[0] < 2 or seats[1] > 8 or seats[0] > seats[1] or float(int(seats[0])) != float(seats[0]) or float(int(seats[1])) != float(seats[1]):
		result.errors.append("Число игроков должно быть от 2 до 8.")
	var phases: Variant = def.rules.get("phases", [])
	if not phases is Array or phases.is_empty():
		result.errors.append("Добавьте хотя бы одну фазу.")
		return result
	var ids := {}
	for phase: Variant in phases:
		if not phase is String or not _id(phase) or ids.has(phase):
			result.errors.append("Неверное или повторяющееся имя фазы.")
		ids[phase] = true
	var zone_ids := {}
	var zone_owners := {}
	var screens: Variant = def.layout.get("screens", [])
	if not screens is Array:
		result.errors.append("Список экранов должен быть массивом.")
		return result
	for screen: Variant in screens:
		if not screen is Dictionary or not screen.get("items", []) is Array:
			result.errors.append("Неверное описание экрана.")
			continue
		if screen.get("items", []).size() > 256:
			result.errors.append("На одном экране не больше 256 элементов.")
		for item: Variant in screen.get("items", []):
			if not item is Dictionary:
				result.errors.append("Неверный элемент раскладки.")
				continue
			if item.has("rect"):
				var rect: Variant = item.rect
				if not rect is Array or rect.size() != 4:
					result.errors.append("Положение элемента задаётся четырьмя числами.")
				else:
					var valid := true
					for coordinate: Variant in rect:
						if not _number(coordinate) or absf(float(coordinate)) > 100000:
							result.errors.append("Недопустимая координата элемента.")
							valid = false
					if valid:
						if float(rect[2]) <= 0 or float(rect[3]) <= 0:
							result.errors.append("Размеры элемента должны быть положительными.")
						if float(rect[0]) < 0 or float(rect[1]) < 48 or float(rect[0]) + float(rect[2]) > 1280 or float(rect[1]) + float(rect[3]) > 720:
							result.warnings.append("Элемент выходит за стол 1280×720 или перекрывает верхнюю полосу.")
			if item.get("kind") == "zone":
				var name_value := str(item.get("id", ""))
				if not item.get("id") is String or not _id(name_value) or zone_ids.has(name_value):
					result.errors.append("Неверная или повторяющаяся зона: %s." % name_value)
				zone_ids[name_value] = true
				zone_owners[name_value] = str(item.get("owner", "shared"))
				if item.get("owner", "shared") not in ["shared", "player", "team"]:
					result.errors.append("Неизвестный владелец зоны %s." % name_value)
	var decks: Variant = def.elements.get("decks", [])
	if not decks is Array:
		result.errors.append("Колоды должны быть массивом.")
		return result
	var components := 0
	var deck_ids := {}
	for deck: Variant in decks:
		if not deck is Dictionary or not deck.get("rows", []) is Array:
			result.errors.append("Неверная колода.")
			continue
		var deck_id := str(deck.get("id", ""))
		if not deck.get("id") is String or not _id(deck_id) or deck_ids.has(deck_id):
			result.errors.append("Неверная или повторяющаяся колода: %s." % deck_id)
		deck_ids[deck_id] = true
		if deck.has("back") and not deck.back is String:
			result.errors.append("Рубашка колоды задаётся ключом ассета.")
		var owner := str(deck.get("owner", "shared"))
		if owner not in ["shared", "player", "team"]:
			result.errors.append("Неизвестный владелец колоды.")
		var destination := str(deck.get("zone", deck_id))
		if not zone_owners.has(destination) or zone_owners.get(destination) != owner:
			result.errors.append("Начальная зона колоды должна иметь того же владельца.")
		var card_size: Variant = deck.get("size", 3)
		if not _number(card_size) or card_size < 1 or card_size > CARD_SIZES.size() or float(int(card_size)) != float(card_size):
			result.errors.append("Неизвестный размер карты в колоде %s." % deck_id)
		var columns: Variant = deck.get("columns", [])
		if not columns is Array or columns.size() > 64:
			result.errors.append("В таблице карт не больше 64 колонок.")
		else:
			var fields := {}
			for column: Variant in columns:
				if not column is Dictionary or not column.get("id") is String or str(column.id).is_empty() or str(column.id).length() > 128 or column.id == "copies" or fields.has(column.id) or column.get("type", "text") not in ["text", "number", "bool", "image"]:
					result.errors.append("Неверная или повторяющаяся колонка карт.")
					continue
				fields[column.id] = true
		if deck.has("face") and not deck.face is Dictionary:
			result.errors.append("Шаблон лица карты должен быть объектом.")
		elif deck.has("face"):
			for binding: String in ["title", "value", "text", "art", "font"]:
				if deck.face.has(binding) and not deck.face[binding] is String:
					result.errors.append("Привязка шаблона карты должна быть текстовым ключом.")
		for row: Variant in deck.get("rows", []):
			if not row is Dictionary or not _number(row.get("copies", 1)):
				result.errors.append("Неверная строка таблицы карт.")
				continue
			if row.get("copies", 1) < 1 or row.get("copies", 1) > MAX_COMPONENTS:
				result.errors.append("Количество копий карты должно быть от 1 до 300.")
				continue
			var copies := int(row.get("copies", 1))
			if float(copies) != float(row.get("copies", 1)) or copies < 1 or copies > MAX_COMPONENTS:
				result.errors.append("Количество копий карты должно быть от 1 до 300.")
			if columns is Array:
				for column: Variant in columns:
					if not column is Dictionary or not row.has(column.get("id")):
						continue
					var value: Variant = row[column.id]
					var type := str(column.get("type", "text"))
					if type == "number" and not _number(value) or type == "bool" and not value is bool or type in ["text", "image"] and not value is String:
						result.errors.append("Значение карты не соответствует типу колонки %s." % str(column.id))
			components += copies * (int(seats[1]) if owner in ["player", "team"] and seats is Array and seats.size() == 2 and _number(seats[1]) else 1)
	if components > MAX_COMPONENTS:
		result.errors.append("В первой версии не больше 300 компонентов.")
	var component_ids := deck_ids.duplicate()
	for kind: String in ["dice", "tokens"]:
		var entries: Variant = def.elements.get(kind, [])
		if not entries is Array:
			result.errors.append("Кубики/жетоны должны быть массивами.")
			continue
		for entry: Variant in entries:
			if not entry is Dictionary or not entry.get("id") is String or not _id(str(entry.get("id", ""))):
				result.errors.append("Компоненту нужен идентификатор.")
				continue
			if component_ids.has(entry.id):
				result.errors.append("Повтор идентификатора компонента.")
			component_ids[entry.id] = true
			var count: Variant = entry.get("count", 1)
			if not _number(count) or count < 1 or count > (30 if kind == "dice" else 300) or float(int(count)) != float(count):
				result.errors.append("Неверное количество компонентов.")
			if kind == "tokens" and not _number(entry.get("value", 1)):
				result.errors.append("Номинал жетона должен быть числом.")
			if kind == "tokens" and _number(count) and count >= 1 and count <= 300:
				components += int(count)
	if components > MAX_COMPONENTS:
		result.errors.append("Карты и жетоны вместе не должны превышать 300 компонентов.")
	var vars: Variant = def.rules.get("vars", [])
	if not vars is Array:
		result.errors.append("Переменные должны быть массивом.")
	else:
		var names := {}
		for v: Variant in vars:
			if not v is Dictionary or not v.get("id") is String or not _id(str(v.get("id", ""))):
				result.errors.append("Неверная переменная.")
				continue
			var name_value := str(v.id)
			if names.has(name_value):
				result.errors.append("Повтор переменной: %s." % name_value)
			names[name_value] = true
			if v.get("scope", "shared") not in ["shared", "player", "team"]:
				result.errors.append("Неизвестная область переменной %s." % name_value)
			var type := str(v.get("type", "number"))
			var initial: Variant = v.get("init", 0)
			if type not in ["number", "text", "bool"] or type == "number" and not _number(initial) or type == "text" and not initial is String or type == "bool" and not initial is bool:
				result.errors.append("Неверный тип или начальное значение переменной %s." % name_value)
	var chains: Variant = def.rules.get("chains", [])
	if def.rules.has("roles"):
		if not def.rules.roles is Array or def.rules.roles.is_empty() or def.rules.roles.size() > 16:
			result.errors.append("Роли должны быть массивом.")
		else:
			for role: Variant in def.rules.roles:
				if not role is Dictionary or not role.get("id") is String or not _id(str(role.get("id", ""))):
					result.errors.append("У роли должен быть идентификатор.")
	if not chains is Array:
		result.errors.append("Цепочки должны быть массивом.")
		return result
	for chain: Variant in chains:
		if not chain is Dictionary or not chain.get("blocks", []) is Array:
			result.errors.append("Неверная цепочка блоков.")
			continue
		var event: Variant = chain.get("event", {})
		if not event is Dictionary or event.get("type", "") not in Blocks.EVENTS:
			result.errors.append("У цепочки нет допустимой шапки события.")
			continue
		if event.has("phase") and event.phase not in phases:
			result.errors.append("Событие ссылается на удалённую фазу.")
		_walk_value(chain.get("guard", true), result, 0)
		if event.has("zone"):
			_walk_value(event.zone, result, 0)
		_walk_blocks(chain.get("blocks", []), result, phases, 0)
	return result

static func _walk_blocks(blocks: Array, result: Dictionary, phases: Array, depth: int) -> void:
	if depth > 32:
		result.errors.append("Слишком глубокое вложение блоков.")
		return
	for block: Variant in blocks:
		if not block is Dictionary:
			result.errors.append("Блок должен быть объектом JSON.")
			continue
		var op := str(block.get("op", ""))
		if not Blocks.OPS.has(op):
			result.errors.append("Неизвестный блок: %s." % op)
			continue
		for field: String in Blocks.OPS[op]:
			if not block.has(field):
				result.errors.append("В блоке %s пустое гнездо %s." % [op, field])
		if op == "phase" and block.get("phase") not in phases:
			result.errors.append("Переход в неизвестную фазу.")
		if op == "sound" and block.get("name") not in Blocks.SOUNDS:
			result.errors.append("Неизвестный встроенный звук.")
		for field: String in block:
			if field not in ["then", "else", "body", "op", "id"]:
				_walk_value(block[field], result, 0)
		for nested in ["then", "else", "body"]:
			if block.has(nested):
				if block[nested] is Array:
					_walk_blocks(block[nested], result, phases, depth + 1)
				else:
					result.errors.append("Вложенные блоки должны быть массивом.")

static func _walk_value(v: Variant, result: Dictionary, depth: int) -> void:
	if depth > 32:
		result.errors.append("Слишком глубокое выражение.")
		return
	if v is Dictionary:
		var op := str(v.get("op", ""))
		if op not in Blocks.EXPRESSIONS:
			result.errors.append("Неизвестное выражение: %s." % op)
			return
		if op == "literal":
			return
		for key: String in v:
			if key != "op":
				_walk_value(v[key], result, depth + 1)
	elif v is Array:
		for entry: Variant in v:
			_walk_value(entry, result, depth + 1)

static func box_valid(box: Dictionary) -> bool:
	var faces: Variant = box.get("faces", {})
	if not faces is Dictionary:
		return false
	for part: Variant in faces:
		if part not in ["front", "back", "spine", "top"] or not faces[part] is Array or faces[part].size() > 64:
			return false
		for layer: Variant in faces[part]:
			if not layer is Dictionary or layer.get("kind") not in ["fill", "text", "image"]:
				return false
			var rect: Variant = layer.get("rect")
			if not rect is Array or rect.size() != 4:
				return false
			for coordinate: Variant in rect:
				if not _number(coordinate) or absf(float(coordinate)) > 4096:
					return false
			if rect[2] <= 0 or rect[3] <= 0:
				return false
			for key: String in ["opacity", "rotation", "font_size", "brightness", "contrast", "saturation", "exposure", "hue", "outline"]:
				if layer.has(key) and not _number(layer[key]):
					return false
			for range_value: Array in [["opacity", 0, 1], ["rotation", -3600, 3600], ["font_size", 8, 512], ["brightness", -2, 2], ["contrast", 0, 4], ["saturation", 0, 4], ["exposure", -8, 8], ["hue", -360, 360]]:
				if layer.has(range_value[0]) and (layer[range_value[0]] < range_value[1] or layer[range_value[0]] > range_value[2]):
					return false
			for key: String in ["visible", "locked", "flip_x", "flip_y", "gradient", "shadow"]:
				if layer.has(key) and not layer[key] is bool:
					return false
			for key: String in ["text", "asset", "font", "color", "color2", "tint", "align", "title", "outline_color"]:
				if layer.has(key) and not layer[key] is String:
					return false
	return true

static func _id(text: String) -> bool:
	if text.is_empty() or text.length() > 64:
		return false
	for c in text:
		if not (c >= "a" and c <= "z" or c >= "0" and c <= "9" or c == "_"):
			return false
	return true

static func _hash(text: String) -> bool:
	if text.length() != 64:
		return false
	for letter: String in text:
		if letter not in "0123456789abcdef":
			return false
	return true

static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _json_only(v: Variant, depth: int, max_depth: int = 48) -> bool:
	if depth > max_depth:
		return false
	if v is String or v is StringName:
		return str(v).length() <= 4096
	if v == null or v is bool or v is int:
		return true
	if v is float:
		return is_finite(v)
	if v is Array:
		if v.size() > 10000:
			return false
		for item: Variant in v:
			if not _json_only(item, depth + 1, max_depth):
				return false
		return true
	if v is Dictionary:
		if v.size() > 1024:
			return false
		for key: Variant in v:
			if not (key is String or key is StringName) or str(key).length() > 4096 or not _json_only(v[key], depth + 1, max_depth):
				return false
		return true
	return false
