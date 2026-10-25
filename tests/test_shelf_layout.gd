extends SceneTree
## Проверка личной раскладки шкафа (hub/shelf_layout.gd): вставка между коробками, ширина полок, сохранение.
## Запуск: godot --headless --path . --script res://tests/test_shelf_layout.gd
const Layout := preload("res://hub/shelf_layout.gd")
var checks := 0
var failed := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(text)


func _initialize() -> void:
	var sizes := {"a": Vector3(0.05, 0.28, 0.24), "b": Vector3(0.05, 0.28, 0.24), "c": Vector3(0.05, 0.28, 0.24)}
	var row := ["a", "b", "c"]
	var poses := {"a": 2, "b": 2}
	var layout := ShelfConfig.row_layout(row, sizes, poses, 0.36)
	check(layout.piles.size() == 2, "Две лежащие коробки образуют одну стопку")
	var center: float = float(layout.piles[0].width) * 0.5
	check(Layout.pile_insert_index(layout.piles, row, center - 0.01) == 0, "Слева от середины стопки — щель перед всей стопкой")
	check(Layout.pile_insert_index(layout.piles, row, center + 0.01) == 2, "Справа от середины стопки — место после всей стопки")
	check(Layout.pile_insert_index([], [], 0.5) == 0, "Вставка на пустую полку")
	var before := ShelfConfig.row_layout(["c", "a", "b"], sizes, poses, 0.36)
	check(before.boxes.a.origin.x > layout.boxes.a.origin.x + 0.04, "Стоящая коробка раздвигает горизонтальную стопку")
	check(is_equal_approx(before.boxes.a.origin.x - layout.boxes.a.origin.x, before.boxes.b.origin.x - layout.boxes.b.origin.x), "Обе коробки стопки смещаются вместе")
	# куда встанет коробка: по центрам соседей
	check(Layout.insert_index([0.1, 0.2, 0.3], 0.05) == 0, "Левее всех — первая")
	check(Layout.insert_index([0.1, 0.2, 0.3], 0.25) == 2, "Между второй и третьей")
	check(Layout.insert_index([0.1, 0.2, 0.3], 0.9) == 3, "Правее всех — последняя")
	check(Layout.insert_index([], 0.5) == 0, "Пустая полка")
	var widths := {"a": 0.07, "b": 0.08, "c": 0.07, "d": 0.1}
	check(is_equal_approx(Layout.row_width(["a", "b"], widths), 0.15), "Ширина полки — сумма толщин")
	check(Layout.fits(["a", "b"], widths, 0.15), "Впритык влезает")
	check(not Layout.fits(["a", "b", "c"], widths, 0.2), "Лишняя коробка не влезает")
	var defaults := [["a", "b"], ["c", "d"]]
	var limits := [0.3, 0.3]
	var path := "user://test_shelf_layout.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Layout.load_rows(defaults, widths, limits, path) == defaults, "Без файла — раскладка по умолчанию")
	check(Layout.save_rows([["b", "c", "a"], ["d"]], path) == OK, "Сохранение")
	check(Layout.load_rows(defaults, widths, limits, path) == [["b", "c", "a"], ["d"]], "Восстановление порядка и полок")
	Layout.save_rows([["b", "x", "b"], ["d"]], path)
	check(Layout.load_rows(defaults, widths, limits, path) == [["b", "a"], ["d", "c"]], "Удалённые и повторы пропускаются, недостающие — на свою полку")
	Layout.save_rows([["a", "b", "c", "d"], []], path)
	check(Layout.load_rows(defaults, widths, limits, path) == defaults, "Не влезает — раскладка по умолчанию")
	Layout.save_rows([["a"]], path)
	check(Layout.load_rows(defaults, widths, limits, path) == defaults, "Другое число полок — по умолчанию")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SHELF: %d проверок, %d ошибок" % [checks, failed])
	quit(0 if failed == 0 else 1)
