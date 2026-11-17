extends SceneTree
## Совместимость снимка комнаты (режим наблюдения) между версиями игры — hub/public_room.gd.
## Снимок проверяют отправитель, хост и каждый зритель своей версией: новое/незнакомое не должно
## отбрасывать всю комнату («глазик» переставал работать после обновлений).
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_public_room_compat.gd

var PublicRoom: GDScript
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА: ", message)


func _initialize() -> void:
	_run.call_deferred()


## Снимок «как у игрока сейчас»: все игры реестра, свои игры, фигурки на разных поверхностях, места коробок.
func _full_snapshot() -> Dictionary:
	var games: Array = (load("res://hub/games.gd").LIST as Array).map(func(g): return str(g.id))
	var figures: Array = load("res://hub/shelf_config.gd").FIGURINES
	var rows: Array = [[], [], [], [], [], [], [], []]
	var poses := {}
	var box_positions := {}
	var i := 0
	for id: String in games + figures:
		rows[i % 8].append(id)
		poses[id] = i % 4
		if not figures.has(id):
			box_positions[id] = fmod(i * 0.137, 1.0)
		i += 1
	var custom := {}
	for k in 24:
		var id := "custom:%08x-0000-4000-8000-%012x" % [k, k]
		custom[id] = {"title": "Своя игра %d" % k, "size": [0.2, 0.25, 0.05]}
		rows[k % 8].append(id)
	return {
		"config": {
			"rows": 4, "cols": 2, "cups": 4, "width": 0.4553, "height": 0.34, "neighbor_order": true,
			"wood": "2a1d42", "shelves": "5a3d22", "lights": [1, 2],
			"figure_positions": {"shelf_girl": 0.0, "shelf_andy": 0.86}, "figure_x": 0.0,
			"box_positions": box_positions, "figure_cells": {"shelf_mummy": 0.3},
			"figure_surfaces": {"shelf_girl": {"surface": "tv", "x": 0.15}, games[0]: {"surface": "wall_lower", "x": 0.4}},
			"figure_yaw": {"shelf_andy": 0.5},
		},
		"placements": rows, "poses": poses, "selected": games[1], "editor": false, "custom": custom,
		"room": "winter",
		"camera": {"zoom": 1.0, "frame": [0.1, 1.2, 2.5, 0.0, 0.0, 0.0, 1.0]},
	}


func _count(clean: Dictionary) -> int:
	var total := 0
	for row: Array in clean.get("placements", []):
		total += row.size()
	return total


func _run() -> void:
	PublicRoom = load("res://hub/public_room.gd")
	var full := _full_snapshot()
	var items := 0
	for row: Array in full.placements:
		items += row.size()
	var clean: Dictionary = PublicRoom.clean(full)
	check(not clean.is_empty(), "полный шкаф (все игры + 24 своих + фигурки) принимается")
	check(_count(clean) == items, "все %d предметов на месте (получено %d)" % [items, _count(clean)])
	check(PublicRoom.clean(clean) == clean, "повторная проверка не меняет снимок (его проверяют хост и зритель)")
	check(var_to_bytes(full).size() < PublicRoom.MAX_BYTES / 2, "полный снимок с двойным запасом по объёму (%d байт)" % var_to_bytes(full).size())

	# Новая версия добавила поля — старая (эта) должна их пропустить, а не отбросить комнату.
	var newer := full.duplicate(true)
	for k in 12:
		newer["future_field_%d" % k] = {"a": [1, 2, 3], "b": "x"}
	newer.config["future_config"] = [1, 2]
	newer.config.figure_surfaces["shelf_andy"] = {"surface": "christmas_tree", "x": 0.5}  # незнакомая поверхность
	newer.config.figure_cells["shelf_fighter"] = "битое"
	newer.config.box_positions["future_game"] = 0.5
	newer.placements[0].append("game_from_future")
	newer.placements[1].append(newer.placements[0][0])  # повтор id
	newer.poses[full.placements[0][1]] = 7  # незнакомая поза
	newer.custom["custom:bad"] = {"title": 5}
	newer["room"] = "workshop:room_from_friend"
	var clean_newer: Dictionary = PublicRoom.clean(newer)
	check(not clean_newer.is_empty(), "снимок новой версии с незнакомыми полями принимается")
	check(_count(clean_newer) == items, "незнакомая игра и повтор пропущены, остальное на месте")
	check(not (clean_newer.config.figure_surfaces as Dictionary).has("shelf_andy"), "незнакомая поверхность — фигурка стоит в шкафу")
	check(not clean_newer.poses.has(full.placements[0][1]), "незнакомая поза пропущена у одной коробки")
	check(clean_newer.custom.size() == 24, "битая своя игра пропущена, остальные 24 на месте")

	var upper := full.duplicate(true)
	var game: String = full.placements[1][0]
	upper.config.upper_edges = [[-2, 3, 1, 3], [1, 3, 2, 2], [99, 0, 0, 0], [1, 3, -2, 3]]
	upper.config.upper_precise_edges = [[-33, 64, 22, 64], [500, 0, 22, 64]]
	upper.config.upper_smoothing = 0.65
	upper.config.upper_shallow_edges = ["-33:64:22:64", "10:20:30:40"]
	upper.config.figure_surfaces[game] = {"surface": "above:-2:1:3", "x": 0.5}
	upper.config.figure_surfaces["shelf_girl"] = {"surface": "above:u:-33:22:64", "x": 0.25, "fit": true}
	upper.config.figure_surfaces["shelf_andy"] = {"surface": "above:1:2:3", "x": 0.5}
	var clean_upper: Dictionary = PublicRoom.clean(upper)
	check(clean_upper.config.upper_edges == [[-2, 3, 1, 3], [1, 3, 2, 2]], "исправные отрезки остаются, битый и повтор пропускаются")
	check(clean_upper.config.upper_smoothing == 0.65, "скругление остаётся в снимке")
	check(clean_upper.config.figure_surfaces[game] == {"surface": "above:-2:1:3", "x": 0.5}, "коробка сохраняет положение на горизонтальной полке")
	check(not clean_upper.config.figure_surfaces.has("shelf_andy"), "наклонный отрезок не принимается как поверхность")
	check(clean_upper.config.upper_precise_edges == [[-33, 64, 22, 64]], "Координаты новой сетки сохраняются, битый отрезок пропускается.")
	check(clean_upper.config.figure_surfaces.shelf_girl == {"surface": "above:u:-33:22:64", "x": 0.25, "fit": true}, "Место на новой сетке проходит проверку.")
	check(clean_upper.config.upper_shallow_edges == ["-33:64:22:64"], "Половинная глубина сохраняется у существующего отрезка.")
	check(PublicRoom.clean(clean_upper) == clean_upper, "повторная проверка сохраняет новые поля")

	# Старая версия (0.9.0) — без мест коробок, комнаты, гирлянд, ячеек.
	var older := {
		"config": {"rows": 4, "cols": 2, "cups": 4, "width": 0.4, "height": 0.34, "figure_x": 1.0},
		"placements": [["king_of_12", "perudo"], ["gloom"], [], [], [], [], [], ["brodilka"]],
		"poses": {"king_of_12": 0}, "selected": "", "editor": false,
	}
	var clean_older: Dictionary = PublicRoom.clean(older)
	check(not clean_older.is_empty() and _count(clean_older) == 4, "снимок старой версии принимается")

	# Безопасность осталась: объект, глубина, огромный объём, сломанный каркас.
	check(PublicRoom.clean({"config": Node.new(), "placements": [], "poses": {}}).is_empty(), "объекты не принимаются")
	var deep: Variant = [1]
	for k in 12:
		deep = [deep]
	var bad := full.duplicate(true)
	bad["x"] = deep
	check(PublicRoom.clean(bad).is_empty(), "слишком глубокая вложенность отбрасывается")
	bad = full.duplicate(true)
	bad.config.rows = 99
	check(PublicRoom.clean(bad).is_empty(), "сломанный каркас (99 рядов) отбрасывается")
	bad = full.duplicate(true)
	bad.placements.pop_back()
	check(PublicRoom.clean(bad).is_empty(), "число ячеек не совпадает с раскладкой — отбрасывается")

	print("СОВМЕСТИМОСТЬ НАБЛЮДЕНИЯ: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures > 0 else 0)
