extends Node3D
## Украшения зимней комнаты главного меню (HubRooms, id "winter") поверх общей комнаты hub/neon_room.gd:
## ёлка с огоньками, игрушками и звездой, подарки, гирлянды (под потолком, на левой стене, вокруг окна,
## на тумбе телевизора), носки для подарков, венок и бумажные снежинки на стенах. Снег за окном
## включает сама комната (snow = true → шейдер окна).
## Ограничения: ёлка — на месте скейтборда (владелец, 14.11), но не ближе к шкафу, чем был скейтборд (шкаф
## может расшириться до x ≈ −0,88): правый край кроны и подарков левее −0,9. Скейтборд зимой стоит в левом
## переднем углу у изножья кровати (skateboard_pose); на задней стене ничего не висит ниже 2,55 м, кроме окна и тумбы, — шкафу,
## доскам и плакатам место не занимаем. Ёлка и подарки — препятствия для мяча (ball_blocks).
## Строится вызовом build(room) после добавления в дерево; координаты — локальные координаты комнаты.

const W := 6.0
const H := 2.8
const BACK := -2.0
const TREE := Vector3(-1.27, 0.0, -1.6)  # у задней стены, где летом скейтборд
const TREE_SCALE := 0.85  # крона уже обычной: правый край не ближе к шкафу, чем скейтборд
const BULB_COLORS: Array[Color] = [Color("ffcf6e"), Color("ff3ea5"), Color("2ef2ff"), Color("b07bff")]
const BOW_SPOTS: Array[Vector2] = [Vector2(0.62, 1.5), Vector2(1.45, 1.85), Vector2(-0.55, 2.25)]  # (z, y) на левой стене
const BULB_ENERGY := 1.12  # 3,2 × 0,35: владелец — огни на 65 % тусклее первой версии (14.11)

var snow := true  # снег за окном
## Скейтборд зимой — в левом переднем углу, прислонён к левой стене (комната применяет и возвращает сама).
var skateboard_pose := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_euler(Vector3(deg_to_rad(-10), 0, deg_to_rad(-12))), Vector3(-2.84, 0.4, 0.62))
var _room: Node3D
var _bulbs: Array = []  # [группа × 4 + цвет] → список Transform3D → MultiMesh
var _bulb_materials: Array[ShaderMaterial] = []  # то же деление: ёлка (0..3) и стены (4..7)
var _group := WALLS  # куда сейчас добавляются лампочки
const TREE_LIGHTS := 0
const WALLS := 1
## Режимы огней (владелец, 14.11): 0 — цвета плавно перетекают волной; 1 — горит один цвет, остальные
## тёмные, через 7 с он гаснет и плавно загорается следующий; 2 — быстро мигают, цвета меняются.
## Ёлка и гирлянды на стенах — отдельно; одинаковые режимы идут синхронно (общее время темы).
const MODE_NAMES := ["Переливы", "По одному цвету", "Мигание"]
const MODES_PATH := "user://room_props.cfg"
var modes: Array[int] = [0, 0]
var _hidden: Array = []  # прежние звёзды комнаты, скрытые на время зимы
var _cassette_colors: Array = []
var sticker_count := 0  # сколько наклеек разложено (для проверки плотности)
var _vcr_saved: Array = []
var _star_material: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0
var _tiers: Array = []  # ярусы ёлки: [низ, высота, радиус]
var _into: Node3D = null  # куда складывать новые сетки (гирлянда шкафа пересобирается отдельно)
var _shelf_garland: Node3D
var _shelf_seen := AABB()
var _shelf_clock := 0.0
var _tv_snow: Control


func build(room: Node3D) -> void:
	_room = room
	var palette := PackedVector3Array()
	for color: Color in BULB_COLORS:
		palette.append(Vector3(color.r, color.g, color.b))
	for group in 2:
		for i in BULB_COLORS.size():
			var m := ShaderMaterial.new()
			m.shader = load("res://hub/rooms/bulb.gdshader")
			m.set_shader_parameter("palette", palette)
			m.set_shader_parameter("base_index", i)
			m.set_shader_parameter("color_index", i)
			m.set_shader_parameter("energy", BULB_ENERGY)
			_bulb_materials.append(m)
			_bulbs.append([])
	load_modes()
	_tree()
	_gifts()
	_ceiling_garlands()
	_left_wall()
	_window_lights()
	_tv_garland()
	_snowflakes()
	_carpet()
	_tv_dress()
	_winter_props()
	_flush_bulbs()
	_update_shelf_garland()


func _exit_tree() -> void:
	_restore_props()
	# венок висит на двери комнаты (не в узле темы) — убираем сами
	var hinge: Variant = _room.get("door_hinge") if is_instance_valid(_room) else null
	if hinge is Node3D and is_instance_valid(hinge):
		for child: Node in (hinge as Node3D).get_children():
			if child.has_meta("winter_decor"):
				child.queue_free()
	# снег на экране телевизора живёт во вьюпорте комнаты — убираем вместе с темой
	if is_instance_valid(_tv_snow):
		_tv_snow.queue_free()


## Препятствия для мяча: [нижний угол, верхний угол] в координатах комнаты.
func ball_blocks() -> Array:
	return [
		[TREE + Vector3(-0.37, 0.0, -0.37), TREE + Vector3(0.37, 2.0, 0.37)],
		[TREE + Vector3(-0.2, 0.0, 0.12), TREE + Vector3(0.37, 0.32, 0.8)],  # подарки
	]


## Новая игра в зимней комнате появляется под ёлкой подарком (hub/rooms/arrivals.gd): лежит плашмя
## перед ёлкой, обложкой вверх (координаты комнаты).
func gift_pose(box_size: Vector3) -> Transform3D:
	var basis := Basis(Vector3.UP, 0.35) * Basis(Vector3.BACK, PI * 0.5)
	return Transform3D(basis, TREE + Vector3(-0.22, box_size.x * 0.5 + 0.01, 0.95))  # перед ёлкой, не в куче подарков


func apply_quality(q: int) -> void:
	if is_instance_valid(_light):
		_light.visible = q >= 1


func _process(delta: float) -> void:
	_t += delta
	for group in 2:
		for i in BULB_COLORS.size():
			var state := Vector2(0.68, i) if Prefs.reduce_motion else _light_state(modes[group], i, _t)
			var m := _bulb_materials[group * BULB_COLORS.size() + i]
			m.set_shader_parameter("lit", state.x)
			m.set_shader_parameter("color_index", int(state.y))
			m.set_shader_parameter("blink", 1.0 if modes[group] == 2 and not Prefs.reduce_motion else 0.0)  # мигание вразнобой считает шейдер
	if _star_material != null:
		_star_material.emission_energy_multiplier = 0.91 if Prefs.reduce_motion else 0.91 + 0.18 * sin(_t * 2.1)
	_shelf_clock += delta
	if _shelf_clock >= 0.25:
		_shelf_clock = 0.0
		_update_shelf_garland()


# --- Примитивы -------------------------------------------------------------------------

