extends Control
## Настоящие столы 1280×720: ввод заранее, чат, темы, пауза, подсказки и параллакс.
var errors := 0
var checks := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func settle() -> void:
	await get_tree().create_timer(0.3).timeout

func move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	await settle()

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/batch26-%s.png" % name)

func start_game(id: String, bots: int) -> Control:
	Net.leave()
	var app: Control = load("res://games/%s/ui/main.tscn" % id).instantiate()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	Net.host_offline(id)
	Net.set_bots(bots)
	check(Net.start_game() == "", "Запуск " + id)
	await settle()
	Net.set_process(false)
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
	var app := await start_game("stillion", 1)
	var table: Control = app.screen
	Net.stillion.phase = "fuse"
	Net.stillion.target = 1
	Net.stillion.players[1].bot = true
	Net._push_state()
	await settle()
	check(table._answer.editable and table._send.disabled, "Можно готовить ответ во время хода бота")
	table._answer.text = "Заранее"
	table._submit()
	check(table._answer.text == "Заранее", "Ранний Enter сохраняет черновик")
	table._top.chat.expanded = true
	table._top.chat._input.grab_focus()
	Net._push_state()
	await settle()
	check(table._top.chat._input.has_focus(), "Обновление не отбирает фокус чата")
	for theme_mode in ["light", "dark"]:
		Prefs.theme_mode = theme_mode
		Prefs.changed.emit()
		await settle()
		table = app.screen
		check(table._answer.text == "Заранее", "Черновик сохраняется при смене темы")
		check(table._top.chat.expanded, "Чат сохраняется при смене темы")
		await snap("st-" + theme_mode)
	Net.set_paused(true)
	await settle()
	var pause: Node = Net.get_children().filter(func(node): return node is PauseLayer)[0]
	var coin: Control = pause._fidget
	coin.position = Vector2(600, 330)
	coin.set_process(false)
	coin.rotation = 0.0
	coin.scale = Vector2.ONE
	coin.set("_in_dock", false)
	coin.set("_vel", Vector2.ZERO)
	await move(coin.get_global_rect().get_center())
	print("COIN HIT ", get_viewport().gui_get_hovered_control(), " coin=", coin, " order=", coin.get_index(), "/", pause._root.get_index(), " position=", coin.position)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = coin.get_global_rect().get_center()
	click.global_position = click.position
	Input.parse_input_event(click)
	await get_tree().process_frame
	check(bool(coin.get("_holding")), "Монету над паузой можно схватить")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await settle()
	await move(Vector2(1100, 600))
	check(coin._get_tooltip(Vector2(-100, -100)) == "", "Вне монеты нет подсказки")
	await snap("pause")
	await close_game(app)
	app = await start_game("hues_and_cues", 2)
	Prefs.changed.disconnect(app._on_prefs)
	table = app.screen
	for theme_mode in ["light", "dark"]:
		Prefs.theme_mode = theme_mode
		HCStyle.sync_prefs()
		get_tree().root.theme = HCStyle.theme()
		app.show_table()
		await settle()
		table = app.screen
		check(table._cues_row.get_global_rect().position.y >= table._top.get_global_rect().end.y, "Подсказки ниже верхней полосы")
		check(not table._side.get_global_rect().intersects(table._cues_row.get_global_rect()), "Подсказки не залезают в игроков")
		table._top.chat.expanded = true
		table._top.chat._input.grab_focus()
		Net._push_state()
		await settle()
		check(table._top.chat._input.has_focus(), "Hues сохраняет фокус чата")
		await snap("hc-" + theme_mode)
	await close_game(app)
	app = await start_game("wavelength", 3)
	table = app.screen
	var background: ColorRect = table.get_child(0)
	await move(Vector2(50, 100))
	var before: Vector2 = background.material.get_shader_parameter("motion")
	var dial_pos: Vector2 = table._dial.global_position
	await snap("wl-left")
	await move(Vector2(1200, 600))
	var after: Vector2 = background.material.get_shader_parameter("motion")
	print("PARALLAX ", before, " -> ", after, " mouse=", get_viewport().get_mouse_position())
	check(before.distance_to(after) > 3, "Параллакс реагирует на мышь")
	check(table._dial.global_position == dial_pos, "Интерфейс не сдвигается вместе с фоном")
	await snap("wl-right")
	await close_game(app)
	print("BATCH26 UI: ", checks, " проверок, ", errors, " ошибок")
	get_tree().quit(1 if errors else 0)

