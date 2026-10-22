class_name WLDial
extends Control
## Шкала «Длины волны»: полукруг 0…100 (слева направо), цветная зона (2-3-4 очка),
## сине-серый экран-шторка и терракотовая стрелка (светлая тема как у Word Slam). Стрелку можно тянуть мышью (can_drag).

signal dial_moved(value: float)
signal drag_finished

var value := 50.0:
	set(v):
		value = clampf(v, 0.0, 100.0)
		queue_redraw()
var target := -1.0:  # центр зоны (-1 — неизвестен)
	set(v):
		target = v
		queue_redraw()
var cover := 1.0:  # 1 — экран закрыт, 0 — открыт
	set(v):
		cover = clampf(v, 0.0, 1.0)
		queue_redraw()
var can_drag := false:
	set(v):
		can_drag = v
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
var guess_side := ""  # «left»/«right» — отметка выбора другой команды

var dragging := false

const BAND_COLORS := {2: Color("f0c870"), 3: Color("e8955f"), 4: Color("c8664f")}


func _init() -> void:
	custom_minimum_size = Vector2(620, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center() -> Vector2:
	return Vector2(size.x / 2.0, size.y - 16)


func _radius() -> float:
	return minf(size.x / 2.0 - 10, size.y - 30)


## Значение 0…100 → угол (0 — слева, 100 — справа), экранные координаты (y вниз).
static func angle_of(v: float) -> float:
	return PI + v / 100.0 * PI


func _draw() -> void:
	var c := _center()
	var r := _radius()
	# основание шкалы: мягкая тень, тонкий ободок, белое поле
	_wedge(c + Vector2(0, 4), r + 14, 0.0, 100.0, Color(0.18, 0.15, 0.1, 0.08))
	_wedge(c, r + 12, 0.0, 100.0, HCStyle.LINE)
	_wedge(c, r + 10, 0.0, 100.0, HCStyle.CARD)
	_wedge(c, r, 0.0, 100.0, HCStyle.CARD_HI)
	# цветная зона
	if target >= 0.0:
		for band in [[10.0, 2], [6.0, 3], [2.0, 4]]:
			_wedge(c, r - 4, target - band[0], target + band[0], BAND_COLORS[band[1]])
		var font := HCStyle.font("bold")
		for band in [[8.0, 2], [4.0, 3], [0.0, 4], [-4.0, 3], [-8.0, 2]]:
			var a := angle_of(clampf(target + band[0], 0, 100))
			var p := c + Vector2(cos(a), sin(a)) * (r - 40)
			draw_string(font, p + Vector2(-6, 8), str(band[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
	# деления
	for i in 21:
		var a := angle_of(i * 5.0)
		var inner := r - (14 if i % 5 == 0 else 7)
		draw_line(c + Vector2(cos(a), sin(a)) * inner, c + Vector2(cos(a), sin(a)) * r, Color(HCStyle.MUTED, 0.6), 2.0, true)
	# экран-шторка: закрывает шкалу, при открытии «отъезжает» вправо
	if cover > 0.001:
		var from := 100.0 - cover * 100.0
		_wedge(c, r + 4, from, 100.0, HCStyle.DUSK)
		_wedge(c, r * 0.35, from, 100.0, HCStyle.DUSK.darkened(0.12))
		for i in 6:
			var a := angle_of(from + (100.0 - from) * (i + 0.5) / 6.0)
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.4, c + Vector2(cos(a), sin(a)) * r, Color(1, 1, 1, 0.12), 3.0, true)
	# отметка «левее/правее» другой команды
	if guess_side != "":
		var ga := angle_of(clampf(value + (-12.0 if guess_side == "left" else 12.0), 2, 98))
		draw_circle(c + Vector2(cos(ga), sin(ga)) * (r + 26), 12, HCStyle.DUSK)
		draw_string(HCStyle.font("bold"), c + Vector2(cos(ga), sin(ga)) * (r + 26) + Vector2(-6, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# стрелка
	var a := angle_of(value)
	var tip := c + Vector2(cos(a), sin(a)) * (r + 4)
	var arrow := HCStyle.INK
	draw_line(c + Vector2(0, 2), tip + Vector2(0, 2), Color(0, 0, 0, 0.12), 8.0, true)
	draw_line(c, tip, arrow, 5.0, true)
	draw_circle(tip, 6, HCStyle.CLAY)
	draw_circle(c + Vector2(0, 2), 22, Color(0, 0, 0, 0.12))
	draw_circle(c, 22, HCStyle.CARD)
	draw_circle(c, 18, arrow)
	draw_circle(c, 7, HCStyle.CLAY)
	if can_drag:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
		draw_circle(tip, 10 + pulse * 4, Color(HCStyle.CLAY, 0.3))


func _wedge(c: Vector2, r: float, v0: float, v1: float, color: Color) -> void:
	v0 = clampf(v0, 0.0, 100.0)
	v1 = clampf(v1, 0.0, 100.0)
	if v1 <= v0:
		return
	var pts := PackedVector2Array([c])
	var steps := maxi(2, int((v1 - v0) / 1.5))
	for i in steps + 1:
		var a := angle_of(lerpf(v0, v1, float(i) / steps))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)


func _value_at(p: Vector2) -> float:
	var d := p - _center()
	var a := atan2(d.y, d.x)  # от -PI до PI; верхняя половина — отрицательные углы
	if a > 0.0:
		a = -PI if a > PI / 2.0 else 0.0
	return clampf((a + PI) / PI * 100.0, 0.0, 100.0)


func _gui_input(event: InputEvent) -> void:
	if not can_drag:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			value = _value_at(event.position)
			dial_moved.emit(value)
			Sfx.play("card_slide", -10, 0.1, 0.05)
		else:
			drag_finished.emit()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		value = _value_at(event.position)
		dial_moved.emit(value)


func _process(_d: float) -> void:
	# кнопку отпустили за пределами шкалы (или шкала стала неактивной) — перетаскивание закончено,
	# иначе стрелка «залипает» и больше не принимает положение с хоста
	if dragging and (not can_drag or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		dragging = false
		drag_finished.emit()
	if can_drag:
		queue_redraw()