func _mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # самодельные сетки (ярусы, провода) — без забот о порядке вершин
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _mesh(mesh: Mesh, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	(_into if parent == self and _into != null else parent).add_child(mi)
	return mi


func _cyl(r_top: float, r_bottom: float, h: float, at: Vector3, material: Material, segments: int = 20) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	return _mesh(c, at, material)


func _sphere(r: float, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return _mesh(s, at, material, parent)


## Провисающая между a и b линия (парабола), n отрезков.
func _swag(a: Vector3, b: Vector3, sag: float, n: int = 16) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		points.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	return points


## Трубка вдоль ломаной (провод гирлянды, мишура): шестигранное сечение, одна сетка.
func _tube(points: PackedVector3Array, radius: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings: Array = []
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length() < 0.1:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var ring: Array = []
		for k in sides:
			var a := k * TAU / sides
			var normal := side * cos(a) + up * sin(a)
			ring.append([points[i] + normal * radius, normal])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			for v: Array in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return _mesh(st.commit(), Vector3.ZERO, material)


## Лампочки гирлянды вдоль линии: каждые step м, чуть ниже провода, цвета по кругу.
func _string_bulbs(points: PackedVector3Array, step: float, hang: float = 0.018, phase: int = 0, size: float = 1.0) -> void:
	var walked := 0.0
	var next := step * 0.5
	var index := phase
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		while next <= walked + length:
			var at := a.lerp(b, (next - walked) / length) + Vector3.DOWN * hang
			_add_bulb(at, index, Vector3(1.0, 1.45, 1.0) * size)
			index += 1
			next += step
		walked += length
	if _group == WALLS:
		_zone(points)


## Невидимая форма вдоль гирлянды: нажатие по ней переключает режим гирлянд на стенах (use_prop).
func _zone(points: PackedVector3Array) -> void:
	var holder: Node3D = _into if _into != null else self
	var body := holder.get_node_or_null("LightsZone") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "LightsZone"
		body.collision_layer = 8
		body.collision_mask = 0
		body.set_meta("room_prop", "wall_lights")
		holder.add_child(body)
	var stride := maxi(1, points.size() / 4)
	var i := 0
	while i < points.size() - 1:
		var j := mini(i + stride, points.size() - 1)
		var a := points[i]
		var b := points[j]
		var span := a.distance_to(b)
		if span > 0.005:
			var dir := (b - a) / span
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.BACK).normalized()
			var up := side.cross(dir).normalized()
			var box := BoxShape3D.new()
			box.size = Vector3(span, 0.06, 0.05)
			var shape := CollisionShape3D.new()
			shape.shape = box
			shape.transform = Transform3D(Basis(dir, up, side), (a + b) * 0.5 + Vector3.DOWN * 0.015)
			body.add_child(shape)
		i = j


func _add_bulb(at: Vector3, index: int, scale: Vector3 = Vector3.ONE) -> void:
	_bulbs[_group * BULB_COLORS.size() + index % BULB_COLORS.size()].append(Transform3D(Basis.from_scale(scale), at))


## Яркость (x, 0..1) и номер цвета (y) лампочки цвета i в режиме mode в момент t.
## Время общее для всех гирлянд — одинаковые режимы на ёлке и стенах идут синхронно.
static func _light_state(mode: int, i: int, t: float) -> Vector2:
	var n := BULB_COLORS.size()
	match mode:
		1:  # один цвет 7 с, затем плавно гаснет, а следующий плавно загорается
			var step := 7.0
			var k := int(floor(t / step))
			var s := t - k * step
			var fade := smoothstep(5.5, 7.0, s)
			var b := 0.0
			if i == k % n:
				b = 1.0 - fade
			elif i == (k + 1) % n:
				b = fade
			return Vector2(0.03 + 0.97 * b, i)
		2:  # мигание: быстро гаснут и снова наливаются цветом, цвета сдвигаются на каждом мигании
			var period := 0.9
			var phase := fposmod(t, period) / period
			var b := 1.0
			if phase < 0.18:
				b = 1.0 - phase / 0.18
			elif phase < 0.36:
				b = (phase - 0.18) / 0.18
			var shift := int(floor((t + period * 0.82) / period))  # смена цвета — в самой тёмной точке
			return Vector2(0.03 + 0.97 * b * b, (i + shift) % n)
		_:  # переливы: каждый цвет — мягкая волна со своим сдвигом
			var wave := 0.5 + 0.5 * sin(t * 0.9 - i * TAU / n)
			wave = wave * wave * (3.0 - 2.0 * wave)
			return Vector2(0.06 + 0.94 * wave, i)


## Свои режимы огней из файла (при сборке и по возвращении из комнаты друга).
func load_modes() -> void:
	var prefs := ConfigFile.new()
	if prefs.load(MODES_PATH) == OK:
		modes[TREE_LIGHTS] = clampi(int(prefs.get_value("winter", "tree_lights", 0)), 0, 2)
		modes[WALLS] = clampi(int(prefs.get_value("winter", "wall_lights", 0)), 0, 2)


func set_mode(group: int, mode: int) -> void:
	modes[group] = clampi(mode, 0, MODE_NAMES.size() - 1)
	var prefs := ConfigFile.new()
	prefs.load(MODES_PATH)
	prefs.set_value("winter", "tree_lights" if group == TREE_LIGHTS else "wall_lights", modes[group])
	prefs.save(MODES_PATH)


## Нажатие на ёлку — следующий режим её огней (комната зовёт для своих «предметов»).
## Нажатие на ёлку — следующий режим её огней; по любой гирлянде на стене, шкафу, телевизоре — гирлянд.
func use_prop(kind: String) -> bool:
	var group := TREE_LIGHTS if kind == "tree_lights" else (WALLS if kind == "wall_lights" else -1)
	if group < 0:
		return false
	set_mode(group, (modes[group] + 1) % MODE_NAMES.size())
	_room.emit_signal("shelf_hint", ("Огни ёлки: " if group == TREE_LIGHTS else "Гирлянды: ") + MODE_NAMES[modes[group]])
	Sfx.play("click", -10)
	return true


## Все огоньки — четыре MultiMesh (по цвету): сотни лампочек дёшево.
func _flush_bulbs() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.011
	sphere.height = 0.022
	sphere.radial_segments = 8
	sphere.rings = 4
	for i in _bulbs.size():
		var list: Array = _bulbs[i]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sphere
		mm.use_custom_data = true  # своё зерно у каждой лампочки: мигание вразнобой
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
			mm.set_instance_custom_data(k, Color(randf(), 0.0, 0.0, 0.0))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _bulb_materials[i]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_into if _into != null else self).add_child(node)
		_bulbs[i] = []


# --- Ёлка ------------------------------------------------------------------------------

## Ярус ёлки: конус с зубчатым краем — концы лап чуть опущены.
func _tier_mesh(radius: float, height: float, tips: int, twist: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0, height, 0)
	var under := Vector3(0, height * 0.18, 0)
	var ring: Array[Vector3] = []
	for k in tips * 2:
		var a := twist + k * PI / tips
		var tip := k % 2 == 0
		var r := radius if tip else radius * 0.8
		ring.append(Vector3(cos(a) * r, -0.035 if tip else 0.03, sin(a) * r))
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		st.add_vertex(apex)
		st.add_vertex(q)
		st.add_vertex(p)
		st.add_vertex(under)
		st.add_vertex(p)
		st.add_vertex(q)
	st.generate_normals()
	return st.commit()


## Радиус кроны на высоте y (наибольший из ярусов) — по нему вешаем огни и игрушки.
func _crown_radius(y: float) -> float:
	var r := 0.0
	for tier: Array in _tiers:
		var y0: float = tier[0]
		var h: float = tier[1]
		if y >= y0 and y <= y0 + h:
			r = maxf(r, float(tier[2]) * (1.0 - (y - y0) / h))
	return r


func _tree() -> void:
	var root := Node3D.new()
	root.name = "Tree"
	root.position = TREE
	add_child(root)
	# ведро-подставка с золотым ободком и ствол
	var pot := _cyl(0.15, 0.12, 0.2, Vector3(0, 0.1, 0), _mat(Color("b81e3c"), 0.35))
	pot.reparent(root, false)
	var rim := _cyl(0.158, 0.158, 0.025, Vector3(0, 0.19, 0), _mat(Color("e9b949"), 0.25, 0.8))
	rim.reparent(root, false)
	var trunk := _cyl(0.035, 0.04, 0.14, Vector3(0, 0.26, 0), _mat(Color("4a2c1c"), 0.9))
	trunk.reparent(root, false)
	# пять ярусов хвои
	var needles := _mat(Color("1f5c43"), 0.9)
	needles.rim_enabled = true
	needles.rim = 0.25
	var specs := [[0.28, 0.5, 0.42], [0.58, 0.46, 0.35], [0.86, 0.43, 0.28], [1.13, 0.4, 0.21], [1.39, 0.42, 0.14]]
	for i in specs.size():
		var spec: Array = specs[i]
		spec = [spec[0], spec[1], float(spec[2]) * TREE_SCALE]
		_tiers.append(spec)
		var tier := _mesh(_tier_mesh(float(spec[2]), float(spec[1]), 11 - i, i * 0.37), Vector3(0, float(spec[0]), 0), needles, root)
		tier.name = "Tier%d" % i
	var top := 1.81
	# огни — спираль снизу вверх
	var turns := 6.0
	var count := 96
	for i in count:
		var s := float(i) / (count - 1)
		var y := lerpf(0.3, top - 0.08, s)
		var a := s * TAU * turns
		var r := _crown_radius(y) * 0.9 + 0.012
		_group = TREE_LIGHTS
		_add_bulb(TREE + Vector3(cos(a) * r, y, sin(a) * r), i)
		_group = WALLS
	# мишура — вторая спираль, золотая
	var tinsel := PackedVector3Array()
	for i in 121:
		var s := float(i) / 120.0
		var y := lerpf(0.36, top - 0.18, s)
		var a := s * TAU * 4.0 + 1.3
		var r := _crown_radius(y) * 0.86 + 0.008
		tinsel.append(TREE + Vector3(cos(a) * r, y, sin(a) * r))
	var gold := _mat(Color("f2c14e"), 0.2, 0.9)
	gold.emission_enabled = true
	gold.emission = Color("f2a93b")
	gold.emission_energy_multiplier = 0.09
	_tube(tinsel, 0.006, gold)
	# игрушки-шары на концах лап
	var rng := RandomNumberGenerator.new()
	rng.seed = 2412
	var colors := [Color("e8304f"), Color("f2c14e"), Color("2ec8e6"), Color("ff3ea5"), Color("d8dcff"), Color("9b5cff")]
	var balls: Array[StandardMaterial3D] = []
	for c: Color in colors:
		var m := _mat(c, 0.12, 0.75)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.12
		balls.append(m)
	for i in 26:
		var tier: Array = specs[i % specs.size()]
		var y := float(tier[0]) + rng.randf_range(0.04, 0.16)
		var a := rng.randf() * TAU
		var r := _crown_radius(y) * 0.93 + 0.02
		var size := rng.randf_range(0.024, 0.036) * (1.0 - 0.12 * (i % specs.size()))
		var ball := _sphere(size, Vector3(cos(a) * r, y - size, sin(a) * r), balls[i % balls.size()], root)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# звезда на макушке — всегда лицом к камере
	_star_material = _glow(Color("ffd84a"), 0.91)
	_star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(_star_mesh(0.085, 0.036), TREE + Vector3(0, top + 0.08, 0), _star_material)
	# нажатие на ёлку переключает режим её огней (NeonRoom._use_room_prop → use_prop)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = TREE + Vector3(0, 1.0, 0)
	body.set_meta("room_prop", "tree_lights")
	var shape := CollisionShape3D.new()
	var cone := CylinderShape3D.new()
	cone.radius = 0.3
	cone.height = 1.7
	shape.shape = cone
	body.add_child(shape)
	add_child(body)
	# тёплый свет от ёлки
	_light = OmniLight3D.new()
	_light.light_color = Color("ffb36b")
	_light.light_energy = 0.32
	_light.light_specular = 0.12  # без яркого блика на белой доске друзей
	_light.omni_range = 2.2
	_light.position = TREE + Vector3(0.25, 1.0, 0.3)
	add_child(_light)


func _star_mesh(outer: float, inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var r1 := outer if i % 2 == 0 else inner
		var r2 := inner if i % 2 == 0 else outer
		var a1 := i * TAU / 10.0 + PI * 0.5
		var a2 := (i + 1) * TAU / 10.0 + PI * 0.5
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0))
		st.add_vertex(Vector3(cos(a2) * r2, sin(a2) * r2, 0))
	return st.commit()


