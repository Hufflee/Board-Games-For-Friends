extends SceneTree
## Два реальных процесса ENet: чужой ответ не стирает клиентский ввод/выбор.
## Запуск: python tools/run_batch22_enet.py (Dummy, отдельные профили).

var net: Node
var checks := 0
var failures := 0
var role := OS.get_environment("B22_ROLE")
var game := OS.get_environment("B22_GAME")
var folder := OS.get_environment("B22_FOLDER")


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func until(test: Callable, message: String) -> bool:
	var start := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - start < 15000:
		await create_timer(0.03).timeout
	var ok := bool(test.call())
	check(ok, message)
	return ok


func marker(name: String) -> void:
	var file := FileAccess.open(folder.path_join(name + ".tmp"), FileAccess.WRITE)
	file.store_string("готово")
	file.close()
	DirAccess.rename_absolute(folder.path_join(name + ".tmp"), folder.path_join(name))


func _run() -> void:
	net = root.get_node("Net")
	net.my_name = "Проверка " + role
	var port := int(OS.get_environment("B22_PORT"))
	if role == "host":
		await _host(port)
	else:
		await _client(port)
	net.leave()
	await process_frame
	print("B22_ENET %s %s: %d проверок, %d ошибок" % [game, role, checks, failures])
	root.get_node("Sfx").request_quit(1 if failures else 0)


func _host(port: int) -> void:
	check(net.host_enet(port, game) == OK, "Открыт сервер")
	if not await until(func() -> bool: return net.members.size() == 2, "Клиент подключился"):
		return
	net.set_bots(1)
	check(net.start_game().is_empty(), "Партия началась")
	if game == "green_team_wins":
		net.green_team.cards[0] = "blank_00"
	else:
		net.first_contact.phase = "vote"
		net.first_contact.clue = [{"symbol": 0, "negative": false}]
	net._push_state()
	if not await until(func() -> bool: return FileAccess.file_exists(folder.path_join("draft")), "Клиент начал своё действие"):
		return
	if game == "green_team_wins":
		check(net.green_team.action(0, "answer", {"round": 0, "answer": "кот"}, true), "Хост дал чужой ответ")
	else:
		check(net.first_contact.action(0, "vote", {"serial": net.first_contact.serial, "slots": [0]}, true), "Хост проголосовал")
	net._push_state()
	if not await until(func() -> bool: return FileAccess.file_exists(folder.path_join("stable")), "Клиент подтвердил сохранение своего ввода"):
		return
	if game == "green_team_wins":
		await until(func() -> bool: return net.green_team.answers.has(1), "Черновик клиента принят хостом")
		check(net.green_team.answers.get(1) == "неоконченный ответ клиента", "Хост получил исходный текст клиента")
	else:
		await until(func() -> bool: return net.first_contact.phase == "result", "Хост получил голос клиента")
		check(net.first_contact.last_votes.get(1) == [2], "Хост получил сохранённый выбор клиента")
	await until(func() -> bool: return FileAccess.file_exists(folder.path_join("done")), "Клиент получил свой итоговый снимок")


func _client(port: int) -> void:
	await create_timer(0.35).timeout
	check(net.join_enet("127.0.0.1", port) == OK, "Клиент подключается")
	if not await until(func() -> bool: return net.view.get("game") == game and net.view.get("phase") == ("answer" if game == "green_team_wins" else "vote"), "Получено задание клиента"):
		return
	var app: Control = load("res://games/" + game + "/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await process_frame
	await process_frame
	check(net.view.seat == 1, "Клиент управляет своим местом")
	if game == "green_team_wins":
		if not is_instance_valid(app.edit):
			check(false, "Клиент получил поле свободного ответа")
			return
		app.edit.text = "неоконченный ответ клиента"
		app.edit.text_changed.emit(app.edit.text)
		app.edit.caret_column = 3
		app.edit.grab_focus()
	else:
		app._pick_card(2)
	marker("draft")
	if not await until(func() -> bool: return 0 in net.view.get("answered", []), "Получено именно клиентское обновление после действия хоста"):
		return
	if game == "green_team_wins":
		check(app.edit.text == "неоконченный ответ клиента" and app.edit.caret_column == 3, "ENet сохраняет текст и курсор клиента")
		check(app.edit.has_focus(), "ENet сохраняет фокус")
	else:
		check(app.selected == [2], "ENet сохраняет выбранную клиентом карточку")
	marker("stable")
	if game == "green_team_wins":
		app._submit(app.edit.text)
		await until(func() -> bool: return 1 in net.view.get("answered", []), "Клиент получил подтверждение своего ответа")
	else:
		net.send_action("vote", {"serial": net.view.serial, "slots": app.selected.duplicate()})
		await until(func() -> bool: return net.view.get("phase") == "result", "Клиент получил результаты голосования")
	marker("done")
	app.queue_free()
	current_scene = null
	await process_frame
