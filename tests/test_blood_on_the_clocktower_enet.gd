extends SceneTree
## Clocktower по реальному ENet: хост-рассказчик и 5 клиентов-игроков в отдельных процессах.
## Чужие действия (шёпот, номинация, руки) не пересоздают стол наблюдателя и не сбрасывают
## открытые окна, черновик шёпота, выбор собеседника и положение плашек; чужое скрытое не приходит.
## Вылет: p5 убивает свой процесс без выхода из сети; p5r — перезапуск с тем же профилем (ключ места
## на диске) садится на то же место с той же ролью; p6 — посторонний с новым профилем остаётся зрителем.
## Запуск: python tools/run_bc_enet.py (Dummy, отдельные APPDATA, роли host/p1..p5, p5r, p6).

var role := OS.get_environment("BC_ROLE")
var net: Node
var checks := 0
var failures := 0
const FOLDER := "res://build/claude_review/bc_enet/"
const PORT := 25511

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА [%s]: %s" % [role, message])

func until(test: Callable, message: String, limit := 20000) -> void:
	var started := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - started < limit:
		await create_timer(0.03).timeout
	check(bool(test.call()), message)

func marker(name: String, text := "готово") -> void:
	var file := FileAccess.open(FOLDER + name + ".tmp", FileAccess.WRITE)
	file.store_string(text)
	file.close()
	DirAccess.rename_absolute(FOLDER + name + ".tmp", FOLDER + name + ".txt")

func has_marker(name: String) -> bool:
	return FileAccess.file_exists(FOLDER + name + ".txt")

func read_marker(name: String) -> String:
	return FileAccess.get_file_as_string(FOLDER + name + ".txt")

func frames(count := 4) -> void:
	for i in count:
		await process_frame

func seat_of(name: String) -> int:
	return int(read_marker("seat_" + name))

func send(kind: String, data: Dictionary = {}) -> void:
	data.revision = int(net.view.get("revision", -1))
	net.send_action(kind, data)

func _run() -> void:
	net = root.get_node("Net")
	net.my_name = "Участник " + role
	if role in ["p5r", "p6"]:
		await _returner()
		print("BC_ENET %s: %d проверок, %d ошибок" % [role, checks, failures])
		net.leave()
		await create_timer(0.3).timeout
		quit(1 if failures else 0)
		return
	if role == "host":
		await _host()
	else:
		await _client()
	print("BC_ENET %s: %d проверок, %d ошибок" % [role, checks, failures])
	net.leave()
	await create_timer(0.3).timeout
	quit(1 if failures else 0)

func _host() -> void:
	check(net.host_enet(PORT, "blood_on_the_clocktower") == OK, "ENet-сервер запущен")
	await until(func(): return net.members.size() == 6, "5 клиентов подключились")
	if net.members.size() != 6:
		return
	net.set_setting("bc_storyteller", 0)
	await create_timer(0.3).timeout
	check(net.start_game().is_empty(), "партия на 5 игроков + рассказчик создана")
	if net.bc == null:
		return
	check(net.bc.storyteller == 0, "рассказчик — хост (место 0)")
	# Ночь не проверяем здесь (её покрывают тесты правил): сразу рассвет первого дня.
	net.bc.dawn()
	net._push_state()
	var roles := {}
	for i in net.bc.players.size():
		roles[i] = str(net.bc.roles[i])
	marker("roles", var_to_str(roles))
	marker("day")
	await until(func(): return has_marker("observer_ready"), "наблюдатель открыл окна", 30000)
	await until(func(): return has_marker("whispered"), "игрок прошептал")
	send("open_nominations")
	await until(func(): return net.bc.phase == "defense", "игрок номинировал")
	send("start_vote")
	await until(func(): return net.bc.phase == "voting", "голосование началось")
	await until(func(): return net.bc.hands.count(true) >= 2, "две руки поднялись одновременно")
	check(net.view.has("grimoire"), "рассказчик-хост видит гримуар")
	marker("voting")
	for name: String in ["p1", "p2", "p3", "p4"]:
		await until(func(): return has_marker("done_" + name), "клиент %s закончил" % name, 30000)
	# Вылет p5: процесс убит, хост замечает это по тайм-ауту ENet (20–45 с).
	await until(func(): return has_marker("p5_identity"), "p5 записал своё место перед вылетом", 30000)
	var lost := seat_of("p5")
	await until(func(): return net.disconnected.has(lost), "хост заметил вылет p5", 120000)
	check(net.bc.players.size() == 6 and net.bc.roles[lost] == str_to_var(read_marker("roles"))[lost], "место и роль вылетевшего сохранены")
	marker("p5_gone")
	await until(func(): return not net.disconnected.has(lost) and net.seat_peers[lost] > 1, "вернувшийся снова сидит на своём месте", 40000)
	check(not net.disconnected.has(lost), "место вылетевшего больше не числится отключённым")
	# Посторонний подключается после того, как p5r сел (и пока оба ещё в сети).
	await until(func(): return net.spectators().size() == 1, "посторонний подключился зрителем, за стол не сел", 40000)
	check(not net.seat_peers.has(int(net.spectators()[0])) and net.bc.players.size() == 6, "посторонний не занял ничьё место")
	await until(func(): return has_marker("done_p5r") and has_marker("done_p6"), "вернувшийся и посторонний закончили", 40000)