# --- Подарки ---------------------------------------------------------------------------

func _gifts() -> void:
	# [размер, сдвиг от ёлки, поворот, цвет коробки, цвет ленты]
	var gifts := [
		# со стороны шкафа (владелец), но правее x = −0,9 не заходят: шкаф может вырасти до скейтборда
		[Vector3(0.26, 0.18, 0.22), Vector3(0.2, 0.0, 0.32), 0.35, Color("ff3ea5"), Color("f2c14e")],
		[Vector3(0.19, 0.24, 0.19), Vector3(0.24, 0.0, 0.62), -0.25, Color("2ec8e6"), Color("f3eaff")],
		[Vector3(0.15, 0.11, 0.15), Vector3(0.2, 0.18, 0.32), 0.9, Color("ffd23d"), Color("e8304f")],  # на розовом
		[Vector3(0.24, 0.13, 0.18), Vector3(-0.04, 0.0, 0.64), -0.6, Color("7a4dff"), Color("2ef2ff")],
	]
	for g: Array in gifts:
		var size: Vector3 = g[0]
		var holder := Node3D.new()
		holder.position = TREE + g[1] + Vector3(0, size.y * 0.5, 0)
		holder.rotation.y = float(g[2])
		add_child(holder)
		_room.call("_soft", size, Vector3.ZERO, "fabric", g[3], holder, Vector3.ZERO, 0.012)
		var ribbon := _mat(g[4], 0.35, 0.3)
		for along: Vector3 in [Vector3(size.x + 0.006, size.y + 0.006, 0.03), Vector3(0.03, size.y + 0.006, size.z + 0.006)]:
			var band := BoxMesh.new()
			band.size = along
			_mesh(band, Vector3.ZERO, ribbon, holder)
		# уменьшенный лоу-поли бант со стены — воткнут сверху посередине, хвосты уходят в коробку
		_bow(Vector3(0, size.y * 0.5 + 0.012, 0), 0.0, holder, 0.5)


# --- Гирлянды и украшения на стенах ------------------------------------------------------

## Гирлянда под потолком по задней и левой стенам — выше шкафа, плакатов и досок.
func _ceiling_garlands() -> void:
	var wire := _mat(Color("1d2a24"), 0.6)
	var y := 2.72
	# задняя стена: шесть провисов от угла до угла
	var xs := [-2.94, -1.96, -0.98, 0.0, 0.98, 1.96, 2.94]
	for i in xs.size() - 1:
		var points := _swag(Vector3(xs[i], y, BACK + 0.05), Vector3(xs[i + 1], y, BACK + 0.05), 0.13)
		_tube(points, 0.003, wire)
		_string_bulbs(points, 0.1, 0.018, i)
	# левая стена: от угла с окном до стены с дверью
	var zs := [-1.95, -0.95, 0.05, 1.05, 2.1]
	for i in zs.size() - 1:
		var points := _swag(Vector3(-W * 0.5 + 0.06, y, zs[i]), Vector3(-W * 0.5 + 0.06, y, zs[i + 1]), 0.14)
		_tube(points, 0.003, wire)
		_string_bulbs(points, 0.1, 0.018, i + 1)


