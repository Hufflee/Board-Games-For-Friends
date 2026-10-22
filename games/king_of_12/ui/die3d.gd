class_name K12Die3D
extends Control
## 3D-кубик d12 (рендер в SubViewport с двойным разрешением, показ через TextureRect). Его можно схватить, протянуть и бросить:
## он летит по сукну, отскакивает от бортика, крутится и ложится нужной гранью к камере.
## Результат (грань) приходит от хоста через set_result(). Как только он известен, оставшийся полёт
## просчитывается заранее (фиксированный шаг физики, без случайностей), и к вращению плавно
## подмешивается поправка — кубик сам останавливается нужной гранью, без доворота в конце.

signal thrown(vel: Vector2)
signal settled

const SIZE := 104.0
const MAX_SPEED := 2600.0

var home := Vector2.ZERO  # центр «своего» места на столе (в координатах родителя)
var felt_center := Vector2(640, 300)
var felt_radii := Vector2(520, 190)
var draggable := false:
	set(v):
		draggable = v
		mouse_default_cursor_shape = Control.CURSOR_DRAG if v else Control.CURSOR_ARROW
		_overlay.queue_redraw()
var crossed := false:
	set(v):
		crossed = v
		_overlay.queue_redraw()
var highlight := Color.TRANSPARENT:
	set(v):
		highlight = v
		_overlay.queue_redraw()
var value_text := "":
	set(v):
		value_text = v
		_value_label.text = v
		_value_label.visible = v != ""

var state := "idle"  # idle, waiting, dragging, flying, settling, returning
var face := 0  # показанная грань (0 — ещё не брошен)

var _body: Node3D
var _q := Quaternion.IDENTITY
var _w := Vector3.ZERO
var _vel := Vector2.ZERO
var _target := 0
var _t := 0.0
var _from_q := Quaternion.IDENTITY
var _to_q := Quaternion.IDENTITY
var _from_pos := Vector2.ZERO
var _grab := Vector2.ZERO
var _samples: Array = []
var _overlay: Control
var _value_label: Label

const STEP := 1.0 / 120.0  # шаг физики полёта (одинаковый для просчёта и показа)
var _fs := {}  # состояние полёта: pos, vel, w, q (без поправки), t
var _acc := 0.0
var _corr := Quaternion.IDENTITY  # поправка, которая приводит полёт к нужной грани
var _plan_steps := 0
var _plan_k := 0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(SIZE * 2, SIZE * 2)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var tex := TextureRect.new()
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size = Vector2(SIZE, SIZE)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.55, 0.75)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 5.2)
	cam.fov = 30.0
	vp.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.9
	sun.light_color = Color(1.0, 0.92, 0.8)
	vp.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 1.5, 3.5)
	fill.light_energy = 0.5
	fill.omni_range = 8.0
	vp.add_child(fill)

	_body = Node3D.new()
	_body.scale = Vector3.ONE * 0.55
	vp.add_child(_body)
	_build_die(_body)
	_q = Quaternion(Vector3(1, 1, 0).normalized(), 0.6)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 15)
	_value_label.add_theme_color_override("font_color", Color.WHITE)
	_value_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_value_label.add_theme_constant_override("outline_size", 6)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.position = Vector2(-80, SIZE - 12)
	_value_label.size = Vector2(SIZE + 160, 44)
	_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_value_label.visible = false
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_value_label)


static func _build_die(body: Node3D) -> void:
	var faces := K12DieGeometry.faces()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var n: Vector3 = faces[f]["normal"]
		var v: PackedVector3Array = faces[f]["verts"]
		for i in range(1, 4):
			for p in [v[0], v[i], v[i + 1]]:
				st.set_normal(n)
				st.add_vertex(p)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.38, 0.82)
	mat.metallic = 0.25
	mat.roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.3
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.18, 0.45)
	mat.emission_energy_multiplier = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = mat
	body.add_child(mesh)

	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	for f in faces:
		var v: PackedVector3Array = faces[f]["verts"]
		for i in 5:
			lines.add_vertex(v[i] * 1.003)
			lines.add_vertex(v[(i + 1) % 5] * 1.003)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.55)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var edge := MeshInstance3D.new()
	edge.mesh = lines.commit()
	edge.material_override = line_mat
	body.add_child(edge)

	for f in faces:
		var n: Vector3 = faces[f]["normal"]
		var u: Vector3 = faces[f]["up"]
		var lbl := Label3D.new()
		lbl.text = str(f) + ("." if f == 6 or f == 9 else "")
		lbl.font_size = 96
		lbl.pixel_size = 0.0082
		lbl.outline_size = 22
		lbl.modulate = Color(1, 1, 1)
		lbl.outline_modulate = Color(0.02, 0.08, 0.25, 1.0)
		lbl.shaded = false
		lbl.double_sided = false
		lbl.transform = Transform3D(Basis(u.cross(n), u, n), faces[f]["center"] + n * 0.02)
		body.add_child(lbl)


# --- API ---------------------------------------------------------------------

