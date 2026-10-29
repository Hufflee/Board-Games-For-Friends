extends SceneTree
## Общие контролы29: реальный стол WL, Enter, тема, fullscreen raster и resize. Dummy/отдельный APPDATA.
var checks := 0
var errors := 0
var net: Node
var prefs: Node
var app: Control
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func settle() -> void:
	await create_timer(0.3).timeout
func enter() -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/global_controls29/" + name + ".png")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	net = root.get_node("Net")
	prefs = root.get_node("Prefs")
	prefs.window_mode = "windowed"
	prefs.resolution = "1280x720"
	prefs._applied_res = ""
	prefs.ui_scale = 1.4
	prefs.apply()
	await settle()
	check(root.content_scale_factor == 1.0 and prefs.ui_scale == 1.0, "Старый масштаб нормализован")
	net.host_offline("wavelength")
	net.set_bots(3)
	check(net.start_game() == "", "Настоящая партия WL запущена")
	net.set_process(false)
	app = load("res://games/wavelength/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	var bar = app.screen._top
	check(not bar._menu_open, "Новая партия начинает со скрытого меню")
	bar.set_menu_open(true)
	await settle()
	for mode: String in ["light", "dark"]:
		prefs.set_value("theme_mode", mode)
		await settle()
		app = current_scene
		bar = app.screen._top
		check(bar._menu_open and bar._drawer.visible, "Меню пережило rebuild: " + mode)
		check(is_equal_approx(bar._esc_btn.modulate.a, 0.8 if mode == "light" else 0.2), "Контраст ESC: " + mode)
		check(bar._esc_btn.ink == Color.BLACK if mode == "light" else bar._esc_btn.ink != Color.BLACK, "Цвет ESC: " + mode)
		await shot("wl-" + mode + "-720")
		var settings: Control = load("res://games/king_of_12/ui/settings_screen.gd").new()
		app.add_child(settings)
		await settle()
		check(settings._resolutions.get_item_metadata(settings._resolutions.selected) == "1280x720", "Текущее разрешение выбрано: " + mode)
		var scale_labels := 0
		for label: Node in settings.find_children("*", "Label", true, false):
			if label.text == "Масштаб интерфейса":
				scale_labels += 1
		check(scale_labels == 0, "Настройка масштаба удалена")
		await shot("settings-" + mode + "-720")
		settings.queue_free()
		await process_frame
	bar = app.screen._top
	var chat = bar.chat
	chat.expanded = true
	await settle()
	check(chat._top_row.visible and chat._toggle.text == "Скрыть чат", "Скрыть чат внутри docked панели")
	check(bar._chat_btn.text == "Чат", "В полосе постоянная кнопка Чат")
	chat._input.grab_focus()
	chat._input.text = "Проверка глобальных контролов"
	await enter()
	check(chat.expanded and not chat._input.has_focus(), "Submit отпустил фокус и сохранил чат")
	check(chat._input.text.is_empty(), "Submit очистил поле")
	check(chat._log.get_parsed_text().contains("Проверка глобальных контролов"), "Сообщение доставлено")
	await enter()
	check(not chat.expanded, "Следующий Enter закрывает чат")
	await enter()
	check(chat.expanded and chat._input.has_focus(), "Enter открывает закрытый чат и фокусирует поле")
	chat.expanded = false
	var edit := LineEdit.new()
	app.add_child(edit)
	edit.grab_focus()
	await enter()
	check(not chat.expanded, "Enter чужого LineEdit не открывает чат")
	edit.queue_free()
	bar.set_menu_open(false)
	await settle()
	prefs.set_value("theme_mode", "light")
	await settle()
	app = current_scene
	check(not app.screen._top._menu_open, "Закрытое меню пережило rebuild")
	var key: Button = load("res://hub/escape_key.gd").new()
	key.set_ink(Color(0.9, 0.9, 0.9))
	check(is_equal_approx(key.modulate.a, 0.2), "Forced dark ESC не зависит от Prefs.light")
	key.free()
	app.queue_free()
	await process_frame
	var settings: Control = load("res://games/king_of_12/ui/settings_screen.gd").new()
	root.add_child(settings)
	await settle()
	root.size = Vector2i(1440, 810)
	await settle()
	check(prefs.current_resolution() == Vector2i(1440, 810), "Ручной resize меняет фактический raster")
	check(settings._resolutions.get_item_metadata(settings._resolutions.selected) == "1440x810", "Ручной размер виден выбранным")
	prefs.set_value("resolution", "1280x720")
	await settle()
	check(root.size == Vector2i(1280, 720), "Повторный выбор прежнего размера работает после resize")
	for window_mode: String in ["borderless", "exclusive"]:
		prefs.set_value("window_mode", window_mode)
		await settle()
		var physical := DisplayServer.window_get_size()
		check(physical == DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), "Fullscreen использует текущий монитор: " + window_mode)
		prefs.set_value("resolution", "1600x900")
		await settle()
		check(prefs.current_resolution() == Vector2i(1600, 900), "Fullscreen raster1600: " + window_mode)
		check(DisplayServer.window_get_size() == physical, "Fullscreen окно сохранило native размер")
		check(root.content_scale_factor == 1.0, "Raster не использует UIscale")
		check(settings._resolutions.get_item_metadata(settings._resolutions.selected) == "1600x900", "Fullscreen выбранное фактическое разрешение")
	prefs.set_value("window_mode", "windowed")
	prefs.set_value("resolution", "1280x720")
	await settle()
	check(root.size == Vector2i(1280, 720), "Возврат в окно восстанавливает физический размер")
	settings.queue_free()
	await process_frame
	prefs.apply()
	net.leave()
	net.host_offline("wavelength")
	net.set_bots(3)
	check(net.start_game() == "", "Следующая партия запущена")
	var next_app: Control = load("res://games/wavelength/ui/main.tscn").instantiate()
	root.add_child(next_app)
	current_scene = next_app
	await settle()
	check(not next_app.screen._top._menu_open, "Новая партия не наследует меню")
	next_app.queue_free()
	await process_frame
	net.leave()
	print("GLOBAL_CONTROLS29: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)