## Левая стена: огоньки вдоль верхней полки, мишура под нижней, носки, венок.
func _left_wall() -> void:
	var shelf_front := -W * 0.5 + 0.05 + 0.45 - 0.01  # передняя кромка полок (WALL_SHELF_DEPTH 0,45)
	var wire := _mat(Color("1d2a24"), 0.6)
	var z0 := -1.82
	var z1 := 0.03
	# огоньки под кромкой верхней полки (1,72 м): три провиса, не мешают предметам на полках
	for i in 3:
		var a := lerpf(z0, z1, i / 3.0)
		var b := lerpf(z0, z1, (i + 1) / 3.0)
		var points := _swag(Vector3(shelf_front, 1.69, a), Vector3(shelf_front, 1.69, b), 0.07)
		_tube(points, 0.003, wire)
		_string_bulbs(points, 0.075, 0.016, i)
	# мишура под кромкой нижней полки (1,10 м)
	var tinsel := _mat(Color("ff6fc0"), 0.25, 0.8)
	tinsel.emission_enabled = true
	tinsel.emission = Color("ff3ea5")
	tinsel.emission_energy_multiplier = 0.12
	for i in 3:
		var a := lerpf(z0, z1, i / 3.0)
		var b := lerpf(z0, z1, (i + 1) / 3.0)
		_tube(_swag(Vector3(shelf_front, 1.07, a), Vector3(shelf_front, 1.07, b), 0.06, 20), 0.011, tinsel)
	# носки для подарков на нижней полке — над кроватью
	for sock: Array in [[-1.45, 0.05], [-0.9, -0.04], [-0.35, 0.03]]:
		_stocking(Vector3(shelf_front + 0.02, 1.03, float(sock[0])), float(sock[1]))
	# венок у двери
	_door_wreath()
	# красные банты по стене, как на референсе владельца
	for spot: Vector2 in BOW_SPOTS:
		_bow(Vector3(-W * 0.5 + 0.06, spot.y, spot.x), PI * 0.5)


## Носок для подарков по референсу владельца: красный войлок с белыми снежинками и ёлочками,
## толстый белый вязаный отворот, петелька. Форма — объёмная «подушка» по силуэту (_pillow).
func _stocking(hook: Vector3, tilt: float) -> void:
	var holder := Node3D.new()
	holder.position = hook
	holder.rotation = Vector3(0, PI * 0.5, tilt)  # лицом в комнату (+x), носок смотрит к окну
	add_child(holder)
	var felt := _mat(Color.WHITE, 0.95)
	felt.albedo_texture = load("res://hub/art/winter/stocking.png")
	var rib := _mat(Color.WHITE, 1.0)
	rib.albedo_texture = load("res://hub/art/winter/cuff.png")
	var body := func(p: Vector2) -> float:
		var leg := _sd_round_box(p, Vector2(0.0, -0.11), Vector2(0.04, 0.085), 0.016)
		var foot := _sd_capsule(p, Vector2(0.0, -0.195), Vector2(0.072, -0.203), 0.043)
		return _smin(leg, foot, 0.03)
	var sock := _mesh(_pillow(body, Rect2(-0.07, -0.26, 0.21, 0.24), 0.004, 0.022), Vector3.ZERO, felt, holder)
	sock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # тонкая «подушка» иначе ловит полосы самотени
	var cuff := func(p: Vector2) -> float:
		return _sd_round_box(p, Vector2(0.0, -0.034), Vector2(0.051, 0.03), 0.014)
	var band := _mesh(_pillow(cuff, Rect2(-0.06, -0.072, 0.12, 0.076), 0.003, 0.03), Vector3.ZERO, rib, holder)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# петелька из белого шнура над отворотом
	var loop := PackedVector3Array()
	for i in 17:
		var a := PI * (1.0 + i / 16.0)
		loop.append(Vector3(-0.03 + cos(a) * 0.012, 0.012 - sin(a) * 0.03, 0.0))
	_tube(loop, 0.0025, _mat(Color("f1eeea"), 1.0)).reparent(holder, false)


## Объёмная «подушка» по двумерному силуэту sdf (< 0 — внутри): сетка с шагом step, точки снаружи
## притягиваются к контуру (гладкий край), толщина растёт от края к середине до depth с каждой стороны.
func _pillow(sdf: Callable, rect: Rect2, step: float, depth: float) -> ArrayMesh:
	var nx := int(ceil(rect.size.x / step)) + 1
	var ny := int(ceil(rect.size.y / step)) + 1
	var points: Array[Vector2] = []
	var values := PackedFloat32Array()
	for j in ny:
		for i in nx:
			var p := rect.position + Vector2(i * step, j * step)
			points.append(p)
			values.append(float(sdf.call(p)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index_of := {}
	var start := 0  # общий счётчик вершин обеих сторон
	for side: float in [1.0, -1.0]:
		for j in ny - 1:
			for i in nx - 1:
				var cell: Array[int] = [j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i]
				if not cell.any(func(k: int) -> bool: return values[k] < 0.0):
					continue
				for tri: Array in [[cell[0], cell[1], cell[2]], [cell[0], cell[2], cell[3]]]:
					var order: Array = [tri[0], tri[2], tri[1]] if side > 0.0 else tri  # лицевая сторона — по часовой (как в Godot)
					for k: int in order:
						var key := k * 2 + (0 if side > 0.0 else 1)
						if not index_of.has(key):
							var p := points[k]
							var d := values[k]
							var z := 0.0
							if d >= 0.0:
								# снаружи — на контур, по градиенту
								var e := step * 0.25
								var grad := Vector2(float(sdf.call(p + Vector2(e, 0))) - float(sdf.call(p - Vector2(e, 0))),
									float(sdf.call(p + Vector2(0, e))) - float(sdf.call(p - Vector2(0, e)))) / (2.0 * e)
								if grad.length() > 0.001:
									p -= grad.normalized() * d
							else:
								z = depth * sqrt(clampf(-d / 0.03, 0.0, 1.0)) * side
							st.set_uv(Vector2((p.x - rect.position.x) / rect.size.x, 1.0 - (p.y - rect.position.y) / rect.size.y))
							st.add_vertex(Vector3(p.x, p.y, z))
							index_of[key] = start
							start += 1
						st.add_index(index_of[key])
	st.generate_normals()
	return st.commit()


static func _sd_round_box(p: Vector2, center: Vector2, half: Vector2, r: float) -> float:
	var q := (p - center).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _sd_capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## Венок из хвойных веточек: сотни тонких иголок-пучков разного зелёного (MultiMesh с цветами)
## на тёмной основе, гроздья ягод и бархатный бант. Гладкого «бублика» больше не видно.
## Венок на двери (створка — NeonRoom.door_hinge): висит на створке и поворачивается вместе с ней.
func _door_wreath() -> void:
	var hinge: Variant = _room.get("door_hinge")
	if not hinge is Node3D or not is_instance_valid(hinge):
		return
	var holder := _wreath(Transform3D(Basis(Vector3.UP, PI), Vector3(-0.3775, 1.45, -0.03)), hinge)
	holder.set_meta("winter_decor", true)
	# дверь — на слое передней стены: видна, только когда камера её показывает (как сама дверь)
	for node: Node in holder.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = 1 << 19


func _wreath(at: Transform3D, parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.transform = at
	parent.add_child(holder)
	var ring_r := 0.135
	var tube_r := 0.034
	var base := TorusMesh.new()
	base.inner_radius = ring_r - tube_r * 0.8
	base.outer_radius = ring_r + tube_r * 0.8
	var core := _mesh(base, Vector3.ZERO, _mat(Color("0f2a1d"), 1.0), holder)
	core.rotation.x = PI * 0.5
	var needle := CylinderMesh.new()
	needle.top_radius = 0.0
	needle.bottom_radius = 0.0035
	needle.height = 0.048
	needle.radial_segments = 4
	needle.rings = 1
	var count := 900
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = needle
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 2512
	var greens := [Color("2c7a52"), Color("35905e"), Color("43a06a"), Color("23663f"), Color("52ad74")]  # светлее: угол синий и тёмный
	for k in count:
		var a := rng.randf() * TAU
		var b := rng.randf_range(-PI * 0.85, PI * 0.85)  # к стене иголки не нужны
		var radial := Vector3(cos(a), sin(a), 0.0)
		var normal := (radial * cos(b) + Vector3.BACK * sin(b)).normalized()
		var centre := radial * ring_r
		var root := centre + normal * tube_r * rng.randf_range(0.4, 0.9)
		# иголка смотрит наружу и по кругу (ветки «закручены» в одну сторону)
		var tangent := Vector3(-sin(a), cos(a), 0.0)
		var dir := (normal * 0.75 + tangent * rng.randf_range(0.2, 0.7) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))).normalized()
		var up := dir
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up)).scaled(Vector3.ONE * rng.randf_range(0.75, 1.25))
		mm.set_instance_transform(k, Transform3D(basis, root + dir * 0.02))
		mm.set_instance_color(k, (greens[rng.randi() % greens.size()] as Color).lightened(rng.randf_range(-0.08, 0.1)))
	var sprigs := MultiMeshInstance3D.new()
	sprigs.multimesh = mm
	var pine := _mat(Color.WHITE, 0.85)
	pine.vertex_color_use_as_albedo = true
	sprigs.material_override = pine
	holder.add_child(sprigs)
	# огоньки по венку — как на ёлке (общие лампочки темы)
	for i in 14:
		var a := i * TAU / 14.0 + 0.2
		var lamp := _sphere(0.0075, Vector3(cos(a), sin(a), 0) * (ring_r + 0.012) + Vector3(0, 0, tube_r * 0.9), _bulb_materials[WALLS * BULB_COLORS.size() + i % BULB_COLORS.size()], holder)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ягоды гроздьями по три
	var berry := _mat(Color("c81d32"), 0.25)
	for i in 6:
		var a := i * TAU / 6.0 + 0.4
		for j in 3:
			var off := Vector3(cos(a), sin(a), 0) * ring_r
			off += Vector3(cos(j * 2.1) * 0.011, sin(j * 2.1) * 0.011, tube_r * 0.95)
			var ball := _sphere(0.009, off, berry, holder)
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# бант внизу: две петли, узел и два хвоста из бархата
	var velvet := _mat(Color("b3162a"), 0.7)
	velvet.rim_enabled = true
	velvet.rim = 0.4
	for s in [-1.0, 1.0]:
		var loop := TorusMesh.new()
		loop.inner_radius = 0.012
		loop.outer_radius = 0.03
		var l := _mesh(loop, Vector3(s * 0.03, -ring_r - 0.01, tube_r + 0.012), velvet, holder)
		l.rotation = Vector3(PI * 0.5, 0, s * 0.35)
		l.scale = Vector3(1.0, 1.0, 0.55)
		var tail := BoxMesh.new()
		tail.size = Vector3(0.018, 0.07, 0.006)
		var t := _mesh(tail, Vector3(s * 0.022, -ring_r - 0.06, tube_r + 0.008), velvet, holder)
		t.rotation.z = s * 0.3
	var knot := BoxMesh.new()
	knot.size = Vector3(0.022, 0.022, 0.016)
	_mesh(knot, Vector3(0, -ring_r - 0.01, tube_r + 0.018), velvet, holder)
	return holder


