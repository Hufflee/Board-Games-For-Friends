extends "res://tests/test_fs_passive_fixes.gd"
## Реальные раздачи Эдема с входными эффектами: завершение подготовки, приватность и повтор партии.

func _initialize() -> void:
	var found := {}
	var members: Array = []
	for name in ["А", "Б", "В", "Г", "Д", "Е", "Ж", "З"]:
		members.append({"name": name})
	# Найденные реальные DLC-раздачи восьми игроков; состав колод не подменяется.
	for seed_value in [131, 138, 148]:
		var g := FSRules.new()
		g.new_game(members, true, seed_value)
		if g.phase != "starting_item":
			continue
		var owner := g.actor()
		var options: Array = g.get_view(owner).starting_options
		for id: int in [16, 69, 77]:
			if found.has(id) or not options.has(id):
				continue
			found[id] = seed_value
			var money: int = g.coins[owner]
			var hand_size: int = g.hands[owner].size()
			check(g.action(owner, "choose_starting_item", {"card": id}), "Выбрана настоящая входная карта Эдема " + str(id))
			check(g.phase == "priority" and g.get_view(owner).starting_pending, "Входной эффект ожидает завершения подготовки")
			check(not g.action(g.current, "end"), "Обычный ход не пропускает входной эффект")
			check(not g.action((g.current + 1) % g.players.size(), "finish_start"), "Другой игрок не завершает подготовку")
			check(g.get_view((owner + 1) % g.players.size()).starting_options.is_empty(), "Скрытые предложения не появляются у соперника после выбора")
			check(g.action(g.current, "finish_start"), "Активный игрок разрешает входной эффект")
			check(g.phase == "turn" and not g.get_view(owner).starting_pending, "После входного эффекта начинается первый ход")
			check(g.coins[owner] == money + (14 if id == 69 else (9 if id == 77 else 0)), "Входные монеты выданы один раз")
			# Первый ход дополнительно берёт одну карту, если Эдем активный.
			check(g.hands[owner].size() == hand_size + (1 if id == 16 else 0) + (1 if owner == g.current else 0), "Входной добор отделён от добора первого хода")
			check(not g.action(g.current, "finish_start"), "Повторное завершение не повторяет награду")
			check(g.items[owner].size() == 1 and g.items[owner][0].eternal, "Стартовое сокровище одно и вечное")
			g.new_game(members, true, seed_value)
			check(g.phase == "starting_item" and g.items[owner].is_empty() and g.coins[owner] == 3, "Новая партия очищает прежний выбор и его бонусы")
			break
		if found.size() == 3:
			break
	check(found.size() == 3, "Найдены реальные раздачи всех трёх входных эффектов")
	print("STARTING COMBINATIONS: ", checks, " проверок, ", errors, " ошибок; seed=", found)
	quit(1 if errors else 0)

