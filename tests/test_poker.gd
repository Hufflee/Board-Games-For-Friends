extends SceneTree
## «Покер»: правила без UI — блайнды и порядок ходов, рейзы, неполный ва-банк, побочные банки, вскрытие,
## места и очки спортивной сессии, докупка в классике, сохранение фишек в партиях ботов.
## Запуск: godot --headless --path . --script res://tests/test_poker.gd
const Rules := preload("res://games/poker/logic/pk_rules.gd")
var checks := 0
var errors := 0


func _init() -> void:
	_run()
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)


func seats(n: int, bots: bool = false) -> Array:
	var out := []
	for i: int in n:
		out.append({"name": "И%d" % (i + 1), "bot": bots})
	return out


func game(n: int, mode: String = "classic", bots: bool = false) -> RefCounted:
	var r: RefCounted = Rules.new()
	r.new_game(seats(n, bots), {"mode": mode, "seed": 7})
	return r


func chips(r: RefCounted) -> int:
	var sum := 0
	for s: int in r.stacks:
		sum += s
	return sum + r.pot()


func _run() -> void:
	_blinds()
	_heads_up()
	_raises()
	_short_all_in()
	_side_pots()
	_showdown_split()
	_places()
	_sport_flow()
	_classic_rebuy()
	_bot_games()


func _blinds() -> void:
	var r: RefCounted = game(4)
	check(r.phase == "hand" and r.street == "preflop", "раздача началась с префлопа")
	check(r.sb_seat == (r.button + 1) % 4, "малый блайнд — слева от кнопки")
	check(r.bb_seat == (r.button + 2) % 4, "большой блайнд — следующий")
	check(r.bets[r.sb_seat] == 1 and r.bets[r.bb_seat] == 2, "блайнды 1/2")
	check(r.stacks[r.bb_seat] == 198 and r.stacks[r.button] == 200, "стеки 100 BB = 200")
	check(r.to_act == (r.button + 3) % 4, "первым ходит место после большого блайнда")
	for s: int in 4:
		check(r.hole[s].size() == 2, "у места %d две карты" % s)
	# все коллируют — у большого блайнда право хода (чек)
	var bb: int = r.bb_seat
	check(r.check_call(r.to_act) and r.check_call(r.to_act) and r.check_call(r.to_act), "три колла")
	check(r.to_act == bb and r.street == "preflop", "большой блайнд ещё может ходить")
	check(r.check_call(bb) and r.street == "flop" and r.board.size() == 3, "чек большого блайнда — флоп")
	check(r.to_act == r.sb_seat, "после флопа первым ходит малый блайнд")
	check(r.pot() == 8, "банк 8")


func _heads_up() -> void:
	var r: RefCounted = game(2)
	check(r.sb_seat == r.button, "вдвоём кнопка — малый блайнд")
	check(r.to_act == r.button, "вдвоём префлоп первой ходит кнопка")
	r.check_call(r.to_act)
	r.check_call(r.to_act)
	check(r.street == "flop" and r.to_act == r.bb_seat, "вдвоём после флопа первым ходит большой блайнд")


func _raises() -> void:
	var r: RefCounted = game(3)
	var first: int = r.to_act
	check(not r.raise_to(first, 3), "рейз меньше минимума (до 4) нельзя")
	check(r.raise_to(first, 6), "рейз до 6")
	var second: int = r.to_act
	check(r.min_raise_to(second) == 10, "следующий минимальный рейз — до 10")
	check(r.raise_to(second, 10), "ре-рейз до 10")
	check(r.fold(r.to_act), "пас")
	var before: int = r.stacks[first]
	check(r.fold(r.to_act), "пас — банк без вскрытия")
	check(r.phase == "showdown" and bool(r.result.get("fold_win", false)), "банк забран без вскрытия")
	check(r.stacks[second] == 200 + 6 + 1 or r.stacks[second] == 200 + 6 + 2, "выигравший получил чужие фишки (%d)" % r.stacks[second])
	check(chips(r) == 600, "фишки сохранились")
	check(before == 194, "стек рейзера до паса")


func _short_all_in() -> void:
	var r: RefCounted = game(3)
	var a: int = r.to_act
	var b: int = (a + 1) % 3
	var c: int = (a + 2) % 3
	# у c (большой блайнд) короткий стек: после рейза до 20 он идёт ва-банк до 25 — неполный рейз
	r.stacks[c] = 23  # плюс 2 в банке = 25
	check(r.raise_to(a, 20), "a: рейз до 20")
	check(r.check_call(b), "b: колл 20")
	check(r.all_in_action(c), "c: ва-банк 25")
	check(r.to_act == a and not r.can_raise(a), "a уже ходил — после неполного ва-банка только колл/пас")
	check(r.check_call(a) and r.to_act == b and not r.can_raise(b), "b тоже только уравнивает")


func _side_pots() -> void:
	var r: RefCounted = game(3)
	r.totals = [50, 100, 100]
	r.folded = [false, false, false]
	var pots: Array = r.side_pots()
	check(pots.size() == 2, "два банка")
	check(pots[0].amount == 150 and pots[0].eligible == [0, 1, 2], "главный 150 на троих")
	check(pots[1].amount == 100 and pots[1].eligible == [1, 2], "побочный 100 на двоих")
	r.folded = [false, false, true]
	pots = r.side_pots()
	check(pots.size() == 2 and pots[0].amount == 150 and pots[1].amount == 100 and pots[1].eligible == [1], "сбросивший платит, но не претендует")