## Красный бант на стене в плоском «лоу-поли» стиле (владелец): петли — кольца из семи граней с ломаным
## контуром и просветом, внутренний край выступает вперёд (грани ловят разный свет), шестигранный узелок,
## хвосты с изломом и вырезом «ласточкин хвост». Заливка — _flat: ступени яркости, без цветного света.
func _bow(at: Vector3, yaw: float, parent: Node3D = null, size: float = 1.6) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	holder.scale = Vector3.ONE * size  # на стене — крупнее (1,6), на подарке — маленький
	(parent if parent != null else self).add_child(holder)
	var red := _flat(null, Color("c4182b"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jitter := [1.0, 0.9, 1.06, 0.94, 1.0, 0.88, 1.05]  # ломаный, не идеально ровный контур
	for side: float in [-1.0, 1.0]:
		var centre := Vector2(side * 0.043, 0.01)
		var tilt := side * 0.32
		var outer: Array[Vector3] = []
		var inner: Array[Vector3] = []
		for n in 7:
			var a := n * TAU / 7.0 + 0.3
			var o := Vector2(cos(a) * 0.046, sin(a) * 0.027) * float(jitter[n])
			var h := Vector2(cos(a) * 0.022 + side * 0.006, sin(a) * 0.009)
			o = o.rotated(tilt) + centre
			h = h.rotated(tilt) + centre
			outer.append(Vector3(o.x, o.y, 0.003 if n % 2 == 0 else 0.0))
			inner.append(Vector3(h.x, h.y, 0.013))
		for n in 7:
			var m := (n + 1) % 7
			_tri(st, outer[n], outer[m], inner[m])
			_tri(st, outer[n], inner[m], inner[n])
	# хвосты: две грани с изломом посередине, конец срезан галочкой
	for side: float in [-1.0, 1.0]:
		var top_l := Vector3(side * 0.003 - 0.008, -0.004, 0.012)
		var top_r := Vector3(side * 0.003 + 0.008, -0.004, 0.012)
		var mid_l := Vector3(side * 0.02 - 0.011, -0.055, 0.004)
		var mid_r := Vector3(side * 0.02 + 0.011, -0.055, 0.009)
		var end_l := Vector3(side * 0.036 - 0.012, -0.108, 0.0)
		var end_r := Vector3(side * 0.036 + 0.012, -0.1, 0.004)
		var notch := Vector3(side * 0.036 + side * 0.002, -0.09, 0.002)
		_tri(st, top_l, top_r, mid_r)
		_tri(st, top_l, mid_r, mid_l)
		_tri(st, mid_l, mid_r, end_r)
		_tri(st, mid_l, end_r, notch)
		_tri(st, mid_l, notch, end_l)
	st.generate_normals()  # без общих вершин — плоские грани
	var bow := _mesh(st.commit(), Vector3.ZERO, red, holder)
	bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hexagon := CylinderMesh.new()
	hexagon.top_radius = 0.015
	hexagon.bottom_radius = 0.017
	hexagon.height = 0.016
	hexagon.radial_segments = 6
	hexagon.rings = 1
	var knot := _mesh(hexagon, Vector3(0, 0.003, 0.014), _flat(null, Color("b3152a")), holder)
	knot.rotation = Vector3(PI * 0.5, 0.0, 0.25)
	knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v: Vector3 in [a, c, b]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


## Ткань, которая почти не отражает свет: альбедо × albedo, без бликов; цвет держит слабое свечение tint × glow.
func _matte(m: StandardMaterial3D, tint: Color, albedo: float, glow: float) -> void:
	m.albedo_color = Color(albedo, albedo, albedo)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = glow


func _felt() -> StandardMaterial3D:
	var felt := _mat(Color.WHITE, 0.95)
	felt.albedo_texture = load("res://hub/art/winter/felt.png")
	felt.uv1_scale = Vector3(6, 6, 6)
	return felt


## Огоньки вокруг окна (рама окна — hub/neon_room.gd _window): сверху два провиса, по бокам вниз.
func _window_lights() -> void:
	var c := Vector3(-1.75, 1.62, BACK + 0.02)
	var half := Vector2(1.25, 0.95) * 0.5
	var z := BACK + 0.1
	var wire := _mat(Color("1d2a24"), 0.6)
	var top := c.y + half.y + 0.03
	var left := c.x - half.x - 0.035
	var right := c.x + half.x + 0.035
	for pair: Array in [[left, c.x], [c.x, right]]:
		var points := _swag(Vector3(pair[0], top, z), Vector3(pair[1], top, z), 0.07)
		_tube(points, 0.003, wire)
		_string_bulbs(points, 0.07, 0.016)
	for x: float in [left, right]:
		var points := PackedVector3Array([Vector3(x, top, z), Vector3(x, c.y - half.y + 0.05, z)])
		_tube(points, 0.003, wire)
		_string_bulbs(points, 0.08, 0.0, 2)


## Мишура и огоньки по передней кромке тумбы телевизора (ниже крышки — фигуркам на ней не мешают).
func _tv_garland() -> void:
	var x0 := 1.6 - 0.43
	var x1 := 1.6 + 0.43
	var z := BACK + 0.545
	var y := 0.6
	var tinsel := _mat(Color("f2c14e"), 0.2, 0.9)
	tinsel.emission_enabled = true
	tinsel.emission = Color("f2a93b")
	tinsel.emission_energy_multiplier = 0.1
	var wire := _mat(Color("1d2a24"), 0.6)
	for i in 2:
		var a := Vector3(lerpf(x0, x1, i * 0.5), y, z)
		var b := Vector3(lerpf(x0, x1, (i + 1) * 0.5), y, z)
		_tube(_swag(a, b, 0.07, 20), 0.01, tinsel)
		var lights := _swag(a + Vector3(0, -0.01, 0.012), b + Vector3(0, -0.01, 0.012), 0.05)
		_tube(lights, 0.0025, wire)
		_string_bulbs(lights, 0.06, 0.012, i, 0.7)  # близко к камере — лампочки мельче


# --- Бумажные снежинки на стенах (рядом со светящимися звёздами) ----------------------------

func _snowflake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: Array = []
	for i in 6:
		var dir := Vector2.from_angle(i * TAU / 6.0)
		segments.append([Vector2.ZERO, dir])
		for at: float in [0.45, 0.7]:
			var side := Vector2(-dir.y, dir.x)
			var arm := 0.32 if at < 0.5 else 0.22
			segments.append([dir * at, dir * at + (dir + side).normalized() * arm])
			segments.append([dir * at, dir * at + (dir - side).normalized() * arm])
	for seg: Array in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := (b - a).orthogonal().normalized() * 0.045
		var quad := [a + n, b + n, b - n, a - n]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(quad[k].x, quad[k].y, 0))
	return st.commit()


func _paper_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# три яруса и ствол, высота 2 (от −1 до 1)
	var tiers := [[0.95, -0.15, 0.55], [0.45, -0.6, 0.75], [-0.05, -1.0 + 0.25, 0.95]]
	var shapes: Array = []
	for t: Array in tiers:
		shapes.append([Vector2(0, float(t[0])), Vector2(float(t[2]), float(t[1])), Vector2(-float(t[2]), float(t[1]))])
	shapes.append([Vector2(-0.12, -0.75), Vector2(0.12, -0.75), Vector2(0.12, -1.0)])
	shapes.append([Vector2(-0.12, -0.75), Vector2(0.12, -1.0), Vector2(-0.12, -1.0)])
	for tri: Array in shapes:
		for k: int in [0, 2, 1]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3((tri[k] as Vector2).x, (tri[k] as Vector2).y, 0))
	return st.commit()


