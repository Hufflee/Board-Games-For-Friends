## Независимые серверные границы BR27. Fixtures без UI/Net, только свои правила.
extends "res://tests/test_brodilka_batch27.gd"

func seed_faces(first: int, second: int = -1) -> int:
	for seed_value in 10000:
		var r := RandomNumberGenerator.new()
		r.seed = seed_value
		if r.randi_range(1, 6) == first and (second < 0 or r.randi_range(1, 6) == second): return seed_value
	return -1

func rejected(b: BRRules, actor: int, choice: int = -99) -> void:
	var before := b.get_view(0).duplicate(true)
	var random := b.rng.state
	var ok := b.roll(actor) if choice == -99 else b.answer(actor, choice)
	check(not ok and b.get_view(0) == before and b.rng.state == random, "Неверный actor/choice не меняет view, rollcount и RNG")

func _run() -> void:
	for helmet in [false, true]:
		var b := game(912)
		b.pos[0] = cell("mine")
		if helmet: b.shop[0].append(BRData.shop_index("helmet"))
		b.rng.seed = seed_faces(1)
		var before := b.coins[0]
		b._cell_fx(0)
		rejected(b, -1)
		rejected(b, 2)
		rejected(b, 1)
		rejected(b, 0, -1)
		rejected(b, 0, 1)
		check(b.roll(0) and b.roll_no == 1 and b.last_roll == [1], "Шахта: ровно один фактический бросок1")
		check(b.skip[0] == (0 if helmet else 1) and b.coins[0] == before + (10 if helmet else 0), "Каска заменяет пропуск на10 монет")
		check(b.stats_rolls.back().seat == 0, "Шахта сохраняет владельца броска")
	for attacker_glove in [false, true]:
		for defender_glove in [false, true]:
			for elephants in 4:
				var b := game(913)
				if attacker_glove: b.shop[0].append(BRData.shop_index("glove"))
				if defender_glove: b.shop[1].append(BRData.shop_index("glove"))
				if elephants & 1: b.shop[0].append(BRData.shop_index("elephant"))
				if elephants & 2: b.shop[1].append(BRData.shop_index("elephant"))
				b.rng.seed = seed_faces(2, 4)
				b._duel(0, 1)
				rejected(b, 1)
				check(b.roll(0) and b.prompt.seat == 1 and b.roll_no == 1, "Схватка: первый запрос только нападающему")
				rejected(b, 0)
				check(b.roll(1) and b.roll_no == 2 and b.last_roll == [4], "Схватка: ровно второй запрос защитнику")
				check(b.stats_rolls[0].seat == 0 and b.stats_rolls[1].seat == 1, "Два реальных владельца в статистике")
				var winner := -1
				if attacker_glove != defender_glove: winner = 0 if attacker_glove else 1
				elif elephants == 1: winner = 0
				elif elephants == 2: winner = 1
				check((b.prompt.is_empty() if winner < 0 else b.prompt.get("kind") == "duel_prize" and b.prompt.seat == winner), "Бонус атаки+перчатки и единственный слон правильно разрешают2/4")
				if winner >= 0: rejected(b, 1 - winner, 0)
	var luck := game(914)
	luck.pos[0] = cell("luck_die")
	luck.rng.seed = 824
	var from := luck.pos[0]
	luck._cell_fx(0)
	var sum := 0
	for i in 3:
		check(luck.prompt.seat == 0 and luck.prompt.data.left == 3 - i and luck.prompt.data.sum == sum, "Удача: сохраняется последовательный накопитель")
		rejected(luck, 1)
		rejected(luck, 0, 1)
		check(luck.roll(0) and luck.roll_no == i + 1, "Удача: каждый запрос увеличивает rollcount ровно на1")
		sum += luck.last_roll[0]
		if i < 2: check(luck.pos[0] == from, "До третьего броска движения нет")
	check(luck.pos[0] == mini(from + sum, BRBoard.finish()), "После третьего сумма применена один раз")
	for coins in [0, 4, 5, 9, 10]:
		for boost in range(1 + mini(2, coins / 5)):
			var b := game(915)
			b.pos[0] = BRBoard.finish() - 1
			b.coins[0] = coins
			b.rng.seed = seed_faces(4)
			b._walk(1)
			check(not b._rolled and b.turn == 0 and b.roll_no == 0, "Приход на финиш не расходует новый бросок")
			if coins >= 5:
				rejected(b, 1, boost)
				rejected(b, 0)
				check(b.answer(0, boost) and b.roll_no == 0 and b._finish_boost == boost and b.phase == "roll", "Boost выбор сохраняет доплату и не автороллит")
				check(b.coins[0] == coins - boost * 5, "Доплата списана ровно один раз")
			rejected(b, 1)
			check(b.roll(0) and b.roll_no == 1, "Финиш: только свой ручной бросок после boost")
			check((b.winner == 0) == (boost == 2), "Raw4 выигрывает только с boost2")
	for kind in ["steal", "burn", "duel_prize"]:
		for inventory in [0, 3]:
			for count in [1, 2]:
				var b := game(916)
				b.shop[0] = [2, 3, 4] if inventory else []
				b.shop[1] = [0, 1] if count == 2 else [0]
				var before_disc := b.disc_shop.duplicate()
				if kind == "duel_prize": b._ask(0, kind, ["Монеты", "Назад", "Карта"], "Fixture награды", {loser = 1})
				else: b._ask(0, kind, ["Жертва"], "Fixture выбора жертвы", {seats = [1]})
				rejected(b, 1, 0)
				check(b.answer(0, 2 if kind == "duel_prize" else 0), "Владелец выбирает цель/награду")
				if count == 2:
					check(b.prompt.kind == "shop_pick" and b.shop[1] == [0, 1], "Две карты: обязательный конкретный выбор до изменения инвентаря")
					rejected(b, 1, 1)
					rejected(b, 0, -1)
					rejected(b, 0, 2)
					check(b.answer(0, 1), "Выбрана именно вторая карта")
				var selected := 1 if count == 2 else 0
				check(b.shop[1] == ([0] if count == 2 else []), "У жертвы удалена ровно выбранная карта")
				check(b.shop[0].size() == inventory + (1 if kind != "burn" and inventory == 0 else 0), "Полный инвентарь не переполнен, сжигание не даёт карту")
				# Проверка сохранённой совместимости: прежде при полном инвентаре выбранная карта сбрасывалась.
				if kind == "burn" or inventory:
					check(b.disc_shop == before_disc + [selected], "Выбранная карта попала в сброс, не потерялась")
				else: check(b.shop[0] == [selected], "Одна карта сразу / конкретная выбранная карта получена")
	print("БРОДИЛКА27 LOW: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
