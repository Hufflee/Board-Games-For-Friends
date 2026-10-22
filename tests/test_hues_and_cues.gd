extends SceneTree
## Автотесты «Оттенков и подсказок». Запуск: godot --headless --script res://tests/test_hues_and_cues.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_data()
	test_cues()
	test_round_flow()
	test_pass_and_three_players()
	test_game_end_and_tiebreak()
	print("Оттенки и подсказки — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int, laps: int = 0) -> HCRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := HCRules.new()
	r.new_game(players, laps, false, 7)
	return r


func test_data() -> void:
	check(HCData.BOARD.size() == 480, "480 клеток")
	check(HCData.coord(HCData.cell(10, 24)) == "K25", "координаты K25")
	check(HCData.dist(HCData.cell(10, 24), HCData.cell(11, 25)) == 1 and HCData.dist(HCData.cell(10, 24), HCData.cell(8, 24)) == 2, "расстояние")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var card := HCData.draw_card(rng)
	check(card.size() == 4 and card.all(func(c): return c >= 0 and c < 480), "карта из 4 цветов")


func test_cues() -> void:
	check(HCRules.check_cue("Море", 1, []) == "", "обычное слово")
	check(HCRules.check_cue("тёплое море", 1, []) != "", "два слова в первой подсказке")
	check(HCRules.check_cue("тёплое море", 2, []) == "", "два слова во второй")
	check(HCRules.check_cue("Красный", 1, []) != "", "красный нельзя")
	check(HCRules.check_cue("серо-голубое", 1, []) != "", "серо-голубое нельзя")
	check(HCRules.check_cue("синева", 1, []) != "", "синева нельзя")
	check(HCRules.check_cue("сердце", 1, []) == "" and HCRules.check_cue("серебро", 1, []) == "" and HCRules.check_cue("белка", 1, []) == "", "сердце, серебро, белка — можно")
	check(HCRules.check_cue("черника", 1, []) == "" and HCRules.check_cue("красота", 1, []) == "", "черника, красота — можно")
	check(HCRules.check_cue("лаванда", 1, []) == "", "абстрактные цвета можно")
	check(HCRules.check_cue("K25", 1, []) != "", "координаты нельзя")
	check(HCRules.check_cue("Море!", 1, ["море"]) != "", "повтор нельзя")


func test_round_flow() -> void:
	var r := make(4)
	var g := r.giver
	check(r.phase == "pick" and r.card.size() == 4, "ведущий тянет карту")
	check(not r.pick_color(g, 999), "только цвет с карты")
	check(not r.pick_color((g + 1) % 4, r.card[0]), "выбирает только ведущий")
	var tgt: int = HCData.cell(8, 10)
	r.card[0] = tgt
	check(r.pick_color(g, tgt) and r.phase == "cue1", "цвет выбран")
	check(r.get_view((g + 1) % 4)["target"] == -1 and r.get_view((g + 1) % 4)["card"].is_empty(), "другие не видят цвет")
	check(not r.give_cue(g, "два слова"), "первая — одно слово")
	check(r.give_cue(g, "Лимон") and r.phase == "guess1", "подсказка дана")
	check(r.order == [(g + 1) % 4, (g + 2) % 4, (g + 3) % 4], "по часовой")
	check(not r.place(g, 0), "ведущий не ставит")
	check(not r.place(r.order[1], 0), "не в свою очередь нельзя")
	check(r.place(r.order[0], tgt), "точно")
	check(not r.place(r.order[1], tgt), "клетка занята")
	check(r.place(r.order[1], HCData.cell(9, 11)), "в рамке")
	check(r.place(r.order[2], HCData.cell(0, 0)), "мимо")
	check(r.phase == "cue2", "вторая подсказка")
	check(not r.give_cue(g, "лимон"), "повтор подсказки")
	check(r.give_cue(g, "спелый лимон") and r.phase == "guess2", "вторая подсказка дана")
	check(r.order == [(g + 3) % 4, (g + 2) % 4, (g + 1) % 4], "против часовой")
	check(r.place(r.order[0], HCData.cell(6, 10)), "вплотную к рамке")
	check(r.skip(), "пропуск хода")
	check(r.place(r.order[2], HCData.cell(8, 11)), "в рамке")
	check(r.phase == "reveal", "подсчёт")
	var gn: Array = r.result["gained"]
	check(gn[(g + 1) % 4] == 3 + 2, "точно + рамка = 5")
	check(gn[(g + 2) % 4] == 2, "рамка = 2")
	check(gn[(g + 3) % 4] == 1, "мимо + вплотную = 1")
	check(gn[g] == 3, "ведущему по очку за фишку в рамке")
	r.advance()
	check(r.phase == "pick" and r.giver == (g + 1) % 4 and r.pieces.is_empty(), "следующий ведущий")


func test_pass_and_three_players() -> void:
	var r := make(3)
	var g := r.giver
	r.card[0] = 100
	r.pick_color(g, 100)
	r.give_cue(g, "закат")
	r.place(r.order[0], 100)
	r.place(r.order[1], 101)
	check(r.pass_cue(g) and r.phase == "reveal" and r.result["passed"], "пас — сразу подсчёт")
	check(r.result["gained"][g] == 4, "трое: ведущему по 2 очка")
	check(r.total_rounds == 6, "3–6 игроков — по два круга")
	check(make(7).total_rounds == 7, "7+ — по одному")


func test_game_end_and_tiebreak() -> void:
	var r := make(3, 1)
	for i in 3:
		r.target = 0
		r.phase = "reveal"
		r.advance()
	check(r.phase == "game_over" and r.winners.size() == 3, "все поровну — общая победа")
	r = make(3, 1)
	r.scores = [5, 5, 1]
	r.round_no = 3
	r.phase = "reveal"
	r.advance()
	check(r.tiebreak and r.giver == 2, "ведёт тот, кто не претендует")
	r.scores = [7, 5, 1]
	r.phase = "reveal"
	r.advance()
	check(r.phase == "game_over" and r.winners == [0], "лидер вырвался — победа")
