extends "res://hub/float_panel.gd"
## Окно мини-игр (шахматы, шашки, го): вкладки партий сверху, «+» — новая партия и приглашения.
## Двигается и сворачивается как чат; при наведении на поле вырастает до двух размеров чата и
## возвращается на место, когда курсор уходит (выключается в «Настройки → Геймплей»).
## Данные и сеть — hub/minigames/mg_net.gd (Net.minigames). Окно одно на всю игру, живёт в своём слое.

const ICONS := {"chess": "♙", "checkers": "◉", "go": "○"}
const SIDE_NAMES := {"chess": ["белые", "чёрные"], "checkers": ["белые", "чёрные"], "go": ["чёрные", "белые"]}

var _mg: Node
var _view: Control
var _board: Board
var _status: Label
var _notice: Label
var _pick_game := "chess"
var _pick_size := 9
var _shown := "?"
var _resign_armed := false


func _ready() -> void:
	_mg = Net.minigames
	key = "minigames"
	title = "Мини-игры"
	base_size = Vector2(340, 330)  # как у чата: при наведении — вдвое больше
	scale_content = false
	mode = Mode.CLOSED
	default_place = func(rect_size: Vector2, parent_size: Vector2) -> Vector2:
		return Vector2(14, maxf(TopBar.HEIGHT + 8, parent_size.y - rect_size.y - 64))
	super._ready()
	tab_selected.connect(func(id: String): _mg.select(id))
	tab_closed.connect(func(id: String): _mg.close(id))
	mode_changed.connect(_sync)
	_mg.changed.connect(_sync)
	_mg.notice.connect(_say)
	_sync()


func open() -> void:
	set_mode(Mode.OPEN)


func toggle() -> void:
	set_mode(Mode.CLOSED if mode == Mode.OPEN else Mode.OPEN)


## Что-то случилось (ход соперника, приглашение): закрытое окно показывается свёрнутой кнопкой с точкой.
func attention() -> void:
	if mode == Mode.CLOSED:
		set_mode(Mode.MINI)
	_sync()


func watching(id: String) -> bool:
	return mode == Mode.OPEN and str(_mg.current) == id and is_visible_in_tree()


func _fill_header() -> void:
	var add := small_button("+", "Новая партия и приглашения")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func(): _mg.select(""))
	header_extra.add_child(add)


func _build_body() -> void:
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 12)
	_notice.add_theme_color_override("font_color", Color("f0b86a"))
	_notice.add_theme_stylebox_override("normal", flat(Color(0.05, 0.06, 0.08, 0.92), 6, 6))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	_notice.z_index = 2
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_notice)


func _process(delta: float) -> void:
	hover_zoom_on = bool(Prefs.get("minigame_zoom")) if Prefs.get("minigame_zoom") != null else true
	super._process(delta)
	if mode == Mode.OPEN and _notice.visible:
		_notice.position = Vector2(8, body.size.y - _notice.size.y - 8)
		_notice.size.x = body.size.x - 16


func _say(text: String) -> void:
	if mode != Mode.OPEN:
		return
	_notice.text = text
	_notice.visible = true
	_notice.reset_size()
	var stamp := Time.get_ticks_msec()
	_notice.set_meta("stamp", stamp)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(_notice) and int(_notice.get_meta("stamp", 0)) == stamp:
			_notice.visible = false)


# --- Вкладки и содержимое ------------------------------------------------------------------

func _sync() -> void:
	if not _built:
		return
	var list := []
	for id: String in _mg.order:
		var session: Dictionary = _mg.sessions[id]
		var rival := "за обоих" if bool(session.local) else str((session.names as Array)[1 - int(session.seat)])
		list.append({"id": id, "text": "%s %s" % [ICONS.get(session.game, ""), rival], "closable": true, "dot": bool(session.dot),
			"tip": "%s · %s" % [_mg.title(str(session.game)), rival]})
	var current := str(_mg.current)
	if mode == Mode.OPEN and _mg.sessions.has(current) and bool(_mg.sessions[current].dot):
		_mg.sessions[current].dot = false
		list[_mg.order.find(current)].dot = false
	set_tabs(list, current)
	mini_dot = int(_mg.dots()) > 0
	hover_zoom = base_size * 2.0 if _mg.sessions.has(current) else Vector2.ZERO
	if mode != Mode.OPEN:
		_apply()
		return
	if current == "":
		_show_lobby()
	else:
		_show_session(current)