func _showdown_split() -> void:
	var r: RefCounted = game(2)
	# одинаковые руки: стол — роял-флеш, банк делится
	r.hole = [[0, 13], [1, 14]]
	r.board = [8, 9, 10, 11, 12]  # 10..A треф
	r.totals = [50, 51]
	r.stacks = [150, 149]
	r.folded = [false, false]
	r._showdown()
	check(r.stacks[0] + r.stacks[1] == 400, "фишки сохранились при делёже")
	check(absi(r.stacks[0] - r.stacks[1]) <= 1, "банк поделён поровну (%d / %d)" % [r.stacks[0], r.stacks[1]])
	var r2: RefCounted = game(2)
	r2.hole = [[12, 25], [0, 14]]  # пара тузов против 2 и 3
	r2.board = [5, 20, 36, 48, 3]  # 7♣ 9♠ Д♦ В♥ 5♣ — без стрита и флеша
	r2.totals = [100, 100]
	r2.stacks = [100, 100]
	r2.folded = [false, false]
	r2._showdown()
	check(r2.stacks[0] == 300 and r2.stacks[1] == 100, "старшая рука забирает банк")
	check(str(r2.result.hands[0]) == "Пара", "название комбинации на вскрытии")


func _places() -> void:
	check(Rules.place_points(1, 4) == 4 and Rules.place_points(2, 4) == 3 and Rules.place_points(3, 4) == 2 and Rules.place_points(4, 4) == 0, "очки 4/3/2/0 при 4 игроках")
	check(Rules.place_points(1, 2) == 2 and Rules.place_points(2, 2) == 0, "вдвоём 2/0")
	check(Rules.place_points(5, 6) == 2 and Rules.place_points(6, 6) == 0, "6 игроков: предпоследнее 2, последнее 0")
	var r: RefCounted = game(4, "sport")
	check(r.target() == 9, "цель при 4 игроках — 9")
	r.stacks = [300, 0, 500, 0]
	r.bust_order = [[3, 2, 40], [1, 5, 10]]
	var places: Array = r.session_places()
	var by_seat := {}
	for e: Dictionary in places:
		by_seat[e.seat] = e
	check(by_seat[2].place == 1 and by_seat[0].place == 2, "живые — по стеку")
	check(by_seat[1].place == 3 and by_seat[3].place == 4, "вылетевший позже — выше")
	check(by_seat[3].points == 0 and by_seat[2].points == 4, "очки по местам")
	r.stacks = [200, 200, 100, 100]
	r.bust_order = []
	places = r.session_places()
	check(places[0].place == 1 and places[1].place == 1 and places[2].place == 3, "равный стек — общее место")


func _sport_flow() -> void:
	var r: RefCounted = game(3, "sport", true)
	var guard := 0
	while r.phase != "session_end" and r.phase != "game_over" and guard < 200000:
		r.tick(0.5)
		guard += 1
	check(r.phase == "session_end" or r.phase == "game_over", "сессия закончилась")
	check(r.hand_no <= 14, "не больше 14 раздач в сессии (%d)" % r.hand_no)
	var total := 0
	for s: int in r.scores:
		total += s
	check(total == 3 + 2 + 0 or total > 0, "очки за сессию начислены (%d)" % total)
	if r.phase == "session_end":
		r.action(0, "next", {}, true)
		check(r.session_no == 2 and r.hand_no == 1, "следующая сессия")
		var all_start := true
		for s: int in 3:
			all_start = all_start and r.stacks[s] + r.totals[s] == 200
		check(all_start, "в новой сессии снова по 100 BB")
	# до победы
	guard = 0
	while r.phase != "game_over" and guard < 2000000:
		r.tick(0.5)
		guard += 1
	check(r.phase == "game_over" and not r.winners.is_empty(), "кто-то набрал %d очков" % r.target())
	var best := 0
	for s: int in r.scores:
		best = maxi(best, s)
	check(best >= 7, "победитель набрал ≥ 7 (%d)" % best)


func _classic_rebuy() -> void:
	var r: RefCounted = game(2)
	var loser: int = r.to_act
	check(r.all_in_action(loser), "ва-банк")
	check(r.all_in_action(r.to_act), "колл ва-банка")
	check(r.phase == "showdown" and r.board.size() == 5, "стол доложен до ривера")
	var busted := -1
	for s: int in 2:
		if r.stacks[s] == 0:
			busted = s
	if busted >= 0:
		r.tick(10.0)
		check(r.phase == "waiting", "второго игрока с фишками нет — ждём докупки")
		check(r.action(busted, "rebuy", {}), "сесть заново")
		check(r.stacks[busted] + r.totals[busted] == 200 and r.rebuys[busted] == 1 and r.phase == "hand", "снова 100 BB, докупка учтена")
		check(r.profit(busted) + r.profit(1 - busted) + r.pot() == 0, "итог по докупкам сходится")
	else:
		check(true, "ничья в ва-банке")
	check(r.action(0, "finish", {}, true) and r.phase == "game_over" and not r.winners.is_empty(), "хост завершает классику")


func _bot_games() -> void:
	for n: int in [2, 5, 8]:
		var r: RefCounted = game(n, "classic", true)
		var start: int = 200 * n
		var ok := true
		for _i: int in 4000:
			r.tick(0.7)
			var rebought := 0
			for s: int in r.rebuys:
				rebought += s
			if chips(r) != start + 200 * rebought:
				ok = false
				print("  фишки: ", chips(r), " ожидалось ", start + 200 * rebought, " фаза ", r.phase)
				break
		check(ok, "партия ботов на %d: фишки сохраняются" % n)
		check(r.hand_no > 5, "боты сыграли раздачи (%d)" % r.hand_no)
