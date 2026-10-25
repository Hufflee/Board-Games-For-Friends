class_name K12TableCard
extends Control
## Карта на столе или в руке: лицо (K12CardView) и рубашка, переворот, перетаскивание ЛКМ.
## Размер базовый (как у полной карты); на столе и в руке карта уменьшается через scale.
## Общая для всех игр сборника: другая игра передаёт своё лицо (face) и рубашку (back_drawer) — механика та же.

signal drag_started(card: K12TableCard)
signal dropped(card: K12TableCard, at: Vector2)
signal clicked(card: K12TableCard)
signal double_clicked(card: K12TableCard)
signal right_clicked(card: K12TableCard)
signal hovered(card: K12TableCard, on: bool)

const BASE := Vector2(138, 228)

var card := ""
var face_up := true:
	set(v):
		face_up = v
		_sync()
var draggable := false
var dragging := false:
	set(v):
		dragging = v
		_lift_to(1.0 if v else 0.0)
var lift := 0.0:  # 0…1 — карта «парит» над столом: под ней тень со смещением
	set(v):
		lift = v
		queue_redraw()
var base_scale := 1.0  # обычный масштаб; при наведении/перетаскивании меняется
var stamp := "":
	set(v):
		stamp = v
		if _face is K12CardView:
			(_face as K12CardView).stamp = v

var card_size := BASE
var back_drawer := Callable()  # своя рубашка: func(ci: CanvasItem, r: Rect2)
var _face: Control
var _back: Control
var _press_pos := Vector2.ZERO
var _grab := Vector2.ZERO
var _moved := false
var _tween: Tween
var _lift_tween: Tween


func _init(card_id: String = "", up: bool = true, face: Control = null, face_size: Vector2 = BASE) -> void:
	card = card_id
	face_up = up
	card_size = face_size
	_face = face
	size = card_size
	custom_minimum_size = card_size
	pivot_offset = card_size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if _face == null and card != "":
		var view := K12CardView.new(card)
		view.stamp = stamp
		_face = view
	if _face:
		_face.size = card_size
		add_child(_face)
		_round_images(_face)
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE  # после _ready карты, иначе она перехватит мышь
		_face.tooltip_text = ""
	_back = Control.new()
	_back.size = card_size
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.draw.connect(func():
		var r := Rect2(Vector2.ZERO, card_size)
		if back_drawer.is_valid():
			back_drawer.call(_back, r)
		else:
			draw_back(_back, r))
	add_child(_back)
	_sync()
	mouse_entered.connect(func(): hovered.emit(self, true))
	mouse_exited.connect(func(): hovered.emit(self, false))


func _round_images(node: Node) -> void:
	if node is TextureRect and (node as TextureRect).material == null:
		var corners := ShaderMaterial.new()
		corners.shader = preload("res://hub/card_corners.gdshader")
		(node as TextureRect).material = corners
	for child in node.get_children(): _round_images(child)


func _sync() -> void:
	if _back:
		_back.visible = not face_up or _face == null
	if _face:
		_face.visible = face_up


func _lift_to(target: float) -> void:
	if not is_inside_tree():
		lift = target
		return
	if _lift_tween:
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.tween_property(self, "lift", target, 0.12 if target > lift else 0.22).set_trans(Tween.TRANS_SINE)


## Тень под картой, пока её несут над столом.
func _draw() -> void:
	if lift <= 0.01:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28 * lift)
	sb.set_corner_radius_all(int(card_size.x * 0.08))
	sb.shadow_color = Color(0, 0, 0, 0.22 * lift)
	sb.shadow_size = int(6 + 10 * lift)
	draw_style_box(sb, Rect2(Vector2(10, 14) * lift, card_size))


## Центр карты в координатах родителя.
func center() -> Vector2:
	return position + pivot_offset


func move_to(c: Vector2, rot: float = 0.0, sc: float = -1.0, time: float = 0.25) -> Tween:
	if sc < 0.0:
		sc = base_scale
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", c - pivot_offset, time)
	_tween.tween_property(self, "rotation", rot, time)
	_tween.tween_property(self, "scale", Vector2.ONE * sc, time)
	return _tween


