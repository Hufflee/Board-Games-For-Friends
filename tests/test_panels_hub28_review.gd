extends SceneTree
## Настоящие Hub/камера: лучи и InputEvent, выбор/редактор после масштабирования сетки.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func frames() -> void:
	for index in 4:
		await process_frame

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await frames()

func escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		Input.parse_input_event(event)
		await frames()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/batch28_hub/low-" + name + ".png")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	var hub: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(1.0).timeout
	var room: Node = hub._room
	var panels: Node3D = room.panels
	var camera: Camera3D = room.camera
	check(panels.camera == camera and camera.is_current(), "Используется настоящая текущая камера Hub")
	await click(camera.unproject_position(panels._launcher.global_position))
	await create_timer(0.06 * panels._items.size() + 1.4).timeout
	check(panels.is_open, "Настоящий клик по кубу открыл панели")
	check(panels._grid_scale > 0 and panels._grid_scale < 1, "Реальный каталог использует уменьшенную сетку")
	var visible_rect := root.get_visible_rect()
	for item: Dictionary in panels._items:
		var dimensions: Vector2 = item.mesh.mesh.size
		for corner in [Vector2(-1,-1), Vector2(-1,1), Vector2(1,-1), Vector2(1,1)]:
			var point := camera.unproject_position(item.root.to_global(Vector3(corner.x * dimensions.x / 2, corner.y * dimensions.y / 2, 0)))
			check(visible_rect.has_point(point), "Угол панели внутри настоящего viewport: " + str(item.game.id))
	await shot("panels-hub")
	var selected := -1
	for index in panels._items.size():
		if panels._items[index].game.id == "the_gang":
			selected = index
	check(selected >= 0, "В каталоге есть целевая The Gang")
	if selected >= 0:
		await click(camera.unproject_position(panels._items[selected].root.global_position))
		await create_timer(0.8).timeout
		check(panels._selected == selected and hub._selected.get("id", "") == "the_gang", "Клик уменьшенной панели выбирает правильную игру")
		check(panels._items[selected].root.scale.x > 1.2, "Выбор увеличивается независимо от масштаба сетки")
		await shot("panels-selected")
		await escape()
		await create_timer(0.8).timeout
		check(panels._selected == -1 and hub._selected.is_empty() and panels.is_open, "Escape снимает выбор, сохраняя сетку")
	await click(camera.unproject_position(panels._editor_tile.global_position))
	await create_timer(0.3).timeout
	check(room._editor_on and panels.input_locked and not panels.is_open, "Клик масштабированного значка открывает настоящий редактор")
	await click(camera.unproject_position(panels._launcher.global_position))
	check(not panels.is_open and panels.input_locked, "Редактор блокирует открытие панелей")
	await escape()
	check(not room._editor_on and not panels.input_locked, "Отмена редактора возвращает право ввода")
	await click(camera.unproject_position(panels._launcher.global_position))
	await create_timer(0.06 * panels._items.size() + 1.4).timeout
	check(panels.is_open, "После отмены редактора сетка снова открывается")
	await escape()
	check(not panels.is_open, "Escape закрывает невыбранную сетку")
	print("PANELS HUB LOW28: проверок=", checks, " ошибок=", errors)
	hub.queue_free()
	current_scene = null
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
