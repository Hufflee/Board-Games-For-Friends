class_name FSData
extends RefCounted
## Русские карты второго мода. Базовый состав сверён с третьим по названиям и числу копий.
static var _data: Dictionary = {}
static var _textures: Dictionary = {}
static var _responses: Array = []
const Support := preload("res://games/four_souls/logic/fs_support.gd")
## У этих монет есть дополнительный текст: неполная Lua-метка не делает их обычными монетами.
const MANUAL_COIN_LOOT := [476, 506, 528, 544]

static func coin_loot_value(id: int) -> int:
	if id in MANUAL_COIN_LOOT:
		return 0
	if id == 649:
		return 10
	var kind: String = str(card(id).get("lua", {}).get("type", ""))
	return int(kind.left(1)) if kind in ["1c", "2c", "3c", "4c", "5c"] else 0

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/manifest.json"))
	return _data
static func card(id: int) -> Dictionary:
	return data().cards[id] if id >= 0 and id < data().cards.size() else preload("res://games/four_souls/logic/fs_outside_cards.gd").CARDS.get(id, {})
static func title(id: int) -> String:
	var c := card(id)
	if c.is_empty():
		return "Пустое место"
	var parts: PackedStringArray = str(c.name).split("/")
	return parts[0] if parts.size() > 1 else str(c.name)
static func texture(id: int) -> Texture2D:
	if not _textures.has(id):
		var path := "res://games/four_souls/art/cards/%d.webp" % id
		if id in [913, 914] and not ResourceLoader.exists(path):
			_textures[id] = ImageTexture.create_from_image(Image.load_from_file(path))
		else:
			_textures[id] = load(path)
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
	const Packet26 = preload("res://games/four_souls/logic/fs_packet26_cards.gd")
	const Packet27 = preload("res://games/four_souls/logic/fs_packet27_cards.gd")
	if id in Packet27.ITEMS:
		if id in Packet27.TAP:
			return "hybrid" if Packet26.PAID.has(id) else "tap"
		return "paid" if Packet26.PAID.has(id) else "passive"
	if id in Packet26.ITEMS:
		if id in Packet26.TAP:
			return "hybrid" if Packet26.PAID.has(id) else "tap"
		return "paid" if Packet26.PAID.has(id) else "passive"
	if id in [44, 50, 843]:
		return "hybrid"
	return "passive" if card(id).get("kind", "") in ["loot", "monster"] else response_kind(id)

## Только ручная часть условного текста; полностью автоматические предметы повторно не вызываются.
## У Неопределённого70 есть отдельная пассивная часть помимо поворотной.
## 06.11: частично автоматизированные карты, временно убранные из колод настоящей партии.
const PARTIAL_OFF28 := [258, 328, 500, 502, 564]
## Добыча «для ответов»: бомбы, отмены, перебросы и защита — в чужой ход лежит справа в руке.
static func reactive_loot28(id: int) -> bool:
	return id in [469, 470, 621] or str(card(id).get("lua", {}).get("type", "")) in ["bombs", "butter", "dice_sheart"]
static func manual_item_trigger(id: int) -> bool:
	return Support.status(id) != "auto" and (id == 70 or item_response_kind(id) in ["passive", "conditional"])

## Напечатанная вечность сохраняется при любом способе получения предмета.
## Мошна Хранителя и Клещ не входят в колоду вечных стартовых предметов.
static func item_entry(id: int, force_eternal: bool = false) -> Dictionary:
	var printed_eternal: bool = card(id).get("kind", "") == "eternal" or id in [69, 503]
	var counters: int = {5: 3, 202: 9}.get(id, 0)
	return {"id": id, "tapped": id in [22, 60, 199], "eternal": force_eternal or printed_eternal, "counters": counters}

## Только безусловная собственная перезарядка по напечатанному тексту.
## Не включает выбор другого предмета и условные броски в конце хода.
static func end_turn_recharge(id: int) -> bool:
	return id in [84, 822, 824, 828, 834, 849, 893, 899]
static func draw_loot_back(canvas: CanvasItem,rect: Rect2) -> void:
	canvas.draw_texture_rect(preload("res://games/four_souls/art/backs/loot.webp"),rect,false)
static func stat(id: int, key: String, fallback: int) -> int:
	if id == 897:
		return int({"hp": 2, "dc": 3, "at": 2}.get(key, fallback))
	if id == 88:
		return int({"hp": 2, "dc": 5, "at": 1}.get(key, fallback))
	if id == 778:
		return int({"hp": 9, "dc": 3, "at": 1}.get(key, fallback))
	if id == 467:
		return 6 if key in ["hp", "dc", "at"] else fallback
	if id == 3:
		return int({"hp": 2, "dc": 3, "at": 1}.get(key, fallback))
	return int(card(id).get("lua", {}).get(key, fallback))

static func effect_title(effect: Dictionary) -> String:
	match str(effect.get("kind","")):
		"player_attack": return "Объявление атаки другого игрока"
		"forced_discard": return title(int(effect.card)) + ": обязательный сброс лута"
		"player_combat": return "Боевой урон в PvP: %d" % int(effect.damage)
		"attack": return "Объявление атаки"
		"purchase": return "Покупка сокровища"
		"death": return "Смерть игрока"
		"monster_death": return "Смерть монстра: " + title(int(effect.card))
		"damage16": return "Отложенный урон: %d" % int(effect.damage)
		"combat": return "Боевой урон: %d" % int(effect.damage)
		"roll", "effect_roll": return "Бросок: %d" % int(effect.value)
	return title(int(effect.get("card",-1)))
