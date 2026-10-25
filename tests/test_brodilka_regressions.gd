extends SceneTree
## Телепорты и ручные броски по картам «Хорошо/Плохо».
var checks := 0
var fails := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		push_error(text)
func _initialize() -> void:
	_run.call_deferred()
func make(seed_value: int) -> BRRules:
	var game := BRRules.new()
	game.new_game([{"name": "Первый"}, {"name": "Второй"}], seed_value)
	game.prompt = {}
	game._queue.clear()
	game._rolled = true
	return game
func _run() -> void:
	for cell in BRBoard.size():
		if str(BRBoard.cell(cell).t).begins_with("tele_"):
			var game := make(45)
			game.pos[0] = cell
			game._cell_fx(0)
			check(game.pos[0] == BRBoard.tele_pair(cell) and game.pos[0] != cell, "Телепорт переносит на парную клетку")
			check(game.teleport["entry"] == cell and game.teleport["exit"] == game.pos[0], "Стол получает обе точки перехода")
			check(game.get_view(0)["teleport"] == game.teleport, "Переход передаётся всем игрокам")
	for cell in BRBoard.size():
		if str(BRBoard.cell(cell).t).begins_with("tele_"):
			var pocket := make(19)
			pocket.pos[0] = maxi(0, cell - 1)
			pocket._teleport(0, cell)
			check(pocket.teleport.entry == cell, "Карманный телепорт показывает настоящий вход в портал")
	for card in BRData.GOODBAD.size():
		for good in [true, false]:
			var side: Dictionary = BRData.GOODBAD[card].good if good else BRData.GOODBAD[card].bad
			if not side.fx in ["die_coins_or_move", "die_lose_or_back", "die_back"]:
				continue
			for seed_value in range(1, 31):
				var game := make(seed_value)
				game.pos[0] = 50
				game.coins[0] = 30
				var before := game.roll_no
				game._gb_fx(0, card, good)
				check(game.prompt.get("kind") == "card_die", "Карта ждёт ручного броска")
				check(game.pos[0] == 50 and game.coins[0] == 30 and game.roll_no == before, "До броска эффект не рассчитывается")
				check(not game.roll(1), "Чужой игрок не бросает кубик карты")
				check(game.roll(0), "Игрок бросает кубик карты")
				var die := game.last_roll[0]
				check(game.roll_no == before + 1, "Результат броска передаётся для анимации")
				match str(side.fx):
					"die_coins_or_move":
						check(game.coins[0] == (40 if die <= 3 else 30) and game.pos[0] == (50 if die <= 3 else 55), "Хорошо: 10 монет или пять клеток")
					"die_lose_or_back":
						check(game.coins[0] == (25 if die <= 3 else 30) and game.pos[0] == (50 if die <= 3 else 40), "Плохо: пять монет или десять клеток назад")
					"die_back": check(game.pos[0] == 50 - die, "Плохо: назад на выпавшее число")
	print("Бродилка: регрессии — %d проверок, ошибок: %d" % [checks, fails])
	quit(1 if fails else 0)
