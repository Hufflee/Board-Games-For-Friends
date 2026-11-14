extends SceneTree
## Тесты правил мини-игр (шахматы, русские шашки, го, 4 в ряд, сапёр, шарики, звёздочки) — hub/minigames/logic.
## Запуск: godot --headless --path . --script res://tests/test_minigames.gd  (код выхода 1 при ошибке)

const Chess := preload("res://hub/minigames/logic/mg_chess.gd")
const Checkers := preload("res://hub/minigames/logic/mg_checkers.gd")
const Go := preload("res://hub/minigames/logic/mg_go.gd")
const Connect4 := preload("res://hub/minigames/logic/mg_connect4.gd")
const Mines := preload("res://hub/minigames/logic/mg_mines.gd")
const Balls := preload("res://hub/minigames/logic/mg_balls.gd")
const Stars := preload("res://hub/minigames/logic/mg_stars.gd")

var _failed := 0
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		printerr("ОШИБКА: " + msg)


## Поле по записи вроде "e4".
func sq(cell: String) -> int:
	return (8 - int(cell.substr(1, 1))) * 8 + (cell.unicode_at(0) - 97)


func play(state: Dictionary, moves: Array) -> void:
	for text: String in moves:
		var error := Chess.apply(state, int(state.turn), {"from": sq(text.substr(0, 2)), "to": sq(text.substr(2, 2))})
		check(error == "", "Шахматы: ход %s отклонён: %s" % [text, error])


func _init() -> void:
	_chess()
	_checkers()
	_go()
	_connect4()
	_mines()
	_balls()
	_stars()
	print("Мини-игры: проверок %d, ошибок %d" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _chess() -> void:
	var state := Chess.new_state()
	check(Chess.moves_from(state, sq("e2")).size() == 2, "Шахматы: у пешки e2 два хода")
	check(Chess.moves_from(state, sq("g1")).size() == 2, "Шахматы: у коня g1 два хода")
	check(Chess.apply(state, 1, {"from": sq("e7"), "to": sq("e5")}) != "", "Шахматы: чёрные не ходят первыми")
	play(state, ["f2f3", "e7e5", "g2g4", "d8h4"])
	check(bool(state.over) and int(state.winner) == 1, "Шахматы: дурацкий мат — победа чёрных")
	state = Chess.new_state()
	play(state, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "e1g1"])
	check(int(state.board[sq("g1")]) == Chess.K and int(state.board[sq("f1")]) == Chess.R, "Шахматы: короткая рокировка ставит короля и ладью")
	state = Chess.new_state()
	play(state, ["e2e4", "a7a6", "e4e5", "d7d5", "e5d6"])
	check(int(state.board[sq("d6")]) == Chess.P and int(state.board[sq("d5")]) == 0, "Шахматы: взятие на проходе снимает пешку")
	# связанная фигура не может открыть короля
	state = Chess.new_state()
	play(state, ["e2e4", "e7e5", "d1h5", "b8c6", "h5f7"])
	check(bool(state.check) and not bool(state.over), "Шахматы: шах ферзём на f7, но не мат")
	check(Chess.moves_from(state, sq("a7")).is_empty(), "Шахматы: под шахом посторонний ход запрещён")
	check(Chess.moves_from(state, sq("e8")).has(sq("f7")), "Шахматы: король может взять шахующего ферзя")
	# превращение
	state = Chess.new_state()
	(state.board as Array).fill(0)
	state.board[sq("e1")] = Chess.K
	state.board[sq("e8")] = Chess.BLACK + Chess.K
	state.board[sq("a7")] = Chess.P
	state.castle = [false, false, false, false]
	check(Chess.needs_promotion(state, sq("a7"), sq("a8")), "Шахматы: пешка на седьмой требует превращения")
	check(Chess.apply(state, 0, {"from": sq("a7"), "to": sq("a8"), "promo": "r"}) == "", "Шахматы: превращение в ладью принято")
	check(int(state.board[sq("a8")]) == Chess.R and bool(state.check), "Шахматы: на a8 ладья, чёрным шах")
	# пат
	state = Chess.new_state()
	(state.board as Array).fill(0)
	state.board[sq("h8")] = Chess.BLACK + Chess.K
	state.board[sq("f7")] = Chess.K
	state.board[sq("g5")] = Chess.Q
	state.castle = [false, false, false, false]
	check(Chess.apply(state, 0, {"from": sq("g5"), "to": sq("g6")}) == "", "Шахматы: ход ферзя принят")
	check(bool(state.over) and int(state.winner) == 2, "Шахматы: пат — ничья")


