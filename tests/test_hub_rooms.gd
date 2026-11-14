extends SceneTree
## Комнаты главного меню и сезонные стикеры: даты сезона, реестр комнат.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_hub_rooms.gd

var _fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("ОШИБКА: ", msg)


func _init() -> void:
	var stickers: GDScript = load("res://hub/stickers.gd")
	var rooms: GDScript = load("res://hub/rooms/hub_rooms.gd")
	check(not stickers.season_open("xmas", {"month": 11, "day": 12}), "12 ноября рождественские ещё закрыты")
	check(stickers.season_open("xmas", {"month": 11, "day": 13}), "13 ноября рождественские открыты")
	check(stickers.season_open("xmas", {"month": 12, "day": 31}), "31 декабря открыты")
	check(stickers.season_open("xmas", {"month": 2, "day": 20}), "20 февраля ещё открыты")
	check(not stickers.season_open("xmas", {"month": 2, "day": 21}), "21 февраля закрыты")
	check(stickers.valid_id("xmas_tree"), "сезонный стикер всегда допустим (уже наклеенные не пропадают)")
	for entry: Dictionary in stickers.CATALOG:
		check(ResourceLoader.exists("res://hub/art/stickers/%s.png" % entry.id), "есть картинка стикера " + str(entry.id))
	for id: String in ["winter", "neon90"]:
		check(rooms.has(id), "в реестре есть комната " + id)
	check(rooms.valid_id("winter") and not rooms.valid_id("../x") and not rooms.valid_id(""), "проверка id комнаты")
	check(not rooms.register({"id": "winter", "title": "Подмена"}), "встроенную комнату не подменить")
	check(rooms.register({"id": "workshop:123", "title": "Из мастерской", "kind": "scene"}) and rooms.has("workshop:123"), "комната из мастерской регистрируется")
	print("test_hub_rooms: ошибок ", _fails)
	quit(1 if _fails > 0 else 0)
