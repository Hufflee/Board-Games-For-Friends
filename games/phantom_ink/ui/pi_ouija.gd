extends Control
## Доска уиджи получает только уже открытые хостом буквы и показывает их по прибытии планшетки.

signal letter_shown(letter: String)
signal dismissed

const BOARD := Vector2(720, 368)
const GOLD := Color("c6a75d")
const INK := Color("39251d")
const ROWS := ["АБВГДЕЁЖЗИЙ", "КЛМНОПРСТУФ", "ХЦЧШЩЪЫЬЭЮЯ", "ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ"]
const SPACE := Vector2(360, 330)

var _keys := {}
var _letters: Array[String] = []
var _marker := SPACE
var _current := ""
var _tween: Tween
var _ending := false
var _opacity := 0.0
var _mist := 0.0
var _clue_row: Control
var _clue_rect := Rect2()
var _table: Control
var _table_rect := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 68
	resized.connect(queue_redraw)
	for row in ROWS.size():
		var letters: String = ROWS[row]
		for i in letters.length():
			_keys[letters[i]] = Vector2(BOARD.x * 0.5 + (i - (letters.length() - 1) * 0.5) * 51, 78 + row * 37)
	_keys[" "] = SPACE
	hide()


func begin(last_letter: String = "") -> void:
	if _tween != null:
		_tween.kill()
	_letters.clear()
	_current = ""
	_ending = false
	_mist = 0.0
	_marker = _keys.get(last_letter, SPACE)
	_opacity = 0.0
	show()
	_tween = create_tween()
	_tween.tween_method(_set_opacity, 0.0, 1.0, 0.3)
	_tween.tween_callback(_next)


func enqueue(letter: String) -> void:
	_letters.append(letter)
	if _tween == null or not _tween.is_running():
		_next()


func finish() -> void:
	_ending = true
	if _tween == null or not _tween.is_running():
		_next()


func track_clue(row: Control, table: Control) -> void:
	_clue_row = row
	_table = table


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(_clue_row) or _clue_row.size.x <= 0.0:
		return
	var inverse := get_global_transform().affine_inverse()
	var clue := inverse * _clue_row.get_global_rect()
	var table := inverse * _table.get_global_rect()
	if clue.position.y >= TopBar.HEIGHT and table.has_area() and (
		not clue.is_equal_approx(_clue_rect) or not table.is_equal_approx(_table_rect)
	):
		_clue_rect = clue
		_table_rect = table
		queue_redraw()


## Ищем место вокруг активной строки, сохраняя саму подсказку на планшете.
func board_rect() -> Rect2:
	var safe := Rect2(24.0, TopBar.HEIGHT + 16.0, size.x - 48.0, size.y - TopBar.HEIGHT - 32.0)
	if _table_rect.has_area():
		safe = safe.intersection(_table_rect.grow(-8.0))
	var centered := _fit_board(safe)
	if not centered.grow(28.0).intersects(_clue_rect):
		return centered
	var clue := _clue_rect.grow(28.0).intersection(safe)
	var spaces := [
		Rect2(safe.position, Vector2(safe.size.x, clue.position.y - safe.position.y)),
		Rect2(safe.position.x, clue.end.y, safe.size.x, safe.end.y - clue.end.y),
		Rect2(safe.position, Vector2(clue.position.x - safe.position.x, safe.size.y)),
		Rect2(clue.end.x, safe.position.y, safe.end.x - clue.end.x, safe.size.y)
	]
	var best := Rect2()
	for available: Rect2 in spaces:
		var candidate := _fit_board(available)
		if candidate.get_area() > best.get_area():
			best = candidate
	return best


func _fit_board(space: Rect2) -> Rect2:
	var zoom := clampf(minf(space.size.x / BOARD.x, space.size.y / BOARD.y), 0.0, 1.0)
	var extent := BOARD * zoom
	return Rect2(space.get_center() - extent * 0.5, extent)


