extends Control
## Поле мини-игры (шахматы, шашки, го): простые фигуры, рисуется только при изменениях.
## Правила — hub/minigames/logic; ход уходит сигналом moved, окно — hub/comms_panel.gd.

signal moved(action: Dictionary)

const Chess := preload("res://hub/minigames/logic/mg_chess.gd")
const Checkers := preload("res://hub/minigames/logic/mg_checkers.gd")
const Go := preload("res://hub/minigames/logic/mg_go.gd")
const LIGHT_PIECE := Color("f1ede4")
const DARK_PIECE := Color("2c3140")
const SHAPES := {
	1: [[Vector2(0.38, 0.78), Vector2(0.45, 0.46), Vector2(0.55, 0.46), Vector2(0.62, 0.78)]],
	2: [[Vector2(0.3, 0.78), Vector2(0.38, 0.54), Vector2(0.27, 0.46), Vector2(0.34, 0.26), Vector2(0.5, 0.14), Vector2(0.55, 0.22),
		Vector2(0.7, 0.32), Vector2(0.74, 0.5), Vector2(0.6, 0.47), Vector2(0.54, 0.45), Vector2(0.66, 0.62), Vector2(0.7, 0.78)]],
	3: [[Vector2(0.36, 0.78), Vector2(0.43, 0.56), Vector2(0.57, 0.56), Vector2(0.64, 0.78)],
		[Vector2(0.5, 0.17), Vector2(0.62, 0.37), Vector2(0.56, 0.55), Vector2(0.44, 0.55), Vector2(0.38, 0.37)]],
	4: [[Vector2(0.3, 0.78), Vector2(0.34, 0.42), Vector2(0.26, 0.42), Vector2(0.26, 0.2), Vector2(0.38, 0.2), Vector2(0.38, 0.29),
		Vector2(0.45, 0.29), Vector2(0.45, 0.2), Vector2(0.55, 0.2), Vector2(0.55, 0.29), Vector2(0.62, 0.29), Vector2(0.62, 0.2),
		Vector2(0.74, 0.2), Vector2(0.74, 0.42), Vector2(0.66, 0.42), Vector2(0.7, 0.78)]],
	5: [[Vector2(0.3, 0.78), Vector2(0.22, 0.3), Vector2(0.36, 0.5), Vector2(0.42, 0.22), Vector2(0.5, 0.48), Vector2(0.58, 0.22),
		Vector2(0.64, 0.5), Vector2(0.78, 0.3), Vector2(0.7, 0.78)]],
	6: [[Vector2(0.3, 0.78), Vector2(0.26, 0.46), Vector2(0.4, 0.38), Vector2(0.6, 0.38), Vector2(0.74, 0.46), Vector2(0.7, 0.78)],
		[Vector2(0.465, 0.1), Vector2(0.535, 0.1), Vector2(0.535, 0.17), Vector2(0.6, 0.17), Vector2(0.6, 0.24), Vector2(0.535, 0.24),
		Vector2(0.535, 0.38), Vector2(0.465, 0.38), Vector2(0.465, 0.24), Vector2(0.4, 0.24), Vector2(0.4, 0.17), Vector2(0.465, 0.17)]],
}
const BASE := [Vector2(0.2, 0.9), Vector2(0.8, 0.9), Vector2(0.73, 0.78), Vector2(0.27, 0.78)]

var _session: Dictionary = {}
var _game := ""
var _state: Dictionary = {}
var _seat := 0
var _local := false
var _selected := -1
var _targets: Array[int] = []
var _hover := -1
var _promo := []  # [from, to] — ждём выбора фигуры превращения

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw())

func set_session(session: Dictionary) -> void:
	var fresh := str(session.id) != str(_session.get("id", "")) or int((session.state as Dictionary).get("moves", 0)) != int(_state.get("moves", -1))
	_session = session
	_game = str(session.game)
	_state = session.state
	_seat = int(session.seat)
	_local = bool(session.local)
	if fresh:
		_selected = -1
		_targets = []
		_promo = []
	if _game == "checkers" and int(_state.get("chain", -1)) >= 0 and _my_turn():
		_selected = int(_state.chain)
		_targets = Checkers.moves_from(_state, _selected)
	queue_redraw()

func _my_turn() -> bool:
	return not bool(_state.get("over", true)) and not bool(_session.get("gone", false)) and (_local or int(_state.turn) == _seat)

func _n() -> int:
	return int(_state.get("size", 9)) if _game == "go" else 8

func _flipped() -> bool:
	return _game != "go" and not _local and _seat == 1

## Квадрат поля внутри узла.
func _rect() -> Rect2:
	var side := floorf(minf(size.x, size.y))
	return Rect2(((size - Vector2(side, side)) * 0.5).floor(), Vector2(side, side))

func _cell_rect(sq: int) -> Rect2:
	var n := _n()
	var area := _rect()
	var cell := area.size.x / n
	var r := sq / n
	var c := sq % n
	if _flipped():
		r = n - 1 - r
		c = n - 1 - c
	return Rect2(area.position + Vector2(c * cell, r * cell), Vector2(cell, cell))

