extends Node3D
## Мини-корзина хаба. Удержание открывает снятие, перетаскивание двигает по стене.

const FILE := "user://room_props.cfg"
const DEFAULT_AT := Vector2(-1.29, 0.94)
const RIM_RADIUS := 0.095
const RIM_THICKNESS := 0.009
const RIM_DEPTH := 0.27
const HOLD_TIME := 0.38
const Fanfare := preload("res://games/king_of_12/audio/music/victory.mp3")
const Confetti := preload("res://hub/confetti.gd")
const RoomIcons := preload("res://hub/room_icons.gd")
const REMOVE_SIZE := Vector2(40, 40)
const NET_LOOPS := 10

var room: Node3D
var _remove: Button
var _held := false
var _dragging := false
var _press_time := 0
var _press_at := Vector2.ZERO
var _start := Vector3.ZERO
var _wall_offset := Vector2.ZERO
var _score_cooldown := 0


func _ready() -> void:
	var plastic: StandardMaterial3D = room._mat(Color("c1b5d9"), 0.72)
	var orange: StandardMaterial3D = room._mat(Color("c65c3e"), 0.52)
	room._soft(Vector3(0.29, 0.21, 0.018), Vector3(0, 0.071, 0.018), "plastic", Color("9083b2"), self, Vector3.ZERO, 0.012)
	room._box(Vector3(0.135, 0.009, 0.006), Vector3(0, 0.104, 0.032), plastic, self)
	for x: float in [-0.067, 0.067]:
		room._box(Vector3(0.008, 0.072, 0.006), Vector3(x, 0.071, 0.032), plastic, self)
	room._box(Vector3(0.07, 0.016, RIM_DEPTH - RIM_RADIUS), Vector3(0, -0.008, (RIM_DEPTH - RIM_RADIUS) * 0.5), orange, self)
	var ring := TorusMesh.new()
	ring.inner_radius = RIM_RADIUS
	ring.outer_radius = RIM_RADIUS + RIM_THICKNESS
	ring.rings = 24
	ring.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.mesh = ring
	rim.material_override = orange
	rim.position.z = RIM_DEPTH
	add_child(rim)
	_make_net()
	_remove = HubStyle.button("", 14)
	_remove.theme = HubStyle.theme()
	_remove.name = "BasketRemove"
	_remove.custom_minimum_size = REMOVE_SIZE
	_remove.size = REMOVE_SIZE
	_remove.draw.connect(func(): RoomIcons.cross(_remove, HubStyle.PINK))
	LeaveGuard.hold(_remove, func(): _set_installed(false), "Снять корзину со стены")
	_remove.hide()
	add_child(_remove)
	var prefs := ConfigFile.new()
	prefs.load(FILE)
	var saved: Variant = prefs.get_value("basket", "at", DEFAULT_AT)
	_set_wall_at(saved if saved is Vector2 else DEFAULT_AT)
	visible = bool(prefs.get_value("basket", "installed", true))


func _make_net() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Array[Vector3] = []
	var middle: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for i in NET_LOOPS:
		var angle := TAU * float(i) / NET_LOOPS
		top.append(_net_point(angle, RIM_RADIUS + 0.002, -0.003))
		middle.append(_net_point(angle + PI / NET_LOOPS, 0.072 + 0.003 * cos(angle * 3.0), -0.058 + 0.004 * sin(angle * 2.0)))
		bottom.append(_net_point(angle, 0.056 + 0.004 * sin(angle * 3.0), -0.119 + 0.005 * cos(angle * 2.0)))
	for i in NET_LOOPS:
		var next := (i + 1) % NET_LOOPS
		_net_rope(mesh, top[i], middle[i], 0.003)
		_net_rope(mesh, top[next], middle[i], 0.003)
		_net_rope(mesh, middle[i], bottom[i], 0.005)
		_net_rope(mesh, middle[i], bottom[next], 0.005)
		_net_rope(mesh, bottom[i], bottom[next], 0.006)
	var net := MeshInstance3D.new()
	net.name = "WovenNet"
	net.mesh = mesh.commit()
	var rope: StandardMaterial3D = room._mat(Color("e2d6cc"), 0.95)
	rope.cull_mode = BaseMaterial3D.CULL_DISABLED
	net.material_override = rope
	add_child(net)


func _net_point(angle: float, radius: float, y: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, RIM_DEPTH + sin(angle) * radius)


func _net_rope(mesh: SurfaceTool, start: Vector3, finish: Vector3, sag: float) -> void:
	var rings: Array = []
	for step in 5:
		var t := float(step) / 4.0
		var center := start.lerp(finish, t) + Vector3.DOWN * (4.0 * sag * t * (1.0 - t))
		var tangent := (finish - start + Vector3.DOWN * (4.0 * sag * (1.0 - 2.0 * t))).normalized()
		var axis := tangent.cross(Vector3.RIGHT).normalized()
		var cross_axis := tangent.cross(axis)
		var ring: Array[Vector3] = []
		for side in 6:
			var angle := TAU * float(side) / 6.0
			ring.append(axis * cos(angle) + cross_axis * sin(angle))
		rings.append({"center": center, "normals": ring})
	for step in 4:
		for side in 6:
			var next := (side + 1) % 6
			_rope_vertex(mesh, rings[step], side)
			_rope_vertex(mesh, rings[step + 1], side)
			_rope_vertex(mesh, rings[step + 1], next)
			_rope_vertex(mesh, rings[step], side)
			_rope_vertex(mesh, rings[step + 1], next)
			_rope_vertex(mesh, rings[step], next)


