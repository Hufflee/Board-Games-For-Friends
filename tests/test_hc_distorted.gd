extends SceneTree
## Искажённые цвета: общая перестановка, скрытый от ведущего фильтр, подготовка и зоны очков.
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func make(seed_value: int, altered: bool = true, n: int = 4) -> HCRules:
	var players := []
	for i in n:
		players.append({"name": "Игрок %d" % i})
	var rules := HCRules.new()
	rules.new_game(players, 1, false, seed_value, n == 2, altered)
	return rules
func _run() -> void:
	var BoardScript = load("res://games/hues_and_cues/ui/hc_board.gd")
	var filters := {}
	for seed_value in range(1, 31):
		var rules := make(seed_value)
		filters[rules.round_filter] = true
		var same := make(seed_value)
		check(rules.color_order == same.color_order and rules.round_filter == same.round_filter, "Одинаковый seed воспроизводит поле и фильтр")
		check(rules.phase == "prepare", "Раунд начинается с подготовки")
		check(not rules.pick_color(rules.giver, rules.card[0]), "До окончания подготовки выбор запрещён")
		var unique := {}
		for color in rules.color_order:
			unique[color] = true
		check(unique.size() == 480 and rules.color_order != range(480), "Перестановка содержит все 480 оттенков")
		var view := rules.get_view(rules.giver)
		check(view["round_filter"] == rules.round_filter, "Ведущий тоже получает фильтр для вступления")
		var guesser := (rules.giver + 1) % rules.players.size()
		view = rules.get_view(guesser)
		check(view["round_filter"] == rules.round_filter, "Угадывающий получает фильтр")
		check(view["color_order"] == rules.get_view(rules.giver)["color_order"], "У всех одна перестановка")
		check(view["target"] == -1 and view["card"].is_empty(), "Новый режим сохраняет тайну ведущего")
		check(rules.finish_prepare() and not rules.finish_prepare(), "Подготовка завершается один раз")
		check(rules.pick_color(rules.giver, rules.card[0]), "После подготовки цвет выбирается")
		var old_order := rules.color_order.duplicate()
		var old_seed := rules.board_seed
		rules.skip_round()
		rules.advance()
		check(rules.phase == "prepare" and rules.board_seed != old_seed and rules.color_order != old_order, "Следующий раунд снова подготавливает новое поле")
	check(filters.size() == 4, "Все четыре фильтра встречаются")
	var center := 7 * 30 + 14
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for cell in 480:
		var points := HCRules.points_for(center, cell, true)
		counts[points] += 1
		for score in [1, 2, 3]:
			var rect := HCRules.score_rect(center, score, true)
			check((points >= score) == rect.has_point(Vector2i(cell % 30, cell / 30)), "Расчёт совпадает с нарисованной зоной")
	check(counts[3] == 4 and counts[2] == 32 and counts[1] == 64, "Точные площади зон 2×2, 6×6, 10×10")
	for corner in [0, 29, 450, 479]:
		var exact := 0
		for cell in 480:
			exact += 1 if HCRules.points_for(corner, cell, true) == 3 else 0
		check(exact == 4, "В углах центр также содержит четыре клетки")
	var rules := make(42)
	rules.finish_prepare()
	rules.target = center
	rules.pieces = [{"seat": 1, "cell": center}, {"seat": 2, "cell": center - 2}, {"seat": 3, "cell": center - 4}]
	rules._score()
	check(rules.result["details"].map(func(d): return d["pts"]) == [3, 2, 1], "Итог начисляет новые очки")
	check(rules.result["giver_points"] == 2, "Ведущий получает очки за область 6×6")
	check(rules.history[0]["color"] == rules.color_order[center], "История сохраняет исходный оттенок")
	var classic := make(42, false)
	check(classic.phase == "pick" and classic.round_filter == -1 and classic.color_order == range(480), "Классический режим сохранён")
	# Полные партии, включая кооператив, передачу ведущего и раунды переигровки.
	for n in [2, 3, 8]:
		for seed_value in range(1, 6):
			var game := make(seed_value, true, n)
			var rounds := 0
			while game.phase != "game_over" and rounds < 80:
				rounds += 1
				check(game.finish_prepare(), "Каждый раунд полной партии начинается с подготовки")
				check(game.pick_color(game.giver, game.card[0]), "Полная партия: выбор цели")
				check(game.give_cue(game.giver, "абрикос" + "а".repeat(rounds)), "Полная партия: подсказка")
				while game.current_guesser() >= 0:
					var cell := 0
					while game.occupied(cell):
						cell += 1
					check(game.place(game.current_guesser(), cell), "Полная партия: фишка")
				check(game.pass_cue(game.giver), "Полная партия: подсчёт")
				game.advance()
			check(game.phase == "game_over", "Партия и переигровки завершаются")
	var directions := {}
	for seed_value in range(1, 31):
		var game := make(seed_value)
		directions[signi(int(game.spin_turns))] = true
		check(absf(game.spin_turns) >= 6.3 and absf(game.spin_turns) <= 10.2, "Скорость движения увеличена на 50 процентов")
		check(game.color_order == HCRules.orbit_order(game.spin_start + game.spin_turns), "Правила и анимация заканчиваются одной раскладкой")
		for ring in HCRules.orbit_rings():
			var index: int = ring.find(game.color_order[ring[0]])
			for k in ring.size():
				check(game.color_order[ring[k]] == ring[(index + k) % ring.size()], "Соседние цвета кольца остаются соседями")
	check(directions.size() == 2, "Встречаются оба направления движения")
	var first_speed := HCRules.spin_progress(0.05) / 0.05
	var peak_speed := (HCRules.spin_progress(0.51) - HCRules.spin_progress(0.49)) / 0.02
	var last_speed := (1.0 - HCRules.spin_progress(0.95)) / 0.05
	check(peak_speed > first_speed * 20 and is_equal_approx(first_speed, last_speed), "Плавный разгон и симметричное торможение")
	var board = BoardScript.new()
	root.add_child(board)
	board.set_process(false)
	board.mode = "place"
	board.play_distorted_round(rules.color_order, 0, rules.board_seed, rules.spin_start, rules.spin_turns, true)
	var start: Array = HCRules.orbit_order(rules.spin_start)
	for cell in 480:
		check(board._cell_color(cell).is_equal_approx(HCData.color(start[cell])), "В начале исходные цветные клетки, без обесцвечивания")
	check(not board.can_click(0), "Анимация блокирует клики")
	board._process(HCRules.PREPARE_SECONDS * 0.25)
	check(board._display_order != start, "Цвета переходят в соседние клетки по кольцам")
	check(board._filter_amount > 0.0 and board._filter_amount < 1.0, "Фильтр плавно появляется в движении")
	board._process(HCRules.PREPARE_SECONDS * 0.25)
	check(is_equal_approx(board._filter_amount, 1.0) and board._reveal_active, "Фильтр полностью применён в середине вращения")
	var middle: Array = board._display_order.duplicate()
	board._process(0.1)
	check(board._display_order != middle and is_equal_approx(board._filter_amount, 1.0), "Цвета продолжают быстро двигаться под фильтром")
	board._process(HCRules.PREPARE_SECONDS * 0.5 - 0.1)
	check(not board._reveal_active and board.can_click(0), "После торможения можно играть")
	check(is_equal_approx(board._filter_amount, 1.0), "Ведущий видит полный фильтр до окончания анимации")
	check(board._display_order == rules.color_order, "Нет скачка раскладки при остановке")
	board._process(0.25)
	check(is_equal_approx(board._filter_amount, 1.0), "До сигнала начала игры фильтр не снимается")
	board.set_filter_view(0, true, true)
	board._process(BoardScript.FILTER_FADE * 0.5)
	check(is_equal_approx(board._filter_amount, 0.5), "После остановки фильтр ведущего исчезает плавно")
	board._process(BoardScript.FILTER_FADE * 0.5)
	for cell in 480:
		check(board._cell_color(cell).is_equal_approx(board.base_color(cell)), "У ведущего остаются чистые цвета")
	board.set_filter_view(3, false)
	board._process(BoardScript.FILTER_FADE)
	for cell in 480:
		var gray: Color = board._cell_color(cell)
		check(is_equal_approx(gray.r, gray.g) and is_equal_approx(gray.g, gray.b), "Четвёртый фильтр полностью чёрно-белый")
	board.free()
	print("Искажённые цвета: %d проверок, ошибок: %d" % [checks, failures])
	quit(1 if failures else 0)
