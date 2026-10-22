extends SceneTree
## Автотесты правил «Перудо». Запуск: godot --headless --script res://tests/test_perudo.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_bid_rules()
	test_ones_rules()
	test_challenge()
	test_maputo()
	test_calza()
	test_lower_face_more_dice()
	test_bot_games()
	print("Перудо — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int = 3) -> PerudoRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := PerudoRules.new()
	r.new_game(players, 5, true, 42)
	for s in n:
		r.shake(s)
	r.turn = 0
	return r


func test_bid_rules() -> void:
	var r := make()
	check(r.phase == "bid", "после тряски — ставки")
	check(r.can_bid(1, 2), "первая ставка любая")
	check(r.place_bid(0, 3, 5), "ставка «3 пятёрки»")
	check(not r.place_bid(0, 4, 5), "не в свой ход нельзя")
	check(r.can_bid(3, 6), "3 шестёрки после 3 пятёрок")
	check(not r.can_bid(3, 4), "3 четвёрки после 3 пятёрок нельзя")
	check(r.can_bid(4, 2), "больше костей — любой номинал")
	check(not r.can_bid(2, 6), "меньше костей нельзя")
	check(not r.can_bid(16, 6), "больше, чем костей на столе, нельзя")


func test_ones_rules() -> void:
	var r := make()
	r.place_bid(0, 5, 5)
	check(r.can_bid(3, 1), "«3 единицы» после «5 пятёрок» (половина вверх)")
	check(not r.can_bid(2, 1), "«2 единицы» после «5 пятёрок» нельзя")
	r.place_bid(1, 3, 1)
	check(r.can_bid(4, 1), "единицы → больше единиц")
	check(not r.can_bid(5, 6), "с 3 единиц нельзя на 5 шестёрок (нужно ≥ 6)")
	check(r.can_bid(6, 2), "6 двоек: удвоено и выше последней «5 пятёрок»")
	var r2 := make()
	r2.place_bid(0, 6, 5)
	r2.place_bid(1, 3, 1)
	check(not r2.can_bid(6, 2), "после «6 пятёрок» — «3 единицы» нельзя «6 двоек» (пример из правил)")
	check(r2.can_bid(6, 6), "…а «6 шестёрок» можно")
	var r3 := make()
	r3.place_bid(0, 2, 1)
	check(r3.can_bid(4, 6), "«4 шестёрки» после «2 единиц» (пример из правил)")
	check(not r3.can_bid(3, 6), "«3 шестёрки» после «2 единиц» нельзя")


func test_challenge() -> void:
	var r := make()
	r.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 3, 6]]
	r.place_bid(0, 6, 2)
	check(r.challenge(1), "не верю")
	# двоек: 2+1+1 = 4, единиц: 1+0+2 = 3 → 7 ≥ 6 → проигрывает сказавший «не верю»
	check(r.reveal["count"] == 7, "подсчёт с джокерами: %d" % r.reveal["count"])
	check(r.reveal["loser"] == 1 and r.counts[1] == 4, "проиграл сказавший «не верю»")
	r.advance()
	check(r.phase == "roll" and r.starter == 1 and r.turn == 1, "новый раунд начинает проигравший")
	var r2 := make()
	r2.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 3, 6]]
	r2.place_bid(0, 4, 1)
	r2.challenge(1)
	check(r2.reveal["count"] == 3 and r2.reveal["loser"] == 0, "единицы считаются только как единицы; проиграл поставивший")


func test_maputo() -> void:
	var r := make()
	r.counts[0] = 1
	r.dice[0] = [3]
	check(r.can_maputo(0), "игрок с одной костью может объявить Мапуто")
	check(r.place_bid(0, 1, 3, true) and r.maputo, "Мапуто объявлено")
	check(not r.can_bid(2, 4), "в Мапуто номинал не меняется")
	check(r.can_bid(2, 3), "в Мапуто только больше костей того же номинала")
	r.dice = [[3], [1, 1, 3, 5, 6], [2, 2, 2, 2, 2]]
	r.place_bid(1, 2, 3)
	r.challenge(2)
	check(r.reveal["count"] == 2 and not r.reveal["wild"], "в Мапуто единицы — не джокеры")
	check(r.reveal["loser"] == 2, "ставка сыграла — проиграл сказавший «не верю»")


