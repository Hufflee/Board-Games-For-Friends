extends Control
## Фишка The Gang, нарисованная кодом: ровные края на любом размере, номинал шрифтом игры.
## Обе стороны одинаковы. Своя фишка у своих карт — игрушка (toy): её можно таскать, швырять
## (трение, отскок от краёв зоны) и подбрасывать щелчком, как монетку; на номинал это не влияет.

signal released(at: Vector2)  # отпустили свою фишку (игрушку) — стол решает, вернуть ли её в центр

const FRICTION := 2.2
const BOUNCE := 0.55
const MAX_SPEED := 2400.0
const TOSS_TIME := 0.7

var value := 1
var round_index := 0
var toy := false
var velocity := Vector2.ZERO
var _holding := false
var _grab := Vector2.ZERO
var _press_at := Vector2.ZERO
var _moved := false
var _samples: Array = []
var _toss_t := -1.0
var _flip := 0.0
var _lift := 0.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	resized.connect(queue_redraw)
	set_process(toy)

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	# Подброс: фишка «ближе» (крупнее), тень отстаёт; ребро — сжатие по ширине.
	var scale_up := 1.0 + _lift * 0.35
	draw_circle(center + Vector2(0, radius * (0.08 + _lift * 0.5)), radius * (0.98 + _lift * 0.1), Color(0, 0, 0, 0.35 - _lift * 0.15), true, -1.0, true)
	draw_set_transform(center, 0.0, Vector2(absf(cos(_flip)) * scale_up, scale_up))
	var tint: Color = TGStyle.ROUND_COLORS[round_index]
	var ink := Color("18130d")
	draw_circle(Vector2.ZERO, radius, tint.darkened(0.25), true, -1.0, true)
	draw_circle(Vector2.ZERO, radius * 0.94, tint, true, -1.0, true)
	# Вставки по ободу, как на настоящих покерных фишках.
	for index in 6:
		var angle := TAU * index / 6.0
		var along := Vector2.from_angle(angle + PI * 0.5)
		var out := Vector2.from_angle(angle)
		var middle := out * radius * 0.8
		var half := along * radius * 0.17
		var depth := out * radius * 0.12
		draw_colored_polygon(PackedVector2Array([middle - half - depth, middle + half - depth, middle + half + depth, middle - half + depth]), ink)
		draw_line(middle - depth, middle + depth, tint, maxf(1.0, radius * 0.05), true)
	draw_arc(Vector2.ZERO, radius * 0.64, 0, TAU, 48, Color(ink, 0.45), maxf(1.0, radius * 0.04), true)
	draw_circle(Vector2.ZERO, radius * 0.6, tint.lightened(0.18), true, -1.0, true)
	var font := TGStyle.weighted_font(TGStyle.HEAD, 700)
	var text := str(value)
	var font_size := int(radius * (0.95 if text.length() == 1 else 0.78))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(-width * 0.5, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	draw_set_transform(Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if not toy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_holding = true
		_moved = false
		_press_at = event.global_position
		_grab = event.global_position - global_position
		velocity = Vector2.ZERO
		_samples = [[Time.get_ticks_msec(), event.global_position]]
		accept_event()

func _input(event: InputEvent) -> void:
	if not toy or not _holding:
		return
	if event is InputEventMouseMotion:
		if event.global_position.distance_to(_press_at) > 4.0:
			_moved = true
		global_position = event.global_position - _grab
		_keep_inside(false)
		_samples.append([Time.get_ticks_msec(), event.global_position])
		if _samples.size() > 6:
			_samples.pop_front()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_holding = false
		if not _moved:
			toss()
		else:
			var first: Array = _samples.front()
			var seconds := maxf(0.016, (Time.get_ticks_msec() - int(first[0])) / 1000.0)
			velocity = ((event.global_position - (first[1] as Vector2)) / seconds).limit_length(MAX_SPEED)
		released.emit(event.global_position)

## Подбросить на месте: в воздухе переворачивается, приземляется той же (одинаковой) стороной.
func toss() -> void:
	if _toss_t >= 0.0:
		return
	_toss_t = 0.0
	Sfx.play("chip", -8, 0.1, 0.03)

func _process(delta: float) -> void:
	if _toss_t >= 0.0:
		_toss_t += delta
		var k := clampf(_toss_t / TOSS_TIME, 0.0, 1.0)
		_lift = sin(k * PI)
		_flip = k * TAU * 3.0
		if k >= 1.0:
			_toss_t = -1.0
			_lift = 0.0
			_flip = 0.0
			Sfx.play("chip", -12, 0.1, 0.03)
		queue_redraw()
	if _holding or velocity.length_squared() < 4.0:
		velocity = Vector2.ZERO
		return
	position += velocity * delta
	velocity *= maxf(0.0, 1.0 - FRICTION * delta)
	_keep_inside(true)

## Игрушка не покидает зону своих карт: от краёв отскакивает.
func _keep_inside(bounce: bool) -> void:
	var area := get_parent() as Control
	if area == null:
		return
	var limit := area.size - size
	if position.x < 0.0 or position.x > limit.x:
		position.x = clampf(position.x, 0.0, maxf(0.0, limit.x))
		if bounce:
			velocity.x = -velocity.x * BOUNCE
	if position.y < 0.0 or position.y > limit.y:
		position.y = clampf(position.y, 0.0, maxf(0.0, limit.y))
		if bounce:
			velocity.y = -velocity.y * BOUNCE
