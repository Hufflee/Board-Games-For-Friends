extends "res://tests/test_fs_passive_fixes.gd"
## Границы Мёртвого кота и атаки Гибельного: исчерпание, смена хода, души и независимые бонусы.

func _initialize() -> void:
	var g := make()
	g.items[0] = [FSData.item_entry(202), FSData.item_entry(223)]
	g._damage_player(0, 3)
	g._finish_responses()
	check(g.hp[0] == 2 and g.items[0][0].counters == 6, "Три урона расходуют три жетона и не снимают здоровье")
	check(g.hands[0].is_empty(), "Полностью предотвращённый урон не запускает добор")
	g.items[0][0].counters = 1
	g._damage_player(0, 2)
	g._finish_responses()
	check(g.hp[0] == 1 and g.items[0][0].counters == 0, "Один оставшийся жетон предотвращает одну из двух единиц урона")
	check(g.hands[0].size() == 1, "Остаточный урон запускает ровно одно событие")
	g.hp[0] = 2
	g._damage_player(0, 1)
	check(g.hp[0] == 1, "Пустой Мёртвый кот не предотвращает следующий урон")
	g = make()
	g.items[0] = [FSData.item_entry(202), FSData.item_entry(115)]
	g._damage_player(0, 1, {"combat": true, "value": 1})
	check(g.hp[0] == 2 and g.items[0][0].counters == 9, "Иммунитет не расходует жетоны Кота")
	g.items[0].append(FSData.item_entry(514))
	g._damage_player(0, 1)
	check(g.items[0][0].counters == 9, "Защита от небоевого урона также сохраняет жетоны")
	g = make()
	g.chars[0] = 884
	g.max_hp[0] = 1
	g.hp[0] = 1
	for pair in [[0, 1], [1, 2], [2, 2], [3, 3], [2, 2], [0, 1]]:
		g.souls[0] = int(pair[0])
		g._refresh_passive_stats()
		check(g.attack[0] == int(pair[1]), "Атака Гибельного при душах " + str(pair[0]))
		check(g.max_hp[0] == 1, "Бонус душ не меняет здоровье Гибельного")
	g.souls[0] = 3
	g._refresh_passive_stats()
	g._gain_item(0, 16)
	g._finish_responses()
	check(g.attack[0] == 4, "Атака Гибельного складывается с бонусом предмета")
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	g.phase = "effect"
	g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0})
	check(g.attack == [3, 2], "Передача предмета не переносит бонус персонажа")
	g = make()
	g.items = [[FSData.item_entry(523)], []]
	g.hands[0] = [475]
	g.phase = "turn"
	g.hp[0] = 0
	g._check_deaths()
	g._finish_responses()
	var coins_before: int = g.coins[0]
	check(g.action(0, "death", {"item": 0, "loot": 475}), "Ребро алчности уничтожено в своём штрафе")
	check(g.coins[0] == coins_before and g.hands[0] == [475], "Защита Ребра действует и при его выборе в том же штрафе")
	var eden_found := false
	for seed_value in range(1, 101):
		g = FSRules.new()
		g.new_game([{"name": "А"}, {"name": "Б"}], false, seed_value)
		if g.phase != "starting_item":
			continue
		eden_found = true
		var owner := g.actor()
		var options: Array = g.get_view(owner).starting_options
		check(options.size() == 3, "Эдему предложены три настоящих сокровища")
		check(g.get_view(1 - owner).starting_options.is_empty(), "Предложения Эдема не передаются другому игроку")
		check(not g.action(1 - owner, "choose_starting_item", {"card": options[0]}), "Другой игрок не выбирает за Эдема")
		check(not g.action(owner, "choose_starting_item", {"card": -1}), "Нельзя выбрать непредложенную карту")
		var chosen: int = options[0]
		check(g.action(owner, "choose_starting_item", {"card": chosen}), "Эдем выбрал предложенное сокровище")
		preload("res://tests/fs_test_setup.gd").finish(g)
		check(g.items[owner].any(func(item): return int(item.id) == chosen and item.eternal), "Выбранное сокровище стало вечным")
		check(g.decks.treasure.has(int(options[1])) and g.decks.treasure.has(int(options[2])), "Остальные предложения возвращены в колоду")
		check(int(options[1]) in g.decks.treasure.slice(0, 2) and int(options[2]) in g.decks.treasure.slice(0, 2), "Остальные предложения находятся под низом колоды")
		check(g.phase == "turn", "После выбора начинается обычный ход")
		break
	check(eden_found, "Проверен настоящий случай раздачи Эдема")
	g = make()
	g.chars[0] = 884
	g.max_hp[0] = 1
	g.hp[0] = 1
	g.souls = [0, 0]
	g.bonuses = [689]
	g.coins = [24, 3]
	g.bank = 73
	check(g.action(0, "effect", {"op": "coins", "amount": 1}), "Натуральное получение25-й монеты")
	check(g.souls[0] == 1 and g.get_view(0).players[0].attack == 2, "Автоматическая бонусная душа сразу меняет видимую атаку Гибельного")
	g = make()
	g.phase = "turn"
	g.hp[0] = 1
	g.items[0] = [FSData.item_entry(677), FSData.item_entry(652)]
	g.hands[0] = [475]
	g.coins = [15, 3]
	g.bank = 82
	g._damage_player(0, 1)
	g._check_deaths()
	g._finish_responses()
	check(g.phase == "death" and g.coins[0] == 15, "Штраф предшествует отложенному Пенни от смертельного урона")
	check(g.action(0, "death", {"item": 0, "loot": 475}), "Принят штраф с уничтожением Пенни")
	check(g.coins[0] == 14, "Штраф списал монету до разрешения пассива")
	g._finish_responses()
	check(g.coins[0] == 15, "Уже созданный эффект Пенни вернул монету после уничтожения источника")
	check(g.hands[0].is_empty() and not g.items[0].any(func(item): return int(item.id) == 677), "Лут и выбранный предмет действительно потеряны")
	print("PASSIVE BOUNDARIES: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
