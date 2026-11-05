extends SceneTree
## Два реальных ENet-процесса: права выбора, задержка начисления, пауза, отключение.
## Запуск: python tools/run_mk_enet.py. Оба процесса используют Dummy и отдельные профили.

var role := OS.get_environment("MK_ROLE")
var net: Node
var checks := 0
var failures := 0
const FOLDER := "res://build/machi_koro_research/enet/"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА: " + message)

func until(test: Callable, message: String) -> void:
	var started := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - started < 12000:
		await create_timer(0.03).timeout
	check(bool(test.call()), message)

func marker(name: String) -> void:
	var file := FileAccess.open(FOLDER + name + ".tmp", FileAccess.WRITE)
	file.store_string("готово")
	file.close()
	DirAccess.rename_absolute(FOLDER + name + ".tmp", FOLDER + name + ".txt")

func send(kind: String, data: Dictionary = {}) -> void:
	data.revision = net.view.get("revision", -1)
	net.send_action(kind, data)

func _run() -> void:
	net = root.get_node("Net")
	if role == "host":
		check(net.host_enet(25489, "machi_koro") == OK, "ENet-сервер запущен")
		await until(func(): return net.members.size() == 2, "клиент подключён")
		if net.members.size() != 2:
			quit(1)
			return
		net.set_bots(0)
		check(net.start_game().is_empty(), "партия создана")
		net.mk.current = 0
		net.mk.revision += 1
		net._push_state()
		await until(func(): return FileAccess.file_exists(FOLDER + "forged.txt"), "клиент отправил поддельные действия")
		await create_timer(0.2).timeout
		check(net.mk.throw_serial == 0 and net.mk.phase == "roll", "as/seat не дают клиенту ход за хоста")
		net.mk.coins[0] += 1
		net.mk.revision += 1
		net._push_state()
		await until(func(): return FileAccess.file_exists(FOLDER + "foreign_stable.txt"), "чужое изменение проверено на клиентском столе")
		net.mk.current = 1
		for city: Array in net.mk.cities:
			city.clear()
		net.mk.coins = [8, 0]
		net.mk._add_card(1, "tv")
		net.mk.result = 6
		net.mk._resolve()
		net.mk.revision += 1
		net._push_state()
		await until(func(): return net.mk.phase == "animation", "клиент выбрал цель Телецентра")
		check(net.mk.coins == [8, 0], "нет мгновенного начисления после выбора")
		net.set_paused(true)
		var remaining: float = net.mk.event_left
		await create_timer(0.4).timeout
		check(net.mk.coins == [8, 0] and is_equal_approx(net.mk.event_left, remaining), "пауза останавливает начисление и время эффекта")
		net.set_paused(false)
		await until(func(): return net.mk.coins == [3, 5], "хост применил перевод после показа")
		await until(func(): return FileAccess.file_exists(FOLDER + "received.txt"), "клиент подтвердил именно свой новый снимок")
		await until(func(): return net.disconnected.has(1), "отключение обработано")
		check(not net.mk.players[1].bot, "место отключившегося не стало ботом")
		net.return_to_party()
		check(net.mk == null, "возврат в хаб очищает правила Мачи Коро")
	else:
		await create_timer(0.5).timeout
		check(net.join_enet("127.0.0.1", 25489) == OK, "ENet-клиент запущен")
		await until(func(): return net.view.get("game") == "machi_koro" and net.view.get("current") == 0, "клиент увидел ход хоста")
		if not net.view.has("you"):
			quit(1)
			return
		check(net.view.you == 1 and not net.view.has("deck") and not net.view.has("jobs"), "своё место и скрытая служебная информация")
		var foreign_app: Control = load("res://games/machi_koro/ui/main.tscn").instantiate()
		root.add_child(foreign_app)
		await process_frame
		await process_frame
		var foreign_table: Control = foreign_app.screen
		var own_card: Control = foreign_table.city_cards.get_child(0)
		var other_card: Control = foreign_table.landmark_cards.get_child(0)
		send("roll", {"count": 1, "as": 0, "seat": 0})
		send("view_seat", {"seat": 0})
		marker("forged")
		await until(func(): return net.view.get("coins", [0])[0] == 4, "клиент получил изменение монет другого игрока")
		await process_frame
		await process_frame
		check(foreign_app.screen == foreign_table and foreign_table.city_cards.get_child(0) == own_card and foreign_table.landmark_cards.get_child(0) == other_card, "реальный ENet: чужой ход сохраняет карты обоих городов")
		foreign_app.free()
		marker("foreign_stable")
		await until(func(): return net.view.get("phase") == "choice" and net.view.get("current") == 1, "клиент получил собственный выбор")
		var app: Control = load("res://games/machi_koro/ui/main.tscn").instantiate()
		root.add_child(app)
		await process_frame
		await process_frame
		var table: Control = app.screen
		var enterprise: Control = table.city_cards.get_child(0)
		var market: Control = table.market_grid.get_child(0)
		var city_position := enterprise.position
		send("choose", {"index": 0})
		send("choose", {"index": 0})
		await until(func(): return net.view.get("phase") == "animation", "клиент получил событие анимации")
		check(net.view.coins == [8, 0], "в событии ещё прежние балансы")
		await until(func(): return net.view.get("coins") == [3, 5], "клиент дождался своего снимка начисления")
		check(net.view.coins == [3, 5], "повторный choose не удвоил перевод")
		await process_frame
		await process_frame
		check(app.screen == table and table.city_cards.get_child(0) == enterprise, "реальный ENet: эффект не пересоздал стол и карту города")
		check(table.market_grid.get_child(0) == market and enterprise.position.is_equal_approx(city_position), "реальный ENet: карта рынка и положение города сохранены после паузы и выплаты")
		app.free()
		marker("received")
	print("MK_ENET %s: %d проверок, %d ошибок" % [role, checks, failures])
	net.leave()
	quit(1 if failures else 0)
