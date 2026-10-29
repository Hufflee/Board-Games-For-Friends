## Каталог оригинальных карточек Things in Rings и справочные русские переводы.
## Самостоятельный модуль данных: не использует сеть или настройки игрока.
class_name TRData
extends RefCounted

const CATALOG_PATH := "res://games/things_in_rings/logic/tr_catalog.json"
const ART_PATH := "res://games/things_in_rings/art/cards/"
static var _cards: Dictionary = {}
static var _textures: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _cards.is_empty():
		return
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	for row: Dictionary in rows:
		_cards[int(row["id"])] = row

static func things() -> Array:
	_ensure_loaded()
	var result: Array = []
	for id: int in _cards:
		if card_kind(id) == "Thing":
			result.append(id)
	return result

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
	return _get_texture(str(id) + ".webp")

static func back_texture(kind: String) -> Texture2D:
	if not kind in ["Thing", "Attribute", "Word", "Context"]:
		return null
	return _get_texture("back_" + kind.to_lower() + ".webp")

static func _get_texture(file_name: String) -> Texture2D:
	if not _textures.has(file_name):
		_textures[file_name] = load(ART_PATH + file_name)
	return _textures[file_name] as Texture2D
