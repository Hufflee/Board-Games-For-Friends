extends SceneTree
## Автотесты «Опасных слов». Запуск: godot --headless --script res://tests/test_dangerous_words.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_setup()
	test_traps_and_turns()
	test_monster_moves_and_curse_push()
	test_monster_fight()
	test_horror_and_defuse()
	test_guess_match()
	test_eight_rounds()
	print("Опасные слова — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(monster: String = "troll", curses: bool = false) -> DWRules:
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}]
	var r := DWRules.new()
	r.new_game(players, [3, 4, 5, 6, 7], monster, false, 5, curses)
	return r


func fill(r: DWRules) -> void:
	for t in 2:
		var lines := []
		for i in r.trap_lines(t):
			lines.append("слово%d" % i)
		check(r.set_traps(t, lines), "ловушки записаны")
		check(r.set_ready(t, true), "команда готова")


## Играет ход текущей команды: ok — отгадали, иначе ловушка.
func play_turn(r: DWRules, ok: bool) -> void:
	check(r.start_timer(), "время пошло")
	var t := r.turn_team
	if ok:
		check(r.guessed(r.explainer(t)), "отгадали")
	else:
		check(r.trap_hit(1 - t, 0), "ловушка")
	r.advance()


func test_setup() -> void:
	var r := make("troll", true)
	check(r.phase == "traps" and r.pos == [0, 0] and r.monster_pos == 4, "старт: обе в первой комнате, монстр в последней")
	check(r.curses.has(1) and r.curses.has(3), "проклятия у второй комнаты и перед монстром")
	check(r.trap_lines(0) == 3, "в комнате 3 — 3 ловушки")
	check(r.secret[0] != "" and r.secret[1] != "", "секретные слова выданы")
	var v := r.get_view(0)
	check(v["secret"][1] != "" and v["secret"][0] == "", "команда видит слово соперника, но не своё")


func test_traps_and_turns() -> void:
	var r := make()
	check(not r.set_ready(0, true), "без ловушек готовым не стать")
	fill(r)
	check(r.phase == "turn_ready" and r.turn_team == 0, "равенство: первой ходит команда 0")
	check(not r.guessed(r.explainer(1)), "«Отгадали» жмёт только объясняющий текущей команды")
	play_turn(r, true)
	check(r.pos[0] == 1 and r.turn_team == 1, "команда 0 прошла дальше, ход команды 1")
	play_turn(r, false)
	check(r.phase == "round_result" and r.monster_pos == 4, "одна прошла — монстр стоит")
	r.advance()
	check(r.phase == "traps" and r.trap_lines(1) == 4 and r.trap_lines(0) == 3, "ловушек по комнате соперника")
	fill(r)
	check(r.order == [1, 0], "отстающая команда ходит первой")


func test_monster_moves_and_curse_push() -> void:
	var r := make("troll", true)
	var c3: String = r.curses[3]
	fill(r)
	play_turn(r, false)
	play_turn(r, false)
	check(r.monster_pos == 3, "обе провалились — монстр ближе")
	check(r.curses.has(2) and r.curses[2] == c3 and not r.curses.has(3), "проклятие сдвинулось вместе с монстром")


func test_monster_fight() -> void:
	var r := make("dragon")
	r.pos = [3, 0]
	r.advance()  # ничего: фаза traps
	r._start_round()
	r.pos = [4, 0]
	r._start_round()
	check(r.fighting[0] and not r.fighting[1], "команда 0 в комнате монстра — сражается")
	check(r.max_guesses(0) == 3, "Дракон: 3 догадки")
	fill(r)
	check(r.order == [1, 0], "отстающая ходит первой, бой — вторым")
	play_turn(r, false)
	check(r.start_timer(), "бой начался")
	for i in 3:
		r.wrong_guess(1)
	check(r.phase == "turn_result" and not r.turn_log[-1]["ok"], "3 неверные догадки — провал")
	r.advance()
	check(r.phase == "round_result" and r.monster_pos == 4, "монстр больше не ходит, бой продолжится")
	r.advance()
	fill(r)
	play_turn(r, false)
	check(r.start_timer(), "второй бой")
	r.guessed(r.explainer(0))
	r.advance()
	check(r.phase == "game_over" and r.winners == [0], "победа над монстром")


func test_horror_and_defuse() -> void:
	var r := make()
	r.curses = {0: "horror"}
	r.pos = [1, 0]
	r._start_round()
	check(r.has_curse(1, "horror"), "проклятие в комнате команды 1")
	fill(r)
	r.horror[0] = 2
	r.order = [1, 0]
	r.turn_i = 0
	r._start_turn()
	r.start_timer()
	r.trap_hit(0, 2)
	check(r.turn_log[-1]["reason"] == "horror", "Слово ужаса")
	var r2 := make()
	r2.curses = {0: "defuse"}
	r2._start_round()
	fill(r2)
	check(r2.phase == "defuse", "Обезвреженная ловушка: выбор номера")
	check(r2.pick_defuse(0, 2) and r2.crossed[1] == 1, "у проклятой команды вычеркнута строка 2")


func test_guess_match() -> void:
	check(DWRules.guess_matches("птичье перо", "перо"), "перо ~ птичье перо")
	check(DWRules.guess_matches("перья", "перо"), "перья ~ перо")
	check(not DWRules.guess_matches("ядовитый", "яд"), "однокоренное не засчитывается")
	check(DWRules.guess_matches("это скорая помощь!", "скорая помощь"), "составное слово")
	check(not DWRules.guess_matches("помощь", "скорая помощь"), "часть составного — мимо")


func test_eight_rounds() -> void:
	var r := make("troll")
	for i in 8:
		fill(r)
		play_turn(r, false)
		play_turn(r, false)
		if r.phase == "round_result":
			r.advance()
	check(r.phase == "game_over" and r.monster_won, "8 раундов — победа монстра")

	# порядок ловушек: больше голосов — выше; при равенстве — перетаскиванием, но только внутри своей группы
	var m := make()
	m.phase = "traps"
	m.ready = [false, false]
	m.cands[0] = []
	for w in ["а", "б", "в", "г", "д"]:
		m.cands[0].append({"w": w, "by": 0, "votes": [0]})
	m.cands[0][0]["votes"] = [0, 1]  # «а» — 2 голоса
	m.cands[0][1]["votes"] = [0, 1]  # «б» — 2 голоса
	m.cands[0][4]["votes"] = []  # «д» — без голоса
	var words := func() -> String:
		return "".join(m.ranked(0).map(func(k): return m.cands[0][k]["w"]))
	var idx := func(w: String) -> int:
		return m.cands[0].map(func(c): return c["w"]).find(w)
	check(words.call() == "абвгд", "больше голосов — выше")
	check(m.move_cand(0, idx.call("а"), 1) == 1 and words.call() == "бавгд", "внутри группы с равными голосами — куда поставили")
	check(m.move_cand(0, idx.call("а"), 4) == 1 and words.call() == "бавгд", "2 голоса не опускаются ниже слов с 1 голосом — последним в своей группе")
	check(m.move_cand(0, idx.call("г"), 0) == 2 and words.call() == "багвд", "1 голос не поднимается выше слов с 2 голосами — первым в своей группе")
	check(m.move_cand(0, idx.call("д"), 0) == 4 and words.call() == "багвд", "без голоса — всегда в самом низу")
