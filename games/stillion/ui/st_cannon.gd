class_name STCannon
extends Control
## Пушка: восемь ракурсов, дыхание, надувание, четыре стадии злости, покраснение и отдача.
## aim — угол к игроку; inflate 0..1 задаётся фитилём. Правила и результат выстрела остаются на столе.

const REGIONS := [
	Rect2(0, 142, 384, 346),
	Rect2(405, 113, 363, 379),
	Rect2(789, 87, 327, 401),
	Rect2(1152, 126, 384, 366),
	Rect2(7, 615, 377, 344),
	Rect2(420, 583, 348, 359),
	Rect2(790, 576, 327, 367),
	Rect2(1152, 582, 351, 358)
]
const MUZZLES := [
	Vector2(351, 287),
	Vector2(327, 310),
	Vector2(192, 324),
	Vector2(56, 305),
	Vector2(61, 258),
	Vector2(126, 139),
	Vector2(192, 124),
	Vector2(298, 141)
]
const FUSES := [
	Vector2(72, 186),
	Vector2(103, 157),
	Vector2(192, 139),
	Vector2(315, 172),
	Vector2(317, 178),
	Vector2(327, 267),
	Vector2(192, 290),
	Vector2(88, 261)
]

var aim := 0.0
var inflate := 0.0
var burning := false
var fuse_left := 12.0  # секунды до выстрела
var fuse_duration := 12.0  # длительность текущего фитиля
const EXPRESSION_TIME := 0.5
const TIMING_ADVANCE := 0.75  # пороги выражения на 25% раньше по доле фитиля
var _angle := 0.0
var _t := 0.0
var _pressure := 0.0
var _spring_v := 0.0
var _recoil := 0.0
var _flash := 0.0
var _blink := 0.0
var _smoke: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _picture: TextureRect
var _paint: ShaderMaterial
var _frame := 0
var _old_frame := 0
var _turn_blend := 1.0
var _anger := 0.0
var _sprite_scale := 1.0


## Визуальное состояние сохраняется при смене темы, правила и таймер остаются на хосте.
func animation_state() -> Dictionary:
	var state := {}
	for key in ["aim", "inflate", "burning", "fuse_left", "fuse_duration", "_angle", "_t", "_pressure", "_spring_v", "_recoil", "_flash", "_blink", "_smoke", "_sparks", "_frame", "_old_frame", "_turn_blend", "_anger"]:
		state[key] = get(key)
	return state.duplicate(true)


