extends SceneTree
## Узкие Enter/focus PI и DW: реальные app/Net/InputEvents, подготовленные законные роли/фазы, без ESC.
var checks := 0
var errors := 0
var net: Node
var app: Control
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func settle() -> void:
	await create_timer(0.15).timeout
func click(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			await settle()
		parent = parent.get_parent()
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()
func key(code: Key, unicode_value: int = 0) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = unicode_value
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await settle()
func entry() -> LineEdit:
	for node in app.screen._body.find_children("*","LineEdit",true,false):
		if node.is_visible_in_tree() and not node.is_queued_for_deletion(): return node
	return null
func unlock(seat: int) -> void:
	net.pi_switch_seat(seat)
	await settle()
	for button in app.find_children("*","Button",true,false):
		if button.text == "Я готов · открыть мой экран":
			await click(button)
			break
func fresh_pi() -> void:
	net.phantom.new_game(net.phantom.players,[0,1,2,3],2901)
	net.phantom.action(1,"object",0)
	net.phantom.action(3,"object",0)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await process_frame
	root.size = Vector2i(1280,720)
	net = root.get_node("Net")
	net.host_offline("phantom_ink")
	net.set_bots(3)
	net.settings.pi_roles = [0,1,2,3]
	check(net.start_game().is_empty(),"PI подготовлен")
	net.set_process(false)
	fresh_pi()
	var hand: Array = net.phantom.hands[0]
	check(net.phantom.action(0,"ask",[hand[0],hand[1]]) and net.phantom.action(1,"question",net.phantom.offered[0]),"PI clue достигнут законными actions")
	net._push_state()
	app = load("res://games/phantom_ink/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	await unlock(1)
	var edit: LineEdit = entry()
	check(edit != null,"Поле clue доступно духу")
	await click(edit)
	edit.text = "123"
	await key(KEY_ENTER)
	check(net.phantom.phase == "clue" and edit.has_focus(),"Невалидный clue сохраняет поле и фокус")
	net.send_chat("Проверка обновления чата PI")
	await settle()
	check(is_instance_valid(edit) and edit.has_focus() and edit.text == "123","Обновление чата не меняет невалидный черновик clue")
	edit.text = "подсказка"
	await key(KEY_ENTER)
	check(net.phantom.phase == "writing" and entry() == null,"Валидный clue меняет фазу, продолжение ввода здесь не требуется")
	# Новый отдельный UI-сценарий: открывшийся после сообщения dropdown не должен перекрывать исходный клик guess.
	app.queue_free()
	current_scene = null
	await settle()
	fresh_pi()
	check(net.phantom.action(0,"guess_begin"),"PI guess достигнут штатным action")
	net._push_state()
	app = load("res://games/phantom_ink/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	await unlock(0)
	edit = entry()
	await click(edit)
	check(edit.has_focus(),"Контроль исходного клика guess: dropdown чата не перекрывает поле")
	print("PI_GUESS_CLICK ",JSON.stringify({"rect":str(edit.get_global_rect()),"focus":str(root.gui_get_focus_owner()),"edit_focus":edit.has_focus()}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/focus29/pi-guess-before.png")
	edit.text = "1"
	await key(KEY_ENTER)
	check(net.phantom.phase == "guess" and edit.has_focus(),"Невалидная буква guess сохраняет фокус")
	edit.text = "а"
	await key(KEY_ENTER)
	check(net.phantom.phase == "judge" and entry() == null,"Первая буква отправлена настоящим Enter, требуется суд духа")
	check(net.phantom.action(1,"judge",true),"Дух законно подтвердил первую букву")
	net._push_state()
	await settle()
	var next_edit: LineEdit = entry()
	var focus_ok: bool = next_edit != null and next_edit.has_focus()
	print("PI_FOCUS_OBSERVATION ",JSON.stringify({"phase":net.phantom.phase,"same_seat":net.view.seat,"can_act":net.view.can_act,"editor_recreated":next_edit != edit,"focused":focus_ok}))
	check(net.phantom.phase == "guess" and focus_ok,"После judge→guess того же медиума повторное разрешённое поле должно получить фокус")
	await key(KEY_NONE,"б".unicode_at(0))
	await key(KEY_ENTER)
	check(net.phantom.phase == "judge" and net.phantom.rows[0].back().pending == "Б","Вторая буква и Enter без повторного клика должны дойти правилам")
	app.queue_free()
	current_scene = null
	net.leave()
	await settle()
	net.host_offline("dangerous_words")
	net.set_bots(3)
	check(net.start_game().is_empty(),"DW подготовлен")
	net.set_process(false)
	app = load("res://games/dangerous_words/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	var table: Control = app.screen
	edit = table._cand_edit
	check(edit != null and net.dwords.phase == "traps","DW candidate доступен в traps")
	await click(edit)
	edit.text = "альфа"
	await key(KEY_ENTER)
	check(edit == table._cand_edit and edit.has_focus() and edit.text.is_empty(),"DW первый Enter сохраняет редактор/фокус и очищает текст")
	await key(KEY_NONE,"б".unicode_at(0))
	await key(KEY_ENTER)
	check(net.dwords.cands[0].size() == 2 and edit.has_focus(),"DW второе предложение Enter без нового клика принято")
	edit.text = "альфа"
	await key(KEY_ENTER)
	check(net.dwords.cands[0].size() == 2 and edit.has_focus(),"DW повтор-кандидат отвергнут без потери фокуса")
	net.send_chat("Проверка обновления чата DW")
	await settle()
	check(edit == table._cand_edit and edit.has_focus(),"Обновление чата DW не отбирает фокус кандидата")
	print("FOCUS29 LOW: проверок=",checks," ошибок=",errors)
	app.queue_free()
	current_scene = null
	net.leave()
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
