extends SceneTree
## Настоящий Word Slam: мышь в чате, фразы, Enter и следующая догадка без нового клика.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func settle() -> void:
	await create_timer(0.2).timeout
func click(control: Control) -> void:
	await load("res://tests/fixtures/top_bar_menu29.gd").reveal(control)
	var at := control.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()
func enter() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var net = root.get_node("Net")
	var app: Control = load("res://games/word_slam/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	net.host_offline("word_slam")
	net.set_bots(3)
	check(net.start_game() == "", "Запуск Word Slam")
	net.set_process(false)
	await settle()
	for seat in net.wslam.storytellers:
		check(net.wslam.set_ready(seat), "Рассказчик готов")
	# Догадки по правилам принимаются после выкладки хотя бы одной карточки своей команды.
	for storyteller in net.wslam.storytellers:
		check(net.wslam.set_holders(storyteller, [["noun:0"], []]), "Рассказчик выложил карточку до догадок")
	net._push_state()
	await settle()
	var table = app.screen
	var seat := 0
	while net.wslam.storytellers.has(seat):
		seat += 1
	table._as = seat
	table._on_state(net.view)
	await settle()
	var chat = table._top_bar.chat
	await click(table._top_bar._chat_btn)
	check(chat.expanded, "Мышь открыла чат")
	await click(chat._input)
	check(chat._input.has_focus(), "Поздние панели стола не перехватывают поле чата")
	chat._input.text = "Проверка чата"
	await enter()
	check(chat._input.has_focus(), "Фокус чата сохранён после настоящего Enter")
	check(chat._input.text.is_empty(), "Сообщение отправлено")
	check(chat._log.get_parsed_text().contains("Проверка чата"), "Отправленное сообщение в журнале")
	await click(chat._quick_btn)
	check(chat.quick_open, "Фразы открываются мышью")
	await click(chat._quick.get_child(0))
	check(not chat.quick_open, "Фраза отправилась мышью")
	await click(table._top_bar._chat_btn)
	check(not chat.expanded, "Чат закрыт")
	check(not net.paused and net.wslam.can_guess(seat), "Выбран живой отгадывающий с карточкой, игра не на паузе")
	var edit: LineEdit = table._guess_edit
	await click(edit)
	edit.text = "невернаядогадка123"
	await enter()
	check(edit.has_focus() and not edit.is_queued_for_deletion(), "Поле догадки осталось активно после Enter")
	check(edit.text.is_empty(), "Догадка отправлена")
	check(net.wslam.guesses.size() > 0, "Правила получили догадку")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/shots/batch28_word_slam")
		root.get_texture().get_image().save_png("res://build/shots/batch28_word_slam/chat-focus.png")
	net.leave()
	app.queue_free()
	await process_frame
	print("ЧАТФОКУС28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
