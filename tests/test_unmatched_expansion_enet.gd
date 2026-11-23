extends SceneTree
## Два процесса ENet для проверки открытой защиты «Элементарно» и приватного прогноза.
## Запуск с UM_ROLE=host/client и одним UM_PORT. Проверка работает через Net.send_action.

const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")

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
	elif role == "client":
		await _client(port)
	else:
		_check(false, "Укажите UM_ROLE=host или UM_ROLE=client")
	net.leave()
	await process_frame
	print("Unmatched, новые герои ENet %s: %d проверок, %d ошибок." % [role, checks, failures])
	quit(int(failures > 0))


func _host(port: int) -> void:
	if not _check(net.host_enet(port, "unmatched") == OK, "Хост открыл порт"):
		return
	if not _check(await _wait(func() -> bool: return net.members.size() == 2), "Клиент подключился к хосту"):
		return
	net.set_setting("um_arena", "marmoreal")
	net.set_setting("um_hero_mode", "free")
	net.set_setting("um_heroes", ["genie", "sherlock"])
	if not _check(net.start_game().is_empty(), "Партия Джинна против Холмса началась"):
		return
	if not _check(await _wait(func() -> bool: return not net.view.get("effect", {}).is_empty()), "После расстановки Ватсона предложена способность Джинна"):
		return
	var initial: Dictionary = net.view.effect
	net.send_action("effect", {"request": initial.id, "answer": null})
	var game: RefCounted = net.unmatched.game
	_check(game.fighters[1][1].space >= 0, "Хост получил сетевое размещение Ватсона")
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	if not _check(_give_card(game, 0, 5) and _give_card(game, 1, 22), "Карты сценария в соответствующих руках"):
		return
	net.send_action("attack", {"fighter": 0, "target": Vector2i(1, 0), "key": "0:05"})
	if not _check(await _wait(func() -> bool: return net.view.get("combat", {}).get("defense", {}).get("key") == "1:22"),
			"Хост получил открытую защиту до прогноза"):
		return
	for view: Dictionary in [net.view, net.unmatched.get_view(-1)]:
		_check(view.combat.get("defense", {}).get("key") == "1:22" and view.combat.attack == {"sealed": true}
			and view.effect.is_empty(), "Атакующий и зритель видят защиту без атаки или запроса числа")
	if not _check(await _wait(func() -> bool: return _finished_view(net.view)), "Хост закончил боевой обмен"):
		return
	var combat: Dictionary = net.unmatched.rules.last_combat
	_check(combat.get("attack_canceled", false) and combat.get("damage", -1) == 0,
		"Угаданная атака отменена, боевой урон равен нулю")
	await create_timer(0.5).timeout


func _client(port: int) -> void:
	if not _check(net.join_enet("127.0.0.1", port) == OK, "Клиент начал подключение"):
		return
	if not _check(await _wait(func() -> bool: return not net.view.get("setup", {}).is_empty()), "Клиент получил расстановку Ватсона"):
		return
	var placement: Dictionary = net.view.setup
	if not _check(placement.get("fighter") == 1 and not placement.cells.is_empty(), "Запрошена свободная клетка для Ватсона"):
		return
	net.send_action("place", {"cell": placement.cells[0]})
	if not _check(await _wait(func() -> bool: return not net.view.get("hand", {}).get("choice", {}).is_empty()),
			"Клиент получил выбор карты защиты"):
		return
	var hand: Dictionary = net.view.hand
	_check(hand.hand == 1 and "1:22" in hand.choice.allowed and net.view.combat.attack == {"sealed": true},
		"Холмсу доступна своя защита и скрыта выбранная атака")
	net.send_action("combat", {"request": hand.choice.id, "hand": 1, "cards": ["1:22"]})
	if not _check(await _wait(func() -> bool: return not net.view.get("effect", {}).is_empty()), "Клиент получил приватный запрос числа"):
		return
	var request: Dictionary = net.view.effect
	_check(net.view.combat.attack == {"sealed": true} and net.view.combat.get("defense", {}).get("key") == "1:22"
		and 1 in request.options, "До ответа Элементарно открыта, атака закрыта, число 1 доступно")
	await create_timer(0.3).timeout
	net.send_action("effect", {"request": request.id, "answer": 1})
	if not _check(await _wait(func() -> bool: return net.view.get("combat", {}).get("attack", {}).get("key") == "0:05"),
			"После ответа клиент получил раскрытую атаку Джинна"):
		return
	_check(await _wait(func() -> bool: return _finished_view(net.view)), "Клиент получил оба сброса и итог боя без урона")


func _give_card(game: RefCounted, place: int, number: int) -> bool:
	var key: String = Catalog.deck_for(game.heroes[place], place)[number - 1].key
	var hand: Array = game.hands[place]
	var deck: Array = game.decks[place]
	if hand.any(func(card: Dictionary) -> bool: return card.key == key):
		return true
	for index in deck.size():
		if deck[index].key == key:
			var card: Dictionary = deck[index]
			deck[index] = hand[0]
			hand[0] = card
			return true
	return false


func _finished_view(view: Dictionary) -> bool:
	if not view.get("combat", {}).is_empty() or view.get("piles", []).size() != 2:
		return false
	var attack_discard: Array = view.piles[0].discard
	var defense_discard: Array = view.piles[1].discard
	if attack_discard.size() != 1 or defense_discard.size() != 1:
		return false
	var outcome: Dictionary = view.get("combat_outcome", {})
	var heroes: Array = view.get("fighters", []).filter(func(figure: Dictionary) -> bool: return figure.hero)
	return attack_discard[0].key == "0:05" and defense_discard[0].key == "1:22" and outcome.has("losses") and outcome.losses.is_empty() \
		and heroes.size() == 2 and heroes.all(func(hero: Dictionary) -> bool: return hero.hp == 16)


func _wait(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await process_frame
	return false


func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok
