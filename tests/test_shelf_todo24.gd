extends Node
## Регрессии скругления коробок и добавления Энди в старые сохранения.
## Запуск: godot --headless --path . res://tests/test_shelf_todo24.tscn
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _ready() -> void:
	var dimensions := Vector3(0.06, 0.3, 0.26)
	var mesh := GameBox.rounded_body(dimensions)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var half := dimensions * 0.5
	for vertex in vertices:
		check(vertex.abs().x <= half.x + 0.00001 and vertex.abs().y <= half.y + 0.00001 and vertex.abs().z <= half.z + 0.00001, "Скругление не увеличивает коробку")
		check(not vertex.abs().is_equal_approx(half), "Острых углов корпуса нет")
	var cover := GameBox.rounded_cover(Vector2(0.26, 0.3))
	var points: PackedVector3Array = cover.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in points:
		check(not (is_equal_approx(absf(point.x), 0.13) and is_equal_approx(absf(point.y), 0.15)), "Обложка не имеет прямых углов")
	var sizes := {"a": Vector3(0.05, 0.25, 0.22), "perudo": Vector3(0.38, 0.17, 0.26), "shelf_girl": Vector3(0.14, 0.285, 0.14), "shelf_andy": Vector3(0.15, 0.152, 0.30)}
	var cfg := {"rows": 4, "cols": 1, "width": 0.65, "height": 0.36, "cups": 2}
	var path := "user://test_andy_migration.cfg"
	ShelfConfig.save_state(cfg, [["a"], [], ["perudo", "shelf_girl"], []], {}, path)
	var state := ShelfConfig.load_state(cfg, [["a"], [], ["perudo", "shelf_girl", "shelf_andy"], []], sizes, path)
	check(state.ok, "Старое сохранение принимается")
	check(state.placements[2].has("shelf_andy") and state.placements[2].has("perudo"), "Энди добавлен в сохранённую ячейку Перудо")
	check(state.placements[0] == ["a"], "Остальные игры сохраняют ячейки")
	var layout := ShelfConfig.row_layout(state.placements[2], sizes, {}, 0.36, state.config.figure_positions, float(state.config.width) - ShelfConfig.GAP)
	check(float(layout.width) <= float(state.config.width) - ShelfConfig.GAP + 0.0005, "Обе фигурки и Перудо помещаются")
	var girl: Vector3 = layout.boxes.shelf_girl.origin
	var andy: Vector3 = layout.boxes.shelf_andy.origin
	check(absf(girl.x - andy.x) >= 0.145 - 0.0005, "Фигурки не пересекаются")
	state.config.figure_positions.shelf_andy = 0.0
	ShelfConfig.save_state(state.config, state.placements, state.poses, path)
	var restored := ShelfConfig.load_state(cfg, [], sizes, path)
	check(restored.config.figure_positions.shelf_andy == 0.0, "Место Энди сохраняется отдельно")
	check(restored.config.figure_positions.shelf_girl == state.config.figure_positions.shelf_girl, "Перенос Энди не меняет личное место первой фигурки")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SHELF TODO24: %d проверок, %d ошибок" % [checks, errors])
	get_tree().quit(0 if errors == 0 else 1)
