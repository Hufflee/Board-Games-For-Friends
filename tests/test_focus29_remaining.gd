extends SceneTree
## Адресные реальные InputEvents для оставшихся пяти полей; запуск --script с Dummy и отдельным APPDATA.
var checks := 0
var errors := 0
var net: Node
var app: Control
var table: Control
var game := ""
var tt_before := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	print("REMAINING ", game, " ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1
func settle() -> void:
	await create_timer(0.18).timeout
func click(control: Control) -> void:
	await load("res://tests/fixtures/top_bar_menu29.gd").reveal(control)
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await settle()
func key(code: Key, uni: int = 0) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.unicode = uni
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await settle()
func entry() -> LineEdit:
	for e: Node in table.find_children("*", "LineEdit", true, false):
		if not table._top.chat.is_ancestor_of(e) and e.is_visible_in_tree() and not e.is_queued_for_deletion():
			return e
	return null
func start(id: String) -> void:
	game = id
	net.host_offline(id)
	net.set_bots(3)
	check(net.start_game().is_empty(), "подготовлена партия")
	net.set_process(false)
	match id:
		"hues_and_cues":
			check(net.hues.pick_color(net.hues.giver, net.hues.card[0]), "цвет выбран правилами")
		"tip_top":
			check(net.tiptop.pick_theme(net.tiptop.captain, 0), "тема выбрана правилами")
		"wavelength":
			check(net.wavelength.choose_side(net.wavelength.psychic, 0), "сторона выбрана правилами")
		"not_a_hat":
			net.nothat.start_play()
		"stillion":
			net.stillion.external_check = false
			net.stillion.tick(STRules.NEW_Q_TIME + 0.1)
			net.stillion.tick(STRules.AIM_TIME + 0.1)
	net._push_state()
	if id == "hues_and_cues":
		root.set_meta(&"hc_skip_intro_once", true)
	app = load("res://games/%s/ui/main.tscn" % id).instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	table = app.screen
	if id == "wavelength":
		table._peek = true
		table._update_panel()
		await settle()
func stop() -> void:
	app.queue_free()
	current_scene = null
	net.leave()
	await settle()
func common() -> void:
	var edit: LineEdit = entry()
	check(edit != null, "поле доступно")
	if edit == null:
		return
	await click(edit)
	check(edit.has_focus(), "реальный клик дал фокус")
	edit.text = ""
	await key(KEY_ENTER)
	check(is_instance_valid(edit) and edit.has_focus(), "невалидный Enter сохранил фокус")
	await key(KEY_NONE, "я".unicode_at(0))
	check(edit.text == "я", "набор после Enter без клика")
	net._push_state()
	await settle()
	check(entry() == edit and edit.has_focus() and edit.text == "я", "тот же снимок Net сохранил поле, фокус и черновик")
	await click(table._top._chat_btn)
	await click(table._top.chat._input)
	check(table._top.chat._input.has_focus(), "реальный клик в чат дал фокус")
	net._push_state()
	await settle()
	check(table._top.chat._input.has_focus(), "Net не крадёт фокус чата")
	if game == "tip_top":
		for seat: int in net.tiptop.players.size():
			if seat != net.tiptop.captain and seat != table._as:
				check(net.tiptop.answer(seat, "чужой ответ"), "подготовлен чужой ответ при открытом чате")
				break
		net._push_state()
		await settle()
		check(table._top.chat._input.has_focus(), "перестройка от чужого ответа не крадёт фокус чата")
		tt_before = net.tiptop.answers.size()
		edit = entry()
	await click(table._top._chat_btn)
	await click(edit)
	net.set_paused(true)
	await settle()
	var paused_owner: Control = root.gui_get_focus_owner()
	net._push_state()
	await settle()
	check(root.gui_get_focus_owner() == paused_owner, "снимок во время паузы не возвращает фокус")
	net.set_paused(false)
	await settle()
	await click(edit)
	edit.text = ""
	await key(KEY_NONE, "я".unicode_at(0))
	await key(KEY_ENTER)
	match game:
		"hues_and_cues":
			check(net.hues.phase == "guess1" and entry() == null, "валидная подсказка Enter штатно закрыла форму")
		"wavelength":
			check(net.wavelength.phase == "guess" and entry() == null, "валидная подсказка Enter штатно закрыла форму")
		"tip_top":
			check(net.tiptop.answers.size() == tt_before + 1, "первый ответ Enter принят")
			var next: LineEdit = entry()
			check(next != null and next.has_focus(), "следующее разрешённое поле после синхронного Net имеет фокус")
			await key(KEY_NONE, "б".unicode_at(0))
			await key(KEY_ENTER)
			check(net.tiptop.answers.size() == tt_before + 2, "повторный ответ без клика принят")
		"stillion":
			check(net.stillion.phase == "fuse" and edit.has_focus() and edit.text.is_empty(), "неизвестный ответ принят как wrong и поле сохраняет фокус")
			var before: int = net.stillion.event_no
			await key(KEY_NONE, "б".unicode_at(0))
			await key(KEY_ENTER)
			check(net.stillion.event_no > before and edit.has_focus(), "повторный ответ без клика дошёл правилам")
		"not_a_hat":
			# У «я» может быть совпадение; отдельный заведомо отсутствующий фильтр проверяется ниже.
			check(net.nothat.phase in ["give", "respond"], "поиск обрабатывает Enter без ошибки")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	for id: String in ["hues_and_cues", "stillion", "tip_top", "wavelength"]:
		if OS.get_environment("REMAINING_CASES") == "hc_nh" and id != "hues_and_cues":
			continue
		await start(id)
		await common()
		await stop()
	await start("not_a_hat")
	var edit: LineEdit = entry()
	check(edit != null, "поле поиска доступно")
	await click(edit)
	edit.text = "неттакогоподарка123"
	edit.text_changed.emit(edit.text)
	edit.caret_column = edit.text.length()
	await key(KEY_ENTER)
	check(net.nothat.phase == "give" and edit.has_focus(), "Enter без совпадений сохраняет поле и фокус")
	await key(KEY_NONE, "я".unicode_at(0))
	check(edit.text.ends_with("я"), "следующий набор без клика")
	net._push_state()
	await settle()
	check(entry() == edit and edit.has_focus(), "снимок Net сохраняет поиск")
	await click(table._top._chat_btn)
	await click(table._top.chat._input)
	net._push_state()
	await settle()
	check(table._top.chat._input.has_focus(), "снимок Net не крадёт фокус чата")
	await click(table._top._chat_btn)
	await click(edit)
	edit.text = ""
	edit.text_changed.emit("")
	await key(KEY_ENTER)
	check(net.nothat.phase == "respond" and entry() == null, "Enter первого совпадения штатно закрывает поиск")
	await stop()
	print("REMAINING_TOTAL проверок=", checks, " ошибок=", errors)
	var f := FileAccess.open("res://build/focus29/remaining-result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "errors": errors}))
	f.close()
	await root.get_node("Sfx").request_quit(1 if errors else 0)


