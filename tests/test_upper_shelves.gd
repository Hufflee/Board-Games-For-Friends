extends SceneTree
## Проверяет куб, сетку, полки и коробки в настоящем хабе.
## Godot --audio-driver Dummy --resolution 1280x720 --script res://tests/test_upper_shelves.gd

const Upper := preload("res://hub/upper_shelves.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func click(position: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func line(room: Node, a: Vector2i, b: Vector2i) -> void:
	click(room._upper_screen(Upper.point(a), room._upper_grid_depth()), true)
	await process_frame
	click(room._upper_screen(Upper.point(b), room._upper_grid_depth()), false)
	await process_frame


func shot(name: String) -> void:
	var path := OS.get_environment("SHELF_SHOTS")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join(name + ".png"))


func run() -> void:
	var mode := OS.get_environment("UPPER_THEME")
	if mode in ["light", "dark"]:
		root.get_node("Prefs").set("theme_mode", mode)
	var joined := Upper.geometry(Upper.read({"upper_edges": [[-1, 4, 0, 4], [0, 4, 2, 4]]}), 0.0)
	check(joined.flat["above:-1:0:4"] == joined.flat["above:0:2:4"], "Соседние горизонтали поддерживают коробку вместе.")
	check(is_equal_approx(Upper.BASIC_TICKS * Upper.UNIT, 0.165), "Обычный шаг увеличен на 10%.")
	check(is_equal_approx(Upper.FINE_TICKS * Upper.UNIT, 0.0825), "Мелкий шаг составляет четверть увеличенной коробки.")
	check(Upper.point(Vector2i(20, 20)).is_equal_approx(Vector2(0.15, 2.485)), "Старые координаты остаются на прежнем месте.")
	var hub: Node = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	await create_timer(2.0).timeout
	var room: Node = hub.get("_room")
	if room == null or not is_instance_valid(room.get("_shelf_cube")):
		check(false, "Не загрузился куб шкафа.")
		quit(1)
		return
	var cube: Node3D = room._shelf_cube._launcher
	var first: Vector2 = room.camera.unproject_position(cube.global_position)
	click(first, true)
	await process_frame
	click(first, false)
	await process_frame
	check(room._editor_on, "Клик по кубу открывает редактор сразу.")
	if not room._editor_on:
		quit(1)
		return
	var button: Button = room._editor_ui.find_child("EditorUpperShelves", true, false)
	button.pressed.emit()
	await create_timer(1.3).timeout
	check(room._upper_edit, "Кнопка открывает сетку.")
	var high := {"rows": 3, "cols": 1, "width": 1.7, "height": 0.7}
	high.row_heights = [0.7, 0.7, 0.7, 0.15]
	high.rows = 4
	check(room._upper_floor(high) < Upper.point(Vector2i(0, Upper.GRID_TOP + Upper.BASIC_TICKS)).y, "Над шкафом предельного размера остаются хотя бы две строки.")
	check(Upper.point(Vector2i(0, Upper.GRID_TOP + Upper.BASIC_TICKS)).y + Upper.THICKNESS * 0.5 + 0.30 * 0.95 < 2.79, "На нижней линии над высоким шкафом хватает места средней коробке.")
	var pane: Control = room._editor_ui.get("_upper_panel")
	check(room._upper_screen(Upper.point(Vector2i(Upper.HALF_WIDTH, Upper.GRID_TOP))).x < pane.position.x, "Крайняя колонка сетки доступна рядом с панелью.")
	var start := Vector2i(-154, 42)
	var left := Vector2i(-110, 86)
	var right := Vector2i(44, 86)
	var end := Vector2i(44, 53)
	check(room._upper_point_at(room._upper_screen(Upper.point(start))) == start, "Точка обычной сетки доступна над шкафом.")
	await line(room, start, left)
	await line(room, left, right)
	var grid: OptionButton = room._editor_ui.find_child("UpperShelfGrid", true, false)
	grid.select(1)
	grid.item_selected.emit(1)
	check(room._upper_grid_points().has(end), "На мелкой сетке доступны промежуточные точки.")
	await line(room, right, end)
	grid.select(0)
	grid.item_selected.emit(0)
	check(room._upper_grid_points().has(end), "Узел мелкой сетки остаётся доступен в обычной.")
	check(Upper.read(room._cabinet).size() == 3, "ЛКМ строит три соединённых отрезка в двух режимах.")
	check(room._upper_spans.size() == 1, "У диагонали и вертикали нет поверхности для коробок.")
	if room._upper_spans.is_empty():
		quit(1)
		return
	var slider: HSlider = room._editor_ui.find_child("UpperShelfSmoothing", true, false)
	slider.value = 0.85
	await create_timer(0.35).timeout
	check(room._upper_lines.size() == 5, "Два поворота заменены кривыми.")
	var depth: OptionButton = room._editor_ui.find_child("UpperShelfDepth", true, false)
	depth.select(1)
	depth.item_selected.emit(1)
	var narrow_start := Vector2i(110, 64)
	var narrow_end := Vector2i(198, 64)
	var edge_point := Upper.point(narrow_end)
	var normal_screen: Vector2 = room._upper_screen(edge_point)
	var shallow_screen: Vector2 = room.camera.unproject_position(Vector3(edge_point.x, edge_point.y, Upper.FRONT - Upper.SHALLOW_DEPTH))
	check(normal_screen.distance_to(shallow_screen) > 1.0, "Смена глубины заметно сдвигает проекцию точки сетки.")
	check(room._upper_point_at(shallow_screen) == narrow_end, "Захват совпадает с точкой на передней кромке половинной полки.")
	await line(room, narrow_start, narrow_end)
	var narrow_surface := Upper.surface(Upper.edge(narrow_start, narrow_end))
	var main_surface := Upper.surface(Upper.edge(left, right))
	check(room._upper_depths.get(main_surface) == Upper.DEPTH and room._upper_depths.get(narrow_surface) == Upper.DEPTH * 0.5, "У отдельных полок может быть разная глубина.")
	var narrow_mid := (Upper.point(narrow_start) + Upper.point(narrow_end)) * 0.5
	var narrow_at: Vector2 = room._upper_screen(narrow_mid, Upper.SHALLOW_DEPTH)
	click(narrow_at, true)
	await process_frame
	click(narrow_at, false)
	await process_frame
	check(room.upper_has_selection() and depth.selected == 1, "Клик выбирает существующую узкую полку.")
	depth.select(0)
	depth.item_selected.emit(0)
	check(room._upper_depths[narrow_surface] == Upper.DEPTH, "Глубину существующей полки можно изменить.")
	check(room._upper_grid_depth() == Upper.DEPTH and room._upper_point_at(normal_screen) == narrow_end, "После изменения глубины сетка следует за выбранной полкой.")
	depth.select(1)
	depth.item_selected.emit(1)
	check(room._upper_depths[narrow_surface] == Upper.SHALLOW_DEPTH and room._upper_depths[main_surface] == Upper.DEPTH, "Смена глубины затрагивает только выбранную полку.")
	await line(room, right, narrow_start)
	check(Upper.read(room._cabinet).size() == 4, "Полки разной глубины нельзя соединить случайно.")
	var depths: Array[float] = []
	for shelf: MeshInstance3D in room._upper_root.get_children():
		depths.append(shelf.mesh.get_aabb().size.z)
	check(depths.size() == 2 and is_equal_approx(depths[0], 0.36) and is_equal_approx(depths[1], 0.18), "Меши полок имеют разную глубину и общий задний край.")
	var straight: Array = room._upper_support[narrow_surface]
	var exact_width: float = straight[1].x - straight[0].x
	check(not room._upper_open_ranges(narrow_surface, Vector3(exact_width, 0.10, Upper.SHALLOW_DEPTH)).is_empty(), "Точный размер горизонтального участка не требует лишнего зазора.")
	check(room._upper_open_ranges(narrow_surface, Vector3(exact_width + 0.01, 0.10, Upper.SHALLOW_DEPTH)).is_empty(), "Слишком широкая коробка не может выступать за полку.")
	var main_flat: Array = room._upper_spans[main_surface]
	var near_joint_width: float = main_flat[1].x - main_flat[0].x - 0.004
	check(not room._upper_open_ranges(main_surface, Vector3(near_joint_width, 0.30, 0.30)).is_empty(), "Габаритная коробка помещается у закруглённого диагонального стыка.")
	var color := Color("674a65")
	room.set_shelf_color(color)
	var mesh: MeshInstance3D = room._upper_root.get_child(0)
	var material: ShaderMaterial = mesh.mesh.surface_get_material(0)
	check(material.get_shader_parameter("albedo") == color, "Цвет существующих полок меняется вместе со шкафом.")
	check(material.shader == preload("res://hub/soft_box.gdshader"), "Полка использует шейдер мебели.")
	check(material.get_shader_parameter("grain") == 1.0 and material.get_shader_parameter("clearcoat_amount") == 0.55, "Полка использует деревянную фактуру и лак шкафа.")
	await shot("upper_shelf_editor")
	grid.select(1)
	grid.item_selected.emit(1)
	await shot("upper_shelf_grid_fine")
	button.pressed.emit()
	await create_timer(1.0).timeout
	var surface: String = room._upper_spans.keys()[0]
	var box: Node
	for candidate: Node in room.boxes:
		var anchor: Dictionary = room._cabinet.get("figure_surfaces", {}).get(room._shelf_id(candidate), {})
		if anchor.is_empty() and not candidate.is_figurine() and room._upper_extent(candidate).z > Upper.SHALLOW_DEPTH and room._upper_can_place(candidate, surface, 0.5):
			box = candidate
			break
	check(box != null, "На горизонтальную полку входит коробка.")
	if box == null:
		quit(1)
		return
	check(not room._upper_can_place(box, narrow_surface, 0.5), "Глубокая коробка не помещается на узкую полку.")
	var legacy_home: Transform3D = room._upper_placed_home(box, {"surface": surface, "x": 0.25})
	var inset: float = room._upper_extent(box).x * 0.5 + 0.005
	var legacy_x := lerpf(main_flat[0].x + inset, main_flat[1].x - inset, 0.25)
	check(is_equal_approx(room._shelf_root.to_global(legacy_home.origin).x, legacy_x), "Старая расстановка сохраняет точную позицию коробки.")
	# Перенос тем же обработчиком мыши, которым пользуется редактор.
	var source: Vector2 = room.camera.unproject_position(box.global_position)
	var requested_world: Vector3 = room._shelf_root.to_global(room._upper_home(box, surface, 0.0).origin)
	var target: Vector2 = room.camera.unproject_position(requested_world)
	click(source, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.relative = target - source
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	click(target, false)
	await create_timer(0.4).timeout
	var id: String = room._shelf_id(box)
	var anchor: Dictionary = room._cabinet.get("figure_surfaces", {}).get(id, {})
	check(anchor.get("surface") == surface and anchor.get("fit") == true, "Отпускание ставит коробку на верхнюю полку.")
	check(
		room._shelf_root.to_global(box.home.origin).x > requested_world.x + 0.001
		and room._upper_can_place(box, surface, float(anchor.get("x", 0.0))),
		"Коробка привязывается к ближайшему свободному месту у диагонали."
	)
	check(not room._upper_can_place(box, "above:несуществующая", 0.5), "Без горизонтальной поверхности коробка не ставится.")
	var snapshot: Dictionary = room.public_snapshot()
	check(snapshot.get("config", {}).get("figure_surfaces", {}).get(id, {}).get("surface") == surface, "Снимок комнаты сохраняет полку и коробку.")
	room.finish_shelf_editor(true)
	await create_timer(0.8).timeout
	await shot("upper_shelf_room")
	var placed: Transform3D = box.home
	var selected_at: Vector2 = room.camera.unproject_position(box.global_position)
	click(selected_at, true, MOUSE_BUTTON_RIGHT)
	await process_frame
	click(selected_at, false, MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	check(room._selected_box == box and room._pose_button.visible, "ПКМ по коробке на верхней полке открывает смену положения.")
	check(room._lift_box == null and box.transform.is_equal_approx(placed), "Выделенная коробка остаётся на верхней полке.")
	var old_mode: int = room._box_modes.get(id, 1)
	var next_mode := (1 - old_mode) if box.is_cups() else (old_mode + 1) % 4
	room._box_modes[id] = next_mode
	var next_fits: bool = room._upper_can_place(box, surface, float(anchor.x))
	room._box_modes[id] = old_mode
	room._pose_button.pressed.emit()
	await create_timer(0.35).timeout
	check(int(room._box_modes.get(id, 1)) == (next_mode if next_fits else old_mode), "Поворот проверяет вместимость верхней полки.")
	check(room._cabinet.figure_surfaces[id].surface == surface and box.transform.is_equal_approx(box.home), "После поворота коробка остаётся на той же полке.")
	room._clear_shelf_selection()
	room._box_modes[id] = old_mode
	room._reflow(false)
	room._save_shelf()
	var stored := ConfigFile.new()
	check(stored.load(ShelfConfig.FILE) == OK, "Расстановка сохранена.")
	var config: Dictionary = stored.get_value("cabinet", "geometry", {})
	check(Upper.read(config).size() == 4, "Геометрия полки сохранена.")
	check(config.get("upper_fine_grid", false) == true, "Выбранный шаг сетки сохранён.")
	check(config.get("figure_surfaces", {}).get(id, {}).get("surface") == surface, "Место коробки сохранено.")
	var loaded := ShelfConfig.load_state(config, stored.get_value("cabinet", "placements"), room._shelf_sizes())
	check(Upper.read(loaded.config).size() == 4 and loaded.config.figure_surfaces[id].surface == surface, "Загрузка сохраняет форму полки и положение коробки.")
	var friend: Dictionary = room.public_snapshot()
	friend.config.wood = "705786"
	check(room.show_remote(friend), "Наблюдение принимает снимок с верхними полками.")
	check(room._upper_spans.has(surface) and box.home.is_equal_approx(room._upper_home(box, surface, float(anchor.x))), "В комнате друга коробка стоит на верхней полке.")
	room.return_home()
	check(room._upper_spans.has(surface) and room.shelf_wood == color, "Возвращение домой восстанавливает полку и цвет.")
	room.open_shelf_editor()
	var retry: Button = room._editor_ui.find_child("EditorUpperShelves", true, false)
	retry.pressed.emit()
	await create_timer(1.0).timeout
	var depth_after: OptionButton = room._editor_ui.find_child("UpperShelfDepth", true, false)
	var main_mid := (Upper.point(left) + Upper.point(right)) * 0.5
	var main_at: Vector2 = room._upper_screen(main_mid)
	click(main_at, true)
	await process_frame
	click(main_at, false)
	await process_frame
	check(room.upper_has_selection(), "Занятая широкая полка выбирается.")
	depth_after.select(1)
	depth_after.item_selected.emit(1)
	check(room._upper_depths[main_surface] == Upper.DEPTH and depth_after.selected == 0, "Полку с глубокой коробкой нельзя сузить.")
	check(room._upper_depths[narrow_surface] == Upper.SHALLOW_DEPTH, "Узкая полка сохраняется после наблюдения и возврата.")
	var midpoint := (Upper.point(right) + Upper.point(end)) * 0.5
	click(room._upper_screen(midpoint), true, MOUSE_BUTTON_RIGHT)
	await process_frame
	check(Upper.read(room._cabinet).size() == 3, "ПКМ убирает свободный отрезок.")
	room.finish_shelf_editor(false)
	check(Upper.read(room._cabinet).size() == 4, "Отмена возвращает полку к сохранённому виду.")
	hub.queue_free()
	await process_frame
	print("Верхние полки: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
