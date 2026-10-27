## Прямой контракт Net для The Gang: приватность, часы, disconnect/reconnect, жизненный цикл и пределы.
## Без UI/ENet/Steam: исходящие сообщения перехватываются тестовым транспортом, production не меняется.
## --headless --audio-driver Dummy --script res://tests/test_the_gang_net_contract.gd.
extends SceneTree

class DirectAPI:
	extends MultiplayerAPIExtension
	var sender := 1
	var peer: MultiplayerPeer = OfflineMultiplayerPeer.new()
	var packets: Array = []
	func _get_unique_id() -> int:
		return 1
	func _get_remote_sender_id() -> int:
		return sender
	func _get_peer_ids() -> PackedInt32Array:
		return PackedInt32Array()
	func _get_multiplayer_peer() -> MultiplayerPeer:
		return peer
	func _set_multiplayer_peer(value: MultiplayerPeer) -> void:
		peer = value
	func _poll() -> Error:
		return OK
	func _object_configuration_add(_object: Object, _configuration: Variant) -> Error:
		return OK
	func _object_configuration_remove(_object: Object, _configuration: Variant) -> Error:
		return OK
	func _rpc(target: int, _object: Object, method: StringName, args: Array) -> Error:
		packets.append({"target": target, "method": method, "args": args.duplicate(true)})
		return OK

var direct_script: GDScript

var checks := 0
var errors := 0
var serial := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(label)

func net() -> Node:
	var n: Node = direct_script.new()
	serial += 1
	n.name = "ПрямойNet%d" % serial
	root.add_child(n)
	n.api = DirectAPI.new()
	set_multiplayer(n.api, n.get_path())
	n.host_offline("the_gang")
	n.set_bots(0)
	return n

func remote(count: int = 3) -> Node:
	var n := net()
	n.mode = "enet"  # Только ветка кода: транспорт остаётся DirectAPI/OfflineMultiplayerPeer.
	for peer in range(2, count + 1):
		n.api.sender = peer
		n._rpc_hello("Друг%d" % peer)
	n.api.sender = 1
	check(n.start_game() == "", "Подготовка: старт прямой удалённой сессии%d" % count)
	return n

func dispose(n: Node) -> void:
	var path: NodePath = n.get_path()
	n.leave()
	set_multiplayer(null, path)
	n.free()

func settle(n: Node) -> void:
	# Первый тик узнаёт новый phase/turn_no, второй публикует новый срок через stamp.
	n._process(0.0)
	n._process(0.0)

func offline_privacy() -> void:
	var n := net()
	n.set_bots(9)
	check(n.player_total() == 10 and n.start_game() == "", "Offline The Gang принимает10 мест")
	if n.gang == null:
		dispose(n)
		return
	check(n.gang.players.size() == 10 and n.seat_peers.size() == 10, "Созданы десять мест и соответствия peer")
	check(n.gang.players.all(func(player): return not bool(player.get("bot", false))), "Дополнительные offline-места — люди hotseat, не обычные боты")
	for seat in 10:
		n.send_action("view_seat", {"seat": seat})
		check(n.tg_view_seat == seat and n.view.seat == seat and n.view.hand == n.gang.hands[seat], "Выбран приватный hotseat%d" % seat)
		check(n.view.hotseat and n.view.game == "the_gang", "View помечен правильной игрой и hotseat")
		check(not n.view.has("hands") and n.view.result.is_empty(), "Нет массива чужих рук до вскрытия")
	n.send_action("take", {"value": 5, "revision": n.gang.revision})
	check(n.gang.chips[9] == 5 and n.gang.chips[0] == 0, "Офлайн-действие относится к выбранному месту9")
	var spectator: Dictionary = n._seat_view(-1, [], 0.0, false)
	check(spectator.seat == -1 and spectator.hand.is_empty() and spectator.result.is_empty(), "Net spectator−1 не видит приватной руки")
	var revision: int = n.gang.revision
	n.send_action("view_seat", {"seat": 10})
	check(n.tg_view_seat == 9 and n.gang.revision == revision, "Неверное hotseat-место не меняет состояние")
	dispose(n)

