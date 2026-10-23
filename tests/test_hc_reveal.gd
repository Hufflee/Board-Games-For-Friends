extends SceneTree
## Проверка окрашивания 480 клеток: godot --headless --path . --script res://tests/test_hc_reveal.gd
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var board_script = load("res://games/hues_and_cues/ui/hc_board.gd")
	var data = load("res://games/hues_and_cues/logic/hc_data.gd")
	var style = load("res://games/hues_and_cues/ui/hc_style.gd")
	style.set_dark(false)
	var board = board_script.new()
	root.add_child(board)
	board.size = Vector2(900,520)
	board.set_process(false)
	check(is_equal_approx(board_script.REVEAL_DURATION,3.0),"Анимация должна длиться 3 секунды")
	for pattern in 3:
		board.mode = "place"
		board.play_reveal(pattern,12345)
		check(board._reveal_delays.size() == 480,"Пропущены клетки")
		check(not board.can_click(0),"Клетку можно выбрать до завершения окрашивания")
		var gray: Color = board._cell_color(0)
		for cell in 480:
			check(board.reveal_progress(cell) == 0.0,"Клетка не серая в начале")
			check(board._cell_color(cell).is_equal_approx(gray),"Начальное поле должно быть серым")
			check(board._reveal_delays[cell] >= 0.0 and board._reveal_delays[cell] <= 2.40001,"Клетка не успеет окраситься")
			if pattern == 0:
				if cell % 30 < 29:
					check(board._reveal_delays[cell] <= board._reveal_delays[cell+1],"Диагональ идёт в неправильном порядке")
				if cell < 450:
					check(board._reveal_delays[cell] <= board._reveal_delays[cell+30],"Диагональ идёт в неправильном порядке по строкам")
			if pattern == 2:
				var mirrored := (cell / 30) * 30 + 29 - cell % 30
				check(is_equal_approx(board._reveal_delays[cell],board._reveal_delays[mirrored]),"Радиальная волна несимметрична")
		if pattern == 1:
			var seen := {}
			for delay in board._reveal_delays: seen[delay] = true
			check(seen.size() == 480,"Случайный порядок содержит пропуски или одинаковые места")
		if pattern == 2:
			check(board._reveal_delays[224] < board._reveal_delays[0],"Радиальная волна должна начинаться в центре")
		board._process(1.5)
		var partial := false
		for cell in 480:
			var progress: float = board.reveal_progress(cell)
			if progress > 0.0 and progress < 1.0: partial = true
		check(partial,"В середине должен быть плавный переход цвета")
		var before: float = board._reveal_elapsed
		var transition := Node.new()
		root.add_child(transition)
		transition.add_to_group("scene_transition")
		board._process(1.0)
		check(board._reveal_elapsed == before,"Вступление проигрывается под переходом из хаба")
		transition.free()
		board.hide()
		board._process(1.0)
		check(board._reveal_elapsed == before,"Скрытое поле расходует время вступления")
		board.show()
		board._process(1.5)
		check(not board._reveal_active,"Окрашивание не завершилось за 3 секунды")
		check(board.can_click(0),"После окрашивания выбор не восстановился")
		for cell in 480:
			check(board._cell_color(cell).is_equal_approx(data.color(cell)),"Конечный цвет отличается от исходного поля")
	# Отдельный RNG: украшение не меняет случайности партии.
	seed(82731)
	var expected := randi()
	seed(82731)
	board.play_reveal(-1,31415)
	check(randi() == expected,"Анимация затрагивает игровой генератор случайных чисел")
	var variants := {}
	for sample in range(1,61):
		board.play_reveal(-1,sample)
		variants[board._reveal_pattern] = true
	check(variants.size() == 3,"Выбор не включает все три варианта")
	board.mode = "pick"
	board.card = [0,1,2,3]
	board._process(3.0)
	board._process(board_script.DIM_IN)
	check(board._cell_color(0).is_equal_approx(data.color(0)),"Цвет выбранной карты изменён")
	check(board._cell_color(4).is_equal_approx(data.color(4).lerp(Color("26272b"),0.62)),"Затемнение остальных клеток сломано")
	board.free()
	print("Окрашивание: ",checks," проверок, ошибок: ",failures)
	quit(1 if failures else 0)
