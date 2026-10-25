class_name FSData
extends RefCounted
## Русские карты второго мода. Базовый состав сверён с третьим по названиям и числу копий.
static var _data: Dictionary = {}
static var _textures: Dictionary = {}
static var _responses: Array = []
static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/manifest.json"))
	return _data
static func card(id: int) -> Dictionary:
	return data().cards[id] if id >= 0 and id < data().cards.size() else {}
static func title(id: int) -> String:
	var c := card(id)
	if c.is_empty():
		return "Пустое место"
	var parts: PackedStringArray = str(c.name).split("/")
	return parts[0] if parts.size() > 1 else str(c.name)
static func texture(id: int) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = load("res://games/four_souls/art/cards/%d.webp" % id)
	return _textures[id]
static func pool(kind: String, dlc: bool) -> Array:
	var out := []
	for c: Dictionary in data().cards:
		if c.kind == kind and (dlc or c.base):
			out.append(int(c.id))
	return out
static func characters(dlc: bool) -> Array:
	return data().characters.filter(func(c): return dlc or c.base)
## По общим правилам лут и активируемые/платные способности доступны и вне своего хода.
## Особые условия конкретной карты по-прежнему проверяются при выполнении её текста.
static func response_kind(id: int) -> String:
	if _responses.is_empty():
		_responses = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/response_catalog.json")).cards
	return str(_responses[id].response_kind) if id>=0 and id<_responses.size() else "none"
static func item_response_kind(id: int) -> String:
	return "passive" if card(id).get("kind","")=="loot" else response_kind(id)
static func draw_loot_back(canvas: CanvasItem,rect: Rect2) -> void:
	canvas.draw_texture_rect(preload("res://games/four_souls/art/backs/loot.webp"),rect,false)
static func stat(id: int, key: String, fallback: int) -> int:
	return int(card(id).get("lua", {}).get(key, fallback))

static func effect_title(effect: Dictionary) -> String:
	match str(effect.get("kind","")):
		"attack": return "Объявление атаки"
		"purchase": return "Покупка сокровища"
		"death": return "Смерть игрока"
		"monster_death": return "Смерть монстра: " + title(int(effect.card))
		"combat": return "Боевой урон: %d" % int(effect.damage)
		"roll", "effect_roll": return "Бросок: %d" % int(effect.value)
	return title(int(effect.get("card",-1)))
