extends RefCounted
## Мини-игра «4 в ряд»: правила без UI. Поле 7 столбцов × 6 рядов, место 0 — красные (ходят первыми), 1 — жёлтые.
## Ход — выбор столбца: шарик падает вниз до первой свободной ячейки. Четыре своих подряд по горизонтали,
## вертикали или диагонали — победа; поле заполнено без четвёрки — ничья (winner = 2).
## Доска: 42 числа (0 пусто, 1 красный, 2 жёлтый), индекс = ряд * 7 + столбец, ряд 0 — верхний.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const COLS := 7
const ROWS := 6


static func new_state(_opts: Dictionary = {}) -> Dictionary:
	var board := []
	board.resize(COLS * ROWS)
	board.fill(0)
	return {"game": "connect4", "board": board, "turn": 0, "over": false, "winner": -1, "reason": "",
		"last": [], "line": [], "moves": 0}


## Ряд, куда упадёт шарик в столбце col; -1 — столбец полон или его нет.
static func drop_row(board: Array, col: int) -> int:
	if col < 0 or col >= COLS:
		return -1
	for row in range(ROWS - 1, -1, -1):
		if int(board[row * COLS + col]) == 0:
			return row
	return -1


static func can_drop(state: Dictionary, col: int) -> bool:
	return not bool(state.over) and drop_row(state.board, col) >= 0


## Ход: {"col": столбец}. Возвращает "" или причину отказа.
static func apply(state: Dictionary, seat: int, move: Dictionary) -> String:
	if bool(state.over):
		return "Партия окончена"
	if seat != int(state.turn):
		return "Сейчас ход соперника"
	var col := int(move.get("col", -1))
	var row := drop_row(state.board, col)
	if row < 0:
		return "Этот столбец заполнен"
	var at := row * COLS + col
	state.board[at] = seat + 1
	state.last = [at]
	state.moves = int(state.moves) + 1
	var line := four_at(state.board, at)
	if not line.is_empty():
		state.over = true
		state.winner = seat
		state.line = line
		state.reason = "Четыре в ряд"
	elif not (state.board as Array).has(0):
		state.over = true
		state.winner = 2
		state.reason = "Поле заполнено — ничья"
	else:
		state.turn = 1 - seat
	return ""


## Клетки четвёрки (или длиннее), проходящей через ячейку at; пусто — четвёрки нет.
static func four_at(board: Array, at: int) -> Array:
	var color := int(board[at])
	if color == 0:
		return []
	var r0 := at / COLS
	var c0 := at % COLS
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var cells := [at]
		for sign: int in [1, -1]:
			var r := r0 + dir.y * sign
			var c := c0 + dir.x * sign
			while r >= 0 and r < ROWS and c >= 0 and c < COLS and int(board[r * COLS + c]) == color:
				cells.append(r * COLS + c)
				r += dir.y * sign
				c += dir.x * sign
		if cells.size() >= 4:
			cells.sort()
			return cells
	return []