func _checkers() -> void:
	var state := Checkers.new_state()
	check(Checkers.movable(state).size() == 4, "Шашки: в начале ходят четыре белые шашки")
	check(Checkers.apply(state, 0, {"from": 40, "to": 32}) != "", "Шашки: по светлым полям и по прямой ходить нельзя")
	state = Checkers.new_state()
	(state.board as Array).fill(0)
	state.board[42] = Checkers.W_MAN
	state.board[35] = Checkers.B_MAN
	state.board[21] = Checkers.B_MAN
	state.board[56] = Checkers.W_MAN
	check(Checkers.must_capture(state), "Шашки: есть обязательное взятие")
	check(Checkers.moves_from(state, 56).is_empty(), "Шашки: при обязательном взятии другой шашкой ходить нельзя")
	check(Checkers.apply(state, 0, {"from": 42, "to": 28}) == "", "Шашки: первое взятие принято")
	check(int(state.chain) == 28 and int(state.turn) == 0 and int(state.board[35]) != 0, "Шашки: серия продолжается, побитая ещё на доске")
	check(Checkers.apply(state, 0, {"from": 28, "to": 14}) == "", "Шашки: второе взятие принято")
	check(int(state.board[35]) == 0 and int(state.board[21]) == 0, "Шашки: побитые сняты в конце хода")
	check(bool(state.over) and int(state.winner) == 0, "Шашки: у чёрных нет шашек — победа белых")
	# простая бьёт назад и становится дамкой на последнем ряду
	state = Checkers.new_state()
	(state.board as Array).fill(0)
	state.board[10] = Checkers.W_MAN
	state.board[62] = Checkers.B_MAN
	check(Checkers.apply(state, 0, {"from": 10, "to": 1}) == "", "Шашки: ход на последний ряд принят")
	check(int(state.board[1]) == Checkers.W_KING, "Шашки: простая стала дамкой")
	state = Checkers.new_state()
	(state.board as Array).fill(0)
	state.board[28] = Checkers.W_MAN
	state.board[37] = Checkers.B_MAN
	state.board[1] = Checkers.B_MAN
	check(Checkers.moves_from(state, 28).has(46), "Шашки: простая бьёт назад")
	# дамка бьёт издалека и выбирает поле за побитой
	state = Checkers.new_state()
	(state.board as Array).fill(0)
	state.board[56] = Checkers.W_KING
	state.board[35] = Checkers.B_MAN
	state.board[5] = Checkers.B_MAN
	var landings := Checkers.moves_from(state, 56)
	check(landings.has(28) and landings.has(21) and landings.has(14) and landings.has(7), "Шашки: дамка бьёт издалека и встаёт на любое поле за шашкой")


func _go() -> void:
	var state := Go.new_state({"size": 9})
	check(Go.apply(state, 0, {"at": 1}) == "", "Го: чёрные ходят первыми")
	check(Go.apply(state, 0, {"at": 2}) != "", "Го: дважды подряд ходить нельзя")
	check(Go.apply(state, 1, {"at": 0}) == "", "Го: белые ставят в угол")
	check(Go.apply(state, 0, {"at": 9}) == "", "Го: чёрные закрывают угол")
	check(int(state.board[0]) == 0 and int(state.caps[0]) == 1, "Го: камень без дыханий снят")
	check(not Go.can_place(state, 0) and Go.apply(state, 1, {"at": 0}) != "", "Го: самоубийственный ход запрещён")
	check(Go.apply(state, 1, {"pass": true}) == "" and Go.apply(state, 0, {"pass": true}) == "", "Го: два паса приняты")
	check(bool(state.over) and int(state.winner) == 0 and is_equal_approx(float(state.score[0]), 81.0), "Го: вся доска за чёрными — 81 очко")
	# ко: нельзя сразу отбить камень обратно
	state = Go.new_state({"size": 9})
	# классическое ко у края: белые берут камень, чёрным нельзя сразу отбить
	for at: int in [1, 9, 19]:
		state.board[at] = 1
	for at: int in [2, 12, 20]:
		state.board[at] = 2
	state.board[11] = 1
	state.turn = 1
	check(Go.apply(state, 1, {"at": 10}) == "", "Го: белые берут камень в ко")
	check(int(state.board[11]) == 0, "Го: камень в ко снят")
	check(Go.apply(state, 0, {"at": 11}) != "", "Го: сразу отбить ко нельзя")
	check(Go.apply(state, 0, {"at": 40}) == "" and Go.apply(state, 1, {"at": 41}) == "", "Го: ходы в стороне приняты")
	check(Go.apply(state, 0, {"at": 11}) == "", "Го: после хода в стороне ко можно отбить")


