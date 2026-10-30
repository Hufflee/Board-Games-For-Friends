extends SceneTree
## «Хором!»: интерфейс на 1280×720. Лобби, письмо (только свой блокнот), «Готов» — все блокноты и пластинки
## по числу ответов, открытие глазиком (пластинка падает), подсветка и глазик вне очереди, «✓», активный ×1,5.
## Запуск: godot --path . --audio-driver Dummy --script res://tests/test_khorom_ui.gd   (KH_THEME=light|dark)
## Кадры — build/khorom/.
var checks := 0
var errors := 0
var net: Node
var app: Control
var previous_mouse := Vector2.ZERO

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)

func settle(frames: int = 5) -> void:
	for _i: int in frames:
		await process_frame

func click(node: Control) -> void:
	var at := node.get_global_rect().get_center()
	for e: InputEvent in _mouse(at):
		Input.parse_input_event(e)
		await settle()

func _mouse(at: Vector2) -> Array:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	move.relative = at - previous_mouse
	previous_mouse = at
	var events: Array = [move]
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		events.append(e)
	return events

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/khorom/%s_%s.png" % [label, root.get_node("Prefs").theme_mode])

func table() -> Control:
	return app.screen

func book(seat: int) -> Control:
	return table().find_child("Notebook%d" % seat, true, false)

func type_row(seat: int, row: int, text: String) -> void:
	var edit: LineEdit = book(seat).find_child("Edit%d" % row, true, false)
	edit.text = text
	edit.text_submitted.emit(text)
	await settle()

func view_seat(seat: int) -> void:
	net.send_action("view_seat", {"seat": seat})
	await settle(8)

func plates(seat: int) -> int:
	var amount := 0
	for row: int in 6:
		if book(seat).find_child("Plate%d" % row, false, false) != null:
			amount += 1
	return amount

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/khorom"))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var theme_name := OS.get_environment("KH_THEME")
	root.get_node("Prefs").theme_mode = theme_name if theme_name in ["light", "dark"] else "light"
	net = root.get_node("Net")
	net.host_offline("khorom")
	net.set_bots(2)
	app = load("res://games/khorom/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle(10)
	var panel: Control = app.screen.find_child("LobbyPanel", true, false)
	check(panel != null, "лобби открыто")
	if panel:
		var off := panel.get_global_rect().get_center() - Vector2(640, 360)
		check(absf(off.x) < 4.0 and absf(off.y) < 4.0, "лобби по центру")
	await shot("lobby")
	await click(app.screen.find_child("StartGame", true, false))
	await settle(10)
	check(net.khr != null and net.khr.phase == "write", "партия началась")
	check(table().find_child("RoundCard", true, false) != null, "карточка раунда на месте")
	# Письмо: виден только свой блокнот, крупно.
	check(book(0).visible and not book(1).visible and not book(2).visible, "пока пишу — только мой блокнот")
	check(book(0).scale.x > 0.9, "мой блокнот крупный (%.2f)" % book(0).scale.x)
	await type_row(0, 0, "Палатка")
	await type_row(0, 1, "спальник")
	check(net.khr.answers[0][0] == "Палатка" and net.khr.answers[0][1] == "спальник", "ответы ушли хосту")
	await shot("write")
	await view_seat(1)
	await type_row(1, 0, "палатки")
	await type_row(1, 2, "фонарь")
	await type_row(1, 3, "котелок")
	await type_row(1, 4, "компас")
	await view_seat(0)
	await click(table().find_child("Ready", true, false))
	await settle(10)
	check(net.khr.ready[0], "игрок 1 готов")
	check(book(0).visible and book(1).visible and book(2).visible, "готов — видны все блокноты")
	check(book(0).scale.x < 0.9, "блокноты уменьшились")
	check(plates(1) == 4 and plates(2) == 0, "пластинки по числу ответов: %d и %d" % [plates(1), plates(2)])
	var hidden_text: Label = book(1).find_child("Text0", true, false)
	check(hidden_text.text == "", "текст чужого ответа не приходит")
	await shot("ready")
	await view_seat(1)
	check(not book(0).visible and book(1).visible, "игрок 2 ещё пишет — видит только свой блокнот")
	await click(table().find_child("Ready", true, false))
	await view_seat(2)
	await type_row(2, 0, "карта")
	await click(table().find_child("Ready", true, false))
	await settle(10)
	check(net.khr.phase == "reveal" and net.khr.turn() == 0, "все готовы — открывает ведущий")
	await view_seat(0)
	await create_timer(0.35).timeout
	check(is_equal_approx(book(0).scale.x, book(1).scale.x * 1.5), "блокнот того, кто ходит, ×1,5")
	var eye: Button = book(0).find_child("Eye0", true, false)
	check(eye != null and eye.visible, "у своего скрытого ответа — глазик")
	await click(eye)
	check(net.khr.revealed[0][0], "глазик открыл ответ")
	await view_seat(1)
	check(plates(0) == 1, "у остальных пластинка с ответа упала (осталась одна)")
	check(book(0).find_child("Text0", true, false).text == "Палатка", "открытый ответ виден")
	var out_of_turn: Button = book(1).find_child("Eye0", true, false)
	check(out_of_turn.visible, "похожий ответ — глазик вне очереди")
	check(book(1)._similar[0], "похожий ответ подсвечен")
	check(not book(1).find_child("Eye2", true, false).visible, "непохожий — без глазика")
	await click(out_of_turn)
	var mark: Button = book(1).find_child("Mark0", true, false)
	check(mark.visible, "у открытого ответа — галочка")
	await click(mark)
	check(net.khr.marked[1][0] and book(1).find_child("Verdict0", false, false) != null, "галочка: +1 и зелёная пластинка")
	check(int(net.khr.score(1)) == 1, "очко засчитано")
	await shot("reveal")
	await view_seat(0)
	await click(book(0).find_child("Eye1", true, false))
	check(net.khr.turn() == 1, "ведущий всё открыл — ход дальше")
	await view_seat(1)
	await click(table().find_child("Pass", true, false))
	check(net.khr.turn() == 2, "«Передать ход»")
	await view_seat(2)
	await click(book(2).find_child("Eye0", true, false))
	check(net.khr.phase == "round_end", "раунд окончен")
	await click(table().find_child("NextRound", true, false))
	await settle(10)
	check(net.khr.kind == "crow" and net.khr.leader == 1, "следующий раунд «Белая ворона»")
	check(book(0).find_child("Mark0", true, false).get_meta("on", false) == false, "новый блокнот чистый")
	# Доигрываем до конца: два раунда — и экран победы.
	net.khr.total_rounds = 2
	for seat: int in 3:
		net.khr.set_ready(seat, true)
	for _i: int in 6:
		if net.khr.phase != "reveal":
			break
		net.khr.pass_turn(net.khr.turn())
	net.khr.revision += 1
	net._push_state()
	await settle(8)
	await click(table().find_child("NextRound", true, false))
	await settle(20)
	check(net.khr.phase == "game_over", "партия окончена")
	var surface: Control = app.find_child("VictorySurface", true, false)
	check(surface != null and surface.is_visible_in_tree(), "экран победы показан")
	await shot("victory")
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	app.queue_free()
	net.leave()
	quit(1 if errors > 0 else 0)
