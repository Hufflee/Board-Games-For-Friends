class_name CGFaces
extends RefCounted
## Привязки шаблона лица к колонкам таблицы. Только данные для видимой карты.

static func fields(row: Dictionary, deck: Dictionary) -> Dictionary:
	var bindings: Dictionary = deck.get("face", {}) if deck.get("face", {}) is Dictionary else {}
	var title := str(bindings.get("title", "title"))
	var value := str(bindings.get("value", "rank"))
	var art := str(bindings.get("art", "art"))
	var text := str(bindings.get("text", "text"))
	return {"title": "" if bindings.has("title") and title.is_empty() else row.get(title, row.get("name", row.get("Название", row.get(value, "Карта")))),
		"rank": row.get(value, ""), "art": row.get(art, ""), "text": row.get(text, ""), "font": bindings.get("font", "")}
