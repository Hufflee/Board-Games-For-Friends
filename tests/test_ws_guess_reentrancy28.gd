extends SceneTree
## Реальный ввод WS: неверные/верные догадки Enter/кнопкой, синхронный host-callback.
## WS_QA_ROLE=host (поумолчанию), server/client — ENet-пара, WS_QA_DIR/WS_QA_PORT.
var checks := 0
var errors := 0
var net: Node
var app: Control
var table: Control
var role := ""
var qa_dir := ""

func _init() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func settle() -> void:
	await create_timer(0.15).timeout

func marker(name: String, payload: String = "ok") -> void:
	if qa_dir.is_empty():
		return
	var file := FileAccess.open(qa_dir.path_join(name), FileAccess.WRITE)
	file.store_string(payload)
	file.close()

func wait_marker(name: String) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not FileAccess.file_exists(qa_dir.path_join(name)) and Time.get_ticks_msec() < deadline:
		await process_frame
	return FileAccess.file_exists(qa_dir.path_join(name))

func click(control: Control) -> void:
	if control == null:
		check(false, "Цель настоящего клика существует")
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()

func enter() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()

func guess_button() -> Button:
	for button: Button in table.find_children("*", "Button", true, false):
		if button.text == "Отгадать":
			return button
	return null

func prepare() -> void:
	var w: WSRules = net.wslam
	if w.phase in ["round_result", "game_over"]:
		w._start_round()
	w.players[0]["team"] = 0
	w.players[1]["team"] = 1
	w.players[2]["team"] = 0
	w.players[3]["team"] = 1
	w.storytellers = [2, 3]
	w.ready = [false, false]
	w.phase = "word"
	w.word = "арбуз"
	w.set_ready(2)
	w.set_ready(3)
	check(w.set_holders(2, [["noun:0"], []]), "Синие выложили настоящую карточку")
	check(w.set_holders(3, [["noun:0"], []]), "Оранжевые выложили настоящую карточку")
	net._push_state()

func build_app() -> void:
	app = load("res://games/word_slam/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	table = app.screen

func four_inputs(use_button: bool) -> void:
	await settle()
	table = app.screen
	if role == "host":
		table._as = 0
		table._on_state(net.view)
		await settle()
	var edit: LineEdit = table._guess_edit
	check(edit != null, "Есть поле отгадывающего")
	if edit == null:
		return
	await click(edit)
	var old_count: int = net.view.guesses.size()
	edit.text = "невернаядогадка"
	print("WS CASE ", role, " button=", use_button, " wrong before")
	if use_button:
		await click(guess_button())
	else:
		await enter()
	check(net.view.phase == "play" and net.view.guesses.size() == old_count + 1, "Неверная догадка принята правилами")
	check(is_instance_valid(edit) and edit == table._guess_edit, "Неверная догадка сохраняет редактор")
	check(edit.has_focus() and edit.text.is_empty(), "После отправки фокус сохранён и текст очищен")
	edit.text = "ещёневерно"
	if use_button:
		await click(guess_button())
	else:
		await enter()
	check(net.view.guesses.size() == old_count + 2, "Повторная догадка без выбора места принята")
	edit.text = "арбуз"
	print("WS CASE ", role, " button=", use_button, " correct before")
	if use_button:
		await click(guess_button())
	else:
		await enter()
	check(net.view.phase == "round_result", "Верная догадка переводит play→round_result")
	check(table._guess_edit == null, "Панель редактора удалена после правильного ответа")
	print("WS CASE ", role, " button=", use_button, " correct returned; process alive")

func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	role = OS.get_environment("WS_QA_ROLE")
	if role.is_empty():
		role = "host"
	qa_dir = OS.get_environment("WS_QA_DIR")
	var port := int(OS.get_environment("WS_QA_PORT"))
	if port == 0:
		port = 28186
	if role == "client":
		check(net.join_enet("127.0.0.1", port) == OK, "Клиент подключается")
		check(await wait_marker("round1"), "Хост подготовилраунд1")
		var deadline := Time.get_ticks_msec() + 15000
		while net.view.get("phase", "") != "play" and Time.get_ticks_msec() < deadline:
			await process_frame
		await build_app()
		check(net.view.you == 1 and net.view.word == "", "Клиент отгадывает и не получает секрет")
		await four_inputs(false)
		marker("done1")
		check(await wait_marker("round2"), "Хост подготовилраунд2")
		deadline = Time.get_ticks_msec() + 15000
		while net.view.get("phase", "") != "play" and Time.get_ticks_msec() < deadline:
			await process_frame
		await four_inputs(true)
		marker("done2")
	elif role == "server":
		check(net.host_enet(port, "word_slam") == OK, "Хост ENet создан")
		marker("listening")
		var deadline := Time.get_ticks_msec() + 20000
		while net.lobby_view.get("members", []).size() < 2 and Time.get_ticks_msec() < deadline:
			await process_frame
		check(net.lobby_view.get("members", []).size() == 2, "Настоящий клиент вошёл")
		net.set_bots(2)
		check(net.start_game().is_empty(), "Четыре места ENet")
		net.set_process(false)
		prepare()
		marker("round1")
		check(await wait_marker("done1"), "Клиент закончилEnter")
		prepare()
		marker("round2")
		check(await wait_marker("done2"), "Клиент закончилкнопку")
		await create_timer(0.4).timeout
	else:
		net.host_offline("word_slam")
		net.set_bots(3)
		check(net.start_game().is_empty(), "Офлайн хост запустилчетыре места")
		net.set_process(false)
		prepare()
		await build_app()
		await four_inputs(false)
		prepare()
		await four_inputs(true)
	print("WS REENTRANCY: role=%s, %d проверок, %d ошибок; release=%s" % [role, checks, errors, not OS.has_feature("debug")])
	if is_instance_valid(app):
		app.queue_free()
	net.leave()
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
