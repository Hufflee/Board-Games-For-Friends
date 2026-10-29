extends SceneTree
## Единый порядок фигурок и коробок, миграция, стопки, упаковка и сохранение.
var checks := 0
var errors := 0
var sizes := {"a": Vector3(0.08, 0.22, 0.18), "b": Vector3(0.08, 0.22, 0.18), "c": Vector3(0.08, 0.22, 0.18), "shelf_girl": Vector3(0.14, 0.28, 0.14), "shelf_andy": Vector3(0.15, 0.15, 0.3)}
var cfg := {"rows": 2, "cols": 1, "width": 0.7, "height": 0.36, "cups": 0, "figure_positions": {"shelf_girl": 0.5, "shelf_andy": 1.0}}
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func layout(ids: Array, poses: Dictionary = {}) -> Dictionary:
	return ShelfConfig.row_layout(ids, sizes, poses, 0.36, ShelfConfig.figure_ratios(cfg), 0.694)
func _initialize() -> void:
	var old := layout(["a", "b", "shelf_girl", "shelf_andy"])
	check(is_equal_approx(old.boxes.shelf_girl.origin.x, 0.347), "Старая свободная позиция не меняется")
	var order := ShelfConfig.visible_order(["shelf_andy", "a", "shelf_girl", "b"], sizes, {}, cfg)
	check(order == ["a", "b", "shelf_girl", "shelf_andy"], "Миграция следует видимому порядку")
	cfg.neighbor_order = true
	for ids: Array in [["shelf_girl", "a", "b"], ["a", "shelf_girl", "b"], ["a", "b", "shelf_girl"], ["shelf_andy", "a", "shelf_girl", "b"], ["shelf_girl", "a", "shelf_andy", "b"]]:
		var row := layout(ids)
		check(row.piles.size() == ids.size(), "Фигурки входят в общий порядок отдельными группами")
		var edge := 0.0
		for pile: Dictionary in row.piles:
			check(is_equal_approx(float(pile.x), edge), "Соседи сдвинуты без перекрытий и старых препятствий")
			edge += float(pile.width)
		check(is_equal_approx(edge, row.width), "Вместимость использует ту же геометрию")
	for ids: Array in [["shelf_girl", "a", "b", "shelf_andy"], ["shelf_andy", "a", "b", "shelf_girl"]]:
		var row := layout(ids, {"a": 2, "b": 2, "shelf_girl": 0})
		check(row.piles.size() == 3 and row.piles[1].ids == ["a", "b"], "Фигурки по краям не входят в горизонтальную стопку")
		check(row.boxes.b.origin.y > row.boxes.a.origin.y, "Высота и порядок стопки сохранены")
	var rows := [["shelf_girl", "a", "b"], ["shelf_andy", "c"]]
	var state := ShelfConfig.solve(cfg, rows, sizes, {})
	check(state.ok and state.placements == rows, "Общий решатель сохраняет ручной порядок и ячейки")
	var path := "user://shelf_push29.cfg"
	check(ShelfConfig.save_state(cfg, rows, {}, path) == OK, "Новый порядок сохраняется")
	var restored := ShelfConfig.load_state(cfg, rows, sizes, path)
	check(restored.ok and restored.placements == rows and restored.config.neighbor_order, "Перезапуск сохраняет новый порядок")
	var packed := ShelfConfig.solve({"rows": 1, "cols": 3, "width": 0.506, "height": 0.36, "cups": 0, "neighbor_order": true}, [["0", "1", "2", "3", "4", "5"]], {"0": Vector3(.3,.3,.2), "1": Vector3(.3,.3,.2), "2": Vector3(.13,.3,.2), "3": Vector3(.13,.3,.2), "4": Vector3(.2,.3,.2), "5": Vector3(.2,.3,.2)}, {})
	check(packed.ok, "Поисковая упаковка сохраняет единую геометрию")
	DirAccess.remove_absolute(path)
	print("SHELF PUSH29: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
