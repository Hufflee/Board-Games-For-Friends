extends SceneTree
## Новый предмет в настоящем шкафу: миграция старого defaults, клик коробки и путь в лобби.
var checks := 0
var errors := 0

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func click_at(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	Input.parse_input_event(move)
	await process_frame
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await create_timer(0.4).timeout

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hub: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(3).timeout
	var box: Node3D = null
	var count := 0
	for item: Node3D in hub._room.boxes:
		if item.game.get("id") == "things_in_rings":
			box = item
			count += 1
	check(count == 1, "Старая расстановка автоматически включила ровно одну новую коробку")
	for side: String in ["front", "back", "spine"]:
		check(load("res://hub/game_box.gd").cover_texture("things_in_rings", side) is Texture2D, "Обложка загружена: " + side)
	if box == null:
		quit(1)
		return
	var at: Vector2 = hub._room.camera.unproject_position(box.global_position)
	check(Rect2(Vector2.ZERO, Vector2(1280,720)).has_point(at), "Новая коробка видна в720p")
	check(hub._room._box_at(at) == box, "Луч клика достигает новой коробки")
	await click_at(at)
	check(hub._room.focused == box and hub._selected.get("id") == "things_in_rings", "Реальный клик открыл новую коробку")
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tir_game/hub-box.png")
	var play: Button = null
	for button: Node in hub.find_children("*", "Button", true, false):
		if button.text == "Играть":
			play = button
	check(play != null, "Новая игра доступна к запуску")
	await click_at(play.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 12000
	while load("res://hub/luma_wipe.gd").is_running() and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.2).timeout
	check(current_scene.scene_file_path == "res://games/things_in_rings/ui/main.tscn", "Клик Играть открыл новое приложение")
	var local: Button = null
	for button: Node in current_scene.find_children("*", "Button", true, false):
		if button.text == "За одним компьютером":
			local = button
	await click_at(local.get_global_rect().get_center())
	check(root.get_node("Net").mode == "offline" and current_scene.screen.find_child("StartGame", true, false) != null, "Из хаба реальными кликами достигнуто лобби")
	root.get_node("Net").leave()
	current_scene.queue_free()
	await process_frame
	print("TIR HUB: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
