
extends RefCounted
## Мини-игра «Шахматы»: полные правила без UI (ходы, шах, рокировка, взятие на проходе, превращение,
## мат, пат, 50 ходов, троекратное повторение, недостаток материала).
## Состояние — обычный словарь (его целиком пересылает хост). Место 0 — белые, 1 — чёрные.
## Доска: 64 числа, индекс = ряд * 8 + столбец, ряд 0 — восьмая горизонталь (сверху), белые внизу.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const P := 1
const N := 2
const B := 3
const R := 4
const Q := 5
const K := 6
const BLACK := 8
const KNIGHT := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const LINE := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const PROMO := {"q": Q, "r": R, "b": B, "n": N}


static func new_state(_opts: Dictionary = {}) -> Dictionary:
	var back := [R, N, B, Q, K, B, N, R]
	var board := []
	board.resize(64)
	board.fill(0)
	for c in 8:
		board[c] = BLACK + int(back[c])
		board[8 + c] = BLACK + P
		board[48 + c] = P
		board[56 + c] = int(back[c])
	return {"game": "chess", "board": board, "turn": 0, "castle": [true, true, true, true], "ep": -1, "half": 0,
		"over": false, "winner": -1, "reason": "", "last": [], "check": false, "reps": {}, "moves": 0}


static func side(piece: int) -> int:
	return -1 if piece == 0 else (1 if piece >= BLACK else 0)


static func kind(piece: int) -> int:
	return piece & 7


static func _in(r: int, c: int) -> bool:
	return r >= 0 and r < 8 and c >= 0 and c < 8


## Бьёт ли сторона by поле sq.
static func attacked(board: Array, sq: int, by: int) -> bool:
	var r := sq / 8
	var c := sq % 8
	var own := BLACK if by == 1 else 0
	var pawn_row := r + 1 if by == 0 else r - 1
	for dc: int in [-1, 1]:
		if _in(pawn_row, c + dc) and int(board[pawn_row * 8 + c + dc]) == own + P:
			return true
	for d: Vector2i in KNIGHT:
		if _in(r + d.y, c + d.x) and int(board[(r + d.y) * 8 + c + d.x]) == own + N:
			return true
	for d: Vector2i in DIAG + LINE:
		if _in(r + d.y, c + d.x) and int(board[(r + d.y) * 8 + c + d.x]) == own + K:
			return true
	for group: Array in [[DIAG, B], [LINE, R]]:
		for d: Vector2i in group[0]:
			var rr := r + d.y
			var cc := c + d.x
			while _in(rr, cc):
				var piece := int(board[rr * 8 + cc])
				if piece != 0:
					if side(piece) == by and (kind(piece) == int(group[1]) or kind(piece) == Q):
						return true
					break
				rr += d.y
				cc += d.x
	return false


static func king_square(board: Array, color: int) -> int:
	return board.find((BLACK if color == 1 else 0) + K)


static func _pseudo(state: Dictionary, sq: int) -> Array[int]:
	var board: Array = state.board
	var piece := int(board[sq])
	var out: Array[int] = []
	if piece == 0:
		return out
	var color := side(piece)
	var r := sq / 8
	var c := sq % 8
	match kind(piece):
		P:
			var step := -1 if color == 0 else 1
			var home := 6 if color == 0 else 1
			if _in(r + step, c) and int(board[(r + step) * 8 + c]) == 0:
				out.append((r + step) * 8 + c)
				if r == home and int(board[(r + 2 * step) * 8 + c]) == 0:
					out.append((r + 2 * step) * 8 + c)
			for dc: int in [-1, 1]:
				if not _in(r + step, c + dc):
					continue
				var to := (r + step) * 8 + c + dc
				var target := int(board[to])
				if (target != 0 and side(target) != color) or to == int(state.ep):
					out.append(to)
		N:
			for d: Vector2i in KNIGHT:
				if _in(r + d.y, c + d.x):
					var to := (r + d.y) * 8 + c + d.x
					if side(int(board[to])) != color:
						out.append(to)
		K:
			for d: Vector2i in DIAG + LINE:
				if _in(r + d.y, c + d.x):
					var to := (r + d.y) * 8 + c + d.x
					if side(int(board[to])) != color:
						out.append(to)
			var rights: Array = state.castle
			var row := 7 if color == 0 else 0
			if sq == row * 8 + 4 and not attacked(board, sq, 1 - color):
				if bool(rights[color * 2]) and int(board[row * 8 + 5]) == 0 and int(board[row * 8 + 6]) == 0 \
						and int(board[row * 8 + 7]) == (BLACK if color == 1 else 0) + R and not attacked(board, row * 8 + 5, 1 - color):
					out.append(row * 8 + 6)
				if bool(rights[color * 2 + 1]) and int(board[row * 8 + 3]) == 0 and int(board[row * 8 + 2]) == 0 and int(board[row * 8 + 1]) == 0 \
						and int(board[row * 8]) == (BLACK if color == 1 else 0) + R and not attacked(board, row * 8 + 3, 1 - color):
					out.append(row * 8 + 2)
		_:
			var dirs: Array = []
			if kind(piece) != R:
				dirs += DIAG
			if kind(piece) != B:
				dirs += LINE
			for d: Vector2i in dirs:
				var rr := r + d.y
				var cc := c + d.x
				while _in(rr, cc):
					var target := int(board[rr * 8 + cc])
					if target == 0:
						out.append(rr * 8 + cc)
					else:
						if side(target) != color:
							out.append(rr * 8 + cc)
						break
					rr += d.y
					cc += d.x
	return out