func drops(state: Dictionary, cols: Array) -> void:
	for col: int in cols:
		var error := Connect4.apply(state, int(state.turn), {"col": col})
		check(error == "", "4 в ряд: ход в столбец %d отклонён: %s" % [col, error])


func _connect4() -> void:
	var state := Connect4.new_state()
	check(Connect4.apply(state, 1, {"col": 0}) != "", "4 в ряд: жёлтые не ходят первыми")
	drops(state, [3])
	check(int(state.board[5 * 7 + 3]) == 1, "4 в ряд: шарик упал на дно столбца")
	drops(state, [3])
	check(int(state.board[4 * 7 + 3]) == 2, "4 в ряд: второй шарик лёг сверху")
	# вертикаль
	state = Connect4.new_state()
	drops(state, [0, 1, 0, 1, 0, 1, 0])
	check(bool(state.over) and int(state.winner) == 0 and (state.line as Array).size() == 4, "4 в ряд: вертикальная четвёрка — победа красных")
	check(Connect4.apply(state, 1, {"col": 2}) != "", "4 в ряд: после победы ходить нельзя")
	# горизонталь
	state = Connect4.new_state()
	drops(state, [0, 0, 1, 1, 2, 2, 3])
	check(bool(state.over) and int(state.winner) == 0, "4 в ряд: горизонтальная четвёрка")
	# диагональ (жёлтые): / снизу-слева вверх-вправо
	state = Connect4.new_state()
	drops(state, [0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3])
	check(bool(state.over) and int(state.winner) == 0, "4 в ряд: диагональная четвёрка красных")
	# полный столбец
	state = Connect4.new_state()
	drops(state, [4, 4, 4, 4, 4, 4])
	check(not Connect4.can_drop(state, 4) and Connect4.apply(state, 0, {"col": 4}) != "", "4 в ряд: в полный столбец нельзя")
	check(Connect4.apply(state, 0, {"col": 7}) != "", "4 в ряд: столбца 7 нет")
	# ничья: поле заполнено без четвёрок (столбцы парами со сдвигом)
	state = Connect4.new_state()
	var order := [0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 2, 3, 2, 3, 2, 3, 3, 2, 3, 2, 3, 2, 4, 5, 4, 5, 4, 5, 5, 4, 5, 4, 5, 4, 6, 6, 6, 6, 6, 6]
	for col: int in order:
		if bool(state.over):
			break
		Connect4.apply(state, int(state.turn), {"col": col})
	check(bool(state.over) and int(state.winner) == 2 and not (state.board as Array).has(0), "4 в ряд: полное поле без четвёрки — ничья")


