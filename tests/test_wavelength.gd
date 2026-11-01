extends SceneTree
## Автотесты «Длины волны». Запуск: godot --headless --script res://tests/test_wavelength.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_points()
	test_turn_flow()
	test_side_guess()
	test_lr_vote()
	test_catchup()
	test_win_and_tiebreak()
	test_coop()
	print("Длина волны — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(coop: bool = false) -> WLRules:
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}]
	var r := WLRules.new()
	r.new_game(players, coop, 11)
	return r


## Полный ход: телепат даёт подсказку, команда ставит стрелку на dial, другая команда выбирает lr.
func turn(r: WLRules, dial: float, lr: String = "left", target: float = 50.0) -> void:
	r.target = target
	var p := r.psychic
	check(r.choose_side(p, 0), "телепат выбрал сторону")
	check(r.give_clue(p, "Кофе"), "подсказка дана")
	var guesser: int = r.team_members(r.active_team).filter(func(s): return s != p)[0]
	check(r.move_dial(guesser, dial), "стрелка сдвинута")
	check(r.lock_dial(guesser), "команда решила")
	if not r.coop:
		for other: int in r.team_members(1 - r.active_team):
			check(r.choose_lr(other, lr), "левее/правее")


func test_points() -> void:
	check(WLRules.points_for(50, 50) == 4, "центр — 4")
	check(WLRules.points_for(50, 52) == 4, "граница центра — 4 (большее)")
	check(WLRules.points_for(50, 55) == 3, "3 очка")
	check(WLRules.points_for(50, 56) == 3, "граница 3/2 — 3")
	check(WLRules.points_for(50, 41) == 2, "2 очка")
	check(WLRules.points_for(50, 60) == 2, "граница зоны — 2")
	check(WLRules.points_for(50, 61) == 0, "мимо — 0")


func test_turn_flow() -> void:
	var r := make()
	check(r.scores == [0, 0] and r.goal(0) == 10 and r.goal(1) == 9, "обе с нуля, второй команде нужно 9")
	check(r.phase == "card" and r.players[r.psychic]["team"] == 0, "ход первой команды, телепат из неё")
	var v_other := r.get_view((r.psychic + 2) % 4)
	check(v_other["target"] < 0.0, "чужие не видят зону")
	check(r.get_view(r.psychic)["target"] >= 3.0, "телепат видит зону")
	check(not r.move_dial(r.psychic, 30), "телепат не двигает стрелку")
	check(not r.give_clue((r.psychic + 2) % 4, "x"), "подсказку даёт только телепат")


func test_side_guess() -> void:
	var r := make()
	turn(r, 55.0, "left", 50.0)  # центр левее стрелки, 3 очка
	check(r.phase == "reveal" and r.result["points"] == 3, "3 очка команде телепата")
	check(r.result["other_points"] == 1 and r.scores == [3, 1], "другая команда угадала «левее» — +1")
	r.advance()
	check(r.active_team == 1, "ход перешёл ко второй команде")
	var r2 := make()
	turn(r2, 50.0, "left", 50.0)
	check(r2.result["points"] == 4 and r2.result["other_points"] == 0, "в центр — другая команда ничего не получает")


