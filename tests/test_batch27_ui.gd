extends Control
## Регрессия темы/фильтров и настоящий мышиный ввод чата. Dummy, отдельный APPDATA.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	await get_tree().create_timer(0.25).timeout

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func start_game(id: String) -> Control:
	Net.leave()
	var app: Control = load("res://games/%s/ui/main.tscn" % id).instantiate()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	Net.host_offline(id)
	Net.set_bots(2)
	check(Net.start_game() == "", "Запуск " + id)
	Net.set_process(false)
	await settle()
	return app

func close_game(app: Control) -> void:
	Net.leave()
	get_tree().current_scene = self
	app.queue_free()
	await settle()

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_run.call_deferred()

func _run() -> void:
	var board_type = load("res://games/hues_and_cues/ui/hc_board.gd")
	var original := Color(0.8, 0.3, 0.1)
	for channel in 3:
		var tint: Color = [Color("3b62ff"), Color("39ed64"), Color("ff404b")][channel]
		check(board_type.filtered_color(original, channel).is_equal_approx(original.lerp(tint, 0.5103)), "Цветной фильтр ослаблен на10%")
	var gray := original.r * 0.2126 + original.g * 0.7152 + original.b * 0.0722
	check(board_type.filtered_color(original, 3).is_equal_approx(original.lerp(Color(gray, gray, gray), 0.8)), "ЧБ ослаблен на20%")
	check(board_type.filtered_color(original, -1) == original, "Без фильтра цвет не меняется")
	Net.settings.hc_mode = "distorted"
	var app := await start_game("hues_and_cues")
	var table: Control = app.screen
	table._board.set_process(false)
	table._board._reveal_elapsed = 1.4
	var match_before: String = Net.game_id
	Prefs.theme_mode = "dark" if Prefs.theme_mode != "dark" else "light"
	Prefs.changed.emit()
	await settle()
	app = get_tree().current_scene
	table = app.screen
	check(Net.game_id == match_before, "Смена темы не меняет партию")
	check(table._board._reveal_elapsed >= 1.4, "Crazy Colors продолжает текущую анимацию")
	table._board.set_process(false)
	table._board._reveal_elapsed = HCRules.PREPARE_SECONDS
	table._board._reveal_active = false
	Prefs.theme_mode = "dark" if Prefs.theme_mode != "dark" else "light"
	Prefs.changed.emit()
	await settle()
	app = get_tree().current_scene
	table = app.screen
	check(not table._board._reveal_active, "Завершённая анимация не начинается заново")
	for dark_mode in ["dark", "light"]:
		if Prefs.theme_mode != dark_mode:
			Prefs.theme_mode = dark_mode
			Prefs.changed.emit()
			await settle()
			app = get_tree().current_scene
			table = app.screen
		await click(table._top._chat_btn)
		check(table._top.chat.expanded, "Кнопка Чат раскрывает панель: " + dark_mode)
		await click(table._top.chat._input)
		check(table._top.chat._input.has_focus(), "Мышь ставит курсор в поле чата: " + dark_mode)
		await click(table._top.chat._quick_btn)
		check(table._top.chat.quick_open and table._top.chat._quick.visible, "Мышь открывает Фразы: " + dark_mode)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/batch27_ui/chat-" + dark_mode + ".png")
		await click(table._top._chat_btn)
	await close_game(app)
	app = await start_game("stillion")
	for dark_mode in ["dark", "light"]:
		table = app.screen
		table._cannon.set_process(false)
		table._cannon._angle = 1.7
		table._cannon.aim = 1.7
		table._cannon._frame = 2
		table._cannon._old_frame = 1
		table._cannon._turn_blend = 0.65
		table._cannon._anger = 0.8
		table._answer.text = "Черновик"
		Prefs.theme_mode = dark_mode
		app.restyle()
		table = app.screen
		check(is_equal_approx(table._cannon._angle, 1.7), "Тема сохраняет угол пушки")
		check(table._cannon._frame == 2 and is_equal_approx(table._cannon._turn_blend, 0.65), "Тема сохраняет стадию поворота")
		check(is_equal_approx(table._cannon._anger, 0.8), "Тема сохраняет злость пушки")
		check(table._answer.text == "Черновик", "Тема сохраняет черновик ответа")
	await close_game(app)
	print("BATCH27 UI: ", checks, " проверок, ", errors, " ошибок")
	await Sfx.request_quit(1 if errors else 0)