func _client() -> void:
	var order := int(role.substr(1))
	await create_timer(0.4 + order * 0.35).timeout
	check(net.join_enet("127.0.0.1", PORT) == OK, "ENet-клиент запущен")
	await until(func(): return net.view.get("game") == "blood_on_the_clocktower" and net.view.get("phase") == "discussion", "клиент увидел первый день", 40000)
	if net.view.get("phase") != "discussion":
		marker("done_" + role)
		return
	var me := int(net.view.get("you", -1))
	check(me > 0, "клиент получил своё место, не рассказчика")
	check(not net.view.has("grimoire"), "у игрока нет гримуара")
	marker("seat_" + role, str(me))
	var app: Control = load("res://games/blood_on_the_clocktower/ui/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	check(app.mode == "table", "клиент открыл стол")
	match role:
		"p2": await _observer(app, me)
		"p1": await _actor(me)
		"p4": await _second_hand()
	await until(func(): return has_marker("voting") or not net.in_game, "хост дошёл до голосования", 40000)
	if role == "p5":
		check(FileAccess.file_exists("user://bc_resume.cfg"), "ключ места сохранён на диск")
		marker("p5_identity", var_to_str({"seat": me, "role": str(net.view.get("role", ""))}))
		print("BC_ENET %s: %d проверок, %d ошибок" % [role, checks, failures])
		# Настоящий вылет: без net.leave() и без закрытия соединения.
		OS.kill(OS.get_process_id())
		return
	app.queue_free()
	marker("done_" + role)

## Наблюдатель: открывает окна, пишет черновик и проверяет, что чужие действия ничего не сбили.
func _observer(app: Control, me: int) -> void:
	var table: Control = app.screen
	await until(func(): return not table.seat_nodes.is_empty(), "плашки мест построены")
	await frames(6)
	app.show_handbook()
	table.log_window.show()
	table.private_text.text = "Черновик наблюдателя"
	table.private_text.grab_focus()
	table.private_text.caret_column = 5
	var chosen_receiver := -1
	if table.receiver.item_count > 1:
		table.receiver.select(1)
		chosen_receiver = table.receiver.get_selected_id()
	var panels := {}
	var places := {}
	for seat: int in table.seat_nodes:
		panels[seat] = table.seat_nodes[seat].panel.get_instance_id()
		places[seat] = table.seat_nodes[seat].panel.position
	var app_screen_id := table.get_instance_id()
	var handbook_id: int = app.handbook.get_instance_id()
	marker("observer_ready")
	var actor_seat := -1
	var second_seat := -1
	await until(func(): return has_marker("seat_p1") and has_marker("seat_p4"), "места соседей известны")
	actor_seat = seat_of("p1")
	second_seat = seat_of("p4")
	await until(func(): return net.view.get("last_whisper", []).has(actor_seat), "наблюдатель видит факт чужого шёпота")
	var whisper_text_leaked := false
	for line in net.view.get("messages", []):
		if "Секрет для p3" in str(line): whisper_text_leaked = true
	check(not whisper_text_leaked and not "Секрет для p3" in var_to_str(net.view), "текст чужого шёпота не пришёл наблюдателю")
	await until(func():
		var people: Array = net.view.get("players", [])
		return net.view.get("phase") == "voting" and people.size() > second_seat and bool(people[actor_seat].hand) and bool(people[second_seat].hand),
		"наблюдатель видит две поднятые руки")
	await frames(6)
	check(app.screen == table and table.get_instance_id() == app_screen_id, "стол не пересоздан чужими действиями")
	var same_panels := true
	var still := true
	for seat: int in panels:
		if not table.seat_nodes.has(seat) or table.seat_nodes[seat].panel.get_instance_id() != panels[seat]:
			same_panels = false
		elif table.seat_nodes[seat].panel.position.distance_to(places[seat]) > 0.5:
			still = false
			print("[p2] плашка %d сдвинулась: %s → %s" % [seat, places[seat], table.seat_nodes[seat].panel.position])
	check(same_panels, "плашки мест — те же узлы")
	check(still, "плашки мест не разлетаются и не сдвигаются")
	check(table.seat_nodes[actor_seat].hand.modulate.a > 0.9 and table.seat_nodes[second_seat].hand.modulate.a > 0.9, "руки показаны на плашках")
	check(is_instance_valid(app.handbook) and app.handbook.get_instance_id() == handbook_id and app.handbook.visible, "справочник остался открытым")
	check(table.log_window.visible, "журнал остался открытым")
	check(table.private_text.text == "Черновик наблюдателя", "черновик шёпота сохранён")
	check(table.private_text.has_focus(), "фокус ввода сохранён")
	check(table.private_text.caret_column == 5, "курсор в черновике на месте")
	if chosen_receiver >= 0:
		check(table.receiver.get_selected_id() == chosen_receiver, "выбранный собеседник сохранён")
	# Приватность: чужие роли и служебное не приходят даже в сериализованном view.
	var view: Dictionary = net.view
	var leaked: Array[String] = []
	for person: Dictionary in view.get("players", []):
		for key: String in ["role", "side", "status", "healthy"]:
			if person.has(key): leaked.append(key)
	check(leaked.is_empty(), "публичные места без роли/стороны/состояния: %s" % [leaked])
	check(not view.has("grimoire") and not view.has("revealed"), "наблюдатель не получил гримуар и раскрытие")
	var roles: Dictionary = str_to_var(read_marker("roles"))
	var own := str(view.get("role", ""))
	var text := var_to_str(view)
	if str(view.get("side", "")) == "good" and not view.has("knowledge"):
		var seen: Array[String] = []
		for seat: int in roles:
			var id := str(roles[seat])
			if seat == me or id == own or id == "": continue
			if text.contains("\"%s\"" % id): seen.append("%d:%s" % [seat, id])
		check(seen.is_empty(), "чужие роли не в сериализованном view: %s" % [seen])
	else:
		print("[p2] сторона %s — сверка чужих ролей пропущена (у злых есть законное знание)" % view.get("side", ""))

## Игрок шепчет третьему, номинирует его и поднимает руку.
func _actor(me: int) -> void:
	await until(func(): return has_marker("observer_ready") and has_marker("seat_p3"), "наблюдатель готов", 30000)
	var friend := seat_of("p3")
	net.send_action("whisper", {"target": friend, "text": "Секрет для p3"})
	await until(func(): return net.view.get("last_whisper", []).has(me), "свой шёпот отмечен")
	marker("whispered")
	await until(func(): return net.view.get("phase") == "nominations", "номинации открыты")
	send("nominate", {"target": friend})
	await until(func(): return net.view.get("phase") == "voting", "голосование по номинации началось")
	net.send_action("hand", {"raised": true})

## Второй игрок поднимает руку одновременно с первым.
func _second_hand() -> void:
	await until(func(): return net.view.get("phase") == "voting", "голосование видно второму игроку", 40000)
	net.send_action("hand", {"raised": true})

## p5r — перезапуск вылетевшего игрока с тем же профилем; p6 — посторонний с чистым профилем.
func _returner() -> void:
	var waits := "p5_gone" if role == "p5r" else "done_p5r"
	var started := Time.get_ticks_msec()
	while not has_marker(waits) and Time.get_ticks_msec() - started < 200000:
		await create_timer(0.1).timeout
	if not has_marker(waits):
		check(false, "не дождался %s" % waits)
		marker("done_" + role)
		return
	if role == "p5r":
		check(net.bc_bridge.resume_token.length() == 48, "ключ места прочитан с диска после перезапуска")
	else:
		check(net.bc_bridge.resume_token.is_empty(), "у постороннего нет ключа")
	check(net.join_enet("127.0.0.1", PORT) == OK, "переподключение запущено")
	await until(func(): return net.view.get("game") == "blood_on_the_clocktower" and net.view.has("players"), "получен стол после подключения", 20000)
	if role == "p5r":
		var before: Dictionary = str_to_var(read_marker("p5_identity"))
		await until(func(): return int(net.view.get("you", -1)) == int(before.seat), "вернулся на своё место %d" % int(before.seat))
		check(str(net.view.get("role", "")) == str(before.role), "та же роль после вылета: %s" % str(before.role))
		check(not bool(net.view.get("spectator", false)), "не зритель")
		var app: Control = load("res://games/blood_on_the_clocktower/ui/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		check(app.mode == "table", "вернувшийся видит стол")
		app.queue_free()
		marker("done_" + role)
		await until(func(): return has_marker("done_p6"), "посторонний проверен", 40000)
		return
	else:
		await frames(10)
		check(bool(net.view.get("spectator", false)) and int(net.view.get("you", -1)) < 0, "посторонний смотрит как зритель")
		check(not net.view.has("role") and not net.view.has("messages") and not net.view.has("grimoire"), "зритель не видит ролей и личных сообщений")
	marker("done_" + role)
