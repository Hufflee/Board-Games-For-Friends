extends SceneTree
## Узкие проверки настоящего мышиного ввода TG: фишки, приватность и edge-pull.
## --headless --audio-driver Dummy --path . --script res://tests/test_batch28_gang_interactions.gd

var checks := 0
var errors := 0
var net: Node
var app: Control
var table: Control

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func frames(count: int = 5) -> void:
	for i in count:
		await process_frame

func mouse(point: Vector2, kind: int, down: bool = false) -> void:
	if kind == 0:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
	await frames(2)

func drag_start(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	await mouse(point, 0)
	await mouse(point, 1, true)

func drop(point: Vector2) -> void:
	await mouse(point, 0, true)
	await mouse(point, 1)
	await frames()

func chip(value: int) -> Control:
	return table.find_child("Chip%d" % value, true, false)

func flip(index: int) -> void:
	var card: Control = table.find_child("PersonalCard%d" % index, true, false)
	var point := card.get_global_rect().position + Vector2(4, 60)
	await mouse(point, 0)
	await mouse(point, 1, true)
	await mouse(point + Vector2(90, 0), 0, true)
	await mouse(point + Vector2(90, 0), 1)
	await create_timer(0.4).timeout

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/shots/batch28_gang_interactions")
	root.get_texture().get_image().save_png("res://build/shots/batch28_gang_interactions/%s.png" % label)

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(2)
	net.settings["turn_limit"] = 0
	check(net.start_game().is_empty(), "Старт3 мест")
	net.set_process(false)
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(15)
	table = app.screen
	check(table._flips.size() == 2 and not table._faces.has(true), "Две карты закрыты")
	await flip(0)
	check(table._faces[0] and not table._faces[1], "Первая карта открывается отдельно")
	await flip(0)
	check(not table._faces.has(true), "Повторный edge-pull закрывает карту")
	var unchanged: int = net.gang.revision
	var point := chip(1).get_global_rect().get_center()
	await mouse(point, 0)
	await mouse(point, 1, true)
	await mouse(point, 1)
	check(net.gang.revision == unchanged, "Короткий клик не заменяет перетаскивание")
	await drag_start(chip(1))
	check(is_instance_valid(table._drag_ghost), "Настоящий захват фишки")
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 1, "Фишка взята к своим картам")
	await drag_start(chip(1))
	await drop(table._center_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 0, "Своя фишка возвращена в центр")
	net.send_action("view_seat", {"seat": 1})
	net.send_action("take", {"value": 2})
	net.send_action("view_seat", {"seat": 0})
	await frames()
	await drag_start(chip(2))
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 2 and net.gang.chips[1] == 0, "Чужая фишка переходит только текущему игроку")
	var revision: int = net.gang.revision
	await drag_start(chip(1))
	await drop(Vector2(1260, 710))
	check(net.gang.revision == revision, "Отпускание вне зон не отправляет ход")
	await drag_start(chip(1))
	net.set_paused(true)
	await frames()
	check(not is_instance_valid(table._drag_ghost), "Пауза отменяет захват")
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.revision == revision, "Отпускание на паузе не меняет правила")
	net.set_paused(false)
	await frames()
	await drag_start(chip(1))
	net.send_action("view_seat", {"seat": 1})
	await frames()
	check(not is_instance_valid(table._drag_ghost) and not table._faces.has(true), "Смена места отменяет перенос и закрывает руку")
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[1] == 0, "Старый перенос не назначает фишку новому месту")
	await flip(1)
	check(table._faces[1], "Вторая карта открывается отдельно")
	table._on_state(net.view.duplicate(true))
	await frames()
	check(table._faces[1], "Обычный rebuild сохраняет открытое лицо")
	var card: Control = table.find_child("PersonalCard0", true, false)
	var edge := card.get_global_rect().position + Vector2(4, 60)
	await mouse(edge, 0)
	await mouse(edge, 1, true)
	await mouse(edge + Vector2(65, 0), 0, true)
	net.set_paused(true)
	await frames()
	check(not table._flips[0].busy and not table._faces[0], "Пауза отменяет незаконченный переворот")
	await mouse(edge + Vector2(65, 0), 1)
	net.set_paused(false)
	await frames()
	await shot("rank-3")
	var saved: Dictionary = net.view.duplicate(true)
	var new_match: Dictionary = saved.duplicate(true)
	new_match.game_id = str(saved.game_id) + "-new"
	table._on_state(new_match)
	await frames()
	check(not table._faces.has(true), "Другой game_id закрывает даже совпадающую руку")
	table._on_state(saved)
	await frames()
	var spectator: Dictionary = net.view.duplicate(true)
	spectator.seat = -1
	spectator.spectator = true
	spectator.hand = []
	table._on_state(spectator)
	await frames()
	await drag_start(chip(1))
	check(not is_instance_valid(table._drag_ghost), "Зритель не захватывает фишки")
	await flip(0)
	check(not table._faces.has(true), "Зритель не открывает личные карты")
	check(not net._seat_view(-1, [], 0.0, false).hand.size(), "Серверный view зрителя остаётся пустым")
	table._on_state(net.view)
	await frames()
	await drag_start(chip(1))
	var newer: Dictionary = net.view.duplicate(true)
	newer.revision += 1
	table._on_state(newer)
	await frames()
	check(not is_instance_valid(table._drag_ghost), "Новая revision отменяет перенос")
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.revision == revision, "Старое отпускание после rebuild не отправлено")
	var mid_card: Control = table.find_child("PersonalCard0", true, false)
	var mid_edge := mid_card.get_global_rect().position + Vector2(4, 60)
	await mouse(mid_edge, 0)
	await mouse(mid_edge, 1, true)
	await mouse(mid_edge + Vector2(65, 0), 0, true)
	net.send_action("view_seat", {"seat": 0})
	await frames()
	await mouse(mid_edge + Vector2(65, 0), 1)
	await create_timer(0.3).timeout
	check(not table._faces.has(true) and not table._flips[0].busy, "Смена места посреди переворота не раскрывает новую руку")
	net.end_game()
	for count in range(4, 10):
		net.set_bots(count - 1)
		check(net.start_game().is_empty(), "Старт%d мест" % count)
		await frames()
		table = app.screen
		check(chip(count) != null and table._flips.size() == 2, "Фишки и рука для%d мест" % count)
		net.end_game()
	net.set_bots(9)
	check(net.start_game().is_empty(), "Старт10 мест")
	await frames(15)
	table = app.screen
	check(table._flips.size() == 2 and not table._faces.has(true), "Новая партия закрывает руку")
	for value in range(1, 11):
		check(chip(value) != null and chip(value).get_global_rect().end.x <= 1280, "Номинал%d доступен в720p" % value)
	await drag_start(chip(10))
	await drop(table._hand_zone.get_global_rect().get_center())
	check(net.gang.chips[0] == 10, "Десятая фишка работает через прежний take")
	await flip(0)
	await shot("rank-10")
	for round_index in range(1, 4):
		net.gang.timeout()
		net._push_state()
		await frames()
		check(int(table._view.round_no) == round_index + 1, "Новый цвет раунда%d" % (round_index + 1))
	await shot("river-10")
	net.gang.timeout()
	net._push_state()
	await frames()
	check(net.gang.phase == "showdown" and table._flips.is_empty(), "Вскрытие не оставляет личных обработчиков")
	print("TG INTERACTIONS: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)