## Голосование другой команды: голос можно сменить, итог — большинством, поровну — кто раньше.
func test_lr_vote() -> void:
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}, {"name": "Д", "team": 1}]
	var r := WLRules.new()
	r.new_game(players, false, 5)
	r.target = 40.0
	var p := r.psychic
	r.choose_side(p, 0)
	r.give_clue(p, "Чай")
	var guesser: int = r.team_members(r.active_team).filter(func(s): return s != p)[0]
	r.move_dial(guesser, 50.0)
	r.lock_dial(guesser)
	var voters: Array = r.lr_voters()
	check(voters.size() == 3 and r.phase == "side", "голосуют трое из другой команды")
	check(not r.choose_lr(guesser, "left"), "команда телепата не голосует")
	check(r.choose_lr(voters[0], "right") and r.phase == "side", "первый голос — ждём остальных")
	check(r.choose_lr(voters[0], "left") and r.lr_votes[voters[0]] == "left", "голос можно поменять")
	check(r.choose_lr(voters[1], "right") and r.phase == "side", "второй голос")
	check(r.get_view(voters[2])["lr_voters"].size() == 3, "в виде — кто голосует")
	check(r.choose_lr(voters[2], "left") and r.phase == "reveal", "все проголосовали — итог")
	check(r.lr == "left" and r.result["other_points"] == 1, "большинство «левее» (2 из 3) — и угадали")
	# поровну — решает голос, поданный раньше; время вышло — итог по поданным
	var t := WLRules.new()
	t.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}], false, 6)
	t.choose_side(t.psychic, 0)
	t.give_clue(t.psychic, "x")
	var g: int = t.team_members(t.active_team).filter(func(s): return s != t.psychic)[0]
	t.lock_dial(g)
	var o: Array = t.lr_voters()
	t.choose_lr(o[1], "right")
	check(t.force_lr() and t.lr == "right", "время вышло — итог по одному голосу")
	var u := WLRules.new()
	u.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}], false, 6)
	u.choose_side(u.psychic, 0)
	u.give_clue(u.psychic, "x")
	u.lock_dial(u.team_members(u.active_team).filter(func(s): return s != u.psychic)[0])
	var w: Array = u.lr_voters()
	u.choose_lr(w[1], "right")
	u.choose_lr(w[0], "left")
	check(u.phase == "reveal" and u.lr == "right", "1:1 — решает голос, поданный раньше")


func test_catchup() -> void:
	var r := make()
	r.scores = [2, 7]
	turn(r, 50.0, "right", 50.0)  # 4 очка, 6 < 7
	r.advance()
	check(r.active_team == 0 and r.result.is_empty(), "догоняющий: та же команда ходит снова")
	var r2 := make()
	r2.scores = [5, 6]
	turn(r2, 50.0, "right", 50.0)  # 9 > 6
	r2.advance()
	check(r2.active_team == 1, "не отстаём — ход переходит")


func test_win_and_tiebreak() -> void:
	var r := make()
	r.scores = [8, 5]
	turn(r, 55.0, "right", 50.0)  # +3 → 11
	r.advance()
	check(r.phase == "game_over" and r.winner == 0, "10+ очков — победа")
	var r2 := make()
	r2.scores = [7, 8]
	turn(r2, 55.0, "left", 50.0)  # 10 : 9 — обе дошли до своей цели
	r2.advance()
	check(r2.phase == "card" and r2.tiebreak.size() > 0, "ничья 10:10 — дополнительные ходы")
	turn(r2, 70.0, "left", 50.0)  # команда 1 мимо, команда 0 угадала левее: +1 команде 0
	r2.advance()
	turn(r2, 55.0, "left", 50.0)  # команда 0: +3, команда 1: +1
	r2.advance()
	check(r2.phase == "game_over" and r2.winner == 0, "доп. ходы: команда 0 набрала больше")


func test_coop() -> void:
	var r := make(true)
	check(r.coop and r.scores == [0, 0] and r.cards_left == 7, "кооператив: 7 карточек")
	turn(r, 50.0, "", 50.0)
	check(r.phase == "reveal" and r.scores[0] == 3 and r.cards_left == 7, "в центр — 3 очка и +1 карточка")
	r.advance()
	for i in 6:
		turn(r, 90.0, "", 10.0)
		r.advance()
	check(r.phase == "card" and r.cards_left == 1, "осталась одна карточка")
	turn(r, 90.0, "", 10.0)
	r.advance()
	check(r.phase == "game_over", "карточки кончились — конец")
	check(WLRules.coop_rating(3) == "Эта штука вообще работает?" and WLRules.coop_rating(26) == "Невероятно!!! (взрыв мозга)", "оценка результата")
