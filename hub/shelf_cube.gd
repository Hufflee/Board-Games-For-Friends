class_name ShelfCube
extends Node3D
## Светящийся куб над шкафом. Нажатие открывает личный редактор шкафа.

signal editor_requested

const LAUNCH_SIZE := 0.11
const LAYER := 2
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float glow = 0.0;
void fragment() {
	vec2 p = abs(UV - 0.5) - vec2(0.44);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - 0.06;
	if (d > 0.0) { discard; }
	float rim = smoothstep(-0.012, 0.0, d);
	float edge = smoothstep(-0.05, 0.0, d);
	vec3 color = vec3(0.07, 0.05, 0.16);
	color += vec3(0.09, 0.095, 0.1) * smoothstep(0.0, 0.16, 0.5 - UV.x + (UV.y - 0.5) * 0.6);
	ALBEDO = mix(color, vec3(0.35, 1.7, 1.9), rim * (0.55 + 0.45 * glow));
	ALPHA = max(0.3 + 0.25 * edge, rim * (0.9 + 0.1 * glow));
}
"""


var camera: Camera3D
var input_locked := false
var _launcher: Node3D
var _launch_mat: ShaderMaterial
var _launch_body: StaticBody3D
var _launch_halo: MeshInstance3D
var _launch_hover := false
var _t := 0.0


func setup(cam: Camera3D, launcher_at: Vector3) -> void:
	camera = cam
	_make_launcher(launcher_at)


func _make_launcher(on_shelf: Vector3) -> void:
	_launcher = Node3D.new()
	add_child(_launcher)
	_launcher.global_position = on_shelf + Vector3(0, LAUNCH_SIZE * 0.5 + 0.004, 0)
	_launch_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	_launch_mat.shader = shader
	_launch_mat.set_shader_parameter("glow", 0.0)
	# рёбра ярче обычного — светятся с ореолом (glow окружения), чтобы куб притягивал взгляд
	var h := LAUNCH_SIZE * 0.5
	# шесть граней-квадратов (у BoxMesh развёртка общая — окантовка вышла бы не по краям граней)
	for f in [[Vector3(0, 0, h), Vector3.ZERO], [Vector3(0, 0, -h), Vector3(0, PI, 0)],
			[Vector3(h, 0, 0), Vector3(0, PI / 2, 0)], [Vector3(-h, 0, 0), Vector3(0, -PI / 2, 0)],
			[Vector3(0, h, 0), Vector3(-PI / 2, 0, 0)], [Vector3(0, -h, 0), Vector3(PI / 2, 0, 0)]]:
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(LAUNCH_SIZE, LAUNCH_SIZE)
		face.mesh = q
		face.position = f[0]
		face.rotation = f[1]
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.material_override = _launch_mat
		_launcher.add_child(face)
	# ореол вокруг куба — светящееся пятно позади него (ничего не освещает, поэтому не проходит сквозь шкаф;
	# где его заслоняет шкаф — не виден)
	_launch_halo = MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.42, 0.42)
	_launch_halo.mesh = hq
	_launch_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hm := ShaderMaterial.new()
	var hs := Shader.new()
	hs.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(0.18, 0.95, 1.0, 1.0);
uniform float power = 0.5;
uniform float floor_y = 0.0;  // крышка шкафа: ниже неё ореол не рисуется (иначе виден внутри полки)
varying float wy;
void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	wy = (bb * vec4(VERTEX, 1.0)).y;
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}
void fragment() {
	if (wy < floor_y) { discard; }
	float r = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	ALBEDO = color.rgb * a * power;
}
"""
	hm.shader = hs
	hm.set_shader_parameter("floor_y", on_shelf.y)
	_launch_halo.material_override = hm
	add_child(_launch_halo)
	_launch_halo.global_position = _launcher.global_position + (camera.global_position - _launcher.global_position).normalized() * -0.08
	_launch_body = StaticBody3D.new()
	_launch_body.collision_layer = 1 << (LAYER - 1)
	_launch_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * LAUNCH_SIZE * 1.15
	cs.shape = shape
	_launch_body.add_child(cs)
	_launcher.add_child(_launch_body)


## Неоновый куб на шкафу невидим (кнопка в редакторе шкафа, владелец 15.11): грани и ореол скрыты,
## форма для нажатия остаётся — куб по-прежнему открывает редактор шкафа.
func set_launcher_hidden(hidden: bool) -> void:
	for face: Node in _launcher.get_children():
		if face is MeshInstance3D:
			(face as MeshInstance3D).visible = not hidden
	_launch_halo.visible = not hidden




func move_launcher(on_shelf: Vector3) -> void:
	(_launch_halo.material_override as ShaderMaterial).set_shader_parameter("floor_y", on_shelf.y)
	_launcher.global_position = on_shelf + Vector3(0, LAUNCH_SIZE * 0.5 + 0.004, 0)
	_launch_halo.global_position = (
		_launcher.global_position + (camera.global_position - _launcher.global_position).normalized() * -0.08
	)


func _launcher_at(screen: Vector2) -> bool:
	var from := camera.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * 10.0, 1 << (LAYER - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == _launch_body


func handle_pointer(event: InputEvent) -> bool:
	if input_locked or not event is InputEventMouse:
		return false
	if event is InputEventMouseMotion:
		var over := _launcher_at(event.position)
		if over and not _launch_hover:
			Sfx.play("hover", -14, 0.1, 0.05)
		_launch_hover = over
		if over:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return over
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _launcher_at(event.position):
		editor_requested.emit()
		return true
	return false


func _process(delta: float) -> void:
	if input_locked:
		_launch_hover = false
	_t += delta
	if _launch_mat:
		var lg: float = _launch_mat.get_shader_parameter("glow")
		var want := 1.0 if _launch_hover else 0.6 + 0.2 * sin(_t * 1.2)  # в покое — мягко «дышит» светом
		_launch_mat.set_shader_parameter("glow", lerpf(lg, want, 1.0 - exp(-delta * 8.0)))
		(_launch_halo.material_override as ShaderMaterial).set_shader_parameter(
			"power", 0.3 + 0.45 * float(_launch_mat.get_shader_parameter("glow"))
		)
		_launcher.scale = _launcher.scale.lerp(
			Vector3.ONE * (1.12 if _launch_hover else 1.0), 1.0 - exp(-delta * 10.0)
		)
		# куб медленно поворачивается и чуть покачивается; при наведении — быстрее
		_launcher.rotation.y += delta * (0.84 if _launch_hover else 0.27)
		_launcher.rotation.x = sin(_t * 0.42) * 0.08
