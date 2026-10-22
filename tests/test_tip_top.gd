extends SceneTree
## Автотесты «Тип Топ». Запуск: godot --headless --script res://tests/test_tip_top.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_data()
	test_round()
	test_lose()
	test_expert()
	test_arrange()
	print("Тип Топ — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int = 4, expert: bool = false) -> TTRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := TTRules.new()
	r.new_game(players, false, expert, 5)
	return r


func test_data() -> void:
	check(TTData.BASE.size() >= 100 and TTData.ADULT.size() >= 100, "колоды по 100+ тем")
	var bad := 0
	for t in TTData.BASE + TTData.ADULT:
		var q: String = str(t[0]).to_lower()
		if q.contains("изобраз") or q.contains("покажите") or q.contains("встаньте"):
			bad += 1
	check(bad == 0, "нет заданий «изобразите / покажите»")


func answer_all(r: TTRules) -> void:
	for s in r.players.size():
		r.answer(s, "ответ %d" % s)


func test_round() -> void:
	var r := make()
	var c := r.captain
	check(r.phase == "theme" and r.unicorns == 4, "жетонов по числу игроков")
	check(not r.pick_theme((c + 1) % 4, 0), "тему выбирает капитан")
	check(r.pick_theme(c, 1) and r.phase == "answer", "тема выбрана")
	check(not r.numbers.has(c), "у капитана нет номера")
	check(not r.answer(c, "капитан"), "капитан не отвечает")
	var nums := r.numbers.duplicate()
	check(r.get_view((c + 1) % 4)["numbers"].size() == 1, "свой номер видит только сам")
	answer_all(r)
	check(r.phase == "order", "все ответили")
	check(not r.answer((c + 1) % 4, "ещё"), "ответ не меняется")
	# выкладываем по возрастанию — без ошибок
	var order: Array = r.to_place()
	check(order.size() == 3, "капитан не выкладывает свой ответ")
	order.sort_custom(func(a, b): return nums[a] < nums[b])
	for s in order:
		check(r.place(c, s), "выкладка")
	check(r.phase == "round_result" and r.poops == 0, "верный порядок — без какашек")
	r.advance()
	check(r.round_no == 2 and r.captain != c, "новый капитан")
	r.pick_theme(r.captain, 0)
	answer_all(r)
	nums = r.numbers.duplicate()
	order = r.to_place()
	order.sort_custom(func(a, b): return nums[a] > nums[b])
	for s in order:
		r.place(r.captain, s)
	check(r.poops == 2 and r.unicorns == 2, "убывающий порядок — 2 ошибки")
	# капитаны по кругу: за 4 раунда при 4 игроках каждый побывал капитаном
	var r2 := make()
	var seen := {}
	for k in 4:
		seen[r2.captain] = true
		r2.pick_theme(r2.captain, 0)
		answer_all(r2)
		r2.force_commit()
		r2.advance()
	check(seen.size() == 4, "капитаны не повторяются до конца круга")


func test_lose() -> void:
	var r := make()
	r.unicorns = 1
	r.pick_theme(r.captain, 0)
	answer_all(r)
	var order: Array = r.to_place()
	order.sort_custom(func(a, b): return r.numbers[a] > r.numbers[b])
	r.place(r.captain, order[0])
	r.place(r.captain, order[1])
	check(r.phase == "game_over" and not r.won, "все жетоны у какашек — поражение")
	r = make()
	for k in 5:
		r.pick_theme(r.captain, 0)
		answer_all(r)
		var o: Array = r.to_place()
		o.sort_custom(func(a, b): return r.numbers[a] < r.numbers[b])
		for s in o:
			r.place(r.captain, s)
		r.advance()
	check(r.phase == "game_over" and r.won and r.level() == 3, "5 раундов без ошибок — одни единороги")


func test_expert() -> void:
	var r := make(4, true)
	var c := r.captain
	r.pick_theme(c, 0)
	answer_all(r)
	check(not r.to_place().has(c), "капитан не выкладывает свою карту")
	check(not r.place(c, (c + 1) % 4), "нужно назвать номер")
	var targets: Array = r.to_place()
	r.place(c, targets[0], r.numbers[targets[0]])
	r.place(c, targets[1], (r.numbers[targets[1]] % 10) + 1)
	r.place(c, targets[2], r.numbers[targets[2]])
	check(r.poops == 1 and r.phase == "guess", "одна ошибка, угадываем номер капитана")
	check(not r.guess_captain(c, 5), "капитан не угадывает свой номер")
	check(r.guess_captain((c + 1) % 4, r.numbers[c]) and r.poops == 0, "угадали — жетон вернулся")


func test_arrange() -> void:
	var r := make()
	var c := r.captain
	r.pick_theme(c, 0)
	answer_all(r)
	var order: Array = r.to_place()
	order.sort_custom(func(a, b): return r.numbers[a] < r.numbers[b])
	check(not r.arrange((c + 1) % 4, order), "раскладывает только капитан")
	check(r.arrange(c, [order[1], order[0]]) and not r.can_commit(), "не все ответы на планшете")
	check(r.arrange(c, order) and r.phase == "order" and r.placed.is_empty(), "раскладка без раскрытия")
	check(not r.arrange(c, [order[0], order[0]]), "без повторов")
	check(r.commit(c) and r.phase == "round_result" and r.poops == 0 and r.log.size() == 3, "«Ответить» — проверка по порядку")
	r = make(4, true)
	r.pick_theme(r.captain, 0)
	answer_all(r)
	var t: Array = r.to_place()
	r.arrange(r.captain, t)
	check(not r.can_commit(), "эксперт: нужны номера")
	var cm := {}
	for s in t:
		cm[s] = r.numbers[s]
	r.arrange(r.captain, t, cm)
	check(r.commit(r.captain) and r.poops == 0 and r.phase == "guess", "эксперт: верные номера")