## Наклейки на стенах: снежинки, бумажные ёлочки и светящиеся звёзды (прежние звёзды комнаты на зиму
## скрываются). Места случайные при каждой сборке, но каждая наклейка держится на расстоянии от соседей,
## бантов, окна, полок и носков — пустых пятен и наложений нет.
func _snowflakes() -> void:
	for node: Node in _room.get_children():
		if node is Label3D and (node as Label3D).text == "★" and (node as Label3D).visible:
			(node as Label3D).visible = false
			_hidden.append(node)
	var flake_mesh := _snowflake_mesh()
	var tree_mesh := _paper_tree_mesh()
	var paper := _glow(Color("e6efff"), 0.55)
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113  # одинаковая раскладка у всех: друзья в гостях видят комнату такой же
	var bows: Array[Vector2] = []
	for spot: Vector2 in BOW_SPOTS:
		bows.append(spot)
	# стены: [плоскость, область (u — вдоль стены, v — высота), запретные прямоугольники]
	# [стена, область, запретные места, зазор между наклейками]; задняя — целиком (над шкафом, за плакатами тоже),
	# левая — реже на 25 % (владелец) и ниже у изножья кровати, где было пусто
	var walls := [
		# от плинтуса до гирлянды под потолком; над телевизором — выше лавовой лампы
		["back", Rect2(-2.92, 0.15, 5.84, 2.33), [Rect2(-2.5, 1.04, 1.5, 1.18), Rect2(-1.98, 0.45, 0.6, 0.6), Rect2(-0.95, 1.33, 0.2, 0.18), Rect2(1.12, 0.0, 0.96, 1.62)], 0.175],
		["left", Rect2(-1.95, 0.15, 4.06, 2.33), [Rect2(-1.88, 0.72, 1.97, 0.46), Rect2(-1.88, 1.6, 1.97, 0.2), Rect2(0.42, 0.0, 0.42, 0.95)], 0.22],
		# стена с дверью (видна при повороте к полкам): кроме двери с наличниками
		["front", Rect2(-2.92, 0.15, 5.84, 2.33), [Rect2(-2.72, 0.0, 1.03, 2.2)], 0.22],
	]
	for wall: Array in walls:
		var area: Rect2 = wall[1]
		var placed: Array[Vector3] = []  # (u, v, радиус)
		if wall[0] == "left":
			for b: Vector2 in bows:
				placed.append(Vector3(b.x, b.y, 0.14))
		var attempts := int(area.get_area() * 3000.0)  # до насыщения: пустых пятен не остаётся
		for n in attempts:
			var kind := rng.randf()
			var r := 0.0
			if kind < 0.4:
				r = rng.randf_range(0.035, 0.05)  # звезда
			elif kind < 0.75:
				r = rng.randf_range(0.045, 0.075)  # снежинка
			else:
				r = rng.randf_range(0.05, 0.07)  # ёлочка
			var at := Vector2(rng.randf_range(area.position.x + r, area.end.x - r), rng.randf_range(area.position.y + r, area.end.y - r))
			var blocked := false
			for hole: Rect2 in wall[2]:
				if hole.grow(r).has_point(at):
					blocked = true
					break
			if blocked:
				continue
			for other: Vector3 in placed:
				if at.distance_to(Vector2(other.x, other.y)) < r + other.z + float(wall[3]):  # без наложений и тесноты
					blocked = true
					break
			if blocked:
				continue
			placed.append(Vector3(at.x, at.y, r))
			sticker_count += 1
			var pos := Vector3(at.x, at.y, BACK + 0.006) if wall[0] == "back" else Vector3(-W * 0.5 + 0.057, at.y, at.x)
			if wall[0] == "front":
				pos = Vector3(at.x, at.y, 2.18 - 0.066)  # NeonRoom.ROOM_FRONT, внутренняя сторона стены
			var node: Node3D
			if kind < 0.4:
				var star: Label3D = _room.call("_glow_label", "★", Vector3.ZERO, int(r * 1250.0), Color("7dffc8"), "regular", 0.0016)
				star.reparent(self, false)
				star.modulate = Color(0.55, 1.1, 0.85)
				node = star
			elif kind < 0.75:
				node = _mesh(flake_mesh, Vector3.ZERO, paper)
				node.scale = Vector3.ONE * r
			else:
				node = _mesh(tree_mesh, Vector3.ZERO, paper)
				node.scale = Vector3.ONE * r
			node.position = pos
			if wall[0] == "front":
				node.rotation.y = PI
				(node as VisualInstance3D).layers = 1 << 19  # слой передней стены: видна вместе со стеной
			elif wall[0] == "left":
				node.rotation.y = PI * 0.5
			node.rotate_object_local(Vector3.BACK, rng.randf_range(-0.5, 0.5) if kind >= 0.75 else rng.randf() * PI)


