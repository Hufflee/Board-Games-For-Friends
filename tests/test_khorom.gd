extends SceneTree
## «Хором!»: правила, очередь открытия во всех раундах, приватность вида, похожесть ответов, счёт.
## Запуск: godot --headless --path . --script res://tests/test_khorom.gd

var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)

func _init() -> void:
	_match()
	_chorus()
	_crow_and_blitz()
	_limits()
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)

func _seats(n: int) -> Array:
	var list := []
	for i: int in n:
		list.append({"name": "Игрок %d" % (i + 1)})
	return list

func _act(r: KHRules, seat: int, kind: String, extra: Dictionary = {}) -> bool:
	var payload := extra.duplicate()
	payload["revision"] = r.revision
	return r.action(seat, kind, payload, seat == 0)

func _match() -> void:
	for pair: Array in [["Кошка", "кошка"], ["ёжик", "ежик"], ["машина", "машинка"], ["собака", "собаками"],
			["горячий чай", "чаи"], ["Красная машина", "машинка"], ["телевизор", "телевизр"], ["апельсин", "апельсины!"]]:
		check(KHMatch.similar(pair[0], pair[1]), "похожи: %s ~ %s" % pair)
	for pair: Array in [["кошка", "кошмар"], ["стол", "диван и шкаф"], ["", "кот"], ["яблоко", "груша"], ["в лес", "в дом"]]:
		check(not KHMatch.similar(pair[0], pair[1]), "не похожи: %s ~ %s" % pair)

func _chorus() -> void:
	var r := KHRules.new()
	check(r.new_game(_seats(3), {"seed": 7, "rounds": 3, "timer": 90}) == "", "партия на троих")
	check(r.kind == "chorus" and r.topics.size() == 1 and r.leader == 0, "первый раунд «Хором», ведущий 0")
	check(r.time_left == 90.0, "таймер письма 90 с")
	_act(r, 0, "write", {"row": 0, "text": "  Палатка "})
	_act(r, 0, "write", {"row": 1, "text": "спальник"})
	_act(r, 1, "write", {"row": 0, "text": "палатки"})
	_act(r, 1, "write", {"row": 2, "text": "фонарь"})
	_act(r, 2, "write", {"row": 0, "text": "котелок"})
	check(r.answers[0][0] == "Палатка", "пробелы по краям обрезаны")
	var early := r.get_view(1)
	check(early.books[0].rows[0].text == "" and early.books[0].filled == 2, "чужие ответы скрыты, видно число строк")
	check(early.books[1].rows[0].text == "палатки", "свои ответы видны")
	check(_act(r, 0, "ready") and not _act(r, 0, "write", {"row": 3, "text": "x"}), "готовый не пишет")
	check(_act(r, 0, "unready") and _act(r, 0, "write", {"row": 3, "text": ""}) and _act(r, 0, "ready"), "можно передумать")
	_act(r, 1, "ready")
	check(r.phase == "write", "ждём всех")
	_act(r, 2, "ready")
	check(r.phase == "reveal" and r.turn() == 0, "все готовы — открытие, ходит ведущий")
	check(not _act(r, 1, "reveal", {"row": 0}), "не в свой ход и без совпадения — нельзя")
	check(_act(r, 0, "reveal", {"row": 0}), "ведущий открывает")
	var view1 := r.get_view(1)
	check(view1.books[0].rows[0].text == "Палатка", "открытый ответ виден всем")
	check(view1.books[1].rows[0].eye and view1.books[1].rows[0].similar, "похожий ответ подсвечен, глазик вне очереди")
	check(not view1.books[1].rows[2].eye, "непохожий — без глазика")
	check(_act(r, 1, "reveal", {"row": 0}), "открыл похожее вне очереди")
	check(r.turn() == 0, "ход всё ещё у ведущего")
	check(_act(r, 0, "mark", {"row": 0}) and _act(r, 1, "mark", {"row": 0}), "оба отметили совпадение")
	check(not _act(r, 2, "mark", {"row": 0}), "скрытый ответ не отмечается")
	check(r.score(0) == 1 and r.score(1) == 1, "по очку за совпадение")
	_act(r, 0, "reveal", {"row": 1})
	check(r.turn() == 1, "у ведущего всё открыто — ход следующему")
	check(_act(r, 1, "pass"), "передать ход")
	check(r.turn() == 2, "ход третьему")
	_act(r, 2, "reveal", {"row": 0})
	check(r.phase == "round_end", "круг пройден — конец раунда")
	check(not r.next_round(false), "следующий раунд — только хост")
	check(_act(r, 0, "next") and r.kind == "crow" and r.leader == 1, "второй раунд «Белая ворона», ведущий сменился")
	check(r.score(0) == 1 and r.answers[0][0] == "", "очки сохранены, блокнот чистый")

