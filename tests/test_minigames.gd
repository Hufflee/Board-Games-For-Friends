extends SceneTree
## Тесты правил мини-игр (шахматы, русские шашки, го) — hub/minigames/logic.
## Запуск: godot --headless --path . --script res://tests/test_minigames.gd  (код выхода 1 при ошибке)

const Chess := preload("res://hub/minigames/logic/mg_chess.gd")
const Checkers := preload("res://hub/minigames/logic/mg_checkers.gd")
const Go := preload("res://hub/minigames/logic/mg_go.gd")

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