func _mines() -> void:
	var state := Mines.new_state({"mode": "classic", "seed": 7})
	check(Mines.apply(state, 0, {"open": 0}) == "", "Сапёр: первая клетка открыта")
	var lay := Mines.layer(state, 0)
	check(int((lay.mine as Array).count(1)) == 40 and int(lay.mine[0]) == 0 and int(lay.mine[1]) == 0 and int(lay.mine[17]) == 0, "Сапёр: 40 мин, первая клетка и соседи без мин")
	check(int(lay.open[0]) == 1 and int(lay.num[0]) == 0 and int((lay.open as Array).count(1)) > 1, "Сапёр: пустая клетка открывает соседей")
	var closed := -1
	for sq in Mines.CELLS:
		if int(lay.open[sq]) == 0 and int(lay.mine[sq]) == 0:
			closed = sq
			break
	check(Mines.apply(state, 0, {"flag": closed}) == "" and int(lay.flag[closed]) == 1 and Mines.mines_left(state) == 39, "Сапёр: флажок уменьшает счётчик")
	check(Mines.apply(state, 0, {"open": closed}) != "", "Сапёр: клетку под флажком не открыть")
	Mines.apply(state, 0, {"flag": closed})
	# открыть все безопасные — победа
	for sq in Mines.CELLS:
		if int(lay.mine[sq]) == 0 and int(lay.open[sq]) == 0 and not bool(state.over):
			Mines.apply(state, 0, {"open": sq})
	check(bool(state.over) and int(state.winner) == 0, "Сапёр: все безопасные клетки открыты — победа")
	# мина — конец
	state = Mines.new_state({"mode": "classic", "seed": 3})
	Mines.apply(state, 0, {"open": 0})
	lay = Mines.layer(state, 0)
	var mine_sq := (lay.mine as Array).find(1)
	check(Mines.apply(state, 0, {"open": mine_sq}) == "" and bool(state.over) and int(state.winner) == -1, "Сапёр: мина — проигрыш")
	_mines_no_guess()
	_mines_chord()
	_mines_deep()


## Поле 16×16 с одной миной на (1,1) и открытой единицей в углу (0,0).
func _chord_state() -> Dictionary:
	var state := Mines.new_state({"mode": "classic", "seed": 1})
	var lay := Mines.layer(state, 0)
	lay.mine[17] = 1
	lay.count = 1
	lay.num = Mines.numbers(lay.mine)
	lay.ready = true
	lay.open[0] = 1
	return state


## Нажатие на число: флажков столько же — открываются соседи; флажок не там — мина.
func _mines_clock() -> void:
	check(Mines.clock_text(83.7) == "01:23" and Mines.clock_text(0.0) == "00:00", "Сапёр: секундомер пишется ММ:СС")
	var state := Mines.new_state({"mode": "classic", "seed": 2})
	check(not Mines.clock_running(state), "Сапёр: до первого хода секундомер стоит")
	Mines.apply(state, 0, {"open": 30})
	check(Mines.clock_running(state), "Сапёр: после первого хода секундомер идёт")
	var deep := Mines.new_state({"mode": "deep", "seed": 2})
	Mines.apply(deep, 0, {"open": 30})
	check(not Mines.clock_running(deep), "Сапёр∞: секундомера нет")


func _mines_chord() -> void:
	_mines_clock()
	var state := _chord_state()
	var lay := Mines.layer(state, 0)
	check(int(lay.num[0]) == 1, "Сапёр: в углу единица")
	check(Mines.apply(state, 0, {"open": 0}) != "" and int(lay.open[1]) == 0, "Сапёр: число без флажков вокруг ничего не открывает")
	Mines.apply(state, 0, {"flag": 17})
	check(Mines.apply(state, 0, {"open": 0}) == "", "Сапёр: нажатие на число с верным флажком принято")
	check(int(lay.open[1]) == 1 and int(lay.open[16]) == 1 and int(lay.open[17]) == 0 and not bool(state.over), "Сапёр: открылись соседи без флажка, мина под флажком осталась")
	check(Mines.apply(state, 0, {"open": 0}) != "", "Сапёр: вокруг уже всё открыто — повторное нажатие ничего не делает")
	state = _chord_state()
	lay = Mines.layer(state, 0)
	Mines.apply(state, 0, {"flag": 16})  # флажок не там
	check(Mines.apply(state, 0, {"open": 0}) == "" and bool(state.over) and int(state.winner) == -1, "Сапёр: флажок не там — нажатие на число открыло мину, проигрыш")
	check((state.boom as Array) == [0, 17], "Сапёр: взорвалась именно мина рядом с числом")
	check(Mines.apply(state, 0, {"flag": 0}) != "", "Сапёр: на открытое число флажок не ставится")


