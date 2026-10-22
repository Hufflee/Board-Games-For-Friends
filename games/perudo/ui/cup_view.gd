class_name PerudoCup
extends Control
## Кожаный стакан для костей. Свой стакан можно зажать мышью и потрясти — при отпускании
## он ударяет о стол (сигнал shaken). Чужие стаканы трясутся анимацией.

signal shaken

var shakeable := false:
	set(v):
		shakeable = v
		mouse_default_cursor_shape = Control.CURSOR_DRAG if v else Control.CURSOR_ARROW
		queue_redraw()
var lifted := false
## Цвет кожи стакана (как у 3D-стаканчиков в шкафу на стартовом экране).
var color := Color("5a2e16"):
	set(v):
		color = v
		queue_redraw()

## Цвета стаканов (и костей) по местам за столом — те же, что у 3D-набора «Перудо» в шкафу.
const SEAT_COLORS := [Color("c8262c"), Color("2f64c8"), Color("e8b21c"), Color("2f9e3a"), Color("e8642a"), Color("4a2c1e"), Color("8a3fc0"), Color("e0e0e0")]


static func seat_color(seat: int) -> Color:
	return SEAT_COLORS[posmod(seat, SEAT_COLORS.size())]

var _holding := false
var _grab := Vector2.ZERO
var _home := Vector2.ZERO
var _energy := 0.0


func _init(side: float = 70.0) -> void:
	custom_minimum_size = Vector2(side, side * 1.15)
	size = custom_minimum_size
	pivot_offset = Vector2(size.x / 2.0, size.y)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var w := size.x
	var h := size.y
	# тень на столе
	draw_set_transform(Vector2(w / 2.0, h - 2), 0, Vector2(1, 0.28))
	draw_circle(Vector2.ZERO, w * 0.5, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# тело стакана: сужается кверху (стакан стоит дном вверх)
	var top := w * 0.3
	var body := PackedVector2Array([
		Vector2(w * 0.08, h - 6), Vector2(w * 0.92, h - 6),
		Vector2(w * 0.5 + top, h * 0.12), Vector2(w * 0.5 - top, h * 0.12),
	])
	var colors := PackedColorArray([color.darkened(0.05), color.darkened(0.4), color.lightened(0.08), color.lightened(0.25)])
	draw_polygon(body, colors)
	# полосы и строчка
	for i in 3:
		var t := 0.32 + i * 0.22
		var y := lerpf(h * 0.12, h - 6, t)
		var half := lerpf(top, w * 0.42, t)
		draw_line(Vector2(w * 0.5 - half, y), Vector2(w * 0.5 + half, y), color.darkened(0.55), 2.0, true)
		_dashes(Vector2(w * 0.5 - half + 3, y - 4), Vector2(w * 0.5 + half - 3, y - 4))
	# дно (верх)
	draw_set_transform(Vector2(w / 2.0, h * 0.12), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, top, color.lightened(0.15))
	draw_arc(Vector2.ZERO, top, 0, TAU, 32, color.darkened(0.3), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# золотой обод внизу
	draw_line(Vector2(w * 0.08, h - 7), Vector2(w * 0.92, h - 7), color.darkened(0.3), 5.0, true)  # валик по краю
	if shakeable:
		var a := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(1.0, 0.85, 0.4, 0.25 + 0.4 * a), false, 2.0)


func _dashes(a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / 7.0)
	for i in n:
		var p := a.lerp(b, (i + 0.2) / n)
		draw_line(p, p + (b - a).normalized() * 3.5, Color(color.lightened(0.45), 0.75), 1.2)


func _gui_input(event: InputEvent) -> void:
	if shakeable and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_holding = true
		_home = position
		_grab = get_global_mouse_position() - global_position
		Sfx.play("die_grab")
		accept_event()


func _input(event: InputEvent) -> void:
	if not _holding:
		return
	if event is InputEventMouseMotion:
		var target: Vector2 = get_global_mouse_position() - _grab
		var parent := get_parent() as CanvasItem
		position = _home + (parent.get_global_transform_with_canvas().affine_inverse() * target - _home).limit_length(60.0)
		rotation = clampf(event.relative.x * 0.03, -0.45, 0.45)
		_energy += event.relative.length()
		if _energy > 140.0:
			_energy = 0.0
			Sfx.play("die_shake", -6, 0.1, 0.12)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_holding = false
		shakeable = false
		_slam()
		shaken.emit()
		get_viewport().set_input_as_handled()


## Удар о стол: стакан возвращается на место с отскоком.
func _slam() -> void:
	var t := create_tween()
	t.tween_property(self, "position", _home + Vector2(0, -24), 0.08)
	t.parallel().tween_property(self, "rotation", 0.0, 0.08)
	t.tween_property(self, "position", _home, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): Sfx.play("die_throw", -2, 0.08, 0.05))
	t.tween_property(self, "scale", Vector2(1.08, 0.92), 0.05)
	t.tween_property(self, "scale", Vector2.ONE, 0.12)


## Анимация тряски (для чужих стаканов и автоброска).
func wobble() -> void:
	var t := create_tween()
	for i in 6:
		t.tween_property(self, "rotation", 0.25 if i % 2 == 0 else -0.25, 0.06)
	t.tween_property(self, "rotation", 0.0, 0.06)
	t.tween_callback(func(): Sfx.play("die_throw", -10, 0.08, 0.05))


## Поднять стакан (вскрытие) или опустить.
func lift(up: bool) -> void:
	if up == lifted:
		return
	lifted = up
	var t := create_tween().set_parallel()
	t.tween_property(self, "position:y", position.y + (-size.y * 0.9 if up else size.y * 0.9), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.25 if up else 1.0, 0.35)


func _process(_d: float) -> void:
	if shakeable:
		queue_redraw()