# --- Колпак Деда Мороза --------------------------------------------------------------------

## Мягкий колпак: красный войлочный верх изогнут и свисает набок (сглаженная трубка по кривой),
## толстая меховая опушка, пушистый помпон на кончике. radius — радиус опушки (м); кончик свисает к +X.
func santa_hat(radius: float) -> Node3D:
	var hat := Node3D.new()
	hat.name = "SantaHat"
	# плоский «лоу-поли» стиль (владелец): мало граней, каждая залита ровно, складки нарисованы в hat.png;
	# цветной свет комнаты колпак не перекрашивает (hub/rooms/fabric.gdshader)
	var velvet := _flat(load("res://hub/art/winter/hat.png"), Color.WHITE)
	velvet.set_shader_parameter("bands", 6)  # грани по обе стороны складки — разные оттенки красного
	var fur := _flat(null, Color("f1ebe4"))
	# ось колпака — кубическая кривая: вверх, затем перегиб набок и вниз
	var p0 := Vector3.ZERO
	var p1 := Vector3(0.0, 1.25, 0.0) * radius
	var p2 := Vector3(0.35, 1.95, 0.05) * radius
	var p3 := Vector3(1.45, 1.05, 0.2) * radius
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 11
	for k in n + 1:
		var t := float(k) / n
		var u := 1.0 - t
		points.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
		radii.append(radius * (0.93 * pow(u, 0.9) + 0.12))
	_mesh(_sweep(points, radii, 9, radius * 0.12), Vector3.ZERO, velvet, hat)
	var band := TorusMesh.new()
	band.inner_radius = radius * 0.78
	band.outer_radius = radius * 1.18
	band.rings = 12
	band.ring_segments = 6
	var b := _mesh(band, Vector3(0, radius * 0.06, 0), fur, hat)
	b.scale = Vector3(1.0, 1.7, 1.0)
	var pom := SphereMesh.new()
	pom.radius = radius * 0.3
	pom.height = radius * 0.58
	pom.radial_segments = 8
	pom.rings = 4
	_mesh(pom, p3 + Vector3(radius * 0.1, -radius * 0.22, 0), fur, hat)
	for node: MeshInstance3D in hat.find_children("*", "MeshInstance3D", false, false):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return hat


