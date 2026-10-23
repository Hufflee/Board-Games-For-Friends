class_name TossDie
extends Control
## Кубик d6 «на столе» (спрайт PerudoDie) с физикой монетки-антистресса: схватить, потянуть и бросить —
## летит с трением, отскакивает от краёв area, кувыркается (грани мелькают); остановился — показывает
## результат с хоста (set_result), через секунду возвращается на место (home) и становится неактивным.
## Пока бросать нельзя — полупрозрачный. API как у K12Die3D: thrown(vel), throw(vel, result), set_result, wait_for_roll.

signal thrown(vel: Vector2)

const SIDE := 64.0
const FRICTION := 2.2
const BOUNCE := 0.55
const MAX_SPEED := 2600.0

var home := Vector2.ZERO  # центр места кубика
var area := Rect2(0, 0, 1280, 720)  # где летает (поле)
var draggable := false:
	set(v):
		draggable = v
		mouse_default_cursor_shape = Control.CURSOR_DRAG if v else Control.CURSOR_ARROW
var state := "idle"  # idle, waiting, dragging, flying, settled, returning

var _die: PerudoDie
var _vel := Vector2.ZERO
var _spin := 0.0
var _result := 0
var _flick := 0.0
var _rest := 0.0
var _rope := 0.0
var _rot0 := 0.0
var _dir0 := 0.0
var _grab := Vector2.ZERO
var _samples: Array = []


func _init() -> void:
	size = Vector2(SIDE, SIDE)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	_die = PerudoDie.new(1, SIDE)
	_die.star_one = false
	_die.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_die)
	modulate.a = 0.45


func center() -> Vector2:
	return position + size * 0.5


func _set_center(p: Vector2) -> void:
	position = p - size * 0.5


func is_busy() -> bool:
	return state in ["dragging", "flying", "returning"]


## Твой бросок: кубик яркий на своём месте, ждёт броска мышью.
func wait_for_roll() -> void:
	state = "waiting"
	_result = 0
	rotation = 0.0
	_set_center(home)
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)


## Бросок без мыши (чужой ход, бот): result — что выпадет (0 — придёт позже через set_result).
func throw(vel: Vector2, result: int = 0) -> void:
	visible = true
	modulate.a = 1.0 if draggable or state == "waiting" else 0.8
	_set_center(home if state != "dragging" else center())
	_vel = vel.limit_length(MAX_SPEED)
	_spin = randf_range(-14.0, 14.0)
	_result = result
	_rest = 0.0
	state = "flying"
	Sfx.play("die_throw", -4, 0.08, 0.05)


func set_result(f: int) -> void:
	_result = clampi(f, 1, 6)


func _gui_input(e: InputEvent) -> void:
	if draggable and state == "waiting" and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		state = "dragging"
		_grab = e.global_position - center()
		_rope = _grab.length()
		_rot0 = rotation
		_dir0 = (-_grab).angle()
		_samples = [[Time.get_ticks_msec(), e.global_position, rotation]]
		Sfx.play("die_grab", -8)
		accept_event()


func _input(e: InputEvent) -> void:
	if state != "dragging":
		return
	if e is InputEventMouseMotion:
		# висит на точке хвата (как монетка): водишь по кругу — кубик крутится вокруг неё
		var m: Vector2 = e.global_position
		var c := center()
		var d := c - m
		if _rope > 3.0 and d.length() > 0.5:
			c = m + d.normalized() * _rope
			rotation = _rot0 + angle_difference(_dir0, d.angle())
		else:
			c = m - _grab
		_set_center(c)
		_samples.append([Time.get_ticks_msec(), m, rotation])
		while _samples.size() > 2 and Time.get_ticks_msec() - int(_samples[0][0]) > 90:
			_samples.pop_front()
		_die.value = randi_range(1, 6) if randf() < 0.15 else _die.value
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		var a: Array = _samples[0]
		var b: Array = _samples[_samples.size() - 1]
		var dt := maxf(0.016, (int(b[0]) - int(a[0])) / 1000.0)
		var vel := ((b[1] as Vector2) - (a[1] as Vector2)) / dt
		if vel.length() < 250.0:
			vel = (area.get_center() - center()).normalized() * 450.0  # отпустил без размаха — лёгкий бросок к центру
		_vel = vel.limit_length(MAX_SPEED)
		_spin = clampf(angle_difference(float(a[2]), float(b[2])) / dt, -30.0, 30.0) + randf_range(-6.0, 6.0)
		_rest = 0.0
		state = "flying"
		draggable = false
		Sfx.play("die_throw", lerpf(-10.0, 0.0, clampf(_vel.length() / 2000.0, 0.0, 1.0)), 0.08, 0.05)
		thrown.emit(_vel)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state != "flying":
		return
	var c := center() + _vel * delta
	var r := area.grow(-SIDE * 0.5)
	if c.x < r.position.x or c.x > r.end.x:
		_vel.x = -_vel.x * BOUNCE
		_spin = -_spin * 0.7
		_hit()
	if c.y < r.position.y or c.y > r.end.y:
		_vel.y = -_vel.y * BOUNCE
		_spin = -_spin * 0.7
		_hit()
	_set_center(c.clamp(r.position, r.end))
	_vel *= exp(-FRICTION * delta)
	_spin *= exp(-2.0 * delta)
	rotation += _spin * delta
	# грани мелькают, пока кубик катится; чем медленнее — тем реже
	var speed := _vel.length()
	_flick += delta * clampf(speed / 60.0, 2.0, 24.0)
	if _flick >= 1.0:
		_flick = 0.0
		_die.value = randi_range(1, 6)
	if speed < 40.0:
		_rest += delta
		if _result > 0 and _rest > 0.15:
			_settle()


func _hit() -> void:
	if _vel.length() > 80.0:
		Sfx.play("die_hit", lerpf(-16.0, -4.0, clampf(_vel.length() / 1500.0, 0.0, 1.0)), 0.15, 0.04)


## Остановился: результат, пауза, потом назад на место и неактивный.
func _settle() -> void:
	state = "settled"
	_die.value = _result
	var t := create_tween()
	t.tween_property(self, "rotation", round(rotation / (PI / 2.0)) * (PI / 2.0), 0.15)
	t.tween_property(self, "scale", Vector2(1.15, 1.15), 0.1)
	t.tween_property(self, "scale", Vector2.ONE, 0.12)
	t.tween_interval(1.0)
	t.tween_callback(func(): state = "returning")
	t.tween_property(self, "position", home - size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(self, "rotation", 0.0, 0.45)
	t.parallel().tween_property(self, "modulate:a", 0.45, 0.45)
	t.tween_callback(func(): state = "idle")