func remote_privacy() -> void:
	var n := remote()
	var original: Array = n.gang.hands.duplicate(true)
	n.tg_view_seat = 2  # Локальный выбор хоста не должен влиять на удалённые view.
	n._push_state()
	for peer in range(1, 4):
		check(n.sent[peer].seat == peer - 1 and n.sent[peer].hand == original[peer - 1], "Удалённый peer%d получает только своё место" % peer)
		check(not n.sent[peer].hotseat, "Удалённый peer%d не получает show_all/hotseat" % peer)
	var revision: int = n.gang.revision
	n._handle_action(2, "view_seat", {"seat": 0})
	check(n.tg_view_seat == 2 and n.gang.revision == revision, "Удалённый peer не может переключить чужое view_seat")
	n._handle_action(2, "take", {"value": 1})
	check(n.gang.chips == [0,1,0], "Peer2 действует своим местом1, а не локально выбранным2")
	n._handle_action(99, "take", {"value": 2})
	check(n.gang.chips == [0,1,0], "Неизвестный/незанявший место peer не действует")
	n.api.sender = 99
	n._rpc_hello("Зритель")
	check(n.sent.has(99) and n.sent[99].spectator and n.sent[99].seat == -1 and n.sent[99].hand.is_empty(),
		"Новый зритель получает отдельный−1 view через настоящий _push_state")
	check(n.gang.hands == original, "Вход зрителя не пересдаёт pocket")
	dispose(n)

func clocks_and_pause() -> void:
	var n := remote()
	n.settings.turn_time = 60
	settle(n)
	n._process(10.0)
	check(is_equal_approx(n._phase_time, 10.0), "Время раунда прошло10 секунд")
	n._handle_action(2, "take", {"value": 2})
	check(is_equal_approx(n._phase_time, 10.0) and n.sent[2].turn_left == 50, "Take не перезапускает срок при рассылке")
	n._handle_action(2, "return", {})
	n._process(3.0)
	n._push_state()
	check(is_equal_approx(n._phase_time, 13.0) and n.sent[1].turn_left == 47, "Return и повторный tick сохраняют общий срок раунда")
	var before: int = n.gang.revision
	n.set_paused(true)
	n._handle_action(2, "take", {"value": 1})
	n._process(500.0)
	check(n.gang.revision == before and n.gang.chips == [0,0,0], "На паузе нет действий и timeout")
	check(is_equal_approx(n._phase_time, 13.0) and n.view.game_paused, "На паузе часы стоят, view показывает паузу")
	n.set_paused(false)
	settle(n)
	check(is_equal_approx(n._phase_time, 13.0) and n.sent[1].turn_left == 47, "Resume/stamp не сбрасывает оставшиеся47 секунд")
	for peer in range(1, 4):
		n._handle_action(peer, "take", {"value": peer})
	check(n.gang.round_no == 2, "Последний take переводит в новый раунд")
	settle(n)
	check(is_equal_approx(n._phase_time, 0.0) and n.sent[1].turn_left == 60, "Новый phase/turn_no получает полные60 секунд через stamp")
	check(n._last_phase == "%s/%d" % [n.gang.phase, n.gang.turn_no], "Ключ таймера включает фазу и turn_no")
	dispose(n)

func finite_timeout() -> void:
	var n := remote()
	n.settings.turn_time = 10
	settle(n)
	n._handle_action(1, "take", {"value": 2})
	n._process(9.5)
	check(n.gang.chips == [2,0,0] and n.gang.round_no == 1, "До конечного срока нет автоподбора")
	n._process(0.5)
	check(n.gang.round_no == 2 and n.gang.history[0][0] == 2, "Timeout заполнил только пропуски и сохранил выбранный2")
	var row: Array = n.gang.history[0].duplicate()
	row.sort()
	check(row == [1,2,3] and n.gang.chips == [0,0,0], "Распределение конечного timeout уникально; новый цвет пуст")
	settle(n)
	check(n.gang.round_no == 2 and n._phase_time == 0.0 and n.sent[1].turn_left == 10, "Переход timeout не проскакивает следующий раунд, новый срок10")
	dispose(n)