func place(c: Vector2, rot: float = 0.0, sc: float = -1.0) -> void:
	if _tween:
		_tween.kill()
	position = c - pivot_offset
	rotation = rot
	scale = Vector2.ONE * (base_scale if sc < 0.0 else sc)


## Переворот с анимацией (сжатие по X, смена стороны, раскрытие).
func flip(to_up: bool, delay: float = 0.0) -> void:
	if to_up == face_up:
		return
	var sx := base_scale
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "scale:x", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		face_up = to_up
		Sfx.play("card_flip", -6, 0.1, 0.03))
	t.tween_property(self, "scale:x", sx, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		right_clicked.emit(self)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				double_clicked.emit(self)
				accept_event()
				return
			_press_pos = event.global_position
			_moved = false
			if draggable:
				dragging = true
				_grab = _to_parent(event.global_position) - center()
				if _tween:
					_tween.kill()
				z_index = 100
				drag_started.emit(self)
			accept_event()


func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		if event.global_position.distance_to(_press_pos) > 6.0:
			_moved = true
		var target: Vector2 = _to_parent(event.global_position) - _grab
		position = target - pivot_offset
		rotation = lerp_angle(rotation, clampf(event.relative.x * 0.01, -0.25, 0.25), 0.3)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		z_index = 0
		get_viewport().set_input_as_handled()
		if _moved:
			dropped.emit(self, _to_parent(event.global_position))
		else:
			clicked.emit(self)


## Точка экрана (координаты вьюпорта) в координатах родителя.
func _to_parent(p: Vector2) -> Vector2:
	return (get_parent() as CanvasItem).get_global_transform_with_canvas().affine_inverse() * p


## Рубашка карты: тёмно-синяя с золотой рамкой, ромбы и кристалл в центре.
static func draw_back(ci: CanvasItem, r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c2a4a")
	sb.set_corner_radius_all(int(r.size.x * 0.07))
	sb.border_color = Color("d4b062")
	sb.set_border_width_all(maxi(2, int(r.size.x * 0.03)))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = int(r.size.x * 0.04)
	ci.draw_style_box(sb, r)
	var inner := r.grow(-r.size.x * 0.09)
	var step := r.size.x * 0.14
	var line := Color(0.83, 0.69, 0.38, 0.22)
	var y := inner.position.y
	while y < inner.end.y:
		var x := inner.position.x
		while x < inner.end.x:
			var c := Vector2(x + step / 2, y + step / 2)
			var pts := PackedVector2Array([c + Vector2(0, -step / 2), c + Vector2(step / 2, 0), c + Vector2(0, step / 2), c + Vector2(-step / 2, 0), c + Vector2(0, -step / 2)])
			ci.draw_polyline(pts, line, 1.0, true)
			x += step
		y += step
	ci.draw_rect(inner, Color(0.83, 0.69, 0.38, 0.6), false, maxf(1.0, r.size.x * 0.012))
	var c := r.get_center()
	var rad := r.size.x * 0.24
	ci.draw_circle(c, rad * 1.25, Color("1c2a4a"))
	ci.draw_arc(c, rad * 1.25, 0, TAU, 40, Color("d4b062"), maxf(1.0, r.size.x * 0.015), true)
	var outer := PackedVector2Array()
	var inner_p := PackedVector2Array()
	for i in 5:
		var a := -PI / 2 + i * TAU / 5
		outer.append(c + Vector2(cos(a), sin(a)) * rad)
		inner_p.append(c + Vector2(cos(a), sin(a)) * rad * 0.6)
	ci.draw_colored_polygon(outer, Color("2a6fa8"))
	ci.draw_colored_polygon(inner_p, Color("5fb4ef"))
	for i in 5:
		ci.draw_line(outer[i], inner_p[i], Color(1, 1, 1, 0.4), 1.0, true)
	var font := ThemeDB.fallback_font
	var fs := int(r.size.x * 0.13)
	var txt := "12"
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(font, c + Vector2(-ts.x / 2, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
