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

## Настоящий щелчок мышью по пункту списка (через окно, как у игрока).
func click_item(list: ItemList, index: int) -> void:
	list.ensure_current_is_visible()
	var rect := list.get_item_rect(index)
	var point := list.get_global_transform_with_canvas() * (rect.get_center() - Vector2(0, list.get_v_scroll_bar().value))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event)
		await process_frame

## Щелчок мышью по плашке игрока на площади.
func click_seat(table: Control, seat: int) -> void:
	var panel: Control = table.seat_nodes[seat].panel
	var point := panel.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event)
		await process_frame

func picked_border(table: Control, seat: int) -> bool:
	var box: StyleBoxFlat = table.seat_nodes[seat].panel.get_theme_stylebox("panel")
	return box.border_width_top == 3

## Выбор игроков щелчком по плашкам (Гадалка — пара, обычный — один), точки голосов приспешников.
func _seat_picks(table: Control) -> void:
	var seats: Array = table.seat_nodes.keys()
	var me := int(net.view.get("you", -1))
	var others: Array = seats.filter(func(x: int): return x != me)
	var a: int = others[0]
	var b: int = others[2]
	var c: int = others[3]
	var pairs: Array = []
	for i in seats.size():
		for j in range(i + 1, seats.size()):
			pairs.append({"label": "пара", "targets": [seats[i], seats[j]]})
	var v: Dictionary = net.view.duplicate(true)
	v.phase = "night"
	v.request = {"token": "test_pair", "title": "Гадалка: выберите двух игроков", "options": pairs}
	table.update_view(v)
	await frames()
	check(table.pick_mode == "pair" and not table.request_options.visible, "Гадалка: вместо длинного списка — выбор на площади")
	await click_seat(table, a)
	check(picked_border(table, a) and table.request_confirm.disabled, "Первый щелчок выделяет плашку, подтверждать рано")
	await click_seat(table, b)
	var expected := -1
	for i in pairs.size():
		if pairs[i].targets.has(a) and pairs[i].targets.has(b): expected = i
	check(table.selected_option == expected and not table.request_confirm.disabled, "Два щелчка выбирают пару (без учёта порядка)")
	check(table.request_summary.text.contains(str(net.view.players[a].name)) and table.request_summary.text.contains("для проверки"), "Панель пишет, кого выбрала Гадалка: " + table.request_summary.text)
	await shot("fortune_pick_1280x720")
	await click_seat(table, a)
	check(not picked_border(table, a) and picked_border(table, b) and table.request_confirm.disabled, "Повторный щелчок снимает выбор")
	await click_seat(table, c)
	await click_seat(table, a)
	await click_seat(table, b)
	check(table.picked.size() == 2 and not table.picked.has(c), "Третий щелчок заменяет самый ранний выбор")
	# Один игрок + особый вариант в списке.
	var single: Array = [{"label": "Не использовать сейчас", "target": -1}]
	for seat: int in others: single.append({"label": str(net.view.players[seat].name), "target": seat})
	v.request = {"token": "test_one", "title": "Выберите игрока", "options": single}
	table.update_view(v)
	await frames()
	check(table.pick_mode == "one" and table.request_options.item_count == 1, "Один игрок: в списке остался только особый вариант")
	await click_seat(table, c)
	check(table.selected_option == others.find(c) + 1 and picked_border(table, c), "Щелчок по плашке выбирает игрока")
	await click_seat(table, a)
	check(table.selected_option == others.find(a) + 1 and not picked_border(table, c), "Щелчок по другой плашке меняет выбор")
	# Голоса приспешников — квадратики цвета голосующих у ника жертвы.
	v.erase("request")
	v.evil_votes = [{"from": a, "target": c}, {"from": b, "target": c}]
	table.update_view(v)
	await frames()
	var votes: HBoxContainer = table.seat_nodes[c].votes
	check(votes.get_child_count() == 2, "У жертвы два квадратика голосов")
	check(votes.get_child_count() == 2 and (votes.get_child(0) as ColorRect).color == net.color_of(int(net.view.players[a].color)), "Квадратик — цвет голосующего приспешника")
	check(table.seat_nodes[a].votes.get_child_count() == 0, "У остальных квадратиков нет")
	await shot("evil_votes_1280x720")
	v.phase = "discussion"
	table.update_view(v)
	await frames()
	check(votes.get_child_count() == 0, "Днём голоса зла не показываются")
	# Без запроса щелчок выбирает собеседника шёпота.
	await click_seat(table, b)
	check(table.receiver.get_selected_id() == b, "Щелчок по плашке выбирает собеседника шёпота")

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
	# Ручной выбор ролей обычными щелчками: клик добавляет роль, повторный клик снимает, другие не сбрасываются.
	var role_list: ItemList = app.screen.roles
	role_list.deselect_all()
	for index: int in [2, 4, 2]:
		await click_item(role_list, index)
	check(role_list.get_selected_items() == PackedInt32Array([4]), "щелчки: роль 3 выбрана и снята повторным щелчком, роль 5 осталась — %s" % [role_list.get_selected_items()])
	await click_item(role_list, 6)
	check(role_list.get_selected_items() == PackedInt32Array([4, 6]), "щелчок по другой роли не снимает прежнюю")
	var roster: GridContainer = app.screen.roster
	check(roster.get_child_count() == 8, "В лобби перечислены все 8 участников")
	check(roster.size.x > 300, "Список участников не сжат в узкую колонку")
	check(str(roster.get_child(0).text).ends_with("рассказчик"), "Рассказчик подписан и стоит первым")
	net.set_bots(15)
	await frames()
	check(roster.get_child_count() == 16, "В лобби перечислены все 16 участников")
	check(app.screen.start.get_global_rect().end.y <= 720, "Кнопка старта видна при 16 участниках")
	var leave_button: Control = app.screen.find_child("Leave", true, false)
	check(leave_button.get_global_rect().end.y <= 720, "«К выбору игры» видна при 16 участниках")
	check(roster.size.y <= (roster.get_parent() as Control).size.y + 1, "16 ников помещаются без прокрутки")
	await shot("lobby_16_1280x720")
	net.set_bots(7)
	await frames()
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
	await _seat_picks(table)
	app.queue_free()
	net.leave()
	await frames()
	print("Clocktower стол: %d проверок, %d ошибок." % [checks, failures])
	quit(1 if failures else 0)

