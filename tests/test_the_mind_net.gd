extends SceneTree
## ENet-проверка The Mind двумя процессами. TM_ROLE=host/client; tools/run_tm_enet.py запускает оба.

var role := OS.get_environment("TM_ROLE")
var net: Node
var checks := 0
var failed := 0
const MARKER := "res://build/mind_tests/enet_client_attempt.txt"

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func wait_until(test: Callable, text: String) -> void:
	var start := Time.get_ticks_msec()
	while not test.call() and Time.get_ticks_msec() - start < 12000:
		await create_timer(0.05).timeout
	check(bool(test.call()), text)

func send(kind: String, data: Dictionary = {}) -> void:
	data["revision"] = net.view.get("revision", -1)
	net.send_action(kind, data)

func _run() -> void:
	net = root.get_node("Net")
	if role == "host":
		check(net.host_enet(23659, "the_mind") == OK, "Сервер запущен")
		await wait_until(func(): return net.members.size() == 2, "Клиент подключён")
		net.set_bots(0)
		check(net.start_game().is_empty(), "Сетевая партия запущена")
		net.mind.hands = [[10], [20]]
		net.mind.revision += 1
		net._push_state()
		await wait_until(func(): return net.mind.ready[1], "Клиент подтвердил готовность")
		check(not net.mind.ready[0], "Подставленное as не действует за хоста")
		check(net.tm_view_seat == 0, "Сетевая подмена места отклонена")
		send("ready")
		await create_timer(0.2).timeout
		send("play", {"card": 10})
		await wait_until(func(): return net.mind.phase == "level_done", "Уровень пройден сетевыми действиями")
		check(net.mind.lives == 2, "Оба числа сыграны без ошибки")
		send("next")
		net.mind.hands = [[50, 70], [10, 60]]
		net.mind.revision += 1
		net._push_state()
		await wait_until(func(): return net.mind.ready[1], "Клиент готов ко второму уровню")
		send("ready")
		send("play", {"card": 50})
		await wait_until(func(): return net.mind.lives == 1 and net.mind.phase == "focus", "Клиент остановил ошибку по сети")
		check(net.mind.discarded == [10] and net.mind.discard_info[0].seat == 1, "Сетевой сброс содержит карту клиента и владельца")
		await create_timer(0.3).timeout
		net.mind.level = net.mind.target
		net.mind._finish(true)
		net.mind.revision += 1
		net._push_state()
		await wait_until(func(): return FileAccess.file_exists(MARKER), "Клиент попытался начать вслепую")
		await create_timer(0.2).timeout
		check(not net.mind.blind, "Продолжение запускает только хост")
		send("blind")
		check(net.mind.blind and net.mind.level == 1, "Хост начал вслепую")
		await wait_until(func(): return net.disconnected.has(1), "Отключение клиента обработано")
		check(not bool(net.mind.players[1].get("bot", false)), "Отключившийся игрок не заменён ботом")
		check(not bool(net.mind.ready[1]) and net.mind.hands[1].size() == 1, "Отключение не даёт согласия и сохраняет руку")
	else:
		await create_timer(0.5).timeout
		check(net.join_enet("127.0.0.1", 23659) == OK, "Подключение к серверу")
		await wait_until(func(): return net.view.get("hand", []) == [20], "Клиент получил только свою руку")
		check(not net.view.has("hands") and net.view.seat == 1, "Приватность и место клиента")
		send("view_seat", {"seat": 0})
		send("ready", {"as": 0})
		await wait_until(func(): return net.view.get("phase") == "play" and net.view.get("pile", []) == [10], "Клиент увидел карту хоста")
		send("play", {"card": 10, "as": 0})
		send("play", {"card": 20})
		await wait_until(func(): return net.view.get("level") == 2 and net.view.get("hand", []) == [10, 60], "Клиент получил вторую раздачу")
		send("ready")
		await wait_until(func(): return bool(net.view.get("can_stop", false)), "СТОП доступен клиенту с меньшей картой")
		check(net.view.lives == 2 and net.view.hand == [10, 60], "Сеть не списывает жизнь до СТОП")
		send("stop")
		await wait_until(func(): return net.view.get("discarded", []) == [10], "Клиент увидел открытый сброс")
		check(net.view.lives == 1 and net.view.discard_info[0].seat == 1, "Одна жизнь снята, карта связана с владельцем")
		await wait_until(func(): return net.view.get("phase") == "game_over", "Клиент увидел общую победу")
		check(bool(net.view.get("won", false)), "Сетевой исход — победа")
		send("blind")
		var marker := FileAccess.open(MARKER, FileAccess.WRITE)
		marker.store_string("попытка отправлена")
		marker.close()
		await wait_until(func(): return bool(net.view.get("blind", false)), "Клиент увидел продолжение вслепую")
		check(net.view.pile.is_empty() and net.view.hand.size() == 1, "Новая закрытая стопка и личная рука")
	print("TM_ENET %s: %d проверок, ошибок %d" % [role, checks, failed])
	net.leave()
	quit(1 if failed else 0)
