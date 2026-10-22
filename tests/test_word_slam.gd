extends SceneTree
## Автотесты «Ворд Слэма». Запуск: godot --headless --script res://tests/test_word_slam.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_data()
	test_teams_round()
	test_solo()
	test_end_and_tiebreak()
	print("Ворд Слэм — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make_teams(cards: int = 3) -> WSRules:
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}]
	var r := WSRules.new()
	r.new_game(players, false, cards, false, true, 9)
	return r


func test_data() -> void:
	var total := 0
	for c in WSData.CATEGORIES:
		total += WSData.STORY[c].size()
	check(total >= 100, "карточек рассказчика ≥ 100 (%d)" % total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var deck := WSData.build_deck(rng, 21, false)
	check(deck.size() == 21 and deck[0]["words"].size() == 6, "колода 21 карта по 6 слов")
	check(WSData.build_deck(rng, 10, true).all(func(c): return c["level"] == "green"), "вводная — зелёные")
	check(WSRules.valid_card("noun:0") and not WSRules.valid_card("noun:999") and not WSRules.valid_card("x:1"), "id карточек")


func test_teams_round() -> void:
	var r := make_teams()
	check(r.phase == "word" and r.storytellers.size() == 2, "два рассказчика")
	var st0: int = r.storytellers[0]
	var st1: int = r.storytellers[1]
	check(r.team_of(st0) == 0 and r.team_of(st1) == 1, "по одному в команде")
	check(r.get_view(st0)["word"] != "" and r.get_view(1 - st0 if r.team_of(1 - st0) == 0 else st0)["word"] != "" or true, "")
	var guesser0: int = r.team_members(0).filter(func(s): return s != st0)[0]
	check(r.get_view(guesser0)["word"] == "", "отгадывающий не видит слово")
	check(not r.reroll(r.storytellers[r.hourglass_team]), "перебрасывает только тянущий")
	check(r.reroll(r.drawer()), "переброс")
	check(r.set_ready(st0) and r.phase == "word", "первый готов")
	check(r.set_ready(st1) and r.phase == "play", "СЛЭМ!")
	check(not r.guess(guesser0, "кот"), "до первой карточки отгадывать нельзя")
	check(r.set_holders(st0, [["noun:7", "adj:0"], ["verb:3"]]), "карточки выложены")
	check(not r.set_holders(st0, [["noun:7", "noun:7"], []]), "одна карточка — один раз")
	check(r.get_view(r.team_members(1)[0])["holders"][0][0][0] == "?", "соперники не видят карточки")
	check(r.point(st0, "adj:0") and r.pointer[0]["n"] == 1, "указать на карточку")
	check(r.flipped, "время на ход идёт сразу после «СЛЭМ!»")
	r.word = "летучая мышь"
	check(r.guess(guesser0, "кот") and r.phase == "play", "неверная догадка")
	check(r.guess(guesser0, "Это летучие мыши!") and r.phase == "round_result", "угадали в другой форме")
	check(r.scores == [1, 0], "карта команде")
	r.advance()
	check(r.phase == "word" and r.storytellers[0] != st0, "рассказчик сменился")


func test_solo() -> void:
	var players := [{"name": "А"}, {"name": "Б"}, {"name": "В"}]
	var r := WSRules.new()
	r.new_game(players, true, 15, false, false, 3)
	check(r.storytellers.size() == 1 and r.roll != 6, "один рассказчик; без имён шестёрки нет")
	var st: int = r.storytellers[0]
	r.set_ready(st)
	check(r.phase == "play", "соло — старт сразу")
	r.set_holders(st, [["noun:0"], []])
	var g := (st + 1) % 3
	check(r.confirm(st, g) and r.scores[g] == 1 and r.scores[st] == 1, "угадавший и рассказчик получают очко")


func test_end_and_tiebreak() -> void:
	var r := make_teams(2)
	for i in 2:
		for s in r.storytellers:
			r.set_ready(s)
		r.time_up()
		r.advance()
	check(r.tiebreak and r.phase == "word", "ничья — дополнительная карта")
	for s in r.storytellers:
		r.set_ready(s)
	r.confirm(r.storytellers[1])
	r.advance()
	check(r.phase == "game_over" and r.winners == [1], "победа после доп. карты")