## Кубик ещё не брошен: медленно крутится на своём месте.
func wait_for_roll() -> void:
	state = "waiting"
	face = 0
	_target = 0
	_set_center(home)
	_w = Vector3(0.4, 1.0, 0.2).normalized() * 1.2


## Показать грань (сразу или плавным поворотом).
func show_face(f: int, animate: bool = true) -> void:
	if f < 1 or f > 12:
		return
	if state in ["dragging", "flying", "settling", "returning"]:
		if state == "dragging" or (state == "flying" and _target == 0):
			set_result(f)
		return
	if f == face and state == "idle":
		return
	face = f
	_target = f
	_w = Vector3.ZERO
	if animate and is_inside_tree():
		_from_q = _q
		_to_q = K12DieGeometry.orientation(f)
		_t = 0.0
		state = "turning"
		Sfx.play("die_shake", -10, 0.06, 0.15)
	else:
		_q = K12DieGeometry.orientation(f)
		state = "idle"
		_apply()


## Бросок с текущего места со скоростью vel (px/с). Грань станет известна через set_result().
func throw(vel: Vector2, result: int = 0) -> void:
	_vel = vel.limit_length(MAX_SPEED)
	Sfx.play("die_throw", lerpf(-10.0, 0.0, clampf(_vel.length() / 2000.0, 0.0, 1.0)), 0.08, 0.05)
	_t = 0.0
	state = "flying"
	var w_extra := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-3, 3))
	_w = _rolling_w(_vel) + w_extra
	_fs = {"pos": center(), "vel": _vel, "w": _w, "q": _q, "t": 0.0}
	_acc = 0.0
	_corr = Quaternion.IDENTITY
	_plan_steps = 0
	_plan_k = 0
	var res := result if result > 0 else _target  # результат мог прийти, пока кубик держали
	_target = 0
	if res > 0:
		set_result(res)


## Результат броска пришёл: просчитываем остаток полёта и вычисляем поправку вращения.
func set_result(f: int) -> void:
	_target = f
	if state != "flying" or _fs.is_empty():
		return
	# начинаем с того, что видно сейчас (если поправка уже была — она сохраняется)
	_fs["q"] = _display_q()
	var sim := _fs.duplicate()
	var n := 0
	while not _flight_done(sim) and n < 3000:
		_flight_step(sim, false)
		n += 1
	var corr := K12DieGeometry.orientation(f) * (sim["q"] as Quaternion).inverse()
	if corr.w < 0.0:
		corr = -corr
	_corr = corr
	_plan_steps = maxi(n, 1)
	_plan_k = 0


func is_busy() -> bool:
	return state in ["dragging", "flying", "settling", "returning"]


# --- Управление мышью ----------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not draggable or state != "waiting":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		state = "dragging"
		Sfx.play("die_grab")
		_grab = _to_parent(event.global_position) - center()
		_samples.clear()
		accept_event()


func _input(event: InputEvent) -> void:
	if state != "dragging":
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = _to_parent(event.global_position) - _grab
		var now := Time.get_ticks_msec() / 1000.0
		_samples.append([now, p])
		while _samples.size() > 2 and now - _samples[0][0] > 0.09:
			_samples.pop_front()
		_set_center(p)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var vel := _release_velocity()
		draggable = false
		throw(vel)
		thrown.emit(_vel)
		get_viewport().set_input_as_handled()


func _release_velocity() -> Vector2:
	var vel := Vector2.ZERO
	var fresh: bool = _samples.size() >= 2 and Time.get_ticks_msec() / 1000.0 - _samples[-1][0] < 0.12
	if fresh:
		var a: Array = _samples[0]
		var b: Array = _samples[-1]
		var dt: float = maxf(0.016, b[0] - a[0])
		vel = (b[1] - a[1]) / dt
	if vel.length() < 250.0:
		vel = (felt_center - center()).normalized().rotated(randf_range(-0.5, 0.5)) * 900.0
	return vel.limit_length(MAX_SPEED)


# --- Анимация ------------------------------------------------------------------

func _process(delta: float) -> void:
	match state:
		"waiting":
			_spin(delta)
		"dragging":
			var now := Time.get_ticks_msec() / 1000.0
			if _samples.size() >= 2 and now - _samples[-1][0] < 0.1:
				var v: Vector2 = (_samples[-1][1] - _samples[0][1]) / maxf(0.016, _samples[-1][0] - _samples[0][0])
				_w = _w.lerp(_rolling_w(v) * 0.6 + Vector3(0, 0, 1.5), 0.2)
			else:
				_w = _w.lerp(Vector3(0.3, 0.8, 1.5), 0.05)
			_spin(delta)
		"flying":
			_acc += delta
			while _acc >= STEP and state == "flying":
				_acc -= STEP
				if _flight_done(_fs):
					if _target > 0:
						# полёт закончился ровно на нужной грани (с учётом поправки)
						state = "settling"
						_t = 0.0
						_from_q = _display_q()
						_to_q = K12DieGeometry.orientation(_target)
					else:
						# результат ещё не пришёл — кубик медленно докручивается на месте
						_fs["w"] = (_fs["w"] as Vector3).lerp(Vector3(0.3, 0.9, 0.4), 0.02)
						_fs["q"] = _rotate(_fs["q"], _fs["w"], STEP)
					break
				_flight_step(_fs, true)
				if _plan_steps > 0:
					_plan_k += 1
			_vel = _fs["vel"]
			_t = _fs["t"]
			_set_center(_fs["pos"])
			_q = _display_q()
			_apply()
		"settling":
			# страховка от погрешности: доводка почти незаметна (кубик уже на нужной грани)
			_t += delta
			var k := ease(minf(_t / 0.15, 1.0), -2.0)
			_q = _from_q.slerp(_to_q, k)
			_apply()
			if _t >= 0.15:
				Sfx.play("die_hit", -14, 0.1, 0.1)
				face = _target
				state = "returning"
				_t = 0.0
				_from_pos = center()
		"returning":
			_t += delta
			var k := ease(minf(_t / 0.6, 1.0), -2.0)
			_set_center(_from_pos.lerp(home, k))
			if _t >= 0.6 + 0.35:
				_set_center(home)
				state = "idle"
				settled.emit()
		"turning":
			_t += delta
			_q = _from_q.slerp(_to_q, ease(minf(_t / 0.5, 1.0), -2.0))
			_apply()
			if _t >= 0.5:
				state = "idle"