func restore_animation(state: Dictionary) -> void:
	for key in animation_state():
		if state.has(key):
			set(key, state[key])
	_sync_sprite(0.0)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Пощекотать пушку"
	_picture = TextureRect.new()
	_picture.texture = preload("res://games/stillion/art/cannon_directions_painted.png")
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.show_behind_parent = true
	_paint = ShaderMaterial.new()
	_paint.shader = preload("res://games/stillion/ui/st_cannon_sprite.gdshader")
	_paint.set_shader_parameter("angry_sheet", preload("res://games/stillion/art/cannon_angry_painted.png"))
	_picture.material = _paint
	add_child(_picture)
	_sync_sprite(0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_blink = 1.0
		_recoil = maxf(_recoil, 0.2)
		Sfx.play("click", -18)
		accept_event()


func deflate() -> void:
	inflate = 0.0
	_spring_v = -3.5


func fire() -> void:
	_recoil = 1.0
	_flash = 1.0
	inflate = 0.0
	_pressure = 0.0
	var direction := Vector2.from_angle(_angle)
	for i in 14:
		_smoke.append(
			{
				"pos": _muzzle_world() + direction * randf_range(0, 12),
				"vel": direction.rotated(randf_range(-0.8, 0.8)) * randf_range(40, 130) + Vector2(0, -20),
				"r": randf_range(8, 20),
				"life": randf_range(0.9, 1.6),
				"age": 0.0
			}
		)


func _process(delta: float) -> void:
	_t += delta
	_angle = lerp_angle(_angle, aim, 1.0 - exp(-delta * 7.0))
	if _pressure > inflate + 0.02 or not is_zero_approx(_spring_v):
		_spring_v += (inflate - _pressure) * 60.0 * delta
		_spring_v *= exp(-delta * 7.0)
		_pressure += _spring_v * delta
		if absf(_spring_v) < 0.02 and absf(_pressure - inflate) < 0.01:
			_spring_v = 0.0
	else:
		_pressure = lerpf(_pressure, inflate, 1.0 - exp(-delta * 5.0))
	_pressure = clampf(_pressure, -0.15, 1.1)
	_recoil = maxf(0.0, _recoil - delta * 2.2)
	_flash = maxf(0.0, _flash - delta * 4.0)
	_blink = maxf(0.0, _blink - delta * 7.0)
	for puff: Dictionary in _smoke:
		puff.age += delta
		puff.pos += puff.vel * delta
		puff.vel *= exp(-delta * 1.8)
		puff.vel.y -= 20.0 * delta
	_smoke = _smoke.filter(func(puff): return puff.age < puff.life)
	if burning:
		_sparks.append(
			{
				"pos": _fuse_tip_world(),
				"vel": Vector2(randf_range(-45, 45), randf_range(-90, -30)),
				"age": 0.0,
				"life": randf_range(0.2, 0.45)
			}
		)
	for spark: Dictionary in _sparks:
		spark.age += delta
		spark.pos += spark.vel * delta
		spark.vel.y += 220.0 * delta
	_sparks = _sparks.filter(func(spark): return spark.age < spark.life)
	_sync_sprite(delta)
	queue_redraw()


## Ракурс меняется на земле: колёса всегда снизу, картинка не переворачивается на голову.
func _sync_sprite(delta: float) -> void:
	if not is_instance_valid(_picture):
		return
	var next := posmod(int(round(_angle / (PI * 0.25))), 8)
	if next != _frame:
		_old_frame = _frame
		_frame = next
		_turn_blend = 0.0
	_turn_blend = minf(1.0, _turn_blend + delta * 10.0)
	var elapsed := maxf(0.0, fuse_duration - fuse_left)
	var start := maxf(0.0, fuse_duration - 3.0) * TIMING_ADVANCE
	var level := clampi(int(ceil((elapsed - start) / EXPRESSION_TIME)), 0, 3) if inflate > 0.0 else 0
	_anger = move_toward(_anger, level / 3.0, delta / (3.0 * EXPRESSION_TIME))
	var region: Rect2 = REGIONS[_frame]
	_sprite_scale = minf(size.x * 0.94 / 384.0, size.y * 0.94 / 401.0)
	_picture.size = region.size * _sprite_scale * 1.36
	_picture.position = Vector2(
		(size.x - _picture.size.x) * 0.5, size.y * 0.86 - region.size.y * _sprite_scale * 1.18
	)
	_picture.pivot_offset = Vector2(_picture.size.x * 0.5, _picture.size.y)
	_picture.rotation = sin(_t * 29.0) * pow(maxf(0.0, _pressure), 4.0) * 0.009
	_picture.rotation += sin(_turn_blend * PI) * 0.02
	_picture.scale = Vector2(1.0 - sin(_turn_blend * PI) * 0.035, 1.0)
	var sheet_size := _picture.texture.get_size()
	var previous: Rect2 = REGIONS[_old_frame]
	_paint.set_shader_parameter(
		"region",
		Vector4(
			region.position.x / sheet_size.x,
			region.position.y / sheet_size.y,
			region.size.x / sheet_size.x,
			region.size.y / sheet_size.y
		)
	)
	_paint.set_shader_parameter(
		"previous_region",
		Vector4(
			previous.position.x / sheet_size.x,
			previous.position.y / sheet_size.y,
			previous.size.x / sheet_size.x,
			previous.size.y / sheet_size.y
		)
	)
	_paint.set_shader_parameter("turn_blend", _turn_blend)
	_paint.set_shader_parameter("anger", _anger)
	_paint.set_shader_parameter("pressure", maxf(0.0, _pressure))
	_paint.set_shader_parameter("heat", clampf(maxf(0.0, _pressure) / TIMING_ADVANCE, 0.0, 1.0))
	_paint.set_shader_parameter("recoil", _recoil)
	_paint.set_shader_parameter("direction", Vector2.from_angle(_angle))
	_paint.set_shader_parameter("breath", sin(_t * 2.2) * 0.012 * (1.0 - maxf(0.0, _pressure)))


func _sprite_point(point: Vector2) -> Vector2:
	var offset := Vector2((_frame % 4) * 384, (_frame / 4) * 512)
	var region: Rect2 = REGIONS[_frame]
	return _picture.position + (offset + point - region.position + region.size * 0.18) * _sprite_scale


func _muzzle_world() -> Vector2:
	return _sprite_point(MUZZLES[_frame]) if is_instance_valid(_picture) else size * 0.5


func _fuse_tip_world() -> Vector2:
	return _sprite_point(FUSES[_frame]) if is_instance_valid(_picture) else size * 0.5


func _draw() -> void:
	for spark: Dictionary in _sparks:
		var alpha := 1.0 - float(spark.age) / float(spark.life)
		draw_circle(spark.pos, 1.5 + alpha, Color(1.0, 0.8, 0.2, alpha))
	if burning:
		_star(_fuse_tip_world(), 5.0 + sin(_t * 35.0), Color("ffd34d"), Color("ff7a1a"))
	if _flash > 0.0:
		_star(
			_muzzle_world(), 24.0 + 30.0 * _flash, Color(1, 0.97, 0.75, _flash), Color(1, 0.55, 0.1, _flash)
		)
	for puff: Dictionary in _smoke:
		var life := float(puff.age) / float(puff.life)
		var radius := float(puff.r) * (1.0 + life * 1.4)
		draw_circle(puff.pos, radius, Color(0.93, 0.9, 0.84, 0.8 * (1.0 - life)))
		draw_arc(puff.pos, radius, 0, TAU, 20, Color(0.12, 0.1, 0.09, 0.5 * (1.0 - life)), 1.5, true)


func _star(center: Vector2, radius: float, inner: Color, outer: Color) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var angle := PI * i / 8.0 + _t * 2.0
		points.append(center + Vector2.from_angle(angle) * radius * (1.0 if i % 2 == 0 else 0.45))
	draw_colored_polygon(points, outer)
	var small := PackedVector2Array()
	for point: Vector2 in points:
		small.append(center + (point - center) * 0.55)
	draw_colored_polygon(small, inner)