func _clear_view() -> void:
	if is_instance_valid(_view):
		body.remove_child(_view)
		_view.queue_free()
	_view = null
	_board = null
	_status = null


func _text(text: String, font: int = 13, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _action(text: String, tip: String, primary: bool = false) -> Button:
	var b := small_button(text, tip)
	b.add_theme_color_override("font_color", Color(0.06, 0.08, 0.11) if primary else INK)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.08, 0.11) if primary else Color.WHITE)
	b.add_theme_stylebox_override("normal", flat(ACCENT if primary else BG_SOFT, 6, 6))
	b.add_theme_stylebox_override("hover", flat(ACCENT.lightened(0.15) if primary else BG_SOFT.lightened(0.12), 6, 6))
	b.add_theme_stylebox_override("pressed", flat(ACCENT.darkened(0.15) if primary else BG_SOFT.darkened(0.15), 6, 6))
	return b


func _toggle_button(text: String, on: bool) -> Button:
	var b := _action(text, "")
	if on:
		b.add_theme_stylebox_override("normal", flat(Color(ACCENT, 0.3), 6, 6, ACCENT))
	return b


func _show_lobby() -> void:
	_shown = ""
	_clear_view()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10
	scroll.offset_top = 8
	scroll.offset_right = -6
	scroll.offset_bottom = -8
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_view = scroll
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	for invite: Dictionary in _mg.invites_in:
		var row := HBoxContainer.new()
		var id := str(invite.id)
		var line := _text("%s зовёт: %s" % [str(invite.name), _mg._game_line(str(invite.game), invite.opts)])
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var yes := _action("Играть", "", true)
		yes.pressed.connect(func(): _mg.answer(id, true))
		row.add_child(yes)
		var no := _action("Нет", "Отказаться")
		no.pressed.connect(func(): _mg.answer(id, false))
		row.add_child(no)
		col.add_child(row)
	for invite: Dictionary in _mg.invites_out:
		var row := HBoxContainer.new()
		var id := str(invite.id)
		var line := _text("Ждём ответа: %s · %s" % [str(invite.name), _mg.title(str(invite.game))], 12, MUTED)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var cancel := _action("Отозвать", "")
		cancel.pressed.connect(func(): _mg.cancel_invite(id))
		row.add_child(cancel)
		col.add_child(row)
	col.add_child(_text("НОВАЯ ПАРТИЯ", 11, MUTED))
	var games := HBoxContainer.new()
	games.add_theme_constant_override("separation", 6)
	for game: String in _mg.GAMES:
		var b := _toggle_button("%s %s" % [ICONS[game], _mg.title(game)], game == _pick_game)
		b.pressed.connect(func():
			_pick_game = game
			_show_lobby())
		games.add_child(b)
	col.add_child(games)
	if _pick_game == "go":
		var sizes := HBoxContainer.new()
		sizes.add_theme_constant_override("separation", 6)
		sizes.add_child(_text("Доска:", 12, MUTED))
		for board_size: int in [9, 13, 19]:
			var b := _toggle_button("%d×%d" % [board_size, board_size], board_size == _pick_size)
			b.pressed.connect(func():
				_pick_size = board_size
				_show_lobby())
			sizes.add_child(b)
		col.add_child(sizes)
	var opts := {"size": _pick_size} if _pick_game == "go" else {}
	var targets: Array = _mg.targets()
	if targets.is_empty():
		col.add_child(_text("Позвать некого: в пати пока только вы. Времени на ход нет, партия один на один.", 12, MUTED))
	else:
		col.add_child(_text("Кого позвать (один на один, без времени на ход):", 12, MUTED))
		var people := HFlowContainer.new()
		people.add_theme_constant_override("h_separation", 6)
		people.add_theme_constant_override("v_separation", 6)
		for target: Dictionary in targets:
			var peer := int(target.peer)
			var b := _action(str(target.name), "Пригласить")
			b.add_theme_color_override("font_color", Net.color_of(int(target.color)).lightened(0.35))
			b.pressed.connect(func(): _mg.invite(peer, _pick_game, opts))
			people.add_child(b)
		col.add_child(people)
	var solo := _action("Играть за обоих на этом компьютере", "Партия без сети: ходите за обе стороны по очереди")
	solo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	solo.pressed.connect(func(): _mg.start_local(_pick_game, opts))
	col.add_child(solo)