func _cell_at(point: Vector2) -> int:
	var n := _n()
	var area := _rect()
	if not area.has_point(point):
		return -1
	var cell := area.size.x / n
	var c := clampi(int((point.x - area.position.x) / cell), 0, n - 1)
	var r := clampi(int((point.y - area.position.y) / cell), 0, n - 1)
	if _flipped():
		r = n - 1 - r
		c = n - 1 - c
	return r * n + c

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := _cell_at((event as InputEventMouseMotion).position)
		if at != _hover:
			_hover = at
			if _game == "go":
				queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if not _my_turn():
		return
	if not _promo.is_empty():
		_pick_promotion(button.position)
		return
	var sq := _cell_at(button.position)
	if sq < 0:
		return
	match _game:
		"go":
			if Go.can_place(_state, sq):
				moved.emit({"at": sq})
		"chess":
			if _targets.has(sq) and _selected >= 0:
				if Chess.needs_promotion(_state, _selected, sq):
					_promo = [_selected, sq]
				else:
					moved.emit({"from": _selected, "to": sq})
					_selected = -1
					_targets = []
			else:
				_selected = sq if Chess.side(int(_state.board[sq])) == int(_state.turn) else -1
				_targets = Chess.moves_from(_state, sq) if _selected >= 0 else ([] as Array[int])
		"checkers":
			if _targets.has(sq) and _selected >= 0:
				moved.emit({"from": _selected, "to": sq})
				_selected = -1
				_targets = []
			elif int(_state.get("chain", -1)) < 0:
				_selected = sq if Checkers.side(int(_state.board[sq])) == int(_state.turn) else -1
				_targets = Checkers.moves_from(_state, sq) if _selected >= 0 else ([] as Array[int])
	queue_redraw()

func _promo_rects() -> Array:
	var area := _rect()
	var cell := area.size.x / 5.0
	var out := []
	for i in 4:
		out.append(Rect2(area.position + Vector2(cell * 0.5 + i * cell, area.size.y * 0.5 - cell * 0.5), Vector2(cell, cell)))
	return out

func _pick_promotion(point: Vector2) -> void:
	var rects := _promo_rects()
	var letters := ["q", "r", "b", "n"]
	for i in 4:
		if (rects[i] as Rect2).has_point(point):
			moved.emit({"from": int(_promo[0]), "to": int(_promo[1]), "promo": letters[i]})
			_selected = -1
			_targets = []
	_promo = []
	queue_redraw()

func _draw() -> void:
	if _state.is_empty():
		return
	match _game:
		"go":
			_draw_go()
		_:
			_draw_squares()

func _draw_squares() -> void:
	var chess := _game == "chess"
	var light := Color("d3dbe6") if chess else Color("e6dac8")
	var dark := Color("7f93ad") if chess else Color("94775c")
	var area := _rect()
	draw_rect(area.grow(3), Color(0.05, 0.06, 0.08))
	var board: Array = _state.board
	var last: Array = _state.get("last", [])
	var taken: Array = _state.get("taken", [])
	var must: Array[int] = []
	if not chess and _my_turn() and Checkers.must_capture(_state):
		must = Checkers.movable(_state)
	var check_sq := -1
	if chess and bool(_state.get("check", false)) and not bool(_state.over):
		check_sq = Chess.king_square(board, int(_state.turn))
	for sq in 64:
		var cell := _cell_rect(sq)
		var is_dark := (sq / 8 + sq % 8) % 2 == 1
		draw_rect(cell, dark if is_dark else light)
		if last.has(sq):
			draw_rect(cell, Color(1.0, 0.86, 0.3, 0.38))
		if sq == check_sq:
			draw_rect(cell, Color(0.9, 0.25, 0.25, 0.55))
		if sq == _selected:
			draw_rect(cell, Color(0.3, 0.85, 0.5, 0.45))
		var piece := int(board[sq])
		if piece != 0:
			var ghost := taken.has(sq)
			if chess:
				_draw_chess_piece(cell, piece)
			else:
				_draw_checker(cell, piece, 0.35 if ghost else 1.0)
			if must.has(sq) and sq != _selected:
				draw_arc(cell.get_center(), cell.size.x * 0.43, 0.0, TAU, 28, Color(0.3, 0.85, 0.5, 0.9), maxf(1.5, cell.size.x * 0.045), true)
	for sq: int in _targets:
		var cell := _cell_rect(sq)
		if int(board[sq]) != 0:
			draw_arc(cell.get_center(), cell.size.x * 0.44, 0.0, TAU, 28, Color(0.2, 0.75, 0.42, 0.9), maxf(2.0, cell.size.x * 0.07), true)
		else:
			draw_circle(cell.get_center(), cell.size.x * 0.16, Color(0.2, 0.75, 0.42, 0.75))
	if not _promo.is_empty():
		draw_rect(area, Color(0, 0, 0, 0.55))
		var rects := _promo_rects()
		var kinds := [Chess.Q, Chess.R, Chess.B, Chess.N]
		for i in 4:
			draw_rect(rects[i], light)
			_draw_chess_piece(rects[i], int(kinds[i]) + (Chess.BLACK if int(_state.turn) == 1 else 0))

