extends SceneTree
## Регрессия ручных бросков клеток, выбора чужой карты и немедленного финишного броска.
var checks := 0
var errors := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)
func game(seed_value: int) -> BRRules:
	var result := BRRules.new()
	result.new_game([{"name": "Первый"}, {"name": "Второй"}], seed_value)
	result._queue.clear()
	result.prompt = {}
	result.turn = 0
	result._rolled = true
	result.phase = "resolve"
	return result
func cell(kind: String) -> int:
	for index in BRBoard.size():
		if BRBoard.cell(index).t == kind:
			return index
	return -1
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for seed_value in range(1, 61):
		var b := game(seed_value)
		b.pos[0] = cell("mine")
		var coins_before := b.coins[0]
		var before := b.roll_no
		var random := RandomNumberGenerator.new()
		random.state = b.rng.state
		var expected := random.randi_range(1, 6)
		b._cell_fx(0)
		check(b.prompt.get("kind") == "card_die" and b.roll_no == before, "Шахта ждёт броска, результат не сгенерирован заранее")
		check(not b.roll(1), "Чужой игрок не бросает в шахте")
		check(b.roll(0) and b.roll_no == before + 1 and b.last_roll == [expected], "Шахта применяет один хостовый бросок")
		check((b.skip[0] == 1 if expected == 1 else b.winner == 0 if expected == 6 else b.coins[0] == coins_before + 10), "Результат шахты сохранён")
		b = game(seed_value)
		b.pos[0] = cell("luck_die")
		var from := b.pos[0]
		b._cell_fx(0)
		var total := 0
		for roll in 3:
			check(b.prompt.kind == "card_die" and b.pos[0] == from, "Кубик удачи ждёт каждый бросок отдельно")
			check(b.roll(0), "Ручной бросок кубика удачи")
			total += b.last_roll[0]
		check(b.roll_no == 3 and b.pos[0] == mini(from + total, BRBoard.finish()), "Движение на сумму только после трёх бросков")
		b = game(seed_value)
		b._duel(0, 1)
		check(b.roll_no == 0 and b.prompt.seat == 0, "Схватка сначала ждёт нападающего")
		check(not b.roll(1) and b.roll(0), "Нападающий сам бросает")
		var attack := b.last_roll[0]
		check(b.roll_no == 1 and b.prompt.seat == 1 and not b.roll(0), "Защищающийся сам бросает вторым")
		check(b.roll(1) and b.roll_no == 2, "Второй ручной бросок")
		var defend := b.last_roll[0]
		if attack + 2 != defend:
			check(b.prompt.kind == "duel_prize" and b.prompt.seat == (0 if attack + 2 > defend else 1), "Бонус нападающего и выбор победителя сохранены")
		else:
			check(b.prompt.is_empty(), "При ничьей без слона нет награды")
	for choice in 2:
		var b := game(34)
		b.shop[0] = []
		b.shop[1] = [0, 1]
		b._ask(0, "steal", ["Второй"], "Кража", {seats = [1]})
		check(b.answer(0, 0) and b.prompt.kind == "shop_pick" and b.shop[1] == [0, 1], "Выбор жертвы не забирает случайную карту")
		check(not b.answer(1, choice), "Жертва не выбирает вместо вора")
		check(b.answer(0, choice) and b.shop[0] == [choice] and b.shop[1] == [1 - choice], "Можно забрать любую из двух карт")
	for coins in [0, 5, 10]:
		var b := game(48)
		b.coins[0] = coins
		b.pos[0] = BRBoard.finish() - 2
		b._walk(2)
		check(b.turn == 0 and not b._rolled, "На финиш-сейфе бросок доступен сразу этому игроку")
		if coins >= 5:
			check(b.prompt.kind == "boost", "Сначала выбор доплаты")
			check(b.answer(0, 1) and b.roll_no == 0 and b.phase == "roll", "Доплата не бросает кубик автоматически")
			check(b.coins[0] == coins - 5, "Цена доплаты сохранена")
		else:
			check(b.phase == "roll", "Без денег сразу ручной бросок")
		check(b.roll(0) and b.roll_no == 1, "На финише можно бросить без ожидания следующего круга")
	print("БРОДИЛКА27: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
