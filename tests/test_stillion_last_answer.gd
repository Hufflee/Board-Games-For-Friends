extends SceneTree
## Регрессии последнего ответа: хост, все места и зритель, проверка jev и новая партия.
## Запуск: godot --headless --path . --script res://tests/test_stillion_last_answer.gd

var failed := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)


func _initialize() -> void:
	var rules := STRules.new()
	var players := [{"name": "А"}, {"name": "Б"}, {"name": "В"}]
	rules.new_game(players, false, 7)
	rules.phase = "fuse"
	var seat := rules.target
	check(not rules.submit((seat + 1) % 3, "чужой"), "Чужой ход отклонён")
	check(rules.players[(seat + 1) % 3].last_answer == "", "Отклонённый ответ не записан")
	check(rules.submit(seat, "неподходящий ответ 123"), "Неверный ответ принят на проверку")
	for viewer in [-1, 0, 1, 2]:
		check(rules.get_view(viewer).players[seat].last_answer == "неподходящий ответ 123", "Ответ виден каждому")
	var view := rules.get_view(1)
	view.players[seat].last_answer = "подмена"
	check(rules.players[seat].last_answer != "подмена", "Клиентская копия не меняет хост")
	rules.external_check = true
	rules.submit(seat, "новый внешний ответ")
	check(rules.get_view(-1).players[seat].last_answer == "новый внешний ответ", "Ответ виден во время проверки")
	rules.resolve_external(int(rules.pending.no), false)
	rules._new_question(seat)
	check(rules.players[seat].last_answer == "новый внешний ответ", "Смена вопроса сохраняет ответ")
	rules.phase = "fuse"
	var answer: Dictionary = rules.question.answers[0]
	rules.submit(seat, str(answer.name))
	check(rules.players[seat].last_answer == answer.name, "Следующий верный ответ заменяет предыдущий")
	rules.new_game(players, false, 8)
	check(rules.players[seat].last_answer == "", "Новая партия очищает ответы")
	print("ПОСЛЕДНИЙ ОТВЕТ: ошибок %d" % failed)
	quit(1 if failed else 0)