func infinite_disconnect_and_reconnect() -> void:
	var n := remote()
	n.settings.turn_time = 0
	settle(n)
	n._process(61.0)
	check(n.gang.chips == [0,0,0], "При INF живые участники не заменяются обычными ботами")
	# Новая независимая сессия: отсчёт fallback проверяется от начала текущего раунда.
	dispose(n)
	n = remote()
	n.settings.turn_time = 0
	settle(n)
	var hand: Array = n.gang.hands[1].duplicate()
	n._on_peer_disconnected(2)
	check(n.seat_peers == [1,0,3] and n.disconnected.get(1) == "Друг2", "Вылет помечает исходное место нулём и сохраняет имя для возврата")
	n._process(59.9)
	check(n.gang.chips == [0,0,0], "INF fallback не срабатывает раньше60 секунд")
	n._process(0.2)
	check(n.gang.chips[1] in [1,2,3] and n.gang.chips[0] == 0 and n.gang.chips[2] == 0,
		"Через60 секунд заполняется только отключённое место, не живые участники")
	var picked: int = n.gang.chips[1]
	n._process(5.0)
	check(n.gang.chips[1] == picked and n.gang.round_no == 1, "Повтор fallback не меняет уже назначенный чип")
	n.api.sender = 7
	n._rpc_hello("Друг2")
	check(n.seat_peers == [1,7,3] and not n.disconnected.has(1), "Существующий reconnect возвращает то же место новому peer7")
	check(n.gang.hands[1] == hand and n.gang.chips[1] == picked and n.sent[7].hand == hand,
		"Reconnect сохраняет pocket/чип и доставляет правильный приватный view")
	check(not n.gang.players[1].bot and n.gang.players[1].name == "Друг2", "Reconnect восстановил имя и человеческую роль")
	n._handle_action(7, "view_seat", {"seat": 0})
	n._handle_action(7, "return", {})
	check(n.gang.chips == [0,0,0], "Вернувшийся peer действует только исходным местом1")
	# Проверка контракта роли сразу после нового отключения, без изменения остальной игры.
	n._on_peer_disconnected(7)
	print("TG NET DISCONNECT РОЛЬ: ", n.gang.players[1])
	check(not bool(n.gang.players[1].get("bot", false)) and not str(n.gang.players[1].name).contains("(бот)"),
		"The Gang: отключённый участник не объявляется обычным ботом; предусмотрен только случайный fallback")
	dispose(n)

func cleanup_and_old_limits() -> void:
	var n := net()
	n.set_bots(2)
	check(n.start_game() == "", "Подготовка: Gang перед переключением игры")
	n.send_action("view_seat", {"seat": 2})
	n.end_game()
	check(n.gang == null and n.tg_view_seat == 0 and not n.in_game and n.view.is_empty(), "End сбрасывает Gang и личное место")
	n.select_game("perudo")
	n.set_bots(1)
	check(n.start_game() == "" and n.perudo != null and n.gang == null, "После Gang запускается Перудо, приоритет _game_obj не захвачен Gang")
	check(n._game_obj() == n.perudo and n.view.game == "perudo", "View и правила следующей игры правильные")
	n.leave()
	check(n.gang == null and n.tg_view_seat == 0 and not n.in_game, "Leave не оставляет Gang активным")
	n.host_offline("the_gang")
	n.set_bots(2)
	check(n.start_game() == "", "Повторный start создаёт новую Gang")
	n._reset_host()
	check(n.gang == null and n.tg_view_seat == 0 and not n.in_game, "_reset_host убирает Gang")
	n.host_offline("perudo")
	n.set_bots(99)
	check(n.bots == 7 and n.player_total() == 8, "Старые offline-игры остались максимум8, не10")
	dispose(n)
	# Настоящие hello создают пати10: общая ёмкость пати не должна обходить предел старой игры.
	n = net()
	n.mode = "enet"
	for peer in range(2, 11):
		n.api.sender = peer
		n._rpc_hello("Друг%d" % peer)
	n.select_game("perudo")
	n.set_bots(0)
	var reported_total: int = n.player_total()
	var bot_count: int = n.bots
	var started: String = n.start_game()
	print("TG NET СТАРЫЙ ЛИМИТ: members=", n.members.size(), " bots=", bot_count,
		" total=", reported_total, " error=", started, " active=", n.in_game)
	check(bot_count >= 0, "Переход пати10 в старую игру не создаёт отрицательное число ботов")
	check(started != "" and not n.in_game, "Пати10 не запускает старую игру сверх MAX8")
	dispose(n)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("Net").set_process(false)
	direct_script = GDScript.new()
	direct_script.source_code = "extends \"res://games/king_of_12/net/net.gd\"\nvar sent: Dictionary = {}\nvar api: MultiplayerAPIExtension\nfunc _ready() -> void:\n\t# Пропускаем только Steam/экранные подписки; все проверяемые production-методы наследуются.\n\tset_process(false)\nfunc _send_view(target: int, payload: Dictionary) -> void:\n\tsent[target] = payload.duplicate(true)\n\tif target == 1:\n\t\t_apply_state(payload)\n"
	if direct_script.reload() != OK:
		await root.get_node("Sfx").request_quit(2)
		return
	for method: String in ["offline_privacy", "remote_privacy", "clocks_and_pause", "finite_timeout", "infinite_disconnect_and_reconnect", "cleanup_and_old_limits"]:
		var before := checks
		var old_errors := errors
		call(method)
		print("THE GANG NET РАЗДЕЛ ", method, ": ", checks - before, " проверок, ", errors - old_errors, " ошибок")
	print("THE GANG NET CONTRACT: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
