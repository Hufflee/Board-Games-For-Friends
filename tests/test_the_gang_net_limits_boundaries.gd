## Границы общего лобби8/10, защита start от отрицательного счётчика и статус Gang при reconnect.
## Прямой тест реального Net с транспортом родительского harness, не настоящий ENet-сокет.
## --headless --audio-driver Dummy --script res://tests/test_the_gang_net_limits_boundaries.gd.
extends "res://tests/test_the_gang_net_contract.gd"

func lobby(count: int, game: String) -> Node:
	var n := net()
	n.mode = "enet"
	for peer: int in range(2, count + 1):
		n.api.sender = peer
		n._rpc_hello("Друг%d" % peer)
	n.api.sender = 1
	n.select_game(game)
	return n

func capacity_boundaries() -> void:
	for game: String in ["perudo", "the_gang"]:
		var maximum: int = 10 if game == "the_gang" else 8
		for count: int in [8, 9, 10]:
			var n := lobby(count, game)
			n.set_bots(-50)
			check(n.bots == 0 and n.player_total() == count, "%s/%d: отрицательная заявка не скрывает людей" % [game, count])
			n.set_bots(99)
			check(n.bots == maxi(0, maximum - count), "%s/%d: добавочные места ограничены неотрицательным остатком" % [game, count])
			check(n.player_total() == maxi(count, maximum), "%s/%d: переполненное лобби не маскируется" % [game, count])
			var error: String = n.start_game()
			check((error == "") == (count <= maximum) and n.in_game == (count <= maximum),
				"%s/%d: start проверяет реальное количество" % [game, count])
			if n.in_game:
				check(n._gp().size() == n.player_total(), "%s: фактических мест ровно столько, сколько проверено" % game)
				if game == "the_gang":
					check(n._gp().all(func(p: Dictionary) -> bool: return not p.bot), "Gang: добавочные места не превращены в обычных ботов")
			dispose(n)
	# Имитируем оставшееся от старой версии отрицательное поле, минуя исправленный setter.
	for count: int in [3, 10]:
		var n := lobby(count, "perudo")
		n.bots = -2
		check(n.player_total() == count, "Старое bots=-2 не уменьшает публичный total%d" % count)
		var error: String = n.start_game()
		check((error == "") == (count <= 8), "Start независимо от setter не пропускает лишних реальных участников")
		if n.in_game:
			check(n._gp().size() == count, "Отрицательное поле не создаёт отрицательные/лишние места при старте")
		dispose(n)
	var n := lobby(3, "perudo")
	n.bots = 6
	check(n.start_game() != "" and not n.in_game, "Обход setter с положительным переполнением также не запускает9 мест старой игры")
	dispose(n)

func disconnect_status() -> void:
	var n := remote()
	var game: RefCounted = n.gang
	var hand: Array = n.gang.hands[1].duplicate()
	n._handle_action(2, "take", {"value": 2})
	var revision: int = n.gang.revision
	var count: int = n.chat_log.size()
	n._on_peer_disconnected(2)
	check(n.chat_log.size() == count + 1, "Отключение создаёт одно отдельное системное сообщение")
	check(n.chat_log.back().kind == "system" and n.chat_log.back().text ==
		"Друг2 отключился. Пропущенный выбор за его место будет сделан случайно по таймеру. Он может вернуться в партию.",
		"Системный чат точно сообщает о случайном выборе по таймеру")
	check(not n.gang.players[1].bot and n.gang.players[1].name == "Друг2", "Отключённое место остаётся человеком с прежним именем")
	check(n.gang.revision == revision and n.gang.hands[1] == hand and n.gang.chips[1] == 2,
		"Смена статуса не пересдаёт карты, не меняет фишку и игровую ревизию")
	n.api.sender = 7
	n._rpc_hello("Друг2")
	check(is_same(n.gang, game) and n.seat_peers[1] == 7, "Штатный reconnect не создаёт новые правила и возвращает прежнее место")
	check(n.gang.players[1].name == "Друг2" and not n.gang.players[1].bot and n.sent[7].hand == hand,
		"Вернувшийся peer получает исходное имя, человеческую роль и свою руку")
	check(n.gang.chips[1] == 2 and not n.disconnected.has(1), "Выбранная фишка и завершение reconnect сохранены")
	dispose(n)
	# В старой игре с обычными ботами прежняя подмена статуса остаётся законной.
	n = lobby(3, "perudo")
	check(n.start_game() == "", "Подготовлена старая игра с обычными ботами")
	n._on_peer_disconnected(2)
	check(n.perudo.players[1].bot and n.perudo.players[1].name == "Друг2 (бот)", "Perudo: исключение Gang не отменяет старый статус бота")
	check(str(n.chat_log.back().text).contains("пока за него играет бот"), "Perudo: прежнее сообщение о боте сохранено")
	dispose(n)

func _run() -> void:
	root.get_node("Net").set_process(false)
	direct_script = GDScript.new()
	direct_script.source_code = "extends \"res://games/king_of_12/net/net.gd\"\nvar sent: Dictionary = {}\nvar api: MultiplayerAPIExtension\nfunc _ready() -> void:\n\tset_process(false)\nfunc _send_view(target: int, payload: Dictionary) -> void:\n\tsent[target] = payload.duplicate(true)\n\tif target == 1:\n\t\t_apply_state(payload)\n"
	if direct_script.reload() != OK:
		await root.get_node("Sfx").request_quit(2)
		return
	capacity_boundaries()
	disconnect_status()
	print("THE GANG NET LIMITS BOUNDARIES: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
