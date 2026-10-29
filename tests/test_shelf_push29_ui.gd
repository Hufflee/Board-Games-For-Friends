extends SceneTree
## Реальный редактор: отмена миграции/невалидного переноса и мышиный сценарий.
var room: Node
var checks := 0
var errors := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	room = load("res://hub/neon_room.gd").new()
	root.add_child(room)
	await create_timer(1).timeout
	var cfg: Dictionary = room._cabinet.duplicate(true)
	cfg.rows = 4
	cfg.cols = 1
	cfg.width = 1.6
	cfg.erase("neighbor_order")
	var rows: Array = [["word_slam", "brodilka", "shelf_girl", "shelf_andy"], [], [], []]
	for box in room.boxes:
		var id: String = room._shelf_id(box)
		if not rows[0].has(id):
			rows[1 if rows[1].size() < 7 else 2].append(id)
	room._apply_shelf_state({"config": cfg, "placements": rows, "poses": {}})
	room.open_shelf_editor()
	var original: Array = room._shelf_ids()
	var original_cfg: Dictionary = room._cabinet.duplicate(true)
	var prefs: Array = room._editor_preferences.duplicate(true)
	var girl: Node
	for box in room.boxes:
		if room._shelf_id(box) == "shelf_girl":
			girl = box
	room._pressed_box = girl
	room._start_drag()
	check(room._cabinet.neighbor_order, "Начало жеста мигрирует старую геометрию")
	room._drag_to = Vector2i(3, 0)
	room._finish_drag(false)
	check(room._shelf_ids() == original and room._cabinet == original_cfg, "Отмена жеста восстанавливает точный снимок")
	check(room._editor_preferences == prefs, "Отмена не меняет предпочтения")
	room._pressed_box = girl
	room._start_drag()
	room._drag_to = Vector2i(-1, -1)
	room._finish_drag(true)
	check(room._shelf_ids() == original and room._cabinet == original_cfg, "Нехватка места возвращает весь предпросмотр")
	room._pressed_box = girl
	room._start_drag()
	room._drag_to = Vector2i(3, 0)
	room._finish_drag(true)
	check(room._shelf_ids()[3] == ["shelf_girl"], "Перенос в другую ячейку")
	check(room._cabinet.neighbor_order, "Успешный жест включает общий порядок")
	var transferred: Array = room._shelf_ids()
	var seen: Dictionary = {}
	var count := 0
	for row: Array in transferred:
		for id in row:
			seen[id] = true
			count += 1
	check(count == room.boxes.size() and seen.size() == count, "После переноса каждый ID присутствует ровно один раз")
	room._apply_shelf_state({"config": room._cabinet, "placements": transferred, "poses": room._box_modes})
	check(room._shelf_ids() == transferred, "Применение нового снимка сохраняет место фигурки в порядке")
	room.finish_shelf_editor(false)
	check(room._shelf_ids() == original and room._cabinet == original_cfg, "Отмена редактора восстанавливает старый порядок и геометрию")
	print("SHELF PUSH UI29: %d проверок, %d ошибок" % [checks, errors])
	if OS.get_environment("SHELF_UI") != "1":
		room.queue_free()
		await process_frame
		quit(1 if errors else 0)
		return
	room.open_shelf_editor()
	DisplayServer.window_set_title("Shelf Push29 UI")
	while true:
		await create_timer(1).timeout
		await process_frame
		root.get_texture().get_image().save_png("res://build/shelf_push29/ui.png")
		var output := {"rows": room._shelf_ids(), "positions": {}}
		for box in room.boxes:
			var pos: Vector2 = room.camera.unproject_position(box.global_position)
			output.positions[room._shelf_id(box)] = [pos.x, pos.y]
		var file := FileAccess.open("res://build/shelf_push29/ui.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(output))
		file.close()