## Плоская заливка (hub/rooms/fabric.gdshader): грани — ступени яркости, цветной свет комнаты не влияет.
func _flat(texture: Texture2D, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://hub/rooms/fabric.gdshader")
	if texture == null:
		var white := Image.create(4, 4, false, Image.FORMAT_RGB8)
		white.fill(Color.WHITE)
		texture = ImageTexture.create_from_image(white)
	m.set_shader_parameter("tex", texture)
	m.set_shader_parameter("tint", tint)
	return m


## Трубка переменного радиуса вдоль кривой, гранями (лоу-поли): у каждой грани своя нормаль; wrinkle — складки.
func _sweep(points: PackedVector3Array, radii: PackedFloat32Array, sides: int, wrinkle: float) -> ArrayMesh:
	var count := points.size()
	var grid: Array = []
	var uvs: Array = []
	for i in count:
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := tangent.cross(Vector3.BACK)
		if side.length() < 0.1:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		for k in sides + 1:
			var a := k * TAU / sides
			var normal := side * cos(a) + up * sin(a)
			# складки: продольные у опушки и поперечные «гармошкой» в месте перегиба
			var along := float(i) / count
			var fold := wrinkle * sin(a * 3.0 + i * 0.7) * (1.0 - along)
			fold += wrinkle * 0.8 * sin(a * 5.0 - i * 1.8) * sin(PI * along)
			grid.append(points[i] + normal * (radii[i] + fold))
			uvs.append(Vector2(float(k) / sides, float(i) / (count - 1)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count - 1:
		for k in sides:
			var a := i * (sides + 1) + k
			var b := a + sides + 1
			for idx: int in [a, a + 1, b, a + 1, b + 1, b]:
				st.set_uv(uvs[idx])
				st.add_vertex(grid[idx])
	st.generate_normals()  # без общих вершин — нормаль на грань, плоские грани
	return st.commit()


# --- Мяч и динозаврик ------------------------------------------------------------------------

var _ball_texture: Texture2D  # прежняя текстура мяча — вернуть, когда тема снимается
var _dino_hat: Node3D


## Мяч зимой — красный со снежинкой с двух сторон; динозаврику (фигурка shelf_andy) — маленький колпак.
func _winter_props() -> void:
	var vcr: Variant = _room.get("vcr_body")
	if vcr is MeshInstance3D and (vcr as MeshInstance3D).material_override is ShaderMaterial:
		var m := (vcr as MeshInstance3D).material_override as ShaderMaterial
		_vcr_saved = [m, m.get_shader_parameter("albedo"), m.get_shader_parameter("albedo2")]
		m.set_shader_parameter("albedo", Color("1c3a2a"))  # тёмно-зелёный
		m.set_shader_parameter("albedo2", Color("15301f"))
	# кассеты: приглушённые белый, красный, зелёный, плоская заливка без влияния цветного света
	var tones := [Color("b9b3ae"), Color("7a1c26"), Color("1f4a34"), Color("8f2430")]
	var tapes: Array = _room.get("cassettes")
	for k in tapes.size():
		var tape := tapes[k] as MeshInstance3D
		if tape == null:
			continue
		_cassette_colors.append([tape, tape.material_override])
		# плоская заливка: торец спереди освещён голубым экраном, а красный голубого не отражает — был чёрным
		var plastic := _flat(null, tones[k % tones.size()])
		plastic.set_shader_parameter("brightness", 0.53)
		# тень цветом вручную (заливка свет комнаты не видит): свет спереди-справа — левый бок темнее,
		# снизу и сзади темнее (полка над кассетами и стенка тумбы)
		plastic.set_shader_parameter("light_dir", Vector3(0.55, 0.6, 0.6))
		plastic.set_shader_parameter("shade_low", 0.45)
		plastic.set_shader_parameter("half_height", 0.095)  # на экране на 25 % темнее (владелец): 0,75 в гамме 2,2 ≈ 0,53 линейно
		tape.material_override = plastic
	var ball: Variant = _room.get("_ball")
	if ball is Node3D and is_instance_valid(ball) and (ball as Node3D).get_child_count() > 0:
		var skin := (ball as Node3D).get_child(0) as MeshInstance3D
		if skin != null and skin.material_override is StandardMaterial3D:
			var rubber := skin.material_override as StandardMaterial3D
			_ball_texture = rubber.albedo_texture
			rubber.albedo_texture = load("res://hub/art/winter/ball.png")
	for box: Variant in _room.get("boxes"):
		if box is Node3D and str((box as Node3D).get_meta("shelf_id", "")) == "shelf_andy":
			for model: Node in (box as Node3D).get_children():
				if model is Node3D and str(model.scene_file_path).ends_with("andy.glb"):
					# модель высотой 1 (масштаб 0,14), голова — вверху спереди: y ≈ 0,97, z ≈ 0,7
					_dino_hat = santa_hat(0.11)
					_dino_hat.position = Vector3(0.0, 0.955, 0.66)
					_dino_hat.rotation = Vector3(-0.25, PI * 0.5, 0.0)  # кончик свисает назад, на шею
					(model as Node3D).add_child(_dino_hat)


func _restore_props() -> void:
	if _vcr_saved.size() == 3:
		(_vcr_saved[0] as ShaderMaterial).set_shader_parameter("albedo", _vcr_saved[1])
		(_vcr_saved[0] as ShaderMaterial).set_shader_parameter("albedo2", _vcr_saved[2])
	_vcr_saved.clear()
	for saved: Array in _cassette_colors:
		if is_instance_valid(saved[0]):
			(saved[0] as MeshInstance3D).material_override = saved[1]
	_cassette_colors.clear()
	for node: Variant in _hidden:
		if is_instance_valid(node):
			(node as Node3D).visible = true
	_hidden.clear()
	var ball: Variant = _room.get("_ball") if is_instance_valid(_room) else null
	if ball is Node3D and is_instance_valid(ball) and _ball_texture != null:
		var skin := (ball as Node3D).get_child(0) as MeshInstance3D
		if skin != null and skin.material_override is StandardMaterial3D:
			(skin.material_override as StandardMaterial3D).albedo_texture = _ball_texture
	if is_instance_valid(_dino_hat):
		_dino_hat.queue_free()


# --- Гирлянда по верху шкафа -----------------------------------------------------------------

## Шкаф игрока меняет размер (редактор, комната друга) — гирлянда пересобирается по его кромке.
func _update_shelf_garland() -> void:
	if not is_instance_valid(_room) or not _room.has_method("shelf_bounds"):
		return
	var bounds: AABB = _room.call("shelf_bounds")
	if bounds.size == Vector3.ZERO or bounds.is_equal_approx(_shelf_seen):
		return
	_shelf_seen = bounds
	if is_instance_valid(_shelf_garland):
		_shelf_garland.queue_free()
	_shelf_garland = Node3D.new()
	_shelf_garland.name = "ShelfGarland"
	add_child(_shelf_garland)
	_into = _shelf_garland
	var top := bounds.end.y - 0.012
	var z := bounds.end.z + 0.014
	var x0 := bounds.position.x + 0.01
	var x1 := bounds.end.x - 0.01
	var swags := maxi(2, roundi((x1 - x0) / 0.32))
	var wire := _mat(Color("1d2a24"), 0.6)
	var tinsel := _mat(Color("f2c14e"), 0.2, 0.9)
	tinsel.emission_enabled = true
	tinsel.emission = Color("f2a93b")
	tinsel.emission_energy_multiplier = 0.1
	for i in swags:
		var a := Vector3(lerpf(x0, x1, float(i) / swags), top, z)
		var b := Vector3(lerpf(x0, x1, float(i + 1) / swags), top, z)
		_tube(_swag(a, b, 0.035, 14), 0.008, tinsel)
		var lights := _swag(a + Vector3(0, -0.006, 0.008), b + Vector3(0, -0.006, 0.008), 0.05)
		_tube(lights, 0.0025, wire)
		_string_bulbs(lights, 0.07, 0.012, i, 0.85)
	# концы свисают по углам
	for x: float in [x0, x1]:
		var drop := PackedVector3Array([Vector3(x, top, z + 0.008), Vector3(x, top - 0.16, z + 0.008)])
		_tube(drop, 0.0025, wire)
		_string_bulbs(drop, 0.05, 0.0, 1, 0.85)
	_flush_bulbs()
	_into = null


# --- Новогодний ковёр ------------------------------------------------------------------------

## Ковёр на 70 % пола по центру комнаты; у стен виден прежний пол. Махровый ворс и лохматые
## скруглённые края — шейдер hub/rooms/carpet.gdshader; рисунок по краям (середину закрывает игрок).
func _carpet() -> void:
	var front := 2.18  # NeonRoom.ROOM_FRONT
	var size := Vector2(W, front - BACK) * sqrt(0.7)
	var mesh := PlaneMesh.new()
	mesh.size = size
	var cloth := ShaderMaterial.new()
	cloth.shader = load("res://hub/rooms/carpet.gdshader")
	cloth.set_shader_parameter("pattern", load("res://hub/art/winter/carpet.png"))
	cloth.set_shader_parameter("size_m", size)
	var carpet := _mesh(mesh, Vector3(0.0, 0.008, (front + BACK) * 0.5), cloth)
	carpet.name = "Carpet"


# --- Новогодний телевизор -----------------------------------------------------------------------

## Колпак Деда Мороза на углу телевизора, огоньки по рамке, снег на экране.
func _tv_dress() -> void:
	var tv := Vector3(1.6, 0.86, BACK + 0.38)  # центр корпуса (neon_room.gd _tv_corner)
	var half := Vector3(0.3, 0.235, 0.16)
	var front := tv.z + half.z + 0.006
	# колпак Деда Мороза из мягкой ткани: опушка-мех, верх свесился с угла наружу (референсы владельца)
	# колпак висит на макушке лавовой лампы (владелец) — наклонён, кончик свисает вперёд-влево;
	# лампа — NeonRoom._tv_corner: основание (tv.x + 0,18; 1,13), металлический колпачок наверху до 1,53 м
	var hat := santa_hat(0.05)
	var lamp_top := Vector3(tv.x + 0.18, 1.5, tv.z - 0.06)
	var axis := Vector3(-0.45, 1.0, 0.4).normalized()
	var flop := Vector3(-1.0, -0.2, 0.6)
	flop = (flop - axis * flop.dot(axis)).normalized()
	hat.transform = Transform3D(Basis(flop, axis, flop.cross(axis)), lamp_top)
	add_child(hat)
	# огоньки по верху и бокам рамки
	var wire := _mat(Color("1d2a24"), 0.6)
	var top := tv.y + half.y - 0.012
	var points := _swag(Vector3(tv.x - half.x, top, front), Vector3(tv.x + half.x, top, front), 0.03, 18)
	_tube(points, 0.0025, wire)
	_string_bulbs(points, 0.055, 0.01, 0, 0.7)
	for x: float in [tv.x - half.x + 0.005, tv.x + half.x - 0.005]:
		var side := PackedVector3Array([Vector3(x, top, front), Vector3(x, tv.y - half.y + 0.03, front)])
		_tube(side, 0.0025, wire)
		_string_bulbs(side, 0.06, 0.0, 2, 0.7)
	# снег на экране: падает за надписями
	var title: Variant = _room.get("_tv_title")
	if title is Control and is_instance_valid(title) and (title as Control).get_parent() is SubViewport:
		var vp := (title as Control).get_parent() as SubViewport
		_tv_snow = TvSnow.new()
		_tv_snow.size = Vector2(vp.size)
		vp.add_child(_tv_snow)
		vp.move_child(_tv_snow, 0)


## Снег на экране телевизора: пиксельные хлопья и сугроб внизу (рисуется во вьюпорт экрана).
class TvSnow extends Control:
	var _flakes: Array[Vector4] = []
	var _time := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 31
		for i in 46:
			_flakes.append(Vector4(rng.randf() * size.x, rng.randf() * size.y, rng.randf_range(18.0, 46.0), rng.randf_range(3.0, 7.0)))

	func _process(delta: float) -> void:
		if not Prefs.reduce_motion:
			_time += delta
			queue_redraw()

	func _draw() -> void:
		for f: Vector4 in _flakes:
			var y := fposmod(f.y + _time * f.z, size.y + 10.0) - 5.0
			var x := f.x + sin(_time * 0.8 + f.y) * 8.0
			var s := roundf(f.w)
			draw_rect(Rect2(roundf(x), roundf(y), s, s), Color(0.85, 0.95, 1.0, 0.75))
		# сугроб из «пикселей» внизу экрана
		for x in range(0, int(size.x), 10):
			var hgt := 18.0 + 8.0 * sin(x * 0.045) + 5.0 * sin(x * 0.13 + 1.0)
			draw_rect(Rect2(x, size.y - hgt, 10, hgt), Color(0.9, 0.96, 1.0, 0.85))
