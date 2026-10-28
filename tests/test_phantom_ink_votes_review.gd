## Голоса Чернил: роли/лимит/смена/приватность и lifecycle, без новой production-логики.
## --headless --audio-driver Dummy --script res://tests/test_phantom_ink_votes_review.gd.
extends SceneTree
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func game(seed_value: int) -> PIRules:
	var p := PIRules.new()
	var members: Array = []
	for i in 8: members.append({"name": "Тест%d" % i})
	p.new_game(members, [0, 0, 0, 1, 2, 2, 2, 3], seed_value)
	check(p.action(3, "object", 0) and p.action(7, "object", 0) and p.phase == "turn", "Оба духа штатно выбрали предмет")
	return p

func reject(p: PIRules, seat: int, arg: Variant) -> void:
	var before: Array = []
	for i in range(-1, 8): before.append(p.get_view(i))
	var random := p._rng.state
	var revision := p.revision
	check(not p.action(seat, "question_vote", arg), "Недопустимый vote отклонён")
	for i in range(-1, 8): check(p.get_view(i) == before[i + 1], "Отклонённый vote не меняет view ни одной роли")
	check(random == p._rng.state and revision == p.revision, "Отказ не меняет RNG/revision")

func complete_clue(p: PIRules, medium: int, spirit: int) -> void:
	var offered: Array = p.hands[p.team].slice(0, 2)
	check(p.action(medium, "ask", offered), "Два вопроса переданы духу штатным action")
	check(p.action(spirit, "question", offered[0]) and p.action(spirit, "clue", "А"), "Дух штатно начал короткую подсказку")
	check(p.tick(1.1) and p.tick(1.1), "Короткая подсказка закончена штатным tick")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for seed_value in [281028, 281029]:
		var p := game(seed_value)
		var a: int = p.hands[0][0]
		var b: int = p.hands[0][1]
		var c: int = p.hands[0][2]
		for seat in [0, 1, 2]:
			check(p.action(seat, "question_vote", a) and p.action(seat, "question_vote", b), "Каждый из трёх медиумов может выбрать два вопроса")
		for seat in [0, 1, 2]:
			var view := p.get_view(seat)
			check(view.question_votes == {a: 3, b: 3} and view.own_question_votes == [a, b], "Своя команда видит общие счётчики и свои два голоса")
		for seat in [-1, 3, 4, 5, 6, 7, 99]:
			var view := p.get_view(seat, true)
			check(not view.question_votes.has(a) and not view.question_votes.has(b) and view.own_question_votes.is_empty(), "Дух/соперники/зритель не видят голосов даже с show_all")
		for seat in [-1, 3, 4, 7, 99]: reject(p, seat, a)
		for arg in [c, -1, 999999, str(a), float(a), [a], true, null]: reject(p, 0, arg)
		check(p.action(0, "question_vote", a), "Можно снять один из двух голосов")
		check(p.get_view(1).question_votes == {a: 2, b: 3} and p.get_view(0).own_question_votes == [b], "Снятие меняет только голос автора")
		check(p.action(0, "question_vote", c) and p.get_view(0).own_question_votes == [b, c], "Снятие+новый выбор сменяет голос")
		var copy := p.get_view(0)
		copy.own_question_votes.clear()
		copy.question_votes.clear()
		check(p.get_view(0).own_question_votes == [b, c] and not p.get_view(1).question_votes.is_empty(), "View не отдаёт изменяемую ссылку на голоса")
		var old_hand: Array = p.hands[0].duplicate()
		check(p.action(1, "refresh"), "Медиум штатно заменил руку")
		check(p.hands[0].size() == 7 and p.hands[0] != old_hand and p.question_votes[0].is_empty(), "Новая рука сбрасывает все голоса команды")
		reject(p, 0, a)
		var q: int = p.hands[0][0]
		check(p.action(2, "question_vote", q), "После refresh новый вопрос голосуется")
		complete_clue(p, 0, 3)
		check(p.team == 1 and p.question_votes[0].is_empty(), "Отправка вопросов/завершение хода очистили голоса")
		check(p.phase == "turn" or p.phase == "eye", "Следующая команда получила нормальную фазу")
		if p.phase == "eye": p.action(4, "eye_skip")
		var other: int = p.hands[1][0]
		check(p.action(4, "question_vote", other) and p.action(5, "question_vote", other), "У второй команды свои голоса")
		check(p.get_view(6).question_votes == {other: 2} and p.get_view(0).question_votes.is_empty(), "Счётчики второй команды не видны первой")
		complete_clue(p, 4, 7)
		check(p.team == 0 and p.get_view(0).own_question_votes.is_empty() and p.get_view(1).question_votes.is_empty(), "Новый круг/ход команды не восстанавливает старые голоса")
		if p.phase == "eye": p.action(0, "eye_skip")
		check(p.action(0, "question_vote", p.hands[0][0]), "В новом ходе разрешён новый голос")
		p.new_game(p.players, p.roles, seed_value + 100)
		check(p.question_votes == [{}, {}], "Новая партия полностью сбрасывает голоса")
	print("INK VOTES LOW RULES: checks=", checks, " errors=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
