class_name CGSession
extends RefCounted
## Мост Net для встроенных JSON-примеров. Внешние пакеты подключаются отдельным безопасным этапом.

const EXAMPLES := ["card_race", "higher_lower", "dice_bid"]
const TITLES := ["Карточная гонка", "Больше или меньше", "Ставка на кубики"]
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
const Faces := preload("res://games/custom/logic/cg_faces.gd")

static func create(example_id: String, players: Array, options: Dictionary = {}) -> Dictionary:
	if example_id not in EXAMPLES:
		return {"error": "Выберите встроенный пример игры."}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/%s.json" % example_id))
	if not parsed is Dictionary:
		return {"error": "Не удалось прочитать пример игры."}
	return create_definition(parsed, players, options)

static func create_custom(id: String, players: Array, options: Dictionary = {}) -> Dictionary:
	var definition := Library.load_game(id)
	if definition.is_empty():
		return {"error": "Игра не найдена в библиотеке автора."}
	return create_definition(definition, players, options)

static func create_definition(parsed: Dictionary, players: Array, options: Dictionary = {}) -> Dictionary:
	var rules := Rules.new()
	var errors := rules.load_definition(parsed)
	if not errors.is_empty():
		return {"error": str(errors[0])}
	var roles: Array = options.get("roles", [])
	var order: Array = options.get("seat_order", range(players.size()))
	var allowed: Array = ["leader", "player"]
	if parsed.rules.has("roles"):
		allowed = []
		for role: Dictionary in parsed.rules.roles:
			allowed.append(str(role.id))
	var seats := players.duplicate(true)
	var leader := 0
	for seat in seats.size():
		var old := int(order[seat])
		var fallback := "leader" if old == 0 and allowed.has("leader") else ("player" if allowed.has("player") else str(allowed[0]))
		var role := str(roles[old]) if old < roles.size() else fallback
		if role not in allowed:
			return {"error": "Назначена неизвестная роль."}
		seats[seat].role = role
		if role == "leader":
			leader = seat
		if int(seats[seat].get("team", -1)) < 0:
			seats[seat].team = seat % 2
	var error := rules.new_game(seats, {"seed": randi(), "leader": leader, "turn_time": options.get("turn_time", 0)})
	return {"rules": rules, "error": error}

static func view(rules: Object, seat: int, hotseat: bool) -> Dictionary:
	var out: Dictionary = rules.get_view(seat)
	var templates := {}
	for cards: Array in out.zones.values():
		for card: Dictionary in cards:
			if card.get("hidden", false):
				continue
			for deck: Dictionary in rules.definition.elements.get("decks", []):
				if str(deck.id) == str(card.deck):
					if deck.get("face", {}).get("layers") is Array:
						# Общий шаблон передаётся один раз, а не вместе с каждой картой руки.
						if not templates.has(str(deck.id)):
							templates[str(deck.id)] = {"face": deck.face.duplicate(true), "size": int(deck.get("size", 3)), "color": Faces.paper(deck)}
						card["face"] = {"template": str(deck.id)}
					else:
						card["face"] = Faces.fields(card.data, deck)
					card["size"] = int(deck.get("size", 3))
					break
	out["cg_meta"] = rules.definition.meta.duplicate(true)
	out["cg_layout"] = rules.definition.layout.duplicate(true)
	out["cg_vars"] = rules.definition.rules.get("vars", []).duplicate(true)
	out["cg_dice"] = rules.definition.elements.get("dice", []).duplicate(true)
	out["cg_card_templates"] = templates
	out["hotseat"] = hotseat
	return out

static func face_fields(view_data: Dictionary, card: Dictionary) -> Dictionary:
	if card.get("hidden", false):
		return {}
	var face: Dictionary = card.get("face", {})
	if face.has("template"):
		var template: Dictionary = view_data.get("cg_card_templates", {}).get(str(face.template), {})
		return Faces.fields(card.get("data", {}), template) if not template.is_empty() else {}
	return card.get("face", card.get("data", {}))
