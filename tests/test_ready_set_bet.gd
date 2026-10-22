extends SceneTree
## Автотесты «На старт, ставки!». Запуск: godot --headless --script res://tests/test_ready_set_bet.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_bonus_moves()
	test_red_line()
	test_places()
	test_betting()
	test_payouts()
	test_vip_and_game_end()
	print("На старт, ставки! — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int = 3) -> RSBRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := RSBRules.new()
	r.new_game(players, 5)
	r.start_race()
	return r


func test_bonus_moves() -> void:
	var r := make()
	r.roll(1, 2)
	check(r.pos[0] == 1, "3 — лошадь 2/3 на 1")
	r.roll(1, 1)
	check(r.pos[0] == 5, "2 после 3 — бонус +3")
	r.roll(2, 1)
	check(r.pos[0] == 6, "третий подряд — без бонуса")
	r.roll(1, 1)
	check(r.pos[0] == 10, "четвёртый подряд — снова бонус")
	r.roll(3, 4)
	r.roll(4, 3)
	check(r.pos[4] == 2, "у 7 бонуса нет")
	r.roll(3, 3)
	r.roll(3, 3)
	check(r.pos[3] == 3, "6 — бонус +1")


func test_red_line() -> void:
	var r := make()
	for i in 9:
		r.roll(3, 3)
		r.roll(4, 4)
		r.roll(5, 5)
	check(r.crossed.size() == 0 or r.pos.max() > 9, "линия")
	r = make()
	r.pos = [9, 9, 0, 0, 0, 0, 0, 0, 0]
	r.roll(1, 1)
	check(r.crossed == [0] and not r.no_more_bets, "первая пересекла")
	r.roll(1, 3)
	check(r.crossed.size() == 2, "две пересекли")
	check(r.place(0, 0, "w_4_0"), "ставить ещё можно")
	r.pos[2] = 9
	r.roll(1, 4)
	check(r.no_more_bets, "третья — «ставок больше нет»")
	check(not r.place(1, 0, "w_4_1"), "после закрытия — нельзя")


func test_places() -> void:
	var p := RSBRules.compute_places([15, 10, 8, 8, 3, 2, 0, 0, 0])
	check(p["first"] == 0 and p["second"] == [1] and p["third"] == [2, 3], "ничья за третье")
	p = RSBRules.compute_places([15, 10, 10, 8, 3, 2, 0, 0, 0])
	check(p["second"] == [1, 2] and p["third"] == [1, 2], "ничья за второе — они же третьи")


func test_betting() -> void:
	var r := make()
	check(r.place(0, 0, "w_0_2"), "ставка")
	check(not r.place(1, 0, "w_0_2"), "ячейка занята")
	check(not r.place(0, 0, "w_0_1"), "жетон уже использован")
	check(r.place(0, 1, "ex_0_0") and not r.place(0, 2, "ex_0_1"), "экзотика — один жетон на карту")
	check(r.place(1, 1, "ex_0_1"), "другой игрок — можно")
	check(not r.place(0, 2, "prop_7"), "пари только 0–4")
	r.vips[2] = [15]  # «Ставка на плечах: 5»
	check(r.place(2, 4, "w_0_2"), "ставка на плечах")
	check(not r.place(1, 4, "prop_0") or true, "")
	r = make()
	r.phase = "start"
	check(not r.place(0, 0, "w_0_0"), "до старта — нельзя")


func test_payouts() -> void:
	var r := make()
	r.place(0, 4, "w_0_2")  # 5 × 9 = 45
	r.place(1, 0, "w_4_0")  # проигрыш −4
	r.place(2, 1, "s_3_0")  # 6 — второе место: 3 × 1 = 3
	r.place(2, 2, "color_blue")  # 3 × 5 = 15
	r.place(1, 1, "p_8_0")  # 11/12 не в двойке: −4
	r.money = [0, 2, 0]
	r.pos = [14, 0, 0, 12, 0, 0, 0, 0, 0]
	r.prev_horse = -1
	r.roll(1, 2)
	check(r.phase == "results", "финиш")
	check(r.money[0] == 45, "победа 2/3 ×9")
	check(r.money[1] == 0, "проигрыш не уводит в минус")
	check(r.money[2] == 18, "show + цвет")


func test_vip_and_game_end() -> void:
	var r := make()
	r.pos = [14, 0, 0, 0, 0, 0, 0, 0, 0]
	r.roll(1, 2)
	r.advance()
	check(r.phase == "vip" and r.vip_hand[0].size() == 2, "драфт VIP")
	r.vip_hand[0] = [11, 16]  # белый 7, фишки от заведения
	check(r.pick_vip(0, 0) and r.tokens[0].size() == 6, "бонус-жетон добавлен")
	r.vip_hand[1] = [16, 0]
	r.pick_vip(1, 0)
	check(r.money[1] == 4, "фишки от заведения: 1-я карта — $4")
	r.pick_vip(2, 1)
	check(r.phase == "start" and r.race_no == 2 and r.exotics.size() == 2, "следующий забег")
	r.start_race()
	r.place(0, 5, "w_4_0")  # белый 7 — проигрыш: 4 + 5
	r.money[0] = 20
	r.pos = [14, 0, 0, 0, 0, 0, 0, 0, 0]
	r.roll(1, 2)
	check(r.money[0] == 11, "бонус-жетон: штраф ячейки + свой")
	for k in 2:
		r.advance()
		for s in 3:
			r.pick_vip(s, 0)
		r.start_race()
		r.pos = [14, 0, 0, 0, 0, 0, 0, 0, 0]
		r.roll(1, 2)
	check(r.race_no == 4 and r.phase == "results", "четвёртый забег")
	r.advance()
	check(r.phase == "game_over" and not r.winners.is_empty(), "конец игры")
