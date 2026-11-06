class_name CGFaces
extends RefCounted
## Привязки шаблона лица к колонкам таблицы. Только данные для видимой карты.
const Definition := preload("res://games/custom/logic/cg_def.gd")

static func text(value: Variant) -> String:
	if value is bool:
		return "Да" if value else "Нет"
	if value is float and value == round(value) and absf(value) < 9223372036854775807.0:
		return str(int(value))
	return str(value)

## Цвет бумаги карт колоды (свойство «Цвет карт»).
const PAPER := "#ded7c8"

static func paper(deck: Dictionary) -> String:
	var value := str(deck.get("color", PAPER))
	return value if Color.html_is_valid(value) else PAPER

## Слой-фон, который красится цветом колоды: помеченный role=card или нижний закреплённый «Фон» старых проектов.
static func is_card_background(layer: Dictionary, index: int) -> bool:
	if layer.get("role", "") == "card":
		return true
	return index == 0 and layer.get("kind") == "fill" and layer.get("locked", false) and str(layer.get("title", "")) == "Фон"

static func dimensions(deck: Dictionary) -> Array:
	var size: Vector2i = Definition.CARD_SIZES[clampi(int(deck.get("size", 3)) - 1, 0, Definition.CARD_SIZES.size() - 1)] * 4
	return [size.x, size.y]

static func columns(deck: Dictionary) -> Array:
	var result: Array = deck.get("columns", []).duplicate(true)
	var known := {}
	for column: Dictionary in result:
		known[str(column.id)] = true
	for row: Dictionary in deck.get("rows", []):
		for key: String in row:
			if key == "copies" or known.has(key):
				continue
			var value: Variant = row[key]
			var type := "bool" if value is bool else ("number" if value is int or value is float else ("image" if key == "art" or value is String and Definition._hash(value) else "text"))
			result.append({"id": key, "type": type})
			known[key] = true
	return result

static func fields(row: Dictionary, deck: Dictionary) -> Dictionary:
	var bindings: Dictionary = deck.get("face", {}) if deck.get("face", {}) is Dictionary else {}
	var title := str(bindings.get("title", "title"))
	var value := str(bindings.get("value", "rank"))
	var art := str(bindings.get("art", "art"))
	var body_field := str(bindings.get("text", "text"))
	var result := {"title": "" if bindings.has("title") and title.is_empty() else row.get(title, row.get("name", row.get("Название", row.get(value, "Карта")))),
		"rank": row.get(value, ""), "art": row.get(art, ""), "text": row.get(body_field, ""), "font": bindings.get("font", ""), "paper": paper(deck)}
	if bindings.get("layers") is Array:
		result["canvas_size"] = dimensions(deck)
		result["layers"] = bindings.layers.duplicate(true)
		for index in result.layers.size():
			var layer: Dictionary = result.layers[index]
			if is_card_background(layer, index):
				layer["color"] = result.paper
			# Цвет из колонки таблицы: у каждой карты свой (например, масть или цвет внутри рамки).
			for pair: Array in [["color_field", "color"], ["fill_field", "fill"]]:
				var source := str(layer.get(pair[0], ""))
				var supplied := str(row.get(source, "")) if not source.is_empty() else ""
				if Color.html_is_valid(supplied):
					layer[pair[1]] = supplied
			var field := str(layer.get("field", ""))
			if field.is_empty():
				continue
			if layer.get("kind") == "image":
				layer["asset"] = str(row.get(field, ""))
			elif layer.get("kind") == "text":
				var supplied: Variant = row.get(field, "")
				layer["text"] = text(supplied)
	return result

static func default_layers(deck: Dictionary) -> Array:
	var dimensions_value := dimensions(deck)
	var width: int = dimensions_value[0]
	var height: int = dimensions_value[1]
	var face: Dictionary = deck.get("face", {})
	var fields := {}
	for column: Dictionary in columns(deck):
		fields[str(column.id)] = true
	var result: Array = [{"kind": "fill", "title": "Фон", "role": "card", "rect": [0, 0, width, height], "color": paper(deck), "locked": true}]
	for spec: Array in [["art", "image", "Рисунок", [32, 128, width - 64, height - 192], "art"],
		["title", "text", "Название", [32, 16, width - 64, 112], "title"],
		["value", "text", "Значение", [0, height * 0.38, width, height * 0.28], "rank"],
		["text", "text", "Описание", [32, height * 0.72, width - 64, height * 0.24], "text"]]:
		var field := str(face.get(spec[0], spec[4]))
		if not fields.has(field):
			continue
		result.append({"kind": spec[1], "title": spec[2], "field": field, "rect": spec[3], "color": "#30263f",
			"font_size": 128 if spec[0] == "value" else 64, "font": str(face.get("font", "")),
			"text": "", "asset": "", "align": "center" if spec[0] == "value" else "left"})
	return result
