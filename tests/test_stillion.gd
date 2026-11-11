extends SceneTree
## Тесты правил «Стиллиона»: банк тем, буквы, оспаривание (большинство, 1 на 1, повтор — выстрел),
## конец букв, выстрел и новая тема, устный режим, боты, конец партии.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_stillion.gd (код выхода 1 при ошибке)

var checks := 0
var failed := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed += 1
		push_error("ПРОВАЛ: " + msg)


func _init() -> void:
	_bank()
	_letters()
	_challenge_majority()
	_challenge_duel_and_repeat()
	_letters_out()
	_timeout()
	_oral()
	_hotseat()
	_bots()
	print("STILLION: %d проверок, %d ошибок" % [checks, failed])
	quit(1 if failed > 0 else 0)


func _names(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": "И%d" % i})
	return out


## Новая партия сразу в фазе ответа у места 0.
func _game(n: int, seed_value := 5) -> STRules:
	var r := STRules.new()
	r.new_game(_names(n), false, seed_value)
	r.target = 0
	r.tick(STRules.NEW_Q_TIME + 0.01)
	r.tick(STRules.AIM_TIME + 0.01)
	return r


func _to_fuse(r: STRules) -> void:
	if r.phase == "aim":
		r.tick(STRules.AIM_TIME + 0.01)


func _bank() -> void:
	var cats := STRules.categories()
	check(cats.size() == 90, "90 тем (есть %d)" % cats.size())
	var names := {}
	var bad := 0
	for c: Dictionary in cats:
		names[c.cat] = true
		var firsts := {}
		for a: Dictionary in c.answers:
			var l := str(a.alts[0]).left(1)
			if not STRules.LETTERS.has(l) or firsts.has(l):
				bad += 1
			firsts[l] = true
		if (c.answers as Array).size() != 14:
			bad += 1
	check(names.size() == 90, "Названия тем не повторяются")
	var hinted := {}
	for c: Dictionary in cats:
		if str(c.hint) != "":
			hinted[c.cat] = c.hint
	check(hinted.size() == 3 and hinted.has("Камень") and hinted.has("Продукт питания") and hinted.has("Часть дома"), "Подсказки у трёх тем, название без скобок")
	check(bad == 0, "У каждой темы 14 ответов на разные разрешённые буквы (ошибок %d)" % bad)
	check(STRules.LETTERS.size() == 24, "24 буквы")
	for l in ["й", "ё", "ю", "э", "ц", "щ", "ъ", "ь", "ы"]:
		check(not STRules.LETTERS.has(l), "Буквы «%s» нет" % l)


func _letters() -> void:
	var r := _game(3)
	check(r.phase == "fuse" and r.target == 0 and r.category.has("cat"), "Тема открыта, пушка на месте 0")
	check(not r.submit(1, "Австрия"), "Не тот игрок не отвечает")
	check(r.submit(0, "Австрия") and r.letter_used("а") and r.target == 1, "Ответ засчитан, «А» погасла, ход дальше")
	check(r.players[0].last_answer == "Австрия", "Последний ответ над игроком")
	_to_fuse(r)
	r.submit(1, "аргентина")
	check(r.last.kind == "wrong" and r.last.why == "used" and r.target == 1, "Занятая буква не принимается")
	r.submit(1, "Эстония")
	check(r.last.kind == "wrong" and r.last.why == "none", "Буквы «Э» нет — не принимается")
	r.submit(1, "Ёлка")
	check(r.letter_used("е") and r.target == 2, "«Ё» считается за «Е»")
	check(r.get_view(2).category == r.category.cat and r.get_view(2).used.size() == 2, "Вид: тема и погасшие буквы")


## 4 игрока: голосуют трое (кроме автора), нужно 2.
func _challenge_majority() -> void:
	var r := _game(4)
	r.submit(0, "Бразилия")
	check(r.votes_needed() == 2, "4 игрока: нужно 2 голоса из 3")
	check(not r.challenge(0), "Автор не оспаривает свой ответ")
	check(r.challenge(2) and r.target == 1 and r.letter_used("б"), "Один голос — ответ ещё в силе")
	check(not r.challenge(2), "Дважды не голосуют")
	check(r.challenge(3) and not r.letter_used("б") and r.target == 0 and r.phase == "aim", "Большинство — не засчитан, пушка вернулась к автору")
	check(r.last.kind == "challenged" and r.retry_seat == 0 and r.players[0].last_answer == "", "Событие и метка повтора")
	_to_fuse(r)
	check(r.fuse_t == 0.0 and r.fuse_len == r.answer_time, "Время автора сначала")
	r.submit(0, "Бельгия")
	_to_fuse(r)
	r.submit(1, "Венгрия")
	check(r.retry_seat == -1 and r.prev.seat == 1, "Следующий ответил — повтор забыт, оспорить можно только последний")
	check(not r.can_challenge(3) or int(r.prev.seat) == 1, "Старый ответ уже не оспорить")


## 1 на 1: хватает одного; оспорили дважды подряд — выстрел автору.
func _challenge_duel_and_repeat() -> void:
	var r := _game(2)
	r.submit(0, "Германия")
	check(r.votes_needed() == 1, "1 на 1: нужен один голос")
	check(r.challenge(1) and r.target == 0 and not r.letter_used("г"), "Один голос отменяет ответ")
	_to_fuse(r)
	r.submit(0, "Гана")
	check(r.prev.retry, "Повторный ответ помечен")
	var lives := int(r.players[0].lives)
	check(r.challenge(1) and r.phase == "boom" and r.target == 0, "Второй раз подряд — выстрел")
	check(int(r.players[0].lives) == lives - 1 and r.last.kind == "boom" and r.last.challenged, "Минус жизнь, событие с пометкой")
	var q := r.q_no
	r.tick(STRules.BOOM_TIME + 0.01)
	check(r.phase == "new_q" and r.q_no == q + 1 and r.used.is_empty() and r.target == 0, "Новая тема, буквы снова все, начинает подстреленный")


func _letters_out() -> void:
	var r := _game(2)
	var cat: Dictionary = r.category
	for l: String in STRules.LETTERS:
		_to_fuse(r)
		r.submit(r.target, l + "тест")
	check(r.phase == "review" and r.letters_left() == 0, "Буквы кончились — окно оспаривания")
	check(r.can_challenge(1 - int(r.prev.seat)), "Последний ответ ещё можно оспорить")
	r.tick(STRules.REVIEW_TIME + 0.01)
	check(r.phase == "new_q" and r.category != cat and r.used.is_empty(), "Потом — новая тема")
	check(int(r.players[0].lives) == r.max_lives and int(r.players[1].lives) == r.max_lives, "Без потерь жизней")
	# оспорили последний ответ в окне — буква снова свободна, автор отвечает
	var r2 := _game(2)
	for l: String in STRules.LETTERS:
		_to_fuse(r2)
		r2.submit(r2.target, l + "тест")
	var author := int(r2.prev.seat)
	check(r2.challenge(1 - author) and r2.phase == "aim" and r2.target == author and r2.letters_left() == 1, "Оспорили в окне — буква вернулась")


func _timeout() -> void:
	var r := _game(3)
	r.max_lives = 1
	r.players[0].lives = 1
	r.tick(r.fuse_len + 0.1)
	check(r.phase == "boom" and not r.players[0].alive, "Не успел — выстрел, без жизней — выбыл")
	r.tick(STRules.BOOM_TIME + 0.01)
	check(r.phase == "new_q" and r.target == 1, "Новую тему начинает следующий живой")
	r.tick(STRules.NEW_Q_TIME + 0.01)
	r.tick(STRules.AIM_TIME + 0.01)
	r.players[1].lives = 1
	r.tick(r.fuse_len + 0.1)
	r.tick(STRules.BOOM_TIME + 0.01)
	check(r.phase == "game_over" and r.winner == 2, "Остался один — победа")


func _oral() -> void:
	var r := STRules.new()
	r.oral = true
	r.new_game(_names(3), false, 9)
	r.target = 0
	r.tick(STRules.NEW_Q_TIME + 0.01)
	r.tick(STRules.AIM_TIME + 0.01)
	check(not r.action(0, "st_answer", {"text": "Австрия"}), "Устно: текст не принимается")
	check(r.action(0, "st_answer", {"letter": "к"}) and r.letter_used("к") and r.target == 1, "Устно: нажатая буква — ответ")
	check(r.players[0].last_answer == "на «К»", "Над игроком — буква")
	_to_fuse(r)
	check(not r.action(1, "st_answer", {"letter": "к"}), "Занятую букву не нажать")
	check(not r.action(1, "st_answer", {"letter": "щ"}), "Буквы «Щ» нет")
	check(r.action(2, "st_challenge", {}) and r.action(1, "st_challenge", {}) and r.target == 0, "Устный ответ тоже оспаривается")


func _hotseat() -> void:
	var r := _game(4)
	r.hotseat = true
	r.submit(0, "Дания")
	check(r.votes_needed() == 1 and r.can_challenge(0), "Один компьютер: одно нажатие, жмёт любой")
	check(r.challenge(0) and r.target == 0 and not r.letter_used("д"), "Оспорено одним нажатием")


func _bots() -> void:
	var r := STRules.new()
	var pl := _names(3)
	for p: Dictionary in pl:
		p.bot = true
	r.new_game(pl, false, 21)
	var answers := 0
	for i in 8000:
		var before := r.event_no
		r.tick(0.05)
		if r.event_no != before and r.last.kind == "ok":
			answers += 1
			check(STJudge.lookup(r.category, str(r.last.name)).get("found", false), "Бот отвечает из списка темы")
		if r.phase == "game_over":
			break
	check(answers > 5, "Боты отвечают (%d)" % answers)
	check(r.phase == "game_over", "Партия ботов доходит до конца")
	# боты не оспаривают и не входят в счёт голосов: 2 человека + 2 бота — хватает одного голоса человека
	var b := STRules.new()
	var pl2 := _names(4)
	pl2[2].bot = true
	pl2[3].bot = true
	b.new_game(pl2, false, 4)
	b.target = 0
	b.tick(STRules.NEW_Q_TIME + 0.01)
	b.tick(STRules.AIM_TIME + 0.01)
	b.submit(0, "Абырвалг")
	check(b.votes_needed() == 1 and not b.can_challenge(2), "Боты не голосуют, нужен один человек")
	for i in 80:
		b.tick(0.05)
	check(b.last.kind != "challenged" and b.letter_used("а"), "Ответ не из списка боты не трогают")
	check(b.challenge(1) and not b.letter_used("а"), "Человек оспорил — не засчитан")
