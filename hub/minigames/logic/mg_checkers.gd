
extends RefCounted
## Мини-игра «Русские шашки»: правила без UI.
## Простая ходит вперёд, бьёт вперёд и назад; дамка ходит и бьёт на любое расстояние; бить обязательно;
## серия взятий — по одному прыжку за действие (state.chain — шашка, которая обязана продолжать);
## побитые снимаются в конце хода и до этого мешают (турецкий удар); простая, дойдя до края в бою,
## сразу становится дамкой и продолжает как дамка. Место 0 — белые (внизу, ходят первыми), 1 — чёрные.
## Доска: 64 числа, индекс = ряд * 8 + столбец, ряд 0 сверху; играют тёмные поля ((ряд + столбец) нечётные).
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const W_MAN := 1
const W_KING := 2
const B_MAN := 3
const B_KING := 4
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const QUIET_LIMIT := 30  # ходов дамками подряд без взятий и ходов простых — ничья


static func new_state(_opts: Dictionary = {}) -> Dictionary:
	var board := []
	board.resize(64)
	board.fill(0)
	for r in 8:
		for c in 8:
			if (r + c) % 2 == 1:
				if r < 3:
					board[r * 8 + c] = B_MAN
				elif r > 4:
					board[r * 8 + c] = W_MAN
	return {"game": "checkers", "board": board, "turn": 0, "chain": -1, "taken": [], "quiet": 0,
		"over": false, "winner": -1, "reason": "", "last": [], "moves": 0}


static func side(piece: int) -> int:
	return -1 if piece == 0 else (0 if piece <= W_KING else 1)


static func is_king(piece: int) -> bool:
	return piece == W_KING or piece == B_KING


static func _in(r: int, c: int) -> bool:
	return r >= 0 and r < 8 and c >= 0 and c < 8


## Взятия шашки с поля sq: [{to, over}]. taken — уже побитые в этой серии (их нельзя бить второй раз).
static func _captures(board: Array, sq: int, taken: Array) -> Array:
	var out := []
	var piece := int(board[sq])
	if piece == 0:
		return out
	var color := side(piece)
	var r := sq / 8
	var c := sq % 8
	for d: Vector2i in DIAG:
		var rr := r + d.y
		var cc := c + d.x
		if is_king(piece):
			while _in(rr, cc) and int(board[rr * 8 + cc]) == 0:
				rr += d.y
				cc += d.x
		if not _in(rr, cc):
			continue
		var over := rr * 8 + cc
		var victim := int(board[over])
		if victim == 0 or side(victim) == color or taken.has(over):
			continue
		rr += d.y
		cc += d.x
		var landings := []
		while _in(rr, cc) and int(board[rr * 8 + cc]) == 0:
			landings.append(rr * 8 + cc)
			if not is_king(piece):
				break
			rr += d.y
			cc += d.x
		if is_king(piece) and landings.size() > 1:
			# дамка обязана встать на поле, с которого бой продолжается, если такое есть
			var better := []
			for to: int in landings:
				var next := board.duplicate()
				next[sq] = 0
				next[to] = piece
				if not _captures(next, to, taken + [over]).is_empty():
					better.append(to)
			if not better.is_empty():
				landings = better
		for to: int in landings:
			out.append({"to": to, "over": over})
	return out


static func _steps(board: Array, sq: int) -> Array[int]:
	var out: Array[int] = []
	var piece := int(board[sq])
	var color := side(piece)
	var r := sq / 8
	var c := sq % 8
	for d: Vector2i in DIAG:
		if not is_king(piece) and d.y != (-1 if color == 0 else 1):
			continue
		var rr := r + d.y
		var cc := c + d.x
		while _in(rr, cc) and int(board[rr * 8 + cc]) == 0:
			out.append(rr * 8 + cc)
			if not is_king(piece):
				break
			rr += d.y
			cc += d.x
	return out


static func must_capture(state: Dictionary) -> bool:
	var board: Array = state.board
	for sq in 64:
		if side(int(board[sq])) == int(state.turn) and not _captures(board, sq, state.taken).is_empty():
			return true
	return false


## Куда может пойти шашка с поля sq прямо сейчас.
static func moves_from(state: Dictionary, sq: int) -> Array[int]:
	var out: Array[int] = []
	var board: Array = state.board
	if bool(state.over) or sq < 0 or sq >= 64 or side(int(board[sq])) != int(state.turn):
		return out
	if int(state.chain) >= 0 and sq != int(state.chain):
		return out
	var captures := _captures(board, sq, state.taken)
	if not captures.is_empty():
		for capture: Dictionary in captures:
			out.append(int(capture.to))
		return out
	if int(state.chain) >= 0 or must_capture(state):
		return out
	return _steps(board, sq)


## Шашки, которыми сейчас можно (или обязательно нужно) ходить.
static func movable(state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for sq in 64:
		if not moves_from(state, sq).is_empty():
			out.append(sq)
	return out


## Одно действие: {"from": поле, "to": поле}. Серия взятий — несколько действий подряд одного игрока.
static func apply(state: Dictionary, seat: int, move: Dictionary) -> String:
	if bool(state.over):
		return "Партия окончена"
	if seat != int(state.turn):
		return "Сейчас ход соперника"
	var from := int(move.get("from", -1))
	var to := int(move.get("to", -1))
	if from < 0 or from >= 64 or not moves_from(state, from).has(to):
		return "Бить обязательно" if must_capture(state) else "Так ходить нельзя"
	var board: Array = state.board
	var piece := int(board[from])
	var over := -1
	for capture: Dictionary in _captures(board, from, state.taken):
		if int(capture.to) == to:
			over = int(capture.over)
	board[from] = 0
	if not is_king(piece) and to / 8 == (0 if seat == 0 else 7):
		piece = W_KING if seat == 0 else B_KING
	board[to] = piece
	state.last = [from, to] if int(state.chain) < 0 else (state.last as Array) + [to]
	if over >= 0:
		(state.taken as Array).append(over)
		state.quiet = 0
		if not _captures(board, to, state.taken).is_empty():
			state.chain = to
			return ""
		for square: int in state.taken:
			board[square] = 0
		state.taken = []
	else:
		state.quiet = int(state.quiet) + 1 if is_king(piece) else 0
	state.chain = -1
	state.moves = int(state.moves) + 1
	state.turn = 1 - seat
	if movable(state).is_empty():
		state.over = true
		state.winner = seat
		state.reason = "У соперника не осталось ходов"
	elif int(state.quiet) >= QUIET_LIMIT:
		state.over = true
		state.winner = 2
		state.reason = "Ничья: 15 ходов дамками без взятий"
	return ""