## Доска после хода (без проверки законности): взятие на проходе, ладья при рокировке, превращение.
static func _moved(board: Array, from: int, to: int, ep: int, promo: int) -> Array:
	var next := board.duplicate()
	var piece := int(next[from])
	var color := side(piece)
	next[from] = 0
	if kind(piece) == P and to == ep:
		next[to + (8 if color == 0 else -8)] = 0
	if kind(piece) == K and absi(to - from) == 2:
		var row := from / 8
		if to > from:
			next[row * 8 + 5] = next[row * 8 + 7]
			next[row * 8 + 7] = 0
		else:
			next[row * 8 + 3] = next[row * 8]
			next[row * 8] = 0
	if kind(piece) == P and (to / 8 == 0 or to / 8 == 7):
		piece = (BLACK if color == 1 else 0) + promo
	next[to] = piece
	return next


## Законные ходы фигуры с поля sq (для стороны, чей сейчас ход).
static func moves_from(state: Dictionary, sq: int) -> Array[int]:
	var out: Array[int] = []
	var board: Array = state.board
	if bool(state.over) or sq < 0 or sq >= 64:
		return out
	var color := side(int(board[sq]))
	if color != int(state.turn):
		return out
	for to: int in _pseudo(state, sq):
		var next := _moved(board, sq, to, int(state.ep), Q)
		if not attacked(next, king_square(next, color), 1 - color):
			out.append(to)
	return out


static func needs_promotion(state: Dictionary, from: int, to: int) -> bool:
	return kind(int(state.board[from])) == P and (to / 8 == 0 or to / 8 == 7)


static func _any_move(state: Dictionary) -> bool:
	for sq in 64:
		if side(int(state.board[sq])) == int(state.turn) and not moves_from(state, sq).is_empty():
			return true
	return false


static func _lacks_material(board: Array) -> bool:
	var minor := 0
	for piece: int in board:
		match kind(piece):
			P, R, Q:
				return false
			N, B:
				minor += 1
	return minor <= 1


static func _position_key(state: Dictionary) -> String:
	return "%s|%d|%s|%d" % [",".join(PackedStringArray((state.board as Array).map(func(x): return str(x)))), int(state.turn), str(state.castle), int(state.ep)]


## Ход: {"from": поле, "to": поле, "promo": "q"|"r"|"b"|"n"}. Возвращает "" или причину отказа.
static func apply(state: Dictionary, seat: int, move: Dictionary) -> String:
	if bool(state.over):
		return "Партия окончена"
	if seat != int(state.turn):
		return "Сейчас ход соперника"
	var from := int(move.get("from", -1))
	var to := int(move.get("to", -1))
	if from < 0 or from >= 64 or to < 0 or to >= 64 or not moves_from(state, from).has(to):
		return "Так ходить нельзя"
	var board: Array = state.board
	var piece := int(board[from])
	var captured := int(board[to]) != 0 or (kind(piece) == P and to == int(state.ep))
	var promo: int = PROMO.get(str(move.get("promo", "q")), Q)
	var rights: Array = state.castle
	if kind(piece) == K:
		rights[seat * 2] = false
		rights[seat * 2 + 1] = false
	for corner: Array in [[63, 0], [56, 1], [7, 2], [0, 3]]:
		if from == int(corner[0]) or to == int(corner[0]):
			rights[int(corner[1])] = false
	state.board = _moved(board, from, to, int(state.ep), promo)
	state.ep = (from + to) / 2 if kind(piece) == P and absi(to - from) == 16 else -1
	state.half = 0 if captured or kind(piece) == P else int(state.half) + 1
	state.last = [from, to]
	state.moves = int(state.moves) + 1
	state.turn = 1 - seat
	state.check = attacked(state.board, king_square(state.board, 1 - seat), seat)
	if not _any_move(state):
		_finish(state, seat if bool(state.check) else 2, "Мат" if bool(state.check) else "Пат — ничья")
		return ""
	if int(state.half) >= 100:
		_finish(state, 2, "Ничья: 50 ходов без взятий и пешек")
		return ""
	if _lacks_material(state.board):
		_finish(state, 2, "Ничья: мат поставить нечем")
		return ""
	var reps: Dictionary = state.reps
	var position := _position_key(state).md5_text()
	reps[position] = int(reps.get(position, 0)) + 1
	if int(reps[position]) >= 3:
		_finish(state, 2, "Ничья: позиция повторилась трижды")
	return ""


static func _finish(state: Dictionary, winner: int, reason: String) -> void:
	state.over = true
	state.winner = winner
	state.reason = reason
