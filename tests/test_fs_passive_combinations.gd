extends "res://tests/test_fs_passive_fixes.gd"
## Новые проверки после исправлений: сочетания, отмена, владение, границы событий и бонусные души.

func settle(g: FSRules) -> void:
	g._finish_responses()

func _initialize() -> void:
	var g := make()
	g._gain_item(0, 16)
	g._gain_item(0, 41)
	settle(g)
	check(g.attack[0] == 3, "Два постоянных бонуса складываются")
	g.action(0, "effect", {"op": "destroy", "item": 0})
	check(g.attack[0] == 2, "Уничтожение одного источника сохраняет второй бонус")
	g._gain_item(1, 79)
	check(g.action(0, "effect", {"op": "swap_items", "target": 1, "item": 0}), "Обмен двух невечных предметов")
	check(g.attack == [1, 2] and g.max_hp == [3, 2], "Обмен переносит оба разных бонуса без остатка")
	g = make()
	g._gain_item(0, 228)
	check(g.attack[0] == 2, "Бонус при пустой руке")
	g.action(0, "effect", {"op": "loot", "amount": 1})
	check(g.attack[0] == 1, "Добор сразу снимает условный бонус пустой руки")
	g = make()
	g.items[0] = [FSData.item_entry(165)]
	g.phase = "turn"
	g._roll_passives(5, 1)
	check(g.phase == "priority" and g.stack.back().kind == "passive", "Обязательный пассив открывает окно ответов")
	var money: int = g.coins[0]
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 1}
	check(g.action(1, "effect", {"op": "cancel"}), "Способность пассива можно отменить в стеке")
	check(g.coins[0] == money, "Отменённый пассив не выдаёт монеты")
	g = make()
	g.items[0] = [FSData.item_entry(165)]
	g.phase = "turn"
	g._roll_passives(5, 1)
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 1}
	check(g.action(1, "effect", {"op": "steal", "target": 0, "item": 0}), "Источник украден после срабатывания")
	g.phase = "priority"
	g._after_stack = "turn"
	settle(g)
	check(g.coins[0] == money + 3 and g.coins[1] == 3, "Уже сработавшая способность сохраняет прежнего владельца")
	g = make()
	g.items[0] = [FSData.item_entry(115), FSData.item_entry(223)]
	g.damage_shields[0] = 1
	g._damage_player(0, 1, {"combat": true, "value": 1})
	check(g.hp[0] == 2 and g.damage_shields[0] == 1 and g.hands[0].is_empty(), "Иммунитет не тратит щит и не запускает событие урона")
	g._damage_player(0, 1)
	check(g.hp[0] == 2 and g.hands[0].is_empty(), "Полное предотвращение не запускает добор за урон")
	g._damage_player(0, 1)
	settle(g)
	check(g.hp[0] == 1 and g.hands[0].size() == 1, "Реальный урон запускает один добор")
	g = make()
	g.room = 769
	g._refresh_passive_stats()
	check(g.max_hp == [3, 3], "Комната здоровья действует на обоих игроков")
	g.room = -1
	g._refresh_passive_stats()
	check(g.max_hp == [2, 2], "Уход комнаты снимает ауру")
	g = make()
	g.monsters = [{"id": 450, "hp": 2, "dc": 4, "at": 1}]
	g.action(0, "effect", {"op": "temporary_monster_dc", "item": 0, "amount": -1})
	var lower: Dictionary = g.monsters[0]
	g.monsters = [{"id": 451, "hp": 2, "dc": 5, "at": 1, "under": lower}]
	g._end_turn()
	settle(g)
	check(g.monsters[0].under.dc == 4, "Временная защита истекает и у накрытого монстра")
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 215, "owner": 0}
	check(g.action(0, "effect", {"op": "discard_monster", "item": 0}), "Сброс верхнего монстра")
	check(g.monsters[0].id == 450, "Под сброшенным монстром открывается прежняя карта")
	g = make()
	g.items[0] = [FSData.item_entry(128)]
	g.hands = [[475], [476]]
	check(g.get_view(0).players[1].hand == [476], "Глаз Гаппи открывает чужую руку владельцу")
	check(not g.get_view(1).players[0].has("hand"), "Открытая рука не утекает обратному зрителю")
	g.items[0].clear()
	check(not g.get_view(0).players[1].has("hand"), "Уход Глаза Гаппи закрывает руку в новом состоянии")
	g = make()
	g.bonuses = [693]
	for i in 5:
		g._gain_item(0, 79)
	g.phase = "turn"
	check(not g.action(0, "claim", {"card": 693, "target": 1}), "Пять сокровищ ещё не дают Душу гордыни")
	g._gain_item(0, 79)
	check(g.action(0, "claim", {"card": 693, "target": 1}), "После шестого сокровища активный игрок выбирает получателя")
	check(g.souls == [0, 1], "Душу получает выбранный игрок")
	check(not g.action(0, "claim", {"card": 693, "target": 0}), "Бонусная душа не получается второй раз")
	g = make()
	g.bonuses = [694]
	g.souls = [2, 0]
	g.phase = "turn"
	check(not g.action(0, "claim", {"card": 694, "target": 0}), "Лидер не может забрать Душу зависти себе")
	check(g.action(0, "claim", {"card": 694, "target": 1}), "Душа зависти достаётся отстающему")
	g = make()
	g.bonuses = [696]
	g.monsters = [{"id": 450, "hp": 1, "dc": 4, "at": 1}]
	g.stack = [{"kind": "monster_death", "card": 450, "slot": 0, "owner": 0}]
	g._resolve_top()
	check(g.bonus_progress.monsters == 0, "Спасённый до разрешения монстр не считается погибшим")
	g = make()
	g.items[0] = [FSData.item_entry(654)]
	g.hp[1] = 1
	g.stack = [{"kind": "death", "owner": 1}]
	g._resolve_top()
	check(g.bonus_progress.deaths == 0 and g.hands[0].is_empty(), "Спасённый игрок не запускает награды за смерть")
	g = make()
	g.items = [[FSData.item_entry(137)], [FSData.item_entry(137)]]
	g.phase = "turn"
	g._gain_coins(0, 1)
	settle(g)
	check(g.phase == "priority" and not g.stack.is_empty(), "Цепочка двух Магнитов ограничена по работе за один вызов и оставляет окно ответов")
	check(g.bank + g.coins[0] + g.coins[1] == 100, "Цепочка передачи не создаёт и не теряет монеты")
	g = make()
	g.items[0] = [FSData.item_entry(180), FSData.item_entry(523), FSData.item_entry(76)]
	g.items[0][0].counters = 2
	g.resolving = {"kind": "item", "card": 180, "owner": 0}
	check(g.action(0, "effect", {"op": "counter", "item": 0, "amount": -1}), "Автоматический набор жетонов не запрещает оплату жетоном")
	check(g.items[0][0].counters == 1, "Стоимость жетоном списывается ровно один раз")
	g.coins[0] = 3
	check(g.action(0, "effect", {"op": "pay_coins", "amount": 3}), "Явная оплата работает с Ребром алчности")
	check(g.coins[0] == 1, "Пенни на нитке уменьшает цену способности на одну монету")
	g = FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.items = [[FSData.item_entry(128)], [], []]
	g.hands = [[475], [476], [477]]
	check(g.get_view(2).players[1].hand == [476], "Открытая Глазом рука видна и третьему игроку")
	check(not g.get_view(2).players[0].has("hand"), "Рука самого владельца Глаза остаётся закрытой")
	g = make()
	g.resolving = {"kind": "loot", "card": 515, "owner": 0}
	g.stack = [{"kind": "resume_effect", "owner": 0, "previous": {"effect": g.resolving, "resume": "turn", "peek": {}}}]
	g.discards.loot.erase(515)
	g._cancel_unresolved()
	check(g.discards.loot.count(515) == 1, "Отмена незавершённого хода сбрасывает лут из отложенного возврата ровно один раз")
	g = make()
	g.peek = {"owner": 0, "deck": "loot", "cards": [515]}
	g.stack = [{"kind": "resume_effect", "owner": 0, "previous": {"effect": g.resolving, "resume": "turn", "peek": g.peek}}]
	check(g.get_view(1).stack.is_empty() and g.get_view(1).peek.is_empty(), "Приватный просмотр не утекает через служебный маркер стека")
	for bonus_id in [692, 696]:
		g = make()
		g.items = [[], []]
		g.bonuses = [bonus_id]
		for event_number in 6:
			g.resolving = {}
			g.phase = "priority"
			if bonus_id == 692:
				g.hp[1] = 0
				g.stack = [{"kind": "death", "owner": 1}]
			else:
				g.monsters = [{"id": 450, "hp": 0, "dc": 4, "at": 1}]
				g.stack = [{"kind": "monster_death", "card": 450, "slot": 0, "owner": 0}]
			g._resolve_top()
		g.phase = "turn"
		g.resolving = {}
		check(g.action(0, "claim", {"card": bonus_id, "target": 0}), "Шесть подтверждённых событий открывают бонусную душу " + str(bonus_id))
	g = make()
	g.items = [[FSData.item_entry(79), FSData.item_entry(79), FSData.item_entry(79), FSData.item_entry(79)], []]
	g.bonuses = [695]
	g.phase = "turn"
	check(not g.action(0, "claim", {"card": 695, "target": 0}), "Душа лени не достаётся лидеру по предметам")
	check(g.action(0, "claim", {"card": 695, "target": 1}), "Четыре предмета открывают Душу лени игроку с минимумом предметов")
	print("PASSIVE COMBINATIONS: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