func _draw_chess_piece(cell: Rect2, piece: int) -> void:
	var white := piece < Chess.BLACK
	var fill := LIGHT_PIECE if white else DARK_PIECE
	var edge := DARK_PIECE if white else Color("cfd5e0")
	var width := maxf(1.0, cell.size.x * 0.035)
	var shapes: Array = SHAPES[piece & 7].duplicate()
	shapes.append(BASE)
	for shape: Array in shapes:
		var points := PackedVector2Array()
		for point: Vector2 in shape:
			points.append(cell.position + point * cell.size)
		draw_colored_polygon(points, fill)
		points.append(points[0])
		draw_polyline(points, edge, width, true)
	var kind := piece & 7
	if kind == Chess.P or kind == Chess.B:
		var center := cell.position + Vector2(0.5, 0.34 if kind == Chess.P else 0.13) * cell.size
		var radius := cell.size.x * (0.14 if kind == Chess.P else 0.05)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 20, edge, width, true)
	elif kind == Chess.Q:
		for tip: Vector2 in [Vector2(0.22, 0.28), Vector2(0.42, 0.2), Vector2(0.58, 0.2), Vector2(0.78, 0.28)]:
			draw_circle(cell.position + tip * cell.size, cell.size.x * 0.045, edge)
	elif kind == Chess.N:
		draw_circle(cell.position + Vector2(0.45, 0.3) * cell.size, cell.size.x * 0.03, edge)

func _draw_checker(cell: Rect2, piece: int, alpha: float) -> void:
	var white := Checkers.side(piece) == 0
	var fill := Color(LIGHT_PIECE if white else DARK_PIECE, alpha)
	var edge := Color(DARK_PIECE if white else Color("cfd5e0"), alpha)
	var center := cell.get_center()
	var radius := cell.size.x * 0.38
	draw_circle(center + Vector2(0, cell.size.x * 0.03), radius, Color(0, 0, 0, 0.3 * alpha))
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 32, edge, maxf(1.0, cell.size.x * 0.04), true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 28, Color(edge, 0.45 * alpha), maxf(1.0, cell.size.x * 0.025), true)
	if Checkers.is_king(piece):
		# дамка — корона из трёх зубцов
		var crown := PackedVector2Array()
		for point: Vector2 in [Vector2(-0.5, 0.35), Vector2(-0.55, -0.3), Vector2(-0.22, 0.02), Vector2(0, -0.42), Vector2(0.22, 0.02), Vector2(0.55, -0.3), Vector2(0.5, 0.35)]:
			crown.append(center + point * radius * 0.8)
		draw_colored_polygon(crown, Color(Color("e0b040"), alpha))

func _draw_go() -> void:
	var n := _n()
	var area := _rect()
	draw_rect(area, Color("dcb873"))
	var cell := area.size.x / n
	var ink := Color("4f3b22")
	var first := area.position + Vector2(cell, cell) * 0.5
	var span := cell * (n - 1)
	for i in n:
		draw_line(first + Vector2(i * cell, 0), first + Vector2(i * cell, span), ink, 1.0)
		draw_line(first + Vector2(0, i * cell), first + Vector2(span, i * cell), ink, 1.0)
	var stars: Array = [2, 4, 6] if n == 9 else ([3, 6, 9] if n == 13 else [3, 9, 15])
	for sr: int in stars:
		for sc: int in stars:
			if n == 9 and (sr == 4) != (sc == 4):
				continue
			draw_circle(first + Vector2(sc * cell, sr * cell), maxf(1.5, cell * 0.09), ink)
	var board: Array = _state.board
	var last: Array = _state.get("last", [])
	for sq in board.size():
		var value := int(board[sq])
		if value == 0:
			continue
		var center := first + Vector2((sq % n) * cell, (sq / n) * cell)
		var black := value == 1
		draw_circle(center + Vector2(0, cell * 0.04), cell * 0.46, Color(0, 0, 0, 0.25))
		draw_circle(center, cell * 0.46, Color("23262e") if black else Color("f4f1ea"))
		draw_arc(center, cell * 0.46, 0.0, TAU, 24, Color("0e1014") if black else Color("b9b2a2"), 1.0, true)
		if last.has(sq):
			draw_circle(center, cell * 0.14, Color("f4f1ea") if black else Color("23262e"))
	if _hover >= 0 and _my_turn() and int(board[_hover]) == 0 and Go.can_place(_state, _hover):
		var center := first + Vector2((_hover % n) * cell, (_hover / n) * cell)
		draw_circle(center, cell * 0.44, Color(Color("23262e") if int(_state.turn) == 0 else Color("f4f1ea"), 0.5))
