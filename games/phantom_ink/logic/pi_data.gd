class_name PIData
extends RefCounted
## Оригинальные карточки из предоставленного PDF.
const QUESTIONS := 102
const OBJECTS := 52
const ROLES := ["Солнце · медиум", "Солнце · дух", "Луна · медиум", "Луна · дух"]
const EYES := [[3, 5, 6], [2, 4, 5]]
static var _questions: Array = []

static func question(id: int) -> String:
	if _questions.is_empty():
		_questions = JSON.parse_string(FileAccess.get_file_as_string("res://games/phantom_ink/art/questions.json"))
	return str(_questions[id]) if id >= 0 and id < _questions.size() else "Вопрос"

static func card(kind: String, id: int) -> Texture2D:
	return load("res://games/phantom_ink/art/cards/%s%d.webp" % [kind, id])

static func default_roles(count: int) -> Array:
	var result: Array = [0, 1, 2, 3]
	for i in range(4, count):
		result.append(0 if i % 2 == 0 else 2)
	return result.slice(0, count)

static func validate(roles: Array, count: int) -> String:
	if count < 4 or count > 8:
		return "Нужно от 4 до 8 игроков: два духа и медиумы обеих команд."
	if roles.size() != count:
		return "Назначьте роль каждому игроку."
	for role in roles:
		if not role is int or role < 0 or role > 3:
			return "Неизвестная роль."
	if roles.count(1) != 1 or roles.count(3) != 1 or roles.count(0) < 1 or roles.count(2) < 1:
		return "В каждой команде нужен ровно один дух и хотя бы один медиум."
	return ""
