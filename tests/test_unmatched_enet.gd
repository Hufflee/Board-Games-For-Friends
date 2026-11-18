extends SceneTree
## Два процесса ENet. Переменные UM_ROLE=host/client и UM_PORT одинаков для обоих.

const Match := preload("res://games/unmatched/logic/um_match.gd")

var net: Node
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	net = root.get_node("Net")
	var role := OS.get_environment("UM_ROLE")
	var port := int(OS.get_environment("UM_PORT"))
	net.my_name = "Проверка " + role
	if role == "host":
		await _host(port)
	else:
		await _client(port)
	net.leave()
	await process_frame
	print("Unmatched ENet %s: %d проверок, %d ошибок." % [role, checks, failures])
	quit(int(failures > 0))


func _host(port: int) -> void:
	if not check(net.host_enet(port, "unmatched") == OK, "Хост открыл локальный порт"):
		return
	if not check(await _wait(func() -> bool: return net.members.size() == 2), "Клиент подключился"):
		return
	net.set_bots(1)
	net.set_unmatched_double_player(0)
	if not check(await _wait(func() -> bool: return net.settings.get("um_double_player", -1) == 1), "Клиент выбрал управление двумя героями"):
		return
	if not check(await _wait(func() -> bool:
		return net.settings.get("um_heroes", []).size() == 4 and net.settings.um_heroes[3] == "robin_hood"), "Клиент изменил своего второго героя"):
		return
	check(Match.controllers_for(3, net.settings.um_double_player) == PackedInt32Array([0, 1, 2, 1]),
		"Оба героя удалённого участника в одной команде")
	net.set_bots(0)
	net.set_setting("um_heroes", ["bloody_mary", "sun_wukong"])
	net.set_setting("um_arena", "sarpedon")
	if not check(await _wait(func() -> bool:
		return net.settings.get("um_heroes", []) == ["bloody_mary", "sinbad"]), "Клиент сменил своего героя в лобби"):
		return
	if not check(await _wait(func() -> bool:
		return net.settings.get("um_heroes", []) == ["bloody_mary", "sun_wukong"]), "Смена чужого героя отклонена"):
		return
	if not check(net.start_game().is_empty(), "Хост запустил партию"):
		return
	var game: RefCounted = net.unmatched.game
	game.fighters[0][0].space = 32
	game.fighters[1][0].space = 33
	var hand: Array = game.hands[0]
	var deck: Array = game.decks[0]
	for index in deck.size():
		if deck[index].definition == "bloody_mary:05":
			var card: Dictionary = deck[index]
			deck[index] = hand[0]
			hand[0] = card
			break
	net.send_action("attack", {"fighter": 0, "target": Vector2i(1, 0)})
	var choice: Dictionary = net.view.hand.choice
	if not check(not choice.is_empty() and not choice.allowed.is_empty(), "Хост получает выбор атаки"):
		return
	net.send_action("combat", {"request": choice.id, "hand": 0, "cards": [choice.allowed[0]]})
	if not check(await _wait(func() -> bool: return net.view.combat.get("attack", {}).has("face")), "Хост получил ответ удалённой защиты"):
		return
	check(await _wait(func() -> bool: return net.view.combat.is_empty()), "Хост разрешил атаку после показа")
	check(net.view.piles[0].discard.size() == 1 and net.view.piles[1].discard.is_empty(), "Итог боя разослан")
	await create_timer(0.2).timeout


func _client(port: int) -> void:
	if not check(net.join_enet("127.0.0.1", port) == OK, "Клиент начал подключение"):
		return
	if not check(await _wait(func() -> bool:
		return net.lobby_view.get("settings", {}).get("um_double_player", -1) == 0), "Клиент увидел выбор участника за двоих"):
		return
	net.set_unmatched_double_player(1)
	if not check(await _wait(func() -> bool:
		return net.lobby_view.get("settings", {}).get("um_double_player", -1) == 1), "Выбор клиента подтверждён хостом"):
		return
	net.set_unmatched_hero(3, "robin_hood")
	if not check(await _wait(func() -> bool:
		return net.lobby_view.get("settings", {}).get("um_heroes", []) == ["bloody_mary", "sun_wukong"]), "Клиент получил настройки персонажей"):
		return
	net.set_unmatched_hero(0, "achilles")
	net.set_unmatched_hero(1, "sinbad")
	if not check(await _wait(func() -> bool:
		return net.lobby_view.get("settings", {}).get("um_heroes", []) == ["bloody_mary", "sinbad"]), "Подтверждён только собственный выбор"):
		return
	net.set_unmatched_hero(1, "sun_wukong")
	if not check(await _wait(func() -> bool:
		return net.view.get("game") == "unmatched" and not net.view.hand.choice.is_empty()), "Клиент получил свой выбор защиты"):
		return
	var hand: Dictionary = net.view.hand
	check(hand.owned == [1] and hand.cards.size() == 5, "Клиент видит одну собственную руку")
	check(net.view.combat.attack == {"sealed": true} and net.view.piles[0].deck_count == 25, "Приватная атака скрыта, счётчик соперника открыт")
	net.send_action("combat", {"request": hand.choice.id, "hand": 1, "cards": []})
	check(await _wait(func() -> bool: return net.view.combat.get("attack", {}).has("face")), "Клиент получил совместное раскрытие")
	check(await _wait(func() -> bool: return net.view.piles[0].discard.size() == 1), "Клиент получил обновлённый открытый сброс")


func _wait(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await process_frame
	return false


func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok
