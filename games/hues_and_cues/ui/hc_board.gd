class_name HCBoard
extends Control
## Поле 30×16: клетки-оттенки, фишки игроков, рамка подсчёта. Клик по клетке — cell_clicked.

signal cell_clicked(cell: int)
signal cell_hovered(cell: int)
signal reveal_finished  # вступление (окрашивание поля) закончилось — пора показывать выбор ведущего

enum RevealPattern { DIAGONAL, RANDOM, RADIAL }
const REVEAL_DURATION := 3.0
const REVEAL_HOLD := 0.15
const REVEAL_FADE := 0.60
const REVEAL_SPREAD := REVEAL_DURATION - REVEAL_HOLD - REVEAL_FADE

const LABEL := 20.0  # поля под буквы и номера

var mode := "none":  # "none" | "pick" (выбор цвета с карты) | "place" (поставить фишку)
	set(v):
		mode = v
		queue_redraw()
var free_pick := false
var card: Array = []
var target := -1  # показать загаданный цвет (ведущему или при подсчёте)
var frame_t := 0.0:  # 0…1 — рамка подсчёта выезжает
	set(v):
		frame_t = v
		queue_redraw()
var points := {}  # cell -> очки (при подсчёте)
var my_color := Color.WHITE  # цвет фишки под курсором
var distorted := false
var color_order: Array = []
var color_filter := -1
var _display_order: Array = []
var _spin_start := 0.0
var _spin_turns := 0.0
var _giver_view := false
var _round_started := false
var _filter_amount := 1.0
const FILTER_FADE := 0.9
var _distort_intro := false
var labels := true  # буквы и номера по краям (на обложке — без них)

var _pieces: Array = []
var _born := {}  # "seat/cell" -> время появления (мс), для анимации
var _hover := -1
var _pitch := 20.0
var _origin := Vector2.ZERO
var _cell_box: StyleBoxFlat
var _reveal_active := false
var _reveal_elapsed := 0.0
var _reveal_pattern := RevealPattern.DIAGONAL
var _reveal_delays := PackedFloat32Array()
## Затемнение «не цвета карты» и кольца выбора у ведущего: во время вступления поле в полном цвете (0),
## после — плавно затемняется (DIM_IN, до 1).
const DIM_IN := 0.5
var _dim := 1.0


## Один запуск на начало партии. Свой RNG не влияет на правила и порядок карт.
## pattern/seed_value нужны для воспроизводимого просмотра и проверок; обычно выбирается случайно.
func play_reveal(pattern: int = -1, seed_value: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	_reveal_pattern = rng.randi_range(0, 2) if pattern < 0 else clampi(pattern, 0, 2)
	var count := HCData.COLS * HCData.ROWS
	_reveal_delays.resize(count)
	var center := Vector2(HCData.COLS - 1, HCData.ROWS - 1) * 0.5
	var min_radius := Vector2(0.5 if HCData.COLS % 2 == 0 else 0.0, 0.5 if HCData.ROWS % 2 == 0 else 0.0).length()
	var max_radius := center.length()
	if _reveal_pattern == RevealPattern.RANDOM:
		var order := PackedInt32Array()
		for cell in count:
			order.append(cell)
		# Fisher–Yates через локальный RNG: каждый квадрат имеет своё место в порядке.
		for i in range(count - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var temp := order[i]
			order[i] = order[j]
			order[j] = temp
		for rank in count:
			_reveal_delays[order[rank]] = REVEAL_HOLD + REVEAL_SPREAD * float(rank) / maxf(1.0, count - 1)
	else:
		for cell in count:
			var col := cell % HCData.COLS
			var row := cell / HCData.COLS
			var weight := 0.0
			if _reveal_pattern == RevealPattern.DIAGONAL:
				weight = float(col + row) / maxf(1.0, HCData.COLS + HCData.ROWS - 2)
			else:
				weight = (Vector2(col, row).distance_to(center) - min_radius) / maxf(0.001, max_radius - min_radius)
			_reveal_delays[cell] = REVEAL_HOLD + REVEAL_SPREAD * clampf(weight, 0.0, 1.0)
	_distort_intro = false
	_reveal_elapsed = 0.0
	_reveal_active = true
	_dim = 0.0
	_hover = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func reveal_progress(cell: int) -> float:
	if not _reveal_active:
		return 1.0
	if _distort_intro:
		return HCRules.spin_progress(_reveal_elapsed / HCRules.PREPARE_SECONDS)
	var progress := clampf((_reveal_elapsed - _reveal_delays[cell]) / REVEAL_FADE, 0.0, 1.0)
	return progress * progress * (3.0 - 2.0 * progress)


## Конечный цвет совпадает с прежней отрисовкой, включая затемнение вне цветов карты
## (во время вступления затемнения нет — оно наплывает после, _dim).
func _cell_color(cell: int) -> Color:
	var color := base_color(cell)
	if _distort_intro and _reveal_active and _display_order.size() == HCData.COLS * HCData.ROWS:
		color = HCData.color(int(_display_order[cell]))
	color = color.lerp(filtered_color(color, color_filter), _filter_amount)
	if mode == "pick" and not free_pick and not card.has(cell):
		var k := _dim * _dim * (3.0 - 2.0 * _dim)
		color = color.lerp(Color("26272b"), 0.62 * k)
	if _reveal_active and not _distort_intro:
		var gray := Color("727780") if HCStyle.dark else Color("b9bbc0")
		return gray.lerp(color, reveal_progress(cell))
	return color


## Исходный цвет позиции после перестановки; карточка ведущего всегда использует его без фильтра.
func base_color(cell: int) -> Color:
	return HCData.color(int(color_order[cell]) if color_order.size() == HCData.COLS * HCData.ROWS else cell)


static func filtered_color(color: Color, channel: int) -> Color:
	if channel < 0:
		return color
	if channel == 3:
		var value := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		return Color(value, value, value, color.a)
	var tint: Color = [Color("3b62ff"), Color("39ed64"), Color("ff404b")][clampi(channel, 0, 2)]
	return color.lerp(tint, 0.567)


## Клетки неподвижны: по кольцам «перепрыгивают» только оттенки, с разгоном и торможением.
func play_distorted_round(order: Array, filter_id: int, _seed_value: int, start_turns: float = 0.0, turns: float = 0.0, giver_view: bool = false) -> void:
	color_order = order.duplicate()
	color_filter = filter_id
	distorted = true
	_distort_intro = true
	_spin_start = start_turns
	_spin_turns = turns
	_giver_view = giver_view
	_round_started = false
	_display_order = HCRules.orbit_order(start_turns)
	_filter_amount = 0.0
	_reveal_elapsed = 0.0
	_reveal_active = true
	_dim = 0.0
	_hover = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


## Ведущий тоже видит фильтр во вступлении; после остановки он плавно исчезает.
func set_filter_view(filter_id: int, giver_view: bool, round_started: bool = true) -> void:
	color_filter = filter_id
	_giver_view = giver_view
	_round_started = round_started


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cell_box = StyleBoxFlat.new()
	_cell_box.anti_aliasing = true
	resized.connect(_relayout)
	_relayout()


func set_pieces(list: Array) -> void:
	var now := Time.get_ticks_msec()
	var keys := {}
	for p in list:
		var k := "%d/%d" % [p["seat"], p["cell"]]
		keys[k] = true
		if not _born.has(k):
			_born[k] = now if not _pieces.is_empty() or list.size() <= 1 else now - 1000
	for k in _born.keys():
		if not keys.has(k):
			_born.erase(k)
	_pieces = list.duplicate(true)
	queue_redraw()


func _relayout() -> void:
	var m := LABEL if labels else 6.0
	_pitch = minf((size.x - m * 2.0) / HCData.COLS, (size.y - m * 2.0) / HCData.ROWS)
	if labels:
		_pitch = floorf(_pitch)
	var w := _pitch * HCData.COLS
	var h := _pitch * HCData.ROWS
	_origin = Vector2(floorf((size.x - w) * 0.5), floorf((size.y - h) * 0.5))
	queue_redraw()


func cell_rect(cell: int, grow: float = 0.0) -> Rect2:
	var gap := maxf(2.0, roundf(_pitch * 0.09))
	var pos := _origin + Vector2(cell % HCData.COLS, cell / HCData.COLS) * _pitch
	return Rect2(pos + Vector2(gap, gap) * 0.5, Vector2(_pitch - gap, _pitch - gap)).grow(grow)


func cell_center(cell: int) -> Vector2:
	return _origin + (Vector2(cell % HCData.COLS, cell / HCData.COLS) + Vector2(0.5, 0.5)) * _pitch


func cell_at(pos: Vector2) -> int:
	var rel := (pos - _origin) / _pitch
	if rel.x < 0 or rel.y < 0 or rel.x >= HCData.COLS or rel.y >= HCData.ROWS:
		return -1
	return int(rel.y) * HCData.COLS + int(rel.x)


func occupied(cell: int) -> bool:
	for p in _pieces:
		if p["cell"] == cell:
			return true
	return false


func can_click(cell: int) -> bool:
	if cell < 0 or _reveal_active:
		return false
	match mode:
		"pick":
			return free_pick or card.has(cell)
		"place":
			return not occupied(cell)
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != _hover:
			_hover = c
			cell_hovered.emit(c)
			queue_redraw()
			if can_click(c):
				Sfx.play("hover", -22, 0.08, 0.03)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_click(c) else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(event.position)
		if can_click(c):
			cell_clicked.emit(c)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		cell_hovered.emit(-1)
		queue_redraw()


func _process(delta: float) -> void:
	var was_revealing := _reveal_active
	if _reveal_active and is_visible_in_tree():
		# Если партия открылась сразу из хаба, не проигрываем вступление под непрозрачным переходом.
		if get_tree().get_first_node_in_group("scene_transition") == null:
			var duration := HCRules.PREPARE_SECONDS if _distort_intro else REVEAL_DURATION
			_reveal_elapsed = minf(duration, _reveal_elapsed + delta)
			if _distort_intro:
				var t := _reveal_elapsed / duration
				_display_order = HCRules.orbit_order(_spin_start + _spin_turns * HCRules.spin_progress(t))
				_filter_amount = smoothstep(0.08, 0.38, t)
			if _reveal_elapsed >= duration:
				_reveal_active = false
				reveal_finished.emit()
			queue_redraw()
	elif _dim < 1.0:
		# вступление закончилось — затемнение и кольца выбора плавно появляются
		_dim = minf(1.0, _dim + delta / DIM_IN)
		queue_redraw()
	if _distort_intro and not was_revealing:
		var amount := move_toward(_filter_amount, 0.0 if _giver_view and _round_started else 1.0, delta / FILTER_FADE)
		if not is_equal_approx(amount, _filter_amount):
			_filter_amount = amount
			queue_redraw()
	var now := Time.get_ticks_msec()
	for k in _born:
		if now - int(_born[k]) < 600:
			queue_redraw()
			return
	if mode == "pick":
		queue_redraw()  # мягкая пульсация цветов карты


func _draw() -> void:
	var font := HCStyle.font("medium")
	var w := _pitch * HCData.COLS
	var h := _pitch * HCData.ROWS
	# подложка поля
	var under := HCStyle.box(Color("26272b"), 14, Color.TRANSPARENT, 0, Color(0, 0, 0, 0.18), 22)
	draw_style_box(under, Rect2(_origin - Vector2(6, 6), Vector2(w + 12, h + 12)))
	# буквы и номера
	var fs := int(clampf(_pitch * 0.38, 10, 14))
	for r in (HCData.ROWS if labels else 0):
		var y := _origin.y + (r + 0.5) * _pitch + fs * 0.36
		var ch := char(65 + r)
		draw_string(font, Vector2(_origin.x - 10 - LABEL * 0.5 - 4, y), ch, HORIZONTAL_ALIGNMENT_CENTER, 12, fs, HCStyle.MUTED)
		draw_string(font, Vector2(_origin.x + w + 8, y), ch, HORIZONTAL_ALIGNMENT_CENTER, 12, fs, HCStyle.MUTED)
	for c in (HCData.COLS if labels else 0):
		var x := _origin.x + c * _pitch
		draw_string(font, Vector2(x, _origin.y - 10), str(c + 1), HORIZONTAL_ALIGNMENT_CENTER, _pitch, fs, HCStyle.MUTED)
		draw_string(font, Vector2(x, _origin.y + h + 10 + fs * 0.8), str(c + 1), HORIZONTAL_ALIGNMENT_CENTER, _pitch, fs, HCStyle.MUTED)
	# клетки
	var radius := int(maxf(2.0, _pitch * 0.14))
	_cell_box.set_corner_radius_all(radius)
	for i in HCData.COLS * HCData.ROWS:
		_cell_box.bg_color = _cell_color(i)
		draw_style_box(_cell_box, cell_rect(i))
	var t := Time.get_ticks_msec() / 1000.0
	# цвета карты (ведущий выбирает)
	if mode == "pick" and not free_pick and _dim > 0.0:
		var pulse := 0.5 + 0.5 * sin(t * 2.4)
		for c in card:
			_ring(cell_rect(c, 2.0 + pulse * 1.5), Color(1, 1, 1, _dim), 2.0)
	# загаданный цвет — тонкое кольцо (ведущему, пока не подсчёт)
	if target >= 0 and frame_t <= 0.0:
		_ring(cell_rect(target, 2.0), Color.WHITE, 2.5)
		_ring(cell_rect(target, 4.5), Color(0, 0, 0, 0.35), 1.0)
	# рамка подсчёта
	if target >= 0 and frame_t > 0.0:
		_draw_frame()
	# фишки
	var now := Time.get_ticks_msec()
	for p in _pieces:
		var k := "%d/%d" % [p["seat"], p["cell"]]
		var age := (now - int(_born.get(k, 0))) / 1000.0
		var s := _ease_back(clampf(age / 0.45, 0.0, 1.0))
		_piece(cell_center(p["cell"]), _pitch * 0.4 * s, HCStyle.piece_color(int(p["seat"])), int(p.get("n", 1)))
	# очки при подсчёте
	if frame_t >= 1.0:
		for cell in points:
			var pts: int = points[cell]
			var pos := cell_center(cell) + Vector2(_pitch * 0.32, -_pitch * 0.42)
			var txt := "+%d" % pts if pts > 0 else "0"
			var bg := HCStyle.SAGE if pts >= 2 else (HCStyle.DUSK if pts == 1 else Color("9a9ca3"))
			var pill := HCStyle.box(bg, 8)
			var tw := 12.0 + 8.0 * txt.length()
			draw_style_box(pill, Rect2(pos - Vector2(tw * 0.5, 9), Vector2(tw, 18)))
			draw_string(HCStyle.font("bold"), pos + Vector2(-tw * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 12, Color.WHITE)
	# клетка под курсором
	if can_click(_hover):
		var r := cell_rect(_hover, _pitch * 0.18)
		var hb := HCStyle.box(base_color(_hover).lerp(filtered_color(base_color(_hover), color_filter), _filter_amount), radius + 2, Color.WHITE, 2, Color(0, 0, 0, 0.3), 8)
		draw_style_box(hb, r)
		if mode == "place":
			_piece(cell_center(_hover), _pitch * 0.32, Color(my_color, 0.75), 0)


func _draw_frame() -> void:
	var c := target
	if distorted:
		var bounds := Rect2(_origin, Vector2(HCData.COLS, HCData.ROWS) * _pitch)
		for pts in [1, 2, 3]:
			var cells := HCRules.score_rect(target, pts, true)
			var rect := Rect2(_origin + Vector2(cells.position) * _pitch, Vector2(cells.size) * _pitch).intersection(bounds)
			var alpha := frame_t * (0.45 if pts == 1 else (0.7 if pts == 2 else 1.0))
			_ring(rect.grow(-1.0), Color(1, 1, 1, alpha), 3.0 if pts == 3 else 2.0)
		return
	var a := clampf(frame_t, 0.0, 1.0)
	var grow := (1.0 - _ease_out(a)) * _pitch * 1.5
	var tl := _origin + Vector2(c % HCData.COLS - 1, c / HCData.COLS - 1) * _pitch
	var rect := Rect2(tl, Vector2(_pitch, _pitch) * 3.0).grow(grow)
	# затемнение вне зоны очков
	var outer := Rect2(_origin + Vector2(c % HCData.COLS - 2, c / HCData.COLS - 2) * _pitch, Vector2(_pitch, _pitch) * 5.0)
	var zone := HCStyle.box(Color.TRANSPARENT, 10, Color(1, 1, 1, 0.45 * a), 2)
	zone.draw_center = false
	draw_style_box(zone, outer.grow(-1))
	var sb := HCStyle.box(Color.TRANSPARENT, 8, Color(1, 1, 1, a), 4, Color(0, 0, 0, 0.35 * a), 10)
	sb.draw_center = false
	draw_style_box(sb, rect)
	_ring(cell_rect(c, 3.0), Color(1, 1, 1, a), 3.0)


func _ring(r: Rect2, col: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.anti_aliasing = true
	sb.border_color = col
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(int(maxf(3.0, _pitch * 0.18)))
	draw_style_box(sb, r)


func _piece(pos: Vector2, r: float, col: Color, n: int) -> void:
	if r <= 0.5:
		return
	draw_circle(pos + Vector2(0, r * 0.18), r * 1.02, Color(0, 0, 0, 0.28 * col.a))
	draw_circle(pos, r, Color(1, 1, 1, col.a))
	draw_circle(pos, r * 0.8, col)
	draw_circle(pos - Vector2(r * 0.25, r * 0.28), r * 0.22, Color(1, 1, 1, 0.35 * col.a))
	if n == 2:
		draw_arc(pos, r * 0.45, 0, TAU, 20, Color(1, 1, 1, 0.75) if col.get_luminance() < 0.6 else Color(0, 0, 0, 0.45), maxf(1.0, r * 0.12), true)


static func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3) + c1 * pow(x - 1.0, 2)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3)
