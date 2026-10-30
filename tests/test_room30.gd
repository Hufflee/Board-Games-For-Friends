extends SceneTree
## Живое обновление комнаты при переносе, вращение и новые поверхности. Запуск с Dummy/OpenGL.
var hub: Node
var owner: Node
var checks := 0
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	hub = load("res://hub/hub.gd").new()
	root.add_child(hub)
	owner = load("res://hub/neon_room.gd").new()
	root.add_child(owner)
	owner.visible = false
	await create_timer(0.7).timeout
	hub.set_process(false)
	var net: Node = root.get_node("Net")
	net.set_process(false)
	net.mode = "enet"
	net.lobby_view = {"members": [{"peer": 1, "name": "Я", "kind": "host"}, {"peer": 2, "name": "Владелец", "kind": "human"}]}
	net.public_rooms = {2: owner.public_snapshot()}
	hub._watch_room(2)
	var room: Node = hub._room
	room.camera.current = true
	var book: Node = owner.boxes.filter(func(box): return not box.is_figurine())[0]
	owner._pressed_box = book
	owner._start_drag()
	var held: Dictionary = owner.public_snapshot()
	var count := 0
	for row: Array in held.placements:
		count += row.size()
	check(count == owner.boxes.size(), "Живой снимок при поднятой книге содержит все ID")
	net.public_rooms[2] = held
	hub._on_public_room(2)
	check(hub._watch_peer == 2 and room.remote_view, "Поднятие книги не выкидывает наблюдателя")
	owner._drag_to = Vector2i(0, 0)
	owner._finish_drag(true)
	net.public_rooms[2] = owner.public_snapshot()
	hub._on_public_room(2)
	check(hub._watch_peer == 2 and room._shelf_ids() == owner._shelf_ids(), "Отпускание книги обновляет живую комнату")
	hub._toggle_watch_follow(true)
	room.focus_id("gloom")
	var cam: Transform3D = room._cam_home
	owner._box_modes.word_slam = 0
	net.public_rooms[2] = owner.public_snapshot()
	hub._on_public_room(2)
	check(not hub._watch_follow and room.focused.game.id == "gloom" and room._cam_home == cam, "Follow OFF сохраняет местный выбор и камеру при обновлении шкафа")
	var invalid: Dictionary = net.public_rooms[2].duplicate(true)
	invalid.placements[0].clear()
	net.public_rooms[2] = invalid
	hub._on_public_room(2)
	check(hub._watch_peer == 2, "Неполное обновление не завершает наблюдение")
	hub._watch_home(false)
	var girl: Node = room.boxes.filter(func(box): return room._shelf_id(box) == "shelf_girl")[0]
	room._select_shelf_box(girl)
	var before: Basis = girl.home.basis
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	Input.parse_input_event(event)
	await process_frame
	check(not girl.home.basis.is_equal_approx(before) and girl.home.basis.y.is_equal_approx(Vector3.UP), "E вращает выделенную фигурку вокруг вертикали")
	event = InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_Q
	Input.parse_input_event(event)
	await process_frame
	check(girl.home.basis.is_equal_approx(before), "Q вращает обратно")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	Input.parse_input_event(wheel)
	await process_frame
	check(not girl.home.basis.is_equal_approx(before), "Колесо вращает выделенную фигурку")
	var angle: float = room._cabinet.figure_yaw.shelf_girl
	room._save_shelf()
	var loaded := ShelfConfig.load_state(room._cabinet, room._shelf_ids(), room._shelf_sizes())
	check(is_equal_approx(loaded.config.figure_yaw.shelf_girl, angle), "Yaw сохраняется и загружается")
	room.open_shelf_editor()
	room._select_shelf_box(girl)
	room._rotate_figure(1)
	room.finish_shelf_editor(false)
	check(is_equal_approx(room._cabinet.figure_yaw.shelf_girl, angle), "Отмена редактора возвращает yaw")
	for surface: String in ["tv", "cabinet"]:
		room._pressed_box = girl
		room._start_drag()
		var point: Vector3 = room._figure_surface_position(girl, surface, 0.25)
		room._drag_update(room.camera.unproject_position(room._shelf_root.to_global(point)))
		check(room._drag_surface.get("surface", "") == surface, "Луч выбирает поверхность " + surface)
		room._finish_drag(true)
		check(girl.home.origin.is_equal_approx(point), "Фигурка стоит на поверхности " + surface)
		var snapshot: Dictionary = room.public_snapshot()
		check(snapshot.config.figure_surfaces.shelf_girl.surface == surface and snapshot.config.figure_yaw.has("shelf_girl"), "Публичный снимок переносит поверхность и yaw " + surface)
		await create_timer(0.7).timeout
		await process_frame
		root.get_texture().get_image().save_png("res://build/room30/" + surface + "720.png")
		var span: Array = room._figure_surface_span(girl, surface)
		if surface == "cabinet":
			var cube: Vector3 = room._shelf_root.to_local(room.shelf_top_right)
			check(span[1].x + room._figure_radius(girl) < cube.x - 0.055 / room.SHELF_SCALE, "Граница верха не допускает пересечения куба при любом yaw")
	room._save_shelf()
	loaded = ShelfConfig.load_state(room._cabinet, room._shelf_ids(), room._shelf_sizes())
	check(loaded.config.figure_surfaces == room._cabinet.figure_surfaces, "Поверхности сохраняются и загружаются")
	var own: Dictionary = room.public_snapshot()
	room.show_remote(owner.public_snapshot())
	room._select_shelf_box(girl)
	var remote_config: Dictionary = room._cabinet.duplicate(true)
	room._rotate_figure(1)
	check(room._cabinet == remote_config, "Вращение заблокировано в чужой комнате")
	room.return_home()
	check(room.public_snapshot() == own, "Возврат домой сохраняет yaw и поверхность")
	await create_timer(0.6).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://build/room30/room720.png")
	print("ROOM30 ", checks, "/", errors)
	net.mode = ""
	hub.queue_free()
	owner.queue_free()
	await process_frame
	quit(1 if errors else 0)