func _show_session(id: String) -> void:
	var session: Dictionary = _mg.sessions[id]
	if _shown != id or _board == null:
		_shown = id
		_resign_armed = false
		_clear_view()
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 8
		col.offset_right = -8
		col.offset_top = 4
		col.offset_bottom = -8
		col.add_theme_constant_override("separation", 4)
		body.add_child(col)
		_view = col
		var bar := HBoxContainer.new()
		bar.name = "Bar"
		bar.add_theme_constant_override("separation", 4)
		col.add_child(bar)
		_status = Label.new()
		_status.add_theme_font_size_override("font_size", 12)
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status.clip_text = true
		_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bar.add_child(_status)
		_board = Board.new()
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.moved.connect(func(action: Dictionary): _mg.move(id, action))
		col.add_child(_board)
	_board.set_session(session)
	var state: Dictionary = session.state
	var seat := int(session.seat)
	var sides: Array = SIDE_NAMES[session.game]
	var over := bool(state.over)
	var my_turn := bool(session.local) or int(state.turn) == seat
	var text := ""
	var color := INK
	if over:
		var winner := int(state.winner)
		if winner == 2:
			text = str(state.reason)
		elif bool(session.local):
			text = "Победили %s. %s" % [sides[winner], str(state.reason)]
		else:
			text = ("Вы победили! " if winner == seat else "Вы проиграли. ") + str(state.reason)
			color = Color("8fd694") if winner == seat else Color("e59a9a")
	elif bool(session.gone):
		text = "Соперник закрыл партию"
		color = MUTED
	elif bool(session.local):
		text = "Ход: %s" % sides[int(state.turn)]
	else:
		text = ("Ваш ход · вы %s" % sides[seat]) if my_turn else ("Ходит соперник · вы %s" % sides[seat])
		color = ACCENT.lightened(0.2) if my_turn else MUTED
	if not over and str(session.game) == "chess" and bool(state.get("check", false)):
		text += " · шах"
	if str(session.game) == "go" and not over:
		text += " · взято %d : %d" % [int(state.caps[0]), int(state.caps[1])]
	_status.text = text
	_status.tooltip_text = text
	_status.add_theme_color_override("font_color", color)
	# кнопки партии пересобираем по состоянию
	var bar := _view.get_node("Bar") as HBoxContainer
	for child: Node in bar.get_children():
		if child != _status:
			bar.remove_child(child)
			child.queue_free()
	var playing := not over and not bool(session.gone)
	if playing and str(session.game) == "go":
		var pass_btn := small_button("Пас", "Пропустить ход. Два паса подряд — конец партии и подсчёт")
		pass_btn.disabled = not my_turn
		pass_btn.pressed.connect(func(): _mg.move(id, {"pass": true}))
		bar.add_child(pass_btn)
	if playing and not bool(session.local):
		var resign := small_button("Точно сдаться?" if _resign_armed else "Сдаться", "Признать поражение")
		resign.pressed.connect(func():
			if _resign_armed:
				_mg.move(id, {"resign": true})
			else:
				_resign_armed = true
				_show_session(id))
		bar.add_child(resign)
	if over or bool(session.gone):
		var again := small_button("Ещё раз", "Начать новую партию с тем же соперником")
		again.add_theme_color_override("font_color", ACCENT)
		again.pressed.connect(func():
			if bool(session.local):
				_mg.close(id)
				_mg.start_local(str(session.game), session.opts)
			else:
				_mg.invite(int((session.peers as Array)[1 - seat]), str(session.game), session.opts))
		bar.add_child(again)


## Поле мини-игры: простые фигуры, рисуется только при изменениях.
class Board:
	extends Control

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
