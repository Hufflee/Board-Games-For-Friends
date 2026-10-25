extends SceneTree
## Тесты правил «Стиллиона»: банк вопросов, проверка ответов (опечатки), ход партии, боты, разбор ответа jev.
## Запуск: godot --headless --path . --script res://tests/test_stillion.gd (код выхода 1 при ошибке)

var checks := 0
var failed := 0


func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ПРОВАЛ: " + msg)


func _initialize() -> void:
	_questions()
	_judge()
	_flow()
	_bots()
	_jev()
	_settings()
	_deck_session()
	_fuse_per_question()
	_near_same()
	print("СТИЛЛИОН: %d проверок, ошибок: %d" % [checks, failed])
	quit(1 if failed > 0 else 0)


func _questions() -> void:
	var all := STQuestions.all()
	check(STQuestions.categories().size() == 10, "10 категорий (сейчас %d)" % STQuestions.categories().size())
	check(all.size() >= 120, "вопросов не меньше 120 (сейчас %d)" % all.size())
	for q: Dictionary in all:
		var counts := {"c": 0, "s": 0, "u": 0, "e": 0}
		var seen := {}
		for a: Dictionary in q.answers:
			counts[a.rarity] += 1
			for alt in a.alts:
				check(not seen.has(alt) or seen[alt] == a.name, "повтор ответа «%s» в «%s»" % [alt, q.text])
				seen[alt] = a.name
		check(counts.c >= 2, "у «%s» мало общеизвестных ответов" % q.text)
		check(q.answers.size() >= 8, "у «%s» меньше 8 ответов" % q.text)


func _judge() -> void:
	check(STJudge.normalize("  Ёжик-в  тумане! ") == "ежик в тумане", "нормализация")
	var q := {"cat": "Тест", "text": "?", "answers": []}
	for item in [["Санкт-Петербург|Питер", "s"], ["Москва", "c"], ["Сыр", "c"]]:
		var alts: Array = []
		for alt in str(item[0]).split("|"):
			alts.append(STJudge.normalize(alt))
		q.answers.append({"name": str(item[0]).split("|")[0], "alts": alts, "rarity": item[1]})
	check(STJudge.lookup(q, "москва").found and not STJudge.lookup(q, "москва").typo, "точное совпадение")
	check(STJudge.lookup(q, "Масква").found and STJudge.lookup(q, "Масква").typo, "одна опечатка прощается")
	check(STJudge.lookup(q, "санкт петербур").name == "Санкт-Петербург", "опечатка в длинном слове")
	check(STJudge.lookup(q, "питер").found, "синоним")
	check(not STJudge.lookup(q, "сор").found, "в коротком слове опечатки не прощаются")
	check(not STJudge.lookup(q, "лондон").found, "чужой ответ не найден")


func _new(n: int, bots: bool = false) -> STRules:
	var r := STRules.new()
	var pl := []
	for i in n:
		pl.append({"name": "И%d" % i, "bot": bots})
	r.new_game(pl, false, 7)
	return r


func _until(r: STRules, phase: String, limit: float = 30.0) -> void:
	var t := 0.0
	while r.phase != phase and t < limit and r.phase != "game_over":
		r.tick(0.1)
		t += 0.1


