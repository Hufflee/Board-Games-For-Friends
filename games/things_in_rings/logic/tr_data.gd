## Каталог оригинальных карточек Things in Rings и справочные русские переводы.
## Самостоятельный модуль данных: не использует сеть или настройки игрока.
class_name TRData
extends RefCounted

const CATALOG_PATH := "res://games/things_in_rings/logic/tr_catalog.json"
const THINGS_PATH := "res://games/things_in_rings/logic/tr_things.json"
const ART_PATH := "res://games/things_in_rings/art/cards/"
const NEW_ART_PATH := "res://games/things_in_rings/art/cards_new/with_detail/"
static var _cards: Dictionary = {}
static var _things: Array = []
static var _textures: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _cards.is_empty():
		return
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	for row: Dictionary in rows:
		_cards[int(row["id"])] = row
	var things_rows: Array = JSON.parse_string(FileAccess.get_file_as_string(THINGS_PATH))
	for row: Dictionary in things_rows:
		var id := int(row["id"])
		row["kind"] = "Thing"
		_cards[id] = row
		_things.append(id)

static func things() -> Array:
	_ensure_loaded()
	return _things.duplicate()

static func rule_pools() -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = {"Attribute": [], "Word": [], "Context": []}
	for id: int in _cards:
		var kind: String = card_kind(id)
		if result.has(kind):
			result[kind].append(id)
	return result

static func card_kind(id: int) -> String:
	_ensure_loaded()
	return str(_cards.get(id, {}).get("kind", ""))

static func card_name(id: int) -> String:
	_ensure_loaded()
	return str(_cards.get(id, {}).get("en", ""))

static func translation(id: int) -> String:
	_ensure_loaded()
	return str(_cards.get(id, {}).get("ru", ""))

static func texture(id: int) -> Texture2D:
	_ensure_loaded()
	if not _cards.has(id):
		return null
	var art := str(_cards[id].get("art", ""))
	if not art.is_empty():
		# Полноразмерные иллюстрации держат только открытые карты.
		return load(NEW_ART_PATH + art) as Texture2D
	return _get_texture(ART_PATH + str(id) + ".webp")

static func has_title_layer(id: int) -> bool:
	_ensure_loaded()
	return _cards.get(id, {}).has("art")

static func back_texture(kind: String) -> Texture2D:
	if not kind in ["Thing", "Attribute", "Word", "Context"]:
		return null
	return _get_texture(ART_PATH + "back_" + kind.to_lower() + ".webp")

static func _get_texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path] as Texture2D