## Поле без угадывания: решатель видит 50/50, а сгенерированные поля решаются логикой от первой клетки.
func _mines_no_guess() -> void:
	var one := []
	one.resize(Mines.CELLS)
	one.fill(0)
	one[0] = 1
	check(Mines.solvable(one, 255), "Сапёр: одна мина в углу находится счётом")
	var trap := one.duplicate()
	for sq: int in [2, 18, 32, 33, 34]:
		trap[sq] = 1  # мина в углу 2×2 за стеной мин — снаружи о ней ничего не узнать
	check(not Mines.solvable(trap, 255), "Сапёр: угол за стеной мин — угадывание, решатель это видит")
	var started := Time.get_ticks_msec()
	var all_ok := true
	for seed_value in 12:
		var state := Mines.new_state({"mode": "classic", "seed": seed_value})
		var start := (seed_value * 37) % Mines.CELLS
		Mines.apply(state, 0, {"open": start})
		all_ok = all_ok and Mines.solvable(Mines.layer(state, 0).mine, start)
	var spent := Time.get_ticks_msec() - started
	print("Сапёр: 12 полей без угадывания за %d мс" % spent)
	check(all_ok, "Сапёр: все 12 сгенерированных полей решаются без угадывания")
	var deep := Mines.new_state({"mode": "deep", "seed": 4})
	Mines.apply(deep, 0, {"open": 120})
	check(Mines.solvable(Mines.layer(deep, 0).mine, 120), "Сапёр∞: первый слой тоже без угадывания")


## Бесконечный режим: слои, видимость нижнего слоя, сброс слоя флажками.
func _mines_deep() -> void:
	var state := Mines.new_state({"mode": "deep", "seed": 11})
	check(Mines.depth_at(state, 0) == 0 and int(state.depth) == 1, "Сапёр∞: сначала виден только первый слой")
	Mines.apply(state, 0, {"open": 0})
	var top := Mines.layer(state, 0)
	check(int(top.num[0]) == 0 and Mines.depth_at(state, 0) == 1, "Сапёр∞: под пустой открытой клеткой виден второй слой")
	check(int(state.depth) == 1, "Сапёр∞: заглянуть на второй слой — ещё не глубина 2")
	check(not bool(Mines.layer(state, 1).ready), "Сапёр∞: мины второго слоя ещё не расставлены")
	# клетка с числом, у которой открыты не все безопасные соседи — нижний слой не виден
	var lay := {"cleared": false, "mine": [], "num": [], "open": [], "flag": []}
	for key: String in ["mine", "num", "open", "flag"]:
		(lay[key] as Array).resize(Mines.CELLS)
		(lay[key] as Array).fill(0)
	lay.mine[2] = 1
	lay.num[1] = 1
	lay.open[1] = 1
	check(not Mines.see_through(lay, 1), "Сапёр∞: число с закрытыми безопасными соседями не прозрачно")
	for near: int in Mines.neighbors(1):
		if near != 2:
			lay.open[near] = 1
	check(not Mines.see_through(lay, 1), "Сапёр∞: безопасные соседи открыты, но мина рядом без флажка — число остаётся")
	lay.flag[2] = 1
	check(Mines.see_through(lay, 1), "Сапёр∞: безопасные соседи открыты и мина под флажком — число прозрачно")
	check(not Mines.see_through(lay, 2), "Сапёр∞: мина не прозрачна")
	# слои независимы: мины второго слоя свои
	var under := 0
	for sq in Mines.CELLS:
		if Mines.depth_at(state, sq) == 1:
			under = sq
			break
	check(Mines.apply(state, 0, {"open": under}) == "", "Сапёр∞: клетка второго слоя открыта")
	var second := Mines.layer(state, 1)
	check(bool(second.ready) and int((second.mine as Array).count(1)) == Mines.mines_for(1, "deep"), "Сапёр∞: на втором слое свои мины (%d)" % Mines.mines_for(1, "deep"))
	check(second.mine != top.mine, "Сапёр∞: мины слоёв различаются")
	check(int(second.mine[under]) == 0 and int(second.open[under]) == 1, "Сапёр∞: первая клетка нового слоя без мины")
	var deep_rng_mines := 0
	var deep_solvable := true
	for probe_seed in 6:
		var probe := Mines.new_state({"mode": "deep", "seed": probe_seed})
		Mines._generate(probe, 3, 100)
		var lay3 := Mines.layer(probe, 3)
		for near: int in Mines.neighbors(100):
			deep_rng_mines += int(lay3.mine[near])
		deep_solvable = deep_solvable and Mines.solvable(lay3.mine, 100)
	check(deep_rng_mines == 0, "Сапёр∞: на нижних слоях первый клик тоже пустой — открывается область")
	check(deep_solvable, "Сапёр∞: нижние слои тоже решаются без угадывания")
	check(Mines.mines_for(30, "deep") == Mines.MAX_DEEP_MINES, "Сапёр∞: мин на слое не больше %d" % Mines.MAX_DEEP_MINES)
	# флажки ровно на всех минах первого слоя — слой сбрасывается
	var left_before := Mines.mines_left(state)
	check(left_before == 40, "Сапёр∞: счётчик верхнего слоя — 40")
	var spare := -1
	for sq in Mines.CELLS:
		if int(top.mine[sq]) == 0 and int(top.open[sq]) == 0 and Mines.depth_at(state, sq) == 0:
			spare = sq
			break
	Mines.apply(state, 0, {"flag": spare})
	for sq in Mines.CELLS:
		if int(top.mine[sq]) == 1:
			Mines.apply(state, 0, {"flag": sq})
	check(not bool(top.cleared) and Mines.mines_left(state) == -1, "Сапёр∞: лишний флажок — слой не сбрасывается, счётчик −1")
	Mines.apply(state, 0, {"flag": spare})
	check(bool(top.cleared) and Mines.top_layer(state) == 1, "Сапёр∞: флажки ровно на минах — слой сброшен, верхний теперь второй")
	check(int(state.depth) == 2, "Сапёр∞: первый слой пройден — глубина 2")
	check(Mines.depth_at(state, spare) >= 1, "Сапёр∞: после сброса везде виден нижний слой")
	check(Mines.mines_left(state) == Mines.mines_for(1, "deep"), "Сапёр∞: счётчик показывает мины второго слоя")
	# мина на глубине — сразу конец, счёт — глубина
	var mine_sq := -1
	for sq in Mines.CELLS:
		if int(second.mine[sq]) == 1 and Mines.depth_at(state, sq) == 1 and int(second.flag[sq]) == 0:
			mine_sq = sq
			break
	check(mine_sq >= 0 and Mines.apply(state, 0, {"open": mine_sq}) == "" and bool(state.over), "Сапёр∞: мина на втором слое — конец")
	check(int(state.depth) == 2 and str(state.reason).contains("Глубина 2"), "Сапёр∞: итог — глубина 2 (второй слой не пройден)")
	# слой проходится и открытием всех клеток без мин
	state = Mines.new_state({"mode": "deep", "seed": 21})
	Mines.apply(state, 0, {"open": 0})
	top = Mines.layer(state, 0)
	for sq in Mines.CELLS:
		if int(top.mine[sq]) == 0 and int(top.open[sq]) == 0:
			top.open[sq] = 1  # как будто игрок открыл всё сам
	Mines.apply(state, 0, {"flag": (top.mine as Array).find(1)})
	Mines.apply(state, 0, {"flag": (top.mine as Array).find(1)})  # флажок туда и обратно — повод пересчитать
	check(bool(top.cleared) and int(state.depth) == 2, "Сапёр∞: открыты все клетки без мин — слой пройден, глубина 2")