func _flow() -> void:
	var r := _new(4)
	check(r.phase == "new_q" and r.get_view(0).question.text == "", "партия начинается с «Новый вопрос!», вопрос пока скрыт")
	r.tick(STRules.NEW_Q_TIME - 0.1)
	check(r.phase == "new_q", "пауза перед вопросом держится")
	r.tick(0.2)
	check(r.phase == "aim" and r.get_view(0).question.text != "", "после паузы — вопрос и наведение")
	check(is_equal_approx(r.fuse_len, STRules.FUSE_START), "фитиль вопроса — полный")
	_until(r, "fuse")
	check(r.phase == "fuse", "после наведения горит фитиль")
	var tgt := r.target
	check(not r.submit((tgt + 1) % 4, "что угодно"), "отвечает только тот, в кого целятся")
	var a: Dictionary = r.question.answers[0]
	check(r.submit(tgt, a.name), "ответ принят")
	check(r.last.kind == "ok" and r.target == (tgt + 1) % 4, "пушка повернулась к следующему по часовой")
	check(int(r.players[tgt].meter) == int(STRules.POINTS[a.rarity]) % STRules.METER_MAX, "очки шкалы по редкости")
	_until(r, "fuse")
	r.submit(r.target, a.name)
	check(r.last.kind == "used" and r.phase == "fuse", "повтор ответа не засчитан, фитиль горит дальше")
	r.submit(r.target, "абракадабра-нет-такого")
	check(r.last.kind == "wrong" and r.phase == "fuse", "неверный ответ без jev — ещё попытка")
	var victim := r.target
	_until(r, "boom")
	check(r.last.kind == "boom" and int(r.players[victim].lives) == STRules.MAX_LIVES - 1, "не успел — минус жизнь")
	_until(r, "aim")
	check(r.target == (victim + 1) % 4, "после выстрела — следующий")
	# шкала: заполнилась — жизнь назад
	var p: Dictionary = r.players[victim]
	p.meter = STRules.METER_MAX - 1
	r.target = victim
	r.phase = "fuse"
	var free_answer := ""
	for x: Dictionary in r.question.answers:
		if not r._is_used(x.name):
			free_answer = x.name
			break
	r.submit(victim, free_answer)
	check(int(p.lives) == STRules.MAX_LIVES and int(p.meter) == 0, "полная шкала возвращает жизнь и обнуляется")
	# смена вопроса после двух потерянных жизней
	var no := r.q_no
	r.q_losses = STRules.LOSSES_PER_QUESTION
	_until(r, "fuse")
	r.tick(r.fuse_len + 0.1)
	_until(r, "aim")
	check(r.q_no != no, "после двух потерь — новый вопрос")
	# внешний судья
	var e := _new(2)
	e.external_check = true
	_until(e, "fuse")
	e.submit(e.target, "совсем незнакомый ответ")
	check(e.phase == "check", "незнакомый ответ уходит на проверку jev")
	var fuse_before := e.fuse_t
	e.tick(1.0)
	check(e.fuse_t == fuse_before, "пока проверяем — фитиль стоит")
	check(e.resolve_external(int(e.pending.no), true, "e"), "вердикт принят")
	check(e.last.kind == "ok" and e.last.rarity == "e", "jev засчитал редкий ответ")
	var e2 := _new(2)
	e2.external_check = true
	_until(e2, "fuse")
	e2.submit(e2.target, "ещё один")
	e2.tick(STRules.CHECK_TIMEOUT + 0.5)
	check(e2.last.kind == "wrong" and e2.phase == "fuse", "jev молчит — не засчитано, игра идёт")


func _bots() -> void:
	for seed_value in 20:
		var r := STRules.new()
		var pl := []
		for i in 2 + seed_value % 7:
			pl.append({"name": "Б%d" % i, "bot": true})
		r.new_game(pl, false, seed_value + 1)
		var t := 0.0
		while r.phase != "game_over" and t < 3000.0:
			r.tick(0.1)
			t += 0.1
		check(r.phase == "game_over" and r.winner >= 0 and r.alive_count() == 1, "боты доигрывают партию (сид %d)" % seed_value)
		var v := r.get_view(0)
		check(v.game == "stillion" and v.players.size() == pl.size(), "view")