func _spin(delta: float) -> void:
	var speed := _w.length()
	if speed > 0.0001:
		_q = (Quaternion(_w / speed, speed * delta) * _q).normalized()
	_apply()


func _apply() -> void:
	if _body:
		_body.quaternion = _q


## Угловая скорость «качения» по столу для экранной скорости v.
static func _rolling_w(v: Vector2) -> Vector3:
	return Vector3(v.y, v.x, 0.0) / 42.0


## Вид кубика сейчас: свободное вращение плюс доля поправки (растёт плавно к концу полёта).
func _display_q() -> Quaternion:
	if _fs.is_empty():
		return _q
	var q: Quaternion = _fs["q"]
	if _plan_steps <= 0:
		return q
	var k := smoothstep(0.0, 1.0, clampf(float(_plan_k) / _plan_steps, 0.0, 1.0))
	return (Quaternion.IDENTITY.slerp(_corr, k) * q).normalized()


## Один шаг полёта. Без случайностей — чтобы просчёт заранее совпал с показом.
func _flight_step(st: Dictionary, live: bool) -> void:
	st["t"] += STEP
	var vel: Vector2 = st["vel"]
	vel *= exp(-1.6 * STEP)
	vel = vel.move_toward(Vector2.ZERO, 260.0 * STEP)
	var p: Vector2 = st["pos"] + vel * STEP
	var w: Vector3 = st["w"]
	var r := felt_radii - Vector2(SIZE, SIZE) * 0.42
	var e := (p - felt_center) / r
	if e.length() > 1.0:
		var normal := Vector2(e.x / r.x, e.y / r.y).normalized()
		if vel.dot(normal) > 0.0:
			if live:
				Sfx.play("die_hit", lerpf(-16.0, -2.0, clampf(vel.length() / 1500.0, 0.0, 1.0)), 0.12, 0.08)
			vel = (vel - 2.0 * vel.dot(normal) * normal) * 0.72
			w += Vector3(-normal.y, normal.x, 0.0) * 2.5 + Vector3(0, 0, 3.0 * signf(vel.cross(normal)))
		p = felt_center + e.normalized() * r
	w = w.lerp(_rolling_w(vel), 1.0 - pow(0.92, STEP * 60.0))
	if vel.length() < 90.0:
		w *= exp(-3.0 * STEP)
	st["vel"] = vel
	st["pos"] = p
	st["w"] = w
	st["q"] = _rotate(st["q"], w, STEP)


func _flight_done(st: Dictionary) -> bool:
	return st["t"] > 0.7 and (st["vel"] as Vector2).length() < 120.0


static func _rotate(q: Quaternion, w: Vector3, dt: float) -> Quaternion:
	var speed := w.length()
	if speed < 0.0001:
		return q
	return (Quaternion(w / speed, speed * dt) * q).normalized()


func _to_parent(p: Vector2) -> Vector2:
	return (get_parent() as CanvasItem).get_global_transform_with_canvas().affine_inverse() * p


func center() -> Vector2:
	return position + size / 2.0


func _set_center(p: Vector2) -> void:
	position = p - size / 2.0


func _draw_overlay() -> void:
	var c := size / 2.0
	if highlight.a > 0.0:
		_overlay.draw_arc(c, SIZE * 0.47, 0, TAU, 48, highlight, 4.0, true)
	if draggable:
		var a := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
		_overlay.draw_arc(c, SIZE * 0.49, 0, TAU, 48, Color(1.0, 0.85, 0.4, 0.45 + 0.5 * a), 3.0, true)
	if crossed:
		var r := SIZE * 0.32
		_overlay.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color(0.95, 0.25, 0.2, 0.95), 6.0, true)
		_overlay.draw_line(c + Vector2(r, -r), c + Vector2(-r, r), Color(0.95, 0.25, 0.2, 0.95), 6.0, true)


func _physics_process(_delta: float) -> void:
	if draggable:
		_overlay.queue_redraw()