func _balls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var state := Balls.new_state()
	Balls.join(state, 2, "Аня", 0, rng)
	Balls.join(state, 3, "Боря", 1, rng)
	check((state.balls as Dictionary).size() == 2, "Шарики: двое в комнате")
	var a: Dictionary = state.balls[2]
	var b: Dictionary = state.balls[3]
	# Аня разгоняется в Борю у края — Боря вылетает, очко Ане
	a.pos = Vector2(0.55, 0.0)
	b.pos = Vector2(0.72, 0.0)
	a.vel = Vector2(1.6, 0.0)
	b.vel = Vector2.ZERO
	var outs := []
	for i in 90:
		for event: Dictionary in Balls.step(state, 1.0 / 30.0, rng):
			if str(event.kind) == "out":
				outs.append(event)
		if not outs.is_empty():
			break
	check(outs.size() == 1 and int(outs[0].peer) == 3 and int(outs[0].by) == 2, "Шарики: Боря вытолкнут Аней")
	check(int(a.score) == 1 and not bool(b.alive), "Шарики: очко Ане, Боря ждёт появления")
	for i in int(Balls.RESPAWN * 30.0) + 2:
		Balls.step(state, 1.0 / 30.0, rng)
	check(bool(b.alive) and (b.pos as Vector2).length() < 0.6, "Шарики: Боря снова на арене")
	# сам укатился — очков никому
	b.pos = Vector2(0.0, 0.95)
	b.vel = Vector2(0.0, 1.0)
	b.hit_by = 0
	for i in 10:
		Balls.step(state, 1.0 / 30.0, rng)
	check(int(a.score) == 1 and int(b.score) == 0, "Шарики: сам укатился — очков никому")
	# рывок с перезарядкой
	for i in 60:
		Balls.step(state, 1.0 / 30.0, rng)
	Balls.steer(state, 2, Vector2(0.5, 0.5), true)
	check(Balls.dash(state, 2) and not Balls.dash(state, 2), "Шарики: рывок, повторный — только после перезарядки")
	state.time = 180.0
	Balls.step(state, 0.05, rng)
	check(int(a.score) == 1, "Сумо: время не сбрасывает серию")
	a.pos = Vector2(1.2, 0)
	Balls.step(state, 0.05, rng)
	check(int(a.score) == 0, "Сумо: вылет сбрасывает серию")
	Balls.leave(state, 3)
	var snap := Balls.snapshot(state)
	check((snap.list as Array).size() == 1 and int(snap.list[0][0]) == 2, "Шарики: вышедший пропал из снимка")
	_balls_ghost()


