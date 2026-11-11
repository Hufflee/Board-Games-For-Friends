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
	# Проверки Jev «Стиллиона» удалены 2026-11-11: игра перешла на темы и буквы, Jev больше не используется.
	print("BATCH26 RULES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
