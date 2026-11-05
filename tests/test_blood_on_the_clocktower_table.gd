extends SceneTree
## Реальные экраны Clocktower, неизменность узлов/ввода при view и снимки 1280×720.
var checks := 0
var failures := 0
var net: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("ОШИБКА: " + message)

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func shot(file: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/botc/" + file + ".png")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	root.get_node("Prefs").theme_mode = "light"
	var app: Control = load("res://games/blood_on_the_clocktower/ui/bc_app.gd").new()
	root.add_child(app)
	await frames()
	check(app.mode == "menu", "Меню открыто")
	await shot("menu_1280x720")
	net.host_offline("blood_on_the_clocktower")
	net.set_bots(7)
	await frames()
	check(app.mode == "lobby", "Лобби открыто")
	check(app.screen.secret.visible, "Закрытая подготовка доступна соло-рассказчику")
	check(app.screen.roles.item_count == 22, "Редактор показывает роли сценария")
	var lobby_id: int = app.screen.get_instance_id()
	app.screen.roles.select(0, false)
	net.lobby_changed.emit()
	check(app.screen.get_instance_id() == lobby_id, "Снимок лобби не пересоздаёт экран")
	await shot("lobby_1280x720")
	check(net.start_game().is_empty(), "Партия начинается")
	await frames()
	check(app.mode == "table", "Постоянный стол открыт")
	var table: Control = app.screen
	var table_id: int = table.get_instance_id()
	check(table.seat_nodes.size() == 7, "На площади семь игроков без рассказчика")
	await shot("story_1280x720")
	table.private_text.text = "Незавершённая личная мысль"
	table.private_text.grab_focus()
	var seat_id: int = table.seat_nodes.values()[0].panel.get_instance_id()
	app.show_handbook()
	app.handbook.hide()
	table.log_window.show()
	net.state_changed.emit(net.view.duplicate(true))
	net.lobby_changed.emit()
	await frames()
	check(app.screen.get_instance_id() == table_id, "Чужое лобби-событие не пересоздаёт стол")
	check(table.seat_nodes.values()[0].panel.get_instance_id() == seat_id, "Повторный view сохраняет узел места")
	check(table.private_text.text == "Незавершённая личная мысль", "Повторный view сохраняет черновик")
	check(table.private_text.has_focus(), "Повторный view сохраняет фокус")
	check(table.log_window.visible, "Повторный view сохраняет открытый журнал")
	table.log_window.hide()
	net.send_action("begin_night", {"revision": int(net.view.revision)})
	await frames()
	check(net.bc.abilities.started, "Рассказчик запускает первую ночь")
	var steps := 0
	while net.bc.phase == "night" and steps < 300:
		steps += 1
		var requests: Array = net.bc.requests.keys()
		if requests.is_empty(): break
		var who := int(requests[0])
		net.send_action("view_seat", {"seat": who})
		await frames()
		var request: Dictionary = net.view.get("request", {})
		check(not request.is_empty(), "Приватный запрос виден адресату")
		net.send_action("private_reply", {"token": request.get("token", ""), "index": 0})
		await frames()
	check(net.bc.phase == "discussion", "Первая ночь завершена через адресные кнопки")
	net.send_action("view_seat", {"seat": 1})
	await frames()
	await shot("player_1280x720")
	check(table.role_key == str(net.view.get("role", "")), "Личная карточка соответствует известной роли")
	# Состав случайный: Шпион по правилам видит гримуар, остальные — нет.
	check(table.grimoire_text.text.is_empty() or str(net.view.get("role", "")) == "spy", "Закрытый гримуар очищен у обычного игрока")
	app.queue_free()
	net.leave()
	await frames()
	print("Clocktower стол: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures else 0)

