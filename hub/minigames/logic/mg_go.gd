
extends RefCounted
## Мини-игра «Го»: правила без UI. Доска 9×9, 13×13 или 19×19. Место 0 — чёрные (ходят первыми), 1 — белые.
## Взятие групп без дыханий, запрет самоубийства и ко (нельзя вернуть позицию, бывшую перед ходом соперника).
## Два паса подряд заканчивают партию; счёт — по территории и камням (китайский), коми белых 6,5.
## Мёртвые камни сами не снимаются: их нужно взять до пасов.
## Доска: size*size чисел (0 пусто, 1 чёрный, 2 белый), индекс = ряд * size + столбец.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const SIZES := [9, 13, 19]
const KOMI := 6.5


static func new_state(opts: Dictionary = {}) -> Dictionary:
	var size := int(opts.get("size", 9))
	if size not in SIZES:
		size = 9
	var board := []
	board.resize(size * size)
	board.fill(0)
	return {"game": "go", "size": size, "board": board, "turn": 0, "before": [], "passes": 0, "caps": [0, 0],
		"over": false, "winner": -1, "reason": "", "last": [], "score": [0.0, 0.0], "moves": 0}


static func _neighbors(sq: int, size: int) -> Array[int]:
	var out: Array[int] = []
	var r := sq / size
	var c := sq % size
	if r > 0:
		out.append(sq - size)
	if r < size - 1:
		out.append(sq + size)
	if c > 0:
		out.append(sq - 1)
	if c < size - 1:
		out.append(sq + 1)
	return out


## Группа камня sq и есть ли у неё дыхания: {"stones": [...], "free": bool}.
static func _group(board: Array, sq: int, size: int) -> Dictionary:
	var color := int(board[sq])
	var seen := {sq: true}
	var stack: Array[int] = [sq]
	var stones: Array[int] = []
	var free := false
	while not stack.is_empty():
		var at: int = stack.pop_back()
		stones.append(at)
		for next: int in _neighbors(at, size):
			var value := int(board[next])
			if value == 0:
				free = true
			elif value == color and not seen.has(next):
				seen[next] = true
				stack.append(next)
	return {"stones": stones, "free": free}


## Доска после камня seat на поле sq. Пустой массив — ход запрещён (занято, самоубийство).
static func _placed(board: Array, sq: int, seat: int, size: int, taken: Array) -> Array:
	if sq < 0 or sq >= board.size() or int(board[sq]) != 0:
		return []
	var mine := seat + 1
	var next := board.duplicate()
	next[sq] = mine
	for near: int in _neighbors(sq, size):
		if int(next[near]) == 3 - mine:
			var group := _group(next, near, size)
			if not bool(group.free):
				for stone: int in group.stones:
					next[stone] = 0
					taken.append(stone)
	if not bool(_group(next, sq, size).free):
		return []
	return next


static func can_place(state: Dictionary, sq: int) -> bool:
	if bool(state.over):
		return false
	var next := _placed(state.board, sq, int(state.turn), int(state.size), [])
	return not next.is_empty() and next != state.before


## Ход: {"at": поле} или {"pass": true}. Возвращает "" или причину отказа.
static func apply(state: Dictionary, seat: int, move: Dictionary) -> String:
	if bool(state.over):
		return "Партия окончена"
	if seat != int(state.turn):
		return "Сейчас ход соперника"
	if bool(move.get("pass", false)):
		state.passes = int(state.passes) + 1
		state.before = []
		state.last = []
		state.moves = int(state.moves) + 1
		state.turn = 1 - seat
		if int(state.passes) >= 2:
			_score(state)
		return ""
	var sq := int(move.get("at", -1))
	var taken := []
	var next := _placed(state.board, sq, seat, int(state.size), taken)
	if next.is_empty():
		return "Сюда поставить нельзя"
	if next == state.before:
		return "Ко: сначала сходите в другое место"
	state.before = state.board
	state.board = next
	(state.caps as Array)[seat] = int(state.caps[seat]) + taken.size()
	state.passes = 0
	state.last = [sq]
	state.moves = int(state.moves) + 1
	state.turn = 1 - seat
	return ""


## Счёт по территории и камням: пустая область идёт тому, чьи камни её окружают целиком.
static func area(board: Array, size: int) -> Array:
	var points := [0.0, 0.0]
	var seen := {}
	for sq in board.size():
		var value := int(board[sq])
		if value != 0:
			points[value - 1] += 1.0
			continue
		if seen.has(sq):
			continue
		var stack: Array[int] = [sq]
		seen[sq] = true
		var count := 0
		var borders := 0
		while not stack.is_empty():
			var at: int = stack.pop_back()
			count += 1
			for next: int in _neighbors(at, size):
				var near := int(board[next])
				if near == 0:
					if not seen.has(next):
						seen[next] = true
						stack.append(next)
				else:
					borders |= near
		if borders == 1 or borders == 2:
			points[borders - 1] += float(count)
	return points


static func _score(state: Dictionary) -> void:
	var points := area(state.board, int(state.size))
	points[1] += KOMI
	state.score = points
	state.over = true
	state.winner = 0 if float(points[0]) > float(points[1]) else 1
	state.reason = "Чёрные %s · белые %s (с коми %s)" % [_num(points[0]), _num(points[1]), _num(KOMI)]


static func _num(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value).replace(".", ",")
