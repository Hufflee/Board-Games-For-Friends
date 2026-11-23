extends SceneTree
## BGSocial: компактное нативное окно, раскрытие, перенос и меню на общем рабочем столе.
## godot --audio-driver Dummy --path . --script res://tests/test_social_window.gd

var errors := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)


func click(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)


func run() -> void:
	root.set_meta(&"bgs_social", true)
	var scene: Control = load("res://hub/social/social.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.5).timeout
	var panel: Control = scene.get("_panel")
	var desktop: Rect2i = scene.get("_desktop")
	var region: Rect2i = scene.get("_window_rect")
	print("COMPACT native=", DisplayServer.window_get_size(), " min=",root.min_size," max=",root.max_size," wrap=",root.wrap_controls," mode=",root.mode," scale=",root.content_scale_size, " size=", root.size, " rect=", region, "panel=", panel.get_global_rect(), " extras=", scene.get("_extras"))
	check(root.size.x < desktop.size.x / 2 and root.size.y < 150, "Свёрнутая кнопка не создаёт нативное окно на весь рабочий стол.")
	var mini_at := panel.get_global_rect().get_center() - Vector2(region.position)
	click(mini_at, true)
	await process_frame
	click(mini_at, false)
	await create_timer(0.3).timeout
	check(panel.is_open(), "Кнопка раскрывается настоящим щелчком после смещения холста.")
	region = scene.get("_window_rect")
	check(root.size.x <= ceili(panel.size.x) + 20 and root.size.y <= ceili(panel.size.y) + 20, "Открытая панель занимает своё нативное окно.")
	var stage_before := panel.position
	var start := panel.position + Vector2(120, 15)
	var shift := Vector2(-70, -60)
	click(start - Vector2(region.position), true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = start + shift - Vector2(region.position)
	motion.global_position = motion.position
	motion.relative = shift
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await create_timer(0.1).timeout
	region = scene.get("_window_rect")
	click(start + shift - Vector2(region.position), false)
	await create_timer(0.2).timeout
	print("DRAG before=", stage_before, " after=", panel.position, " window=", root.position, "rect=", region)
	check(panel.position.distance_to(stage_before + shift) < 2.0, "Перенос сохраняет координаты при изменении размера нативного окна.")
	check(root.size.x < desktop.size.x and root.size.y < desktop.size.y, "После переноса окно снова ограничено панелью.")
	panel.call("_toggle_friends_menu", (panel.get("header_extra") as HBoxContainer).get_child(1))
	await create_timer(0.2).timeout
	check(is_instance_valid(panel.get("_menu")) and panel.get("_menu").visible, "Меню друзей открывается в компактном окне.")
	if not OS.get_environment("SOCIAL_WINDOW_SHOT").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SOCIAL_WINDOW_SHOT"))
	panel.call("_close_menu")
	panel.set_mode(1)
	await create_timer(0.2).timeout
	check(root.size.y < 150, "Повторное сворачивание возвращает компактный размер.")
	print("SOCIAL WINDOW: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
