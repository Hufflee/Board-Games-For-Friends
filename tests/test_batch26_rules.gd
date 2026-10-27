extends SceneTree
## Голоса Чернил, оспаривание Jev и разнообразие вопросов; без сети/ключа API.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	var p := PIRules.new()
	var members := []
	for i in 6:
		members.append({"name": "Игрок %d" % i})
	p.new_game(members, [0, 0, 1, 2, 2, 3], 26)
	p.phase = "turn"
	var first: int = p.hands[0][0]
	var second: int = p.hands[0][1]
	var third: int = p.hands[0][2]
	check(p.action(0, "question_vote", first), "Медиум голосует")
	check(p.action(1, "question_vote", first), "Второй медиум голосует за тот же вопрос")
	check(p.get_view(0).question_votes[first] == 2, "Подсчитаны два голоса")
	check(p.get_view(2).question_votes.is_empty(), "Дух не видит закрытую руку через голоса")
	check(p.get_view(3).question_votes.is_empty(), "Соперник не видит чужие голоса")
	check(not p.action(2, "question_vote", first), "Дух не голосует за вопросы медиумов")
	check(not p.action(3, "question_vote", first), "Соперник не голосует в чужой ход")
	check(p.action(0, "question_vote", second), "Два голоса разрешены")
	check(not p.action(0, "question_vote", third), "Третий голос отклонён")
	check(p.action(0, "question_vote", first) and p.get_view(1).question_votes[first] == 1, "Свой голос снимается")
	check(p.action(1, "ask", [first, second]), "Два вопроса передаются духу")
	check(p.question_votes[0].is_empty(), "Передача вопросов очищает голоса")
	var s := STRules.new()
	s.external_check = true
	s.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	s.phase = "fuse"
	var seat := s.target
	check(s.submit(seat, "неизвестный ответ проверки"), "Ответ уходит в Jev")
	var no: int = s.pending.no
	check(s.resolve_external(no, false), "Отказ получен")
	check(s.can_appeal(seat), "После отказа можно оспорить")
	check(not s.action(1 - seat, "st_appeal", {}), "Соперник не оспаривает чужой ответ")
	check(s.action(seat, "st_appeal", {}), "Автор оспаривает")
	check(s.pending.appeal and s.pending.no != no, "Новый запрос имеет отдельный номер и признак оспаривания")
	var appeal_no: int = s.pending.no
	var fuse := s.fuse_t
	var question_time := s.q_time
	s.tick(9.0)
	check(s.phase == "check" and s.fuse_t == fuse and s.q_time == question_time, "Подробная проверка ждёт дольше и замораживает таймеры")
	check(not s.resolve_external(no, true), "Запоздавший старый ответ не засчитывается")
	check(s.resolve_external(appeal_no, false) and not s.can_appeal(seat), "Повторный отказ нельзя бесконечно оспаривать")
	s.submit(seat, "следующий неизвестный ответ")
	s.resolve_external(int(s.pending.no), false)
	s.action(seat, "st_appeal", {})
	check(s.resolve_external(int(s.pending.no), true, "u"), "Положительный пересмотр засчитывается")
	check(s.used.size() == 1 and s.target != seat, "Ответ засчитан один раз и ход передан")
	var normal := STJev.request_body({"text": "Вопрос"}, "Ответ")
	var deep := STJev.request_body({"text": "Вопрос"}, "Ответ", true)
	check(deep.state.has("review_mode") and not normal.state.has("review_mode"), "Режим подробного пересмотра отправляется в API")
	check(str(deep.questions.correct.instructions).contains("Do not accept merely"), "Пересмотр не означает автоматическое принятие")
	var football := 0
	var all := STQuestions.all()
	for q: Dictionary in all:
		if str(q.text).contains("футбол") or str(q.text).contains("Премьер-лиги") or str(q.text).contains("Золотого мяча"):
			football += 1
	check(all.size() >= 120 and football == 1, "Остался один футбольный вопрос, общее число сохранено")
	print("BATCH26 RULES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