func _jev() -> void:
	var q: Dictionary = STQuestions.all()[0]
	var body := STJev.request_body(q, "подъезд")
	check(body.questions.correct.type == "noul" and body.questions.rarity.type == "choice", "форма запроса jev")
	check(body.state.player_answer == "подъезд" and body.model == STJev.MODEL, "состояние запроса")
	var ok := STJev.parse({"answers": {"correct": {"noul": true}, "rarity": {"choice": "smart"}}})
	check(ok.ok and ok.rarity == "e", "разбор: bool + choice (редкость jev — на ступень выше)")
	var prob := STJev.parse({"answers": {"correct": {"noul": 0.2}, "rarity": {"choice": {"common": 0.7, "erudite": 0.3}}}})
	check(not prob.ok and prob.rarity == "s", "разбор: вероятности")
	check(STJev.parse({"answers": {"correct": {"noul": 0.42}, "rarity": {"choice": "erudite"}}}).ok, "порог «верно» — 0,4")
	check(not STJev.parse({"answers": {"correct": {"noul": 0.38}, "rarity": {"choice": "school"}}}).ok, "ниже 0,4 — не засчитано")
	check(STJev.parse("мусор").error, "мусор вместо ответа")
	# засчитанный jev ответ уходит в файл новых ответов
	var path := "user://test_stillion_new_answers.jsonl"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var v := STJev.parse({"answers": {"correct": {"noul": 0.9}, "rarity": {"choice": "smart"}}})
	STJev.log_new_answer(q, " подъём ", v, path)
	STJev.log_new_answer(q, "съезд", v, path)
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var rec = JSON.parse_string(lines[0])
	check(lines.size() == 2 and rec is Dictionary and rec.answer == "подъём" and rec.question == q.text and is_equal_approx(float(rec.p), 0.9) and rec.jev == "smart",
		"новый ответ записан в файл (дописывается, с вопросом и уверенностью)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Настройки партии: жизни, размер шкалы, «обычные игроки» (редкость на ступень выше).
func _settings() -> void:
	var r := STRules.new()
	r.max_lives = 5
	r.meter_max = 10
	r.new_game([{"name": "А"}, {"name": "Б"}], false, 3)
	check(int(r.players[0].lives) == 5 and int(r.get_view(0).max_lives) == 5, "жизни из настройки")
	check(int(r.get_view(0).meter_max) == 10, "размер шкалы из настройки")
	check(r.perceived("x", "u") == "u", "знатоки: редкость как в списке")
	r.casual = true
	check(r.perceived("x", "u") == "e" and r.perceived("x", "s") == "u" and r.perceived("x", "e") == "e", "обычные: умник → эрудит, школьник → умник")
	for q: Dictionary in STQuestions.all():
		var commons: Array = []
		for a: Dictionary in q.answers:
			if a.rarity == "c":
				commons.append(a.name)
		if commons.size() < 2:
			continue
		r.question = q
		check(r.perceived(commons[0], "c") == "c", "самый очевидный ответ остаётся общеизвестным")
		check(r.perceived(commons[commons.size() - 1], "c") == "s", "менее очевидный общеизвестный → школьник")
		break
	# очки шкалы и цветные куски
	_until(r, "fuse")
	var tgt := r.target
	var a: Dictionary = r.question.answers[0]
	r.submit(tgt, a.name)
	var got: String = r.used[0].rarity
	check((r.players[tgt].parts as Array) == [got] and int(r.players[tgt].meter) == int(STRules.POINTS[got]), "ответ лёг на шкалу куском своей редкости")


## Колода вопросов на сессию лобби: между партиями вопросы не повторяются, пока не кончатся все.
func _deck_session() -> void:
	var total := STQuestions.all().size()
	var deck: Array = []  # как Net._st_deck
	var seen := {}
	var repeats := 0
	var last := {}
	for game in 3:
		var r := STRules.new()
		r.deck = deck
		r.new_game([{"name": "А"}, {"name": "Б"}], false, 11 + game)
		for k in 40:
			if seen.has(r.question.text):
				repeats += 1
			seen[r.question.text] = true
			last = r.question
			if k < 39:
				r._next_question()
	check(repeats == 0 and seen.size() == total, "%d вопросов за 3 партии без повторов (повторов: %d)" % [total, repeats])
	check(deck.is_empty(), "колода сессии израсходована")
	var r2 := STRules.new()
	r2.deck = deck
	r2.question = last
	r2._next_question()
	check(r2.question.text != last.text and deck.size() == total - 1, "колода перемешана заново, новый круг — не с последнего вопроса")


## Фитиль: короче с каждым верным ответом на вопрос, на новом вопросе — снова полный.
func _fuse_per_question() -> void:
	var r := _new(3)
	_until(r, "fuse")
	var a: Dictionary = r.question.answers[0]
	r.submit(r.target, a.name)
	check(is_equal_approx(r.fuse_len, STRules.FUSE_START - STRules.FUSE_STEP), "верный ответ — фитиль короче")
	_until(r, "fuse")
	var b: Dictionary = r.question.answers[1]
	r.submit(r.target, b.name)
	check(is_equal_approx(r.fuse_len, STRules.FUSE_START - 2 * STRules.FUSE_STEP), "ещё ответ — ещё короче")
	var no := r.q_no
	r.q_time = STRules.QUESTION_TIME  # вопрос «выдохся»: при следующей смене цели — новый
	_until(r, "fuse")
	r.submit(r.target, r.question.answers[2].name)
	check(r.phase == "new_q" and r.q_no == no + 1, "смена вопроса — пауза «Новый вопрос!»")
	check(is_equal_approx(r.fuse_len, STRules.FUSE_START), "новый вопрос — фитиль снова полный")


## Почти одинаковые ответы (только номер в конце разный) — один ответ.
func _near_same() -> void:
	check(STJudge.base("dust 2") == "dust" and STJudge.base("gta iv") == "gta" and STJudge.base("убить билла 2") == "убить билла", "основа без номера")
	check(STJudge.base("11 22 63") == "11", "номер-название не съедается целиком")
	var r := STRules.new()
	r.new_game([{"name": "А"}, {"name": "Б"}], false, 2)
	for q: Dictionary in STQuestions.all():
		if q.text == "Назовите карту Counter-Strike":
			r.question = q
	_until(r, "fuse")
	r.used.clear()
	r.submit(r.target, "даст 2")
	check(r.last.kind == "ok", "dust 2 засчитан")
	_until(r, "fuse")
	r.submit(r.target, "dust")
	check(r.last.kind == "used", "dust после dust 2 — уже называли")
	r.submit(r.target, "mirage")
	check(r.last.kind == "ok", "другая карта засчитана")
