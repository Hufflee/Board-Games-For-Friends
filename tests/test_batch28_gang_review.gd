extends "res://tests/test_batch28_gang_interactions.gd"
## Независимые утверждения low; переиспользуются только helpers настоящего мышиного ввода автора.

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(9)
	net.settings["turn_limit"] = 30
	check(net.start_game().is_empty(), "Независимый старт10 мест")
	net.set_process(false)
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(15)
	table = app.screen
	net._tg_process(0.0)
	net._tg_process(3.0)
	var elapsed: float = net._phase_time
	var turn: int = net.gang.turn_no
	var clock_id: int = table._top._clock.get_instance_id()
	var view_before: Dictionary = net.view.duplicate(true)
	await flip(0)
	await flip(1)
	check(table._faces[0] and table._faces[1], "Обе карты можно независимо открыть жестами")
	check(net.view == view_before, "Локальный переворот не мутирует серверный view")
	for index in 2:
		var texture: Texture2D = table.find_child("PersonalCard%d" % index, true, false).texture
		check(texture.resource_path.ends_with("/%s.webp" % net.view.hand[index]), "Открыто только своё изображение%d" % index)
	await drag_start(chip(10))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await frames()
	check(not is_instance_valid(table._drag_ghost), "Escape отменяет действительный захват")
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 0, "Отпускание после Escape не выбирает фишку")
	await drag_start(chip(10))
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 10, "Новый захват после отмены работает")
	check(net._phase_time == elapsed and net.gang.turn_no == turn, "Take/rebuild не перезапускает срок раунда")
	check(table._top._clock.get_instance_id() == clock_id, "Rebuild не пересоздаёт часы TopBar")
	await drag_start(chip(10))
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 10, "Свою фишку нельзя вернуть отпусканием в своей руке")
	await drag_start(chip(10))
	await drop(table._center_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 0 and net._phase_time == elapsed, "Return в центр не обнуляет таймер")
	net._tg_process(2.0)
	check(is_equal_approx(net._phase_time, elapsed + 2.0), "Тот же раунд продолжает прежний отсчёт")
	net.set_paused(true)
	await frames()
	var revision: int = net.gang.revision
	await drag_start(chip(1))
	check(not is_instance_valid(table._drag_ghost), "Во время паузы нельзя начать новый перенос")
	await drop(table._hand_zone.get_global_rect().get_center())
	await flip(0)
	check(net.gang.revision == revision and table._faces[0], "Пауза не позволяет ход и закрытие открытой карты")
	net.set_paused(false)
	await frames()
	# Настоящий клик по кнопке места, а не вызов её pressed.
	var seat_button: Control = table.find_child("Seat1", true, false)
	var point := seat_button.get_global_rect().get_center()
	await mouse(point, 0)
	await mouse(point, 1, true)
	await mouse(point, 1)
	await frames()
	check(int(net.view.seat) == 1 and not table._faces.has(true), "Клик места меняет право и закрывает обе карты")
	for index in 2:
		var texture: Texture2D = table.find_child("PersonalCard%d" % index, true, false).texture
		check(texture.resource_path.ends_with("/back.webp"), "После смены места карта%d закрыта" % index)
	# Незавершённый переворот отменяется rebuild; прежний tween не раскрывает новую карту позднее.
	var card: Control = table.find_child("PersonalCard0", true, false)
	var edge := card.get_global_rect().position + Vector2(4, 60)
	await mouse(edge, 0)
	await mouse(edge, 1, true)
	await mouse(edge + Vector2(65, 0), 0, true)
	var old_flip: Node = table._flips[0]
	check(old_flip.busy, "Подготовлен настоящий незавершённый edge-pull")
	net._push_state()
	await frames()
	await mouse(edge + Vector2(65, 0), 1)
	await create_timer(0.5).timeout
	check(not table._faces.has(true) and not table._flips[0].busy, "Старый callback после rebuild не раскрывает карту")
	check(not is_instance_valid(old_flip), "Старый обработчик переворота удалён вместе с картой")
	check(net.gang.revision == revision, "Просмотр/пауза/rebuild не создали серверных ходов")
	print("TG LOW REVIEW: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
