extends SceneTree
## Правила28.10: границы calza/единиц/Палифико и совместимость с ботом.
## --headless --audio-driver Dummy --path . --script res://tests/test_perudo_batch28.gd
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func make() -> PerudoRules:
	var r := PerudoRules.new()
	r.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}, {"name": "Г"}], 5, true, 28)
	r.begin()
	for seat in 4:
		r.shake(seat)
	r.turn = 0
	return r

func _init() -> void:
	for special in [false, true]:
		for total in range(1, 31):
			for face in range(1, 7):
				check(PerudoRules.check_bid({}, [], special, total, 1, face) == (face != 1), "Первая ставка, включая одну кость/Палифико")
	for prev in range(1, 12):
		var old := {"q": prev, "face": 1, "seat": 0}
		for face in range(2, 7):
			for q in range(1, 31):
				check(PerudoRules.check_bid(old, [old], false, 30, q, face) == (q >= 2 * prev + 1), "С единиц ровно2q+1")
	for prev in range(1, 15):
		for face in range(2, 7):
			var old := {"q": prev, "face": face, "seat": 0}
			for q in range(1, 16):
				check(PerudoRules.check_bid(old, [old], false, 30, q, 1) == (q >= ceili(prev / 2.0)), "На единицы половина вверх")
	var r := make()
	check(not r.place_bid(0, 1, 1), "Первая единица отвергнута движком")
	check(r.place_bid(0, 5, 4), "Пять четвёрок приняты")
	check(r.can_bid(3, 1) and not r.can_bid(2, 1), "Пример владельца5 четвёрок→3 единицы")
	check(not r.can_bid(3, 3), "Оговорка не меняет обычные переходы")
	r = make()
	r.counts[2] = 4
	r.dice = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6], [2, 3, 4, 5], [3, 4, 5, 6, 6]]
	r.place_bid(0, 3, 2)
	check(r.turn == 1 and r.can_calza(2), "Живой участник2 можетcalza в ход1")
	check(not r.can_calza(0) and not r.can_calza(-1) and not r.can_calza(99), "Автор/неверные места исключены")
	check(not r.challenge(2), "Дудо по-прежнему только в свою очередь")
	check(r.get_view(2).can_calza and not r.get_view(0).can_calza, "Адресные права вview")
	check(r.get_view(2).dice[0].is_empty(), "Чужие кости скрыты доcalza")
	check(r.calza(2), "Calza вне очереди принята")
	check(r.reveal.count == 3 and r.reveal.gained == 2 and r.counts[2] == 5, "Точноеcalza возвращаеткость говорящему")
	check(r.starter == 2 and r.history.size() == 1, "Следующийраунд и история принадлежат говорящему")
	check(not r.calza(3) and r.history.size() == 1, "Второй одновременный вызов после вскрытия отвергнут")
	r = make()
	r.counts[3] = 0
	r.dice[3] = []
	r.place_bid(0, 1, 2)
	check(not r.calza(3), "Выбывший не можетcalza")
	r.counts[2] = 1
	check(r.calza(2), "Неверноеcalza живого вне очереди разрешено как риск")
	check(r.counts[2] == 0 and r.reveal.loser == 2, "Кость теряет именно ошибившийся")
	r = make()
	r.maputo = true
	r.counts = [1, 0, 0, 0]
	r.dice = [[1], [], [], []]
	check(not r.can_bid(1, 1) and r.can_bid(1, 2), "При единственнойединице остаётся перваяставка на2")
	check(PerudoBot.act(r, 0), "Бот не застревает на первомходе Палифико")
	r = make()
	r.maputo = true
	r.place_bid(0, 2, 4)
	check(not r.can_bid(3, 1) and not r.can_bid(3, 5) and r.can_bid(3, 4), "Палифико сохраняет номинал")
	r = make()
	for phase in ["seating", "roll", "reveal", "game_over"]:
		r.phase = phase
		check(not r.can_calza(2) and not r.calza(2), "Calza невозможна внеbid")
	print("PERUDO28 RULES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
