extends SceneTree
## Настоящие клики меню/лобби/фишек и переключение закрытых мест The Gang.
## --audio-driver Dummy --path . --script res://tests/test_the_gang_ui.gd; TG_SHOTS=1 для кадров.

var checks := 0
var errors := 0
var app: Control
var net: Node

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func frames(count: int = 5) -> void:
	for index in count:
		await process_frame

func click(control: Control) -> void:
	if control == null:
		check(false, "Цель клика должна существовать")
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	if OS.get_environment("TG_TRACE") == "1":
		var hovered := root.gui_get_hovered_control()
		print("TG CLICK ", control.name, " at ", point, " hover=", hovered.get_path() if hovered else "null")
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		Input.parse_input_event(button)
		await process_frame
	await frames()

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func pick_seat(seat: int) -> void:
	var picker := app.find_child("Seat%d" % seat, true, false) as Button
	check(picker != null, "Переключатель мест есть")
	if picker == null:
		return
	await click(picker)
	await frames()
	check(int(net.view.get("seat", -1)) == seat, "Настоящее переключение на место%d" % seat)

func shot(name: String) -> void:
	if OS.get_environment("TG_SHOTS") != "1" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/shots/the_gang")
	root.get_texture().get_image().save_png("res://build/shots/the_gang/%s.png" % name)

func _run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.leave()
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(12)
	if app.find_child("LocalGame", true, false) == null:
		check(false, "Меню должно успешно загрузиться до кликов")
		await root.get_node("Sfx").request_quit(1)
		return
	await click(app.find_child("LocalGame", true, false))
	check(net.player_total() == 3, "Локальный старт создаёт три живых места")
	await click(app.find_child("StartGame", true, false))
	await create_timer(1.0).timeout
	check(net.in_game and net.gang != null, "Игра запущена через лобби")
	check(net.view.hand.size() == 2 and not net.view.has("hands"), "Получена только личная рука")
	await shot("table-3-hidden")
	await click(app.find_child("PeekCards", true, false))
	await shot("table-3-hand")
	var steps := 0
	while net.gang.phase != "game_over" and steps < 85:
		if net.gang.phase == "showdown":
			await shot("showdown-3")
			await click(app.find_child("NextHeist", true, false))
		else:
			var current_round: int = net.gang.turn_no
			for seat in 3:
				await pick_seat(seat)
				var control := app.find_child("Chip%d" % (seat + 1), true, false) as Button
				check(control != null and not control.disabled, "Фишка доступна выбранному месту")
				if control == null or control.disabled:
					break
				await click(control)
				steps += 1
			check(net.gang.turn_no > current_round, "После трёх выборов раунд завершён")
		steps += 1
	check(net.gang.phase == "game_over", "Полная UI-партия завершилась")
	check(net.gang.vaults == 3 or net.gang.alarms == 3, "Конец партии имеет законное основание")
	await shot("game-over-3")
	net.end_game()
	await frames()
	for index in 7:
		await click(app.find_child("AddPlayer", true, false))
	check(net.player_total() == 10, "В локальном лобби добавлены десять мест")
	await shot("lobby-10")
	await click(app.find_child("StartGame", true, false))
	await create_timer(1.0).timeout
	check(net.gang.players.size() == 10, "Десять мест приняты логикой и сетью")
	await pick_seat(9)
	await click(app.find_child("PeekCards", true, false))
	await shot("table-10-hand")
	check(net.view.hand == net.gang.hands[9], "Личный view десятого места правильный")
	check(not net._seat_view(-1, [], 0.0, false).hand.size(), "Зритель через Net не получает карманные карты")
	# Только память тестового процесса: пользовательские настройки не сохраняются.
	var preferences := root.get_node("Prefs")
	for mode in ["light", "dark"]:
		preferences.theme_mode = mode
		preferences.changed.emit()
		await frames(12)
		await click(app.find_child("PeekCards", true, false))
		await shot("table-10-" + mode)
		check(net.view.seat == 9 and net.gang.players.size() == 10, "Тема не меняет место и партию")
		await click(app.find_child("Rules", true, false))
		await shot("rules-" + mode)
		await click(app.find_child("CloseRules", true, false))
		await click(app.find_child("Settings", true, false))
		await shot("settings-" + mode)
		await click(app.find_child("CloseSettings", true, false))
	var top := get_first_node_in_group("top_bar")
	await click(top.get("_pause_btn"))
	await create_timer(0.4).timeout
	check(net.paused, "Настоящая кнопка поставила игру на паузу")
	var revision: int = net.gang.revision
	await click(app.find_child("Chip1", true, false))
	check(net.gang.revision == revision, "Пауза блокирует игровые клики")
	await click(top.get("_pause_btn"))
	await create_timer(0.4).timeout
	check(not net.paused, "Настоящая кнопка продолжила игру")
	print("THE GANG UI: %d проверок, %d ошибок; шагов партии: %d" % [checks, errors, steps])
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