func _next() -> void:
	if not _letters.is_empty():
		_current = _letters.pop_front()
		_tween = create_tween()
		_tween.tween_method(_set_marker, _marker, _keys.get(_current, SPACE), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_callback(_arrived)
	elif _ending and _mist == 0.0:
		_tween = create_tween()
		_tween.tween_method(_dissolve, 0.0, 1.0, 0.62)
		_tween.tween_callback(func():
			hide()
			dismissed.emit())


func _arrived() -> void:
	letter_shown.emit(_current)
	_next()


func _set_marker(point: Vector2) -> void:
	_marker = point
	queue_redraw()


func _set_opacity(value: float) -> void:
	_opacity = value
	queue_redraw()


func _dissolve(value: float) -> void:
	_mist = value
	_set_opacity(1.0 - smoothstep(0.08, 0.92, value))


func _centered(font: Font, value: String, at: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at + Vector2(-width * 0.5, font_size * 0.31), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	var place := board_rect()
	var zoom := place.size.x / BOARD.x
	if zoom <= 0.0:
		return
	draw_set_transform(place.position, 0.0, Vector2.ONE * zoom)
	var board := Rect2(Vector2.ZERO, BOARD)
	var wood := StyleBoxFlat.new()
	wood.bg_color = Color(Color("a97d50"), _opacity)
	wood.border_color = Color(INK, _opacity)
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(20)
	wood.shadow_color = Color(0.06, 0.045, 0.035, _opacity * 0.74)
	wood.shadow_size = 22
	wood.shadow_offset = Vector2(0, 9)
	draw_style_box(wood, board)
	draw_rect(board.grow(-14), Color(INK, _opacity * 0.78), false, 2.0)
	draw_rect(board.grow(-20), Color(GOLD, _opacity * 0.70), false, 1.0)
	for i in 24:
		var x := 25.0 + fposmod(float(i) * 73.1, 220.0)
		var y := 27.0 + float(i) * 13.0
		draw_line(Vector2(x, y), Vector2(BOARD.x - x * 0.54, y + sin(float(i)) * 4.0), Color(INK, _opacity * 0.10), 1.0, true)
	var title := PIStyle.font("title")
	var text := PIStyle.font()
	_centered(title, "ДОСКА УИДЖИ", Vector2(360, 39), 24, Color(INK, _opacity))
	for x in [69.0, 651.0]:
		var center := Vector2(x, 39)
		draw_arc(center, 11.0, 0, TAU, 32, Color(INK, _opacity * 0.82), 1.5, true)
		for spoke in 8:
			var direction := Vector2.from_angle(spoke * TAU / 8.0)
			draw_line(center + direction * 14.0, center + direction * 18.0, Color(INK, _opacity * 0.65), 1.5, true)
	for key: String in _keys:
		_centered(text, key if key != " " else "ПРОБЕЛ", _keys[key], 22 if key != " " else 13, Color(INK, _opacity))
	var outer := PackedVector2Array([_marker + Vector2(0, -26), _marker + Vector2(29, 24),
		_marker + Vector2(-29, 24), _marker + Vector2(0, -26)])
	var tint := Color(Color("f0d49a"), _opacity)
	# Раздельные планки оставляют отверстие открытым, чтобы буква читалась под планшеткой.
	draw_polyline(outer, Color(INK, _opacity), 7.0, true)
	draw_polyline(outer, tint, 3.0, true)
	draw_arc(_marker, 14.0, 0, TAU, 48, tint, 2.0, true)
	if _mist > 0.0:
		for i in 25:
			var angle := float(i) * 2.39996
			var drift := Vector2.from_angle(angle)
			var at := BOARD * 0.5 + drift * Vector2(306, 138) * (0.45 + _mist * 0.66)
			var radius := 31.0 + fmod(float(i) * 13.0, 26.0) + _mist * 27.0
			at = at.clamp(Vector2.ONE * radius, BOARD - Vector2.ONE * radius)
			draw_circle(at, radius, Color(0.75, 0.83, 0.76, sin(_mist * PI) * 0.04), true, -1.0, true)
