class_name HubRooms
extends RefCounted
## Реестр комнат главного меню. Комната — это только окружение (стены, мебель, украшения, вид за окном);
## личная расстановка игрока (шкаф, коробки, фигурки, плакаты, доски, мяч, корзина) в неё не входит
## и одинакова в любой комнате.
##
## Запись: {id, title, hint, icon, kind, theme, source, preview}
##   id      — уникальный код (сохраняется локально и передаётся друзьям в режиме наблюдения);
##   title   — название в списке, hint — подсказка;
##   icon    — значок линиями из hub/room_icons.gd (`RoomIcons.room_icon`), preview — путь к картинке
##             (для комнат из мастерской; встроенным хватает значка);
##   season  — сезонная комната (сезоны — hub/stickers.gd SEASONS): вне сезона её нет в списке;
##   kind    — способ построения: "neon" — общая комната hub/neon_room.gd плюс тема-украшения `theme`
##             (путь к скрипту Node3D с методом build(room)); в будущем "scene" — готовая сцена
##             (glb / tscn из Blender), загруженная из мастерской Steam;
##   source  — "builtin" или "workshop".
## Новая встроенная комната — запись в LIST. Комната из мастерской — `register(...)` при загрузке.

const DEFAULT := "neon90"  # комната по умолчанию вне сезона
## Сезонная комната (поле season): в свой сезон (даты — hub/stickers.gd SEASONS, зимний — 13.11–20.02) она
## по умолчанию и один раз за сезон включается сама, даже если выбрана другая (владелец, 14.11); игрок может
## сменить обратно. Вне сезона её нет в списке, и своя комната становится DEFAULT.
const SEASON_ROOMS := {"xmas": "winter"}
const Stickers := preload("res://hub/stickers.gd")
const SAVE_PATH := "user://room_props.cfg"

const LIST: Array = [
	{
		"id": "winter", "title": "Зимняя", "icon": "winter",
		"hint": "Та же комната к Новому году: ёлка, гирлянды и снег за окном",
		"kind": "neon", "theme": "res://hub/rooms/winter_decor.gd", "source": "builtin", "preview": "", "season": "xmas",
	},
	{
		"id": "neon90", "title": "Неоновая 90-х", "icon": "neon",
		"hint": "Классическая неоновая детская 90-х",
		"kind": "neon", "theme": "", "source": "builtin", "preview": "",
	},
]

## Добавленные во время работы (комнаты из мастерской). Ключи — как у LIST.
static var _extra: Array = []


static func all() -> Array:
	var rooms: Array = LIST.duplicate(true)
	rooms.append_array(_extra)
	return rooms


static func by_id(id: String) -> Dictionary:
	for entry: Dictionary in all():
		if str(entry.id) == id:
			return entry
	return {}


static func has(id: String) -> bool:
	return not by_id(id).is_empty()


## Комната открыта сейчас: не сезонная или её сезон идёт.
static func in_season(entry: Dictionary) -> bool:
	return Stickers.season_open(str(entry.get("season", "")))


## Комнаты для списка в редакторе шкафа (сезонные — только в свой сезон).
static func listed() -> Array:
	return all().filter(func(entry: Dictionary) -> bool: return in_season(entry))


## Комната из мастерской (пока не используется): проверяем поля, повтор id заменяет запись.
static func register(entry: Dictionary) -> bool:
	if not entry.get("id") is String or not valid_id(entry.id) or not entry.get("title") is String:
		return false
	for i in _extra.size():
		if str(_extra[i].id) == entry.id:
			_extra[i] = entry
			return true
	for builtin: Dictionary in LIST:
		if str(builtin.id) == entry.id:
			return false
	_extra.append(entry)
	return true


## id из сети или файла: короткий, только латиница, цифры и «_ - :».
static func valid_id(id: Variant) -> bool:
	if not id is String or (id as String).is_empty() or (id as String).length() > 48:
		return false
	for ch in (id as String):
		if not (ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9" or ch in ["_", "-", ":"]):
			return false
	return true


static func saved_id() -> String:
	var prefs := ConfigFile.new()
	prefs.load(SAVE_PATH)
	var id := str(prefs.get_value("room", "theme", ""))
	var date := Time.get_date_dict_from_system()
	for season: String in SEASON_ROOMS:
		# сезон считается по году его начала: январь и февраль относятся к прошлогоднему
		var year := int(date.year) - (1 if int(date.month) < 6 else 0)
		var key := "season_" + season
		if Stickers.season_open(season, date) and int(prefs.get_value("room", key, 0)) != year:
			prefs.set_value("room", key, year)
			id = SEASON_ROOMS[season]
			prefs.set_value("room", "theme", id)
			prefs.save(SAVE_PATH)
	var entry := by_id(id)
	return id if not entry.is_empty() and in_season(entry) else default_id()


## Комната по умолчанию сегодня: сезонная в свой сезон, иначе DEFAULT.
static func default_id() -> String:
	for season: String in SEASON_ROOMS:
		if Stickers.season_open(season):
			return SEASON_ROOMS[season]
	return DEFAULT


static func save_id(id: String) -> void:
	var prefs := ConfigFile.new()
	prefs.load(SAVE_PATH)
	prefs.set_value("room", "theme", id)
	prefs.save(SAVE_PATH)