func test_calza() -> void:
	var r := make()
	r.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 3, 6]]
	r.counts[1] = 4
	r.dice[1] = [2, 3, 4, 4]
	r.place_bid(0, 7, 2)
	check(r.calza(1), "Калзак")
	check(r.reveal["count"] == 7 and r.reveal["loser"] == -1 and r.reveal["gained"] == 1, "ровно 7 — Калзак удался")
	check(r.counts[1] == 5, "кость вернулась (до 5)")
	check(r.starter == 1, "раунд начинает сказавший «Калзак»")
	var r2 := make()
	r2.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 3, 6]]
	r2.place_bid(0, 6, 2)
	r2.calza(1)
	check(r2.reveal["loser"] == 1 and r2.counts[1] == 4, "не ровно — кость теряет сказавший «Калзак»")
	var r3 := make()
	r3.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 3, 6]]
	r3.place_bid(0, 8, 2)
	r3.dice = [[1, 2, 2, 5, 6], [2, 3, 4, 4, 6], [1, 1, 2, 2, 6]]
	r3.calza(1)
	check(r3.counts[1] == 5 and r3.reveal["gained"] == -1 and r3.reveal["loser"] == -1, "угадал, но больше стартового числа костей не бывает")


func test_lower_face_more_dice() -> void:
	# «Можно ставить больше костей при более низком номинале»
	var r := make()
	r.place_bid(0, 4, 6)
	for face in range(2, 7):
		check(r.can_bid(5, face), "после «4 шестёрок» можно «5 × %d»" % face)
	check(not r.can_bid(4, 3), "после «4 шестёрок» нельзя «4 тройки» (то же количество — только номинал выше)")
	check(r.min_quantity(2) == 5, "минимум для двоек после «4 шестёрок» — 5 (так подставит панель)")
	check(r.place_bid(1, 5, 2), "ставка «5 двоек» принята")
	check(r.can_bid(6, 2) and r.can_bid(5, 3), "дальше: «6 двоек» или «5 троек»")
	# то же через проверку, которой пользуется панель ставки у клиента
	check(PerudoRules.check_bid({"q": 4, "face": 6, "seat": 0}, [{"q": 4, "face": 6, "seat": 0}], false, 15, 5, 2), "панель: «5 двоек» после «4 шестёрок» разрешена")
	# с единиц на более низкий номинал: удвоить и перебить последнюю обычную ставку
	var r2 := make()
	r2.place_bid(0, 6, 5)
	r2.place_bid(1, 3, 1)
	check(r2.can_bid(7, 2), "«6 пятёрок» → «3 единицы» → можно «7 двоек»")
	check(not r2.can_bid(6, 2), "…но не «6 двоек»")


func test_bot_games() -> void:
	var finished := 0
	for g in 400:
		var n := 2 + g % 7
		var players := []
		for i in n:
			players.append({"name": "Б%d" % i, "bot": true})
		var r := PerudoRules.new()
		r.new_game(players, 5, true, g + 1)
		var steps := 0
		while r.phase != "game_over" and steps < 5000:
			steps += 1
			match r.phase:
				"roll":
					for s in n:
						r.shake(s)
				"bid":
					if not PerudoBot.act(r, r.turn):
						check(false, "бот не смог сходить (партия %d)" % g)
						break
				"reveal":
					r.advance()
		if r.phase == "game_over" and r.winner >= 0 and r.total_dice() == r.counts[r.winner]:
			finished += 1
	check(finished == 400, "партии ботов доиграны: %d/400" % finished)