func _rope_vertex(mesh: SurfaceTool, ring: Dictionary, side: int) -> void:
	var normal: Vector3 = ring.normals[side]
	mesh.set_normal(normal)
	mesh.add_vertex((ring.center as Vector3) + normal * 0.00165)


func install() -> void:
	if visible:
		room.shelf_hint.emit("Корзина уже висит · удерживайте её для переноса или снятия")
		return
	_set_wall_at(DEFAULT_AT)
	_set_installed(true)
	room.shelf_hint.emit("Корзина под окном · удерживайте для переноса")


func _set_installed(on: bool) -> void:
	visible = on
	_remove.hide()
	_held = false
	_dragging = false
	_save()


func _save() -> void:
	var prefs := ConfigFile.new()
	prefs.load(FILE)
	prefs.set_value("basket", "installed", visible)
	prefs.set_value("basket", "at", Vector2(position.x, position.y))
	prefs.save(FILE)


func _set_wall_at(at: Vector2) -> void:
	position = Vector3(clampf(at.x, -2.72, 2.68), clampf(at.y, 0.36, 1.92), room.BACK + 0.012)


func _hit(screen: Vector2) -> bool:
	var cam: Camera3D = room.camera
	var center := global_position + Vector3(0, 0.055, 0.03)
	if cam.is_position_behind(center):
		return false
	var a := cam.unproject_position(global_position + Vector3(-0.15, -0.115, RIM_DEPTH))
	var b := cam.unproject_position(global_position + Vector3(0.15, 0.18, 0.0))
	var bounds := Rect2(a, b - a).abs().grow(5)
	return bounds.has_point(screen) and room._box_at(screen) == null


func _process(_delta: float) -> void:
	if not visible or room.remote_view:
		_remove.hide()
		return
	if _held and not _dragging and Time.get_ticks_msec() - _press_time >= int(HOLD_TIME * 1000):
		_remove.show()
	if _remove.visible:
		var p: Vector2 = room.camera.unproject_position(global_position + Vector3.UP * 0.23)
		_remove.position = (p - Vector2(REMOVE_SIZE.x * 0.5, REMOVE_SIZE.y)).clamp(
			Vector2(8, 8), get_viewport().get_visible_rect().size - REMOVE_SIZE - Vector2(8, 8))


func _input(event: InputEvent) -> void:
	if not _held:
		return
	if event is InputEventMouseMotion and Time.get_ticks_msec() - _press_time >= int(HOLD_TIME * 1000):
		if _dragging or event.position.distance_to(_press_at) > 8.0:
			var hit: Variant = room._wall_point(event.position)
			if hit is Vector3:
				_dragging = true
				_remove.hide()
				_set_wall_at(Vector2(hit.x, hit.y) + _wall_offset)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _dragging:
			_save()
		_held = false
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		position = _start
		_held = false
		_dragging = false
		_remove.hide()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or room.remote_view or room._ball_held or room._drag_box != null or room.focused != null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not room._pointer_clear():
			return
		if not _hit(event.position):
			_remove.hide()
			return
		var hit: Variant = room._wall_point(event.position)
		if not hit is Vector3:
			return
		_held = true
		_press_at = event.position
		_press_time = Time.get_ticks_msec()
		_start = position
		_wall_offset = Vector2(position.x - hit.x, position.y - hit.y)
		get_viewport().set_input_as_handled()


## Контакт сферы с круглым металлическим ободом. Внутри остаётся отверстие для мяча.
func rim_contact(ball_at: Vector3, velocity: Vector3, radius: float) -> Array:
	if not visible or _dragging or room.remote_view:
		return []
	var center := position + Vector3.BACK * RIM_DEPTH
	var tube := RIM_THICKNESS * 0.5
	var reach := radius + tube
	var gap := ball_at - center
	if absf(gap.y) >= reach:
		return []
	var flat := Vector3(gap.x, 0.0, gap.z)
	var distance := flat.length()
	if distance <= 0.0001 or absf(distance - RIM_RADIUS - tube) >= reach:
		return []
	var closest := center + flat * ((RIM_RADIUS + tube) / distance)
	var offset := ball_at - closest
	var separation := offset.length()
	if separation >= reach:
		return []
	var normal := offset / separation if separation > 0.0001 else -velocity.normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	return [normal, reach - separation]


func check_ball(previous: Vector3, next: Vector3, radius: float) -> bool:
	if not visible or _dragging or room.remote_view or Time.get_ticks_msec() < _score_cooldown:
		return false
	var center := position + Vector3.BACK * RIM_DEPTH
	if previous.y < center.y or next.y >= center.y:
		return false
	var cross_at := previous.lerp(next, inverse_lerp(previous.y, next.y, center.y))
	if Vector2(cross_at.x - center.x, cross_at.z - center.z).length() > RIM_RADIUS - radius:
		return false
	_score_cooldown = Time.get_ticks_msec() + 1000
	var conf := Confetti.make(Color("ffba78"))
	conf.position = room.camera.unproject_position(to_global(Vector3(0, 0.05, RIM_DEPTH)))
	conf.amount = 30
	conf.lifetime = 0.95
	conf.explosiveness = 0.92
	conf.direction = Vector2.UP
	conf.spread = 60.0
	conf.z_index = 20
	add_child(conf)
	Confetti.start(conf)
	var chime := AudioStreamPlayer.new()
	chime.stream = Fanfare
	chime.bus = "SFX"
	chime.volume_db = -19.0
	add_child(chime)
	chime.play()
	chime.create_tween().tween_callback(chime.queue_free).set_delay(1.1)
	room.shelf_hint.emit("Попадание!")
	return true
