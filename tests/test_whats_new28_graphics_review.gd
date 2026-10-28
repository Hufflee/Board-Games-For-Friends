extends SceneTree
## Настоящий Hub: окно новостей,1280×720, обе настройки темы, реальные клики/прокрутка.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func frames() -> void:
	for index in 5:
		await process_frame
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await frames()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/batch28_hub/whats-" + name + ".png")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await frames()
	root.size = Vector2i(1280,720)
	var prefs: Node = root.get_node("Prefs")
	var old_theme: String = prefs.theme_mode
	for mode in ["light","dark"]:
		prefs.theme_mode = mode
		prefs.changed.emit()
		var hub: Control = load("res://hub/hub.tscn").instantiate()
		root.add_child(hub)
		current_scene = hub
		await create_timer(0.5).timeout
		var open_button: Button
		for button in hub.find_children("*","Button",true,false):
			if button.text == "Что нового?":
				open_button = button
		check(open_button != null, "Есть кнопка новостей: " + mode)
		await click(open_button)
		var news: Control
		for node in hub.get_children():
			if node.get_script() != null and node.get_script().resource_path == "res://hub/whats_new.gd":
				news = node
		check(news != null, "Клик открыл настоящее окно: " + mode)
		if news != null:
			var text: RichTextLabel = news.find_children("*","RichTextLabel",true,false)[0]
			check(root.get_visible_rect().encloses(text.get_global_rect()), "Область текста внутри720p: " + mode)
			check(text.get_parsed_text().contains("Перудо") and text.get_parsed_text().contains("первую ставку раунда нельзя делать на единицы"), "Актуальные пункты Перудо в тексте: " + mode)
			var close: Button
			for button in news.find_children("*","Button",true,false):
				check(root.get_visible_rect().encloses(button.get_global_rect()), "Кнопка целиком внутри720p: " + mode)
				if button.text == "Понятно":
					close = button
			for label in news.find_children("*","Label",true,false):
				check(root.get_visible_rect().encloses(label.get_global_rect()), "Заголовок/версия внутри720p: " + mode)
			await shot(mode + "-top")
			text.scroll_to_line(text.get_line_count() - 1)
			await frames()
			check(text.get_v_scroll_bar().value > 0, "Старая история доступна прокруткой: " + mode)
			await shot(mode + "-bottom")
			await click(close)
			check(not is_instance_valid(news), "Кнопка Понятно закрыла окно после прокрутки: " + mode)
		hub.queue_free()
		current_scene = null
		await frames()
	prefs.theme_mode = old_theme
	prefs.changed.emit()
	print("WHATS GRAPHICS LOW28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