## Курсор ушёл с поля — через секунду призрак; вернулся — 1,5 с проявляется, всё это время без столкновений.
func _balls_ghost() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var state := Balls.new_state()
	Balls.join(state, 2, "Аня", 0, rng)
	Balls.join(state, 3, "Боря", 1, rng)
	var a: Dictionary = state.balls[2]
	var b: Dictionary = state.balls[3]
	Balls.steer(state, 2, Vector2.ZERO, true)
	Balls.steer(state, 3, Vector2.ZERO, true)
	Balls.steer(state, 2, Vector2.ZERO, false)  # курсор Ани ушёл с поля
	for i in 15:
		Balls.step(state, 1.0 / 30.0, rng)
	check(not Balls.intangible(a, float(state.time)), "Шарики: через полсекунды без курсора ещё не призрак")
	for i in 20:
		Balls.step(state, 1.0 / 30.0, rng)
	check(Balls.intangible(a, float(state.time)) and is_equal_approx(Balls.opacity(a, float(state.time)), Balls.GHOST_ALPHA), "Шарики: через секунду — полупрозрачный призрак")
	# Боря влетает в призрака — проходит насквозь
	Balls.steer(state, 3, Vector2.ZERO, false)
	b.off_at = float(state.time)
	a.pos = Vector2(0.0, 0.0)
	a.vel = Vector2.ZERO
	b.pos = Vector2(-0.3, 0.0)
	b.vel = Vector2(1.2, 0.0)
	for i in 12:
		Balls.step(state, 1.0 / 30.0, rng)
	check((a.vel as Vector2).length() < 0.001 and int(a.hit_by) == 0 and (b.pos as Vector2).x > 0.0, "Шарики: призрака нельзя толкнуть — Боря пролетел насквозь")
	# курсор вернулся: шарик сразу едет, но 1,5 с проявляется и безвреден
	Balls.steer(state, 3, Vector2.ZERO, true)
	b.off_at = -100.0
	Balls.steer(state, 2, Vector2(0.8, 0.0), true)
	var woke := float(state.time)
	check(is_equal_approx(float(a.wake_at), woke), "Шарики: возвращение курсора запускает проявление")
	Balls.step(state, 1.0 / 30.0, rng)
	check((a.vel as Vector2).x > 0.0, "Шарики: после возвращения шарик сразу едет")
	for i in 20:
		Balls.step(state, 1.0 / 30.0, rng)
	var mid := Balls.opacity(a, float(state.time))
	check(mid > Balls.GHOST_ALPHA and mid < 1.0 and Balls.intangible(a, float(state.time)), "Шарики: проявляется постепенно и ещё неуязвим")
	b.pos = (a.pos as Vector2) + Vector2(Balls.RADIUS, 0.0)
	b.vel = Vector2.ZERO
	b.hit_by = 0
	Balls.step(state, 1.0 / 30.0, rng)
	check(int(b.hit_by) == 0, "Шарики: проявляющийся шарик никого не толкает")
	for i in 30:
		Balls.step(state, 1.0 / 30.0, rng)
	check(not Balls.intangible(a, float(state.time)) and is_equal_approx(Balls.opacity(a, float(state.time)), 1.0), "Шарики: через 1,5 с снова обычный")
	b.pos = (a.pos as Vector2) + Vector2(Balls.RADIUS, 0.0)
	Balls.step(state, 1.0 / 30.0, rng)
	check(int(b.hit_by) == 2, "Шарики: проявившийся шарик снова толкается")
	# короткий уход курсора (меньше секунды) — без призрака и без проявления
	Balls.steer(state, 2, Vector2.ZERO, false)
	Balls.step(state, 0.5, rng)
	Balls.steer(state, 2, Vector2.ZERO, true)
	check(not Balls.intangible(a, float(state.time)), "Шарики: курсор ушёл на полсекунды — шарик остался обычным")
	var row: Array = (Balls.snapshot(state).list as Array)[0]
	check(row.size() >= 9, "Шарики: прозрачность едет в снимке")
	# посерел до конца — инерция пропадает сразу
	a.pos = Vector2.ZERO
	a.vel = Vector2(0.6, 0.0)
	Balls.steer(state, 2, Vector2.ZERO, false)
	for i in 29:
		Balls.step(state, 1.0 / 30.0, rng)
	check((a.vel as Vector2).length() > 0.0, "Шарики: пока не посерел до конца, шарик катится")
	for i in 3:
		Balls.step(state, 1.0 / 30.0, rng)
	check((a.vel as Vector2).length() == 0.0, "Шарики: посерел до конца — инерция пропала мгновенно")
	# начался ход игрока — сразу призрак и стоп
	Balls.steer(state, 2, Vector2(0.5, 0.0), true)
	for i in 60:
		Balls.step(state, 1.0 / 30.0, rng)
	check(not Balls.intangible(a, float(state.time)) and (a.vel as Vector2).length() > 0.0, "Шарики: снова обычный и едет")
	Balls.force_ghost(state, 2)
	check(is_equal_approx(Balls.opacity(a, float(state.time)), Balls.GHOST_ALPHA) and (a.vel as Vector2).length() == 0.0, "Шарики: свой ход — шарик мгновенно серый и стоит")
	Balls.steer(state, 2, Vector2(0.5, 0.0), true)
	check(Balls.intangible(a, float(state.time)) and is_equal_approx(float(a.wake_at), float(state.time)), "Шарики: после хода курсор вернулся — шарик проявляется 1,5 с")