func _crow_and_blitz() -> void:
	var r := KHRules.new()
	r.new_game(_seats(3), {"seed": 3, "rounds": 3, "timer": 0})
	_act(r, 0, "ready"); _act(r, 1, "ready"); _act(r, 2, "ready")
	_act(r, 0, "next")
	check(r.kind == "crow" and r.time_left == 0.0, "без таймера")
	_act(r, 1, "write", {"row": 0, "text": "ворона"})
	_act(r, 1, "write", {"row": 1, "text": "сова"})
	_act(r, 2, "write", {"row": 0, "text": "Вороны"})
	for seat: int in 3:
		_act(r, seat, "ready")
	check(r.turn() == 1, "ходит новый ведущий")
	_act(r, 1, "reveal", {"row": 0})
	_act(r, 1, "reveal", {"row": 1})
	check(r.score(1) == 2, "«Белая ворона»: открытые ответы сразу дают очки")
	_act(r, 1, "mark", {"row": 0})
	check(r.score(1) == 1, "«✕» на совпавшем снимает очко")
	check(r.turn() == 2, "ведущий всё открыл — ход дальше (пустой блокнот пропущен)")
	_act(r, 2, "reveal", {"row": 0})
	check(r.phase == "round_end", "конец «Белой вороны»")
	_act(r, 0, "next")
	check(r.kind == "blitz" and r.topics.size() == 6 and r.leader == 2, "«Блиц»: шесть тем, ведущий 2")
	for seat: int in 3:
		for row: int in 6:
			if not (seat == 1 and row == 0):
				_act(r, seat, "write", {"row": row, "text": "ответ %d-%d" % [seat, row]})
	for seat: int in 3:
		_act(r, seat, "ready")
	check(r.turn() == 2 and r.blitz_row == 0, "блиц: тема 1, начинает ведущий")
	check(not _act(r, 2, "reveal", {"row": 1}), "блиц: только текущая тема")
	_act(r, 2, "reveal", {"row": 0})
	check(r.turn() == 0, "дальше по кругу")
	_act(r, 0, "reveal", {"row": 0})
	check(r.blitz_row == 1 and r.turn() == 2, "у игрока 2 пусто — тема 2, снова ведущий")
	for _i: int in 40:
		if r.phase != "reveal":
			break
		_act(r, r.turn(), "reveal", {"row": r.blitz_row})
	check(r.phase == "round_end", "блиц открыт до конца")
	_act(r, 0, "next")
	check(r.phase == "game_over", "после трёх раундов — конец")

func _limits() -> void:
	var r := KHRules.new()
	check(r.new_game(_seats(2)) != "", "двоим нельзя")
	check(r.new_game(_seats(9)) != "", "девятерым нельзя")
	r.new_game(_seats(4), {"seed": 1, "rounds": 1, "timer": 90})
	_act(r, 3, "write", {"row": 0, "text": "лишний длинный текст ".repeat(5)})
	check(r.answers[3][0].length() <= KHRules.MAX_TEXT, "длина ответа ограничена")
	check(not r.tick(10.0) and r.phase == "write", "время ещё есть")
	check(r.tick(100.0) and r.phase == "reveal" and r.turn() == 3, "время вышло — к открытию, пустые блокноты пропущены")
	_act(r, 3, "reveal", {"row": 0})
	check(r.phase == "round_end", "единственный ответ открыт — конец раунда")
	_act(r, 3, "mark", {"row": 0})
	_act(r, 0, "next")
	check(r.phase == "game_over" and r.winners == [3], "победитель — больше очков")
