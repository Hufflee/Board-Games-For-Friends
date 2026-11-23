extends SceneTree
## Два процесса ENet: открытая атака Томоэ, защита сестры и общий котёл.
## UM_ROLE=host/client, UM_PORT одинаковый; действия проходят через Net.send_action.

const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
var net: Node
var checks := 0
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	net = root.get_node("Net")
	var role := OS.get_environment("UM_ROLE")
	var port := int(OS.get_environment("UM_PORT"))
	net.my_name = "Проверка " + role
	if role == "host": await host(port)
	else: await client(port)
	net.leave()
	await process_frame
	print("Unmatched, самураи и сёстры ENet %s: %d проверок, %d ошибок." % [role, checks, errors])
	quit(int(errors > 0))


func host(port: int) -> void:
	if not check(net.host_enet(port, "unmatched") == OK, "Хост открыл порт"): return
	if not check(await wait_for(func() -> bool: return net.members.size() == 2), "Клиент подключился"): return
	net.set_setting("um_arena", "marmoreal")
	net.set_setting("um_hero_mode", "free")
	net.set_setting("um_heroes", ["tomoe", "witches"])
	if not check(net.start_game().is_empty(), "Партия началась"): return
	if not check(await wait_for(func() -> bool: return net.unmatched.game.pending().is_empty()), "Обе сестры расставлены через сеть"): return
	var game: RefCounted = net.unmatched.game
	game.fighters[0][0].space = 13
	game.fighters[1][0].space = 7
	give_card(game, 0, 12)
	give_card(game, 1, 29)
	net.send_action("attack", {"fighter": 0, "target": Vector2i(1, 0), "key": "0:12"})
	if not check(await wait_for(func() -> bool: return net.view.get("combat", {}).get("pending_reveal", false)), "Атака открыта до выбора защиты"): return
	var spectator: Dictionary = net.unmatched.get_view(-1)
	check(spectator.combat.attack.key == "0:12" and spectator.combat.get("defense", {}).is_empty(), "Зритель видит открытую атаку без защиты")
	check(spectator.hand.cards.is_empty() and spectator.effect.is_empty(), "Зрителю не выдана чужая рука")
	if not check(await wait_for(func() -> bool: return finished(net.view)), "Бой и конец хода разрешились"): return
	check(game.fighters[0][0].health == 9 and game.fighters[1][0].health == 1, "Сестра отразила полученные 5 единиц урона")
	check(net.unmatched.rules.seat == 1, "После последнего боя Томоэ ход завершён")
	await create_timer(0.5).timeout


func client(port: int) -> void:
	if not check(net.join_enet("127.0.0.1", port) == OK, "Подключение началось"): return
	for index in 2:
		if not check(await wait_for(func() -> bool: return not net.view.get("setup", {}).is_empty() and int(net.view.setup.get("fighter", -1)) == index + 1), "Получена расстановка сестры"): return
		var request: Dictionary = net.view.setup
		net.send_action("place", {"cell": request.cells[0]})
	if not check(await wait_for(func() -> bool: return not net.view.get("hand", {}).get("choice", {}).is_empty()), "Получен выбор защиты"): return
	var hand: Dictionary = net.view.hand
	check(net.view.combat.attack.get("key") == "0:12" and net.view.combat.get("pending_reveal", false), "Клиент видит атаку 7 до выбора защиты")
	check("1:29" in hand.choice.allowed and hand.hand == 1, "Клиент выбирает только свою защиту")
	net.send_action("combat", {"request": hand.choice.id, "hand": 1, "cards": ["1:29"]})
	if not check(await wait_for(func() -> bool: return finished(net.view)), "Клиент получил итог боя и котёл"): return
	check(net.view.piles[1].discard.is_empty() and net.view.piles[1].special.size() == 2, "Защита лежит в котле рядом с памяткой рецептов")
	check(net.view.piles[1].special[1].key == "1:29", "Публичная карта котла совпадает у клиента")


func give_card(game: RefCounted, place: int, number: int) -> void:
	var key: String = Catalog.deck_for(game.heroes[place], place)[number - 1].key
	if game.hands[place].any(func(card: Dictionary) -> bool: return card.key == key): return
	for index in game.decks[place].size():
		if game.decks[place][index].key == key:
			var card: Dictionary = game.decks[place][index]
			game.decks[place][index] = game.hands[place][0]
			game.hands[place][0] = card
			return


func finished(view: Dictionary) -> bool:
	return view.get("combat", {}).is_empty() and not view.get("combat_outcome", {}).is_empty() and view.get("active", -1) == 1


func wait_for(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return false


func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
	return ok
