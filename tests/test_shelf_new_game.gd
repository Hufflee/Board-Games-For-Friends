extends SceneTree
## Шкаф хаба (06.11): новая игра из обновления не помещается в сохранённую расстановку игрока —
## шкаф расширяется по ширине, прежние коробки остаются в своих ячейках и по порядку, новая встаёт в новое место.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_shelf_new_game.gd

const Shelf := preload("res://hub/shelf_config.gd")
const PATH := "user://test_shelf_new_game.cfg"

var checks := 0
var fails := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ПРОВАЛ: ", msg)


func _initialize() -> void:
	var box := Vector3(0.09, 0.28, 0.25)  # толщина 9 см, стоит корешком
	var sizes := {}
	for id in ["a", "b", "c", "d", "e", "f", "new_game"]:
		sizes[id] = box
	var config := {"rows": 2, "cols": 1, "width": 0.30, "height": 0.36, "cups": 0}
	var rows := [["a", "b", "c"], ["d", "e", "f"]]
	var poses := {}
	for id in ["a", "b", "c", "d", "e", "f"]:
		poses[id] = 1
	# Проверяем: обе ячейки забиты (3 × 9 см в 29,4 см), сохраняем как расстановку игрока.
	var full := Shelf.solve(config, rows, _without(sizes, "new_game"), poses)
	check(full.ok, "исходная расстановка помещается")
	check(Shelf.save_state(config, rows, poses, PATH) == OK, "сохранение игрока записано")

	var result := Shelf.load_state({"rows": 4, "cols": 1, "width": 0.65, "height": 0.36, "cups": 2}, [[]], sizes, PATH)
	check(result.ok, "новая игра встала без сброса к стандартной расстановке")
	if result.ok:
		var cells: Array = result.placements
		check(float(result.config.width) > 0.30, "шкаф стал шире (%.2f м)" % float(result.config.width))
		check(float(result.config.width) <= 0.30 + 0.12, "расширение небольшое, а не до предела (%.2f м)" % float(result.config.width))
		check((cells[0] as Array).slice(0, 3) == ["a", "b", "c"], "первая полка: прежние коробки на местах и по порядку %s" % str(cells[0]))
		check((cells[1] as Array).slice(0, 3) == ["d", "e", "f"], "вторая полка: прежние коробки на местах и по порядку %s" % str(cells[1]))
		var all: Array = []
		for row: Array in cells:
			all.append_array(row)
		check(all.count("new_game") == 1 and all.size() == 7, "новая игра одна, ни одна коробка не потеряна %s" % str(cells))
		check(int(result.config.rows) == 2 and int(result.config.cols) == 1, "ряды и столбцы игрока не изменились")

	# Если место есть — шкаф не расширяется.
	var roomy := {"rows": 2, "cols": 1, "width": 0.45, "height": 0.36, "cups": 0}
	Shelf.save_state(roomy, rows, poses, PATH)
	var same := Shelf.load_state({"rows": 4, "cols": 1, "width": 0.65, "height": 0.36, "cups": 2}, [[]], sizes, PATH)
	check(same.ok and is_equal_approx(float(same.config.width), 0.45), "при свободном месте ширина та же")
	check(same.ok and (same.placements[0] as Array).slice(0, 3) == ["a", "b", "c"], "и прежние места те же")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("Шкаф и новая игра: %d проверок, провалов %d" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _without(sizes: Dictionary, id: String) -> Dictionary:
	var copy := sizes.duplicate()
	copy.erase(id)
	return copy