func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var state := Stars.new_state()
	check(not Stars.step(state, 10.0, rng), "Звёздочки: в пустой комнате звёзд нет")
	Stars.join(state, 2, "Аня", 0)
	Stars.join(state, 3, "Боря", 1)
	var spawned := false
	for i in 400:
		if Stars.step(state, 0.05, rng):
			spawned = true
			break
	var star: Dictionary = state.star
	check(spawned and not star.is_empty(), "Звёздочки: звезда появилась")
	check(float(star.x) >= Stars.EDGE and float(star.x) <= 1.0 - Stars.EDGE and float(star.y) >= Stars.EDGE, "Звёздочки: звезда не у самого края экрана")
	var id := int(star.id)
	check(not Stars.catch_star(state, 2, id + 1, rng), "Звёздочки: чужой номер звезды не засчитан")
	check(Stars.catch_star(state, 3, id, rng), "Звёздочки: Боря поймал первым")
	check(not Stars.catch_star(state, 2, id, rng), "Звёздочки: Аня опоздала")
	check(int(state.players[3].score) == 1 and int(state.players[2].score) == 0, "Звёздочки: очко только первому")
	# непойманная звезда улетает
	for i in 400:
		if Stars.step(state, 0.05, rng) and not (state.star as Dictionary).is_empty():
			break
	Stars.step(state, Stars.LIFE + 0.1, rng)
	check((state.star as Dictionary).is_empty() and str(state.last).contains("улетела"), "Звёздочки: непойманная звезда улетает")
	Stars.leave(state, 3)
	check((Stars.snapshot(state).list as Array).size() == 1, "Звёздочки: вышедший пропал из таблицы")
