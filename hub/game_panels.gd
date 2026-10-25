class_name GamePanels
extends Node3D
## «Окошки игр» в хабе, как интерфейс в VR: на шкафу сверху справа стоит стеклянный куб;
## по щелчку из него плавно вылетают прозрачные стеклянные панели — по одной на игру, на каждой постер
## (лицевая сторона коробки; «Перудо» — снимок 3D-набора стаканов). Панели висят в 3D не идеально ровно
## (каждая чуть сдвинута и повёрнута), вся группа плывёт за курсором (параллакс), постер внутри стекла — тоже,
## на своей глубине. Наведение — панель наклоняется к курсору и над ней появляется название; щелчок — она
## подлетает ближе, остальные расступаются и гаснут, справа — карточка игры с описанием и «Играть».
## Закрыть — куб ещё раз, щелчок мимо или Esc: панели улетают обратно в него.
## Создаёт NeonRoom, карточку игры ведёт hub.gd.

signal game_selected(game: Dictionary)
signal game_released
signal editor_requested
var input_locked := false
var _editor_tile: Node3D
var _editor_body: StaticBody3D
var _editor_mat: ShaderMaterial

const PANEL_H := 0.17  # высота стекла, м (ширина — по пропорциям постера)
const CELL := Vector2(0.25, 0.17)  # шаг сетки (по самой широкой панели)
const COLS := 3
const GAP := Vector2(0.035, 0.05)
const DIST := 1.25  # от камеры до плоскости панелей, м
const CENTER := Vector2(0.49, -0.02)  # центр сетки относительно центра экрана, м: справа от шкафа, левый столбец чуть заходит на шкаф
const TURN := 1.6  # боковые столбцы повёрнуты к среднему (рад на метр от центрального столбца, ~26°)
const CENTER_DEPTH := 0.09  # средний столбец — глубже (дальше от игрока), м
const LAUNCH_SIZE := 0.11  # куб-кнопка на шкафу, м
const FLY_TIME := 0.6  # полёт окошка из куба на место, с
const FLY_SCALE := 0.12  # размер окошка в момент вылета (внутри куба)
const LAYER := 2  # слой столкновений панелей (лучи коробок в шкафу его не видят)
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D poster : source_color, filter_linear_mipmap;
uniform bool has_poster = true;
uniform vec4 tint : source_color = vec4(0.07, 0.05, 0.16, 1.0);
uniform vec4 rim : source_color = vec4(0.18, 0.95, 1.0, 1.0);
uniform float poster_aspect = 1.5;  // ширина / высота постера
uniform float panel_aspect = 1.42;
uniform vec2 shift = vec2(0.0);  // параллакс постера внутри стекла (доля панели)
uniform float fade = 1.0;  // появление / угасание
uniform float glow = 0.0;  // наведение / выбор
uniform float base_alpha = 0.55;  // заливка стекла
uniform float rim_alpha = 0.75;  // окантовка

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(panel_aspect, 1.0);
	float d = rbox(p, vec2(panel_aspect, 1.0) * 0.5, 0.06);
	if (d > 0.0) { discard; }
	// стекло: тёмная прозрачная подложка, к краю светлее (как толщина стекла)
	float edge = smoothstep(-0.05, 0.0, d);
	vec3 col = tint.rgb;
	float a = base_alpha + 0.25 * edge;
	// постер — внутри стекла с отступом, со своим параллаксом
	vec2 inner = vec2(panel_aspect, 1.0) * 0.5 - 0.06;
	vec2 pp = p - shift * vec2(panel_aspect, 1.0);
	// вписать постер по высоте/ширине с сохранением пропорций
	vec2 half_p = inner;
	if (poster_aspect > inner.x / inner.y) { half_p.y = inner.x / poster_aspect; } else { half_p.x = inner.y * poster_aspect; }
	vec2 puv = pp / (half_p * 2.0) + 0.5;
	float in_p = step(0.0, puv.x) * step(puv.x, 1.0) * step(0.0, puv.y) * step(puv.y, 1.0);
	if (has_poster && in_p > 0.5) {
		float pd = rbox(pp, half_p, 0.035);
		float pm = 1.0 - smoothstep(-0.004, 0.004, pd);
		vec4 pt = texture(poster, puv);
		col = mix(col, pt.rgb, pm * 0.94 * pt.a);
		a = mix(a, 0.96, pm * pt.a);
	}
	// блик на стекле: мягкая диагональная полоса, идёт против параллакса
	float g = smoothstep(0.16, 0.0, abs((p.x - p.y * 0.6) + shift.x * 2.5 - 0.15));
	col += vec3(0.9, 0.95, 1.0) * g * 0.10;
	// светящийся край; ярче при наведении
	float rim_k = smoothstep(-0.012, 0.0, d);
	col = mix(col, rim.rgb, rim_k * (0.55 + 0.45 * glow));
	a = max(a, rim_k * (rim_alpha + (1.0 - rim_alpha) * glow));
	col += rim.rgb * glow * 0.06;
	ALBEDO = col;
	ALPHA = a * fade;
}
"""

## Тень пластинки: размытый тёмный силуэт позади стекла (свет сверху-слева) — видно, что пластинка висит в воздухе.
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float panel_aspect = 1.42;
uniform float spread = 0.15;  // мягкость края (доля высоты)
uniform float strength = 0.85;
uniform float fade = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(panel_aspect, 1.0) * (1.0 + spread * 2.0);
	vec2 q = abs(p) - (vec2(panel_aspect, 1.0) * 0.5 - 0.06);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.06;
	float a = 1.0 - smoothstep(-spread * 0.5, spread, d);
	ALBEDO = vec3(0.02, 0.0, 0.05);
	ALPHA = a * a * strength * fade;
}
"""
const SHADOW_OFF := Vector3(0.026, -0.04, -0.07)  # тень: правее, ниже и позади стекла

var camera: Camera3D
var is_open := false
var _items: Array = []  # [{game, root, mesh, mat, body, label, home: Transform3D, depth, seed}]
const ORDER_FILE := "user://game_panels.cfg"
var _panel_press := -1
var _panel_hold := 0.0
var _panel_drag := -1
var _panel_point := Vector2.ZERO
var _hover := -1
var _selected := -1
var _t := 0.0
var _shader: Shader
var _anchor := Transform3D.IDENTITY  # плоскость панелей перед камерой (снимается при открытии)
var _launcher: Node3D  # стеклянный квадратик справа сверху от шкафа
var _launch_mat: ShaderMaterial
var _launch_body: StaticBody3D
var _launch_halo: MeshInstance3D
var _launch_hover := false
var _open_t := 0.0  # сколько прошло с открытия (панели вылетают по очереди)
var _veil: MeshInstance3D  # лёгкое затемнение комнаты за окошками — шкаф не мешает читать постеры
var _veil_mat: StandardMaterial3D


func setup(cam: Camera3D, games: Array, launcher_at: Vector3) -> void:
	camera = cam
	_shader = Shader.new()
	_shader.code = SHADER
	_veil = MeshInstance3D.new()
	var vq := QuadMesh.new()
	vq.size = Vector2(4.0, 3.0)
	_veil.mesh = vq
	_veil_mat = StandardMaterial3D.new()
	_veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_veil_mat.albedo_color = Color(0.03, 0.01, 0.07, 0.0)
	_veil_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_veil.material_override = _veil_mat
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_veil)
	for g in games:
		if g.get("shelf", true):  # одна панель на игру: «Тип Топ» — одна (версии — переключателем в карточке)
			_items.append(_make(g))
	_load_order()
	_make_launcher(launcher_at)
	_make_editor_tile()
	for it in _items:
		(it["root"] as Node3D).visible = false
	_veil.visible = false


## Кнопка — стеклянный куб на шкафу сверху справа: каждая грань — то же стекло, что у окошек
## (полупрозрачная заливка, светящаяся окантовка), сквозь него видны дальние грани. Медленно вращается.
## Значок редактора — дочернее 3D-окошко верхней левой игры: общий поворот и параллакс.
func _make_editor_tile() -> void:
	if _items.is_empty():
		return
	var first: Node3D = _items[0].root
	var panel_size: Vector2 = (_items[0].mesh.mesh as QuadMesh).size
	_editor_tile = Node3D.new()
	first.add_child(_editor_tile)
	_editor_tile.position = Vector3(-panel_size.x * 0.5 - 0.047, panel_size.y * 0.5 - 0.0375, 0.004)
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	glass.mesh = quad
	_editor_mat = ShaderMaterial.new()
	_editor_mat.shader = _shader
	_editor_mat.set_shader_parameter("has_poster", false)
	_editor_mat.set_shader_parameter("panel_aspect", 1.0)
	_editor_mat.set_shader_parameter("tint", Color("101b33"))
	_editor_mat.set_shader_parameter("base_alpha", 0.7)
	_editor_mat.set_shader_parameter("glow", 0.35)
	glass.material_override = _editor_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_editor_tile.add_child(glass)
	var icon := MeshInstance3D.new()
	var face := QuadMesh.new()
	face.size = Vector2(0.045, 0.045)
	icon.mesh = face
	icon.position.z = 0.002
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = ShelfIcons.icon()
	icon.material_override = material
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_editor_tile.add_child(icon)
	_editor_body = StaticBody3D.new()
	_editor_body.collision_layer = 0
	_editor_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.075, 0.075, 0.012)
	collision.shape = shape
	_editor_body.add_child(collision)
	_editor_tile.add_child(_editor_body)


func _make_launcher(on_shelf: Vector3) -> void:
	_launcher = Node3D.new()
	add_child(_launcher)
	_launcher.global_position = on_shelf + Vector3(0, LAUNCH_SIZE * 0.5 + 0.004, 0)
	_launch_mat = ShaderMaterial.new()
	_launch_mat.shader = _shader
	_launch_mat.set_shader_parameter("has_poster", false)
	_launch_mat.set_shader_parameter("panel_aspect", 1.0)
	_launch_mat.set_shader_parameter("fade", 1.0)
	_launch_mat.set_shader_parameter("glow", 0.0)
	_launch_mat.set_shader_parameter("shift", Vector2.ZERO)
	_launch_mat.set_shader_parameter("base_alpha", 0.3)
	_launch_mat.set_shader_parameter("rim_alpha", 0.9)
	# рёбра ярче обычного — светятся с ореолом (glow окружения), чтобы куб притягивал взгляд
	_launch_mat.set_shader_parameter("rim", Color(0.35, 1.7, 1.9))
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


## Откуда вылетают и куда улетают окошки: из центра куба, лицом к игроку.
func _launch_xf() -> Transform3D:
	return Transform3D(camera.global_transform.basis, _launcher.global_position)

func move_launcher(on_shelf: Vector3) -> void:
	_launcher.global_position = on_shelf + Vector3(0, LAUNCH_SIZE * 0.5 + 0.004, 0)
	_launch_halo.global_position = (
		_launcher.global_position + (camera.global_position - _launcher.global_position).normalized() * -0.08
	)


func _make(g: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var id := str(g.get("id", ""))
	var tex := GameBox.cover_texture(id, "front")
	if tex == null and ResourceLoader.exists("res://hub/covers/%s_poster.png" % id):
		tex = load("res://hub/covers/%s_poster.png" % id)  # «Перудо» — снимок 3D-набора стаканов (tools/render/perudo_poster)
	# стекло — по пропорциям постера (с полями под рамку), чтобы постер занимал его почти целиком
	var aspect := float(tex.get_width()) / maxf(1.0, tex.get_height()) if tex else 1.3
	var size := Vector2(clampf(PANEL_H * aspect * 1.04, 0.14, CELL.x), PANEL_H)
	var mesh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mesh.mesh = q
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("panel_aspect", size.x / size.y)
	mat.set_shader_parameter("glow", 0.0)
	mat.set_shader_parameter("shift", Vector2.ZERO)
	mat.set_shader_parameter("has_poster", tex != null)
	if tex:
		mat.set_shader_parameter("poster", tex)
		mat.set_shader_parameter("poster_aspect", float(tex.get_width()) / maxf(1.0, tex.get_height()))
	else:
		mat.set_shader_parameter("tint", Color(g.get("color", Color("6b3fa0")), 1.0).darkened(0.35))
	mat.set_shader_parameter("fade", 0.0)
	mesh.material_override = mat
	# тень — отдельная размытая плашка позади стекла (рисуется раньше, тоже прозрачная)
	var shadow := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = size * 1.34
	shadow.mesh = sq
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SHADOW_SHADER
	smat.shader = ssh
	smat.set_shader_parameter("panel_aspect", size.x / size.y)
	smat.set_shader_parameter("fade", 0.0)
	smat.render_priority = -1
	shadow.material_override = smat
	shadow.position = SHADOW_OFF
	root.add_child(shadow)
	root.add_child(mesh)
	# своя подпись на стекле у игр без обложки (Перудо — набор стаканов)
	if tex == null:
		var big := Label3D.new()
		big.text = str(g.get("title", id)).to_upper()
		big.font = HubStyle.font("title")
		big.font_size = 48
		big.pixel_size = 0.0012
		big.modulate = HubStyle.TEXT
		big.outline_size = 8
		big.position = Vector3(0, 0, 0.002)
		big.no_depth_test = false
		root.add_child(big)
	# название над панелью — при наведении
	var label := Label3D.new()
	label.text = str(g.get("title", id))
	label.font = HubStyle.font("title")
	label.font_size = 40
	label.pixel_size = 0.0011
	label.outline_size = 10
	label.outline_modulate = Color(0.04, 0.02, 0.08, 0.0)  # контур гаснет вместе с текстом (_process)
	label.modulate = Color(HubStyle.CYAN.r * 1.4, HubStyle.CYAN.g * 1.4, HubStyle.CYAN.b * 1.4, 0.0)
	label.position = Vector3(0, size.y * 0.5 + 0.022, 0.01)
	label.shaded = false
	# длинное название — не шире окошка (с запасом), переносится и растёт вверх; рисуется поверх соседних окошек
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if label.text.length() > 16:
		label.font_size = 30  # длинное название — мельче, в две строки
	label.width = size.x * 2.6 / label.pixel_size
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	root.add_child(label)
	# тело для луча мыши — отдельный слой, чтобы не мешать выбору коробок
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (LAYER - 1)
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.01)
	cs.shape = shape
	body.add_child(cs)
	body.input_ray_pickable = false
	root.add_child(body)
	return {"game": g, "root": root, "mesh": mesh, "mat": mat, "body": body, "label": label,
		"home": Transform3D.IDENTITY, "depth": 1.0, "seed": randf() * TAU, "tilt": Vector2.ZERO, "label_a": 0.0, "shadow": shadow, "smat": smat}


## Раскладка: сетка по 4 в ряд в плоскости перед камерой, с лёгким разбросом глубины и поворота.
func _layout() -> void:
	var fwd := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	# плоскость — перед камерой, по центру экрана, чуть выше середины (внизу — подсказка и панели хаба)
	var center := camera.global_position + fwd * DIST + up * 0.03
	_anchor = Transform3D(Basis(right, up, -fwd), center)
	var n := _items.size()
	var rows := int(ceil(float(n) / COLS))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # раскладка одна и та же при каждом открытии
	for i in n:
		var r := i / COLS
		var c := i % COLS
		var in_row := mini(COLS, n - r * COLS)
		var x := (c - (in_row - 1) * 0.5) * (CELL.x + GAP.x) + CENTER.x
		var y := ((rows - 1) * 0.5 - r) * (CELL.y + GAP.y) + CENTER.y
		var z := rng.randf_range(-0.06, 0.06)
		# повернуты к центру (как экраны вокруг человека в VR) + немного вразнобой
		# сначала — лицом к игроку (сетка правее центра: без этого правый столбец камера видит сбоку,
		# и его поворот «съедается» перспективой), потом — симметрично к среднему столбцу
		var face_yaw := atan2(-x, DIST - z)
		var face_pitch := atan2(y, DIST - z)
		var yaw := face_yaw - (x - CENTER.x) * TURN + rng.randf_range(-0.04, 0.04)
		var pitch := face_pitch + rng.randf_range(-0.04, 0.04)
		var roll := rng.randf_range(-0.03, 0.03)
		var b := Basis.from_euler(Vector3(pitch, yaw, roll))
		var deeper := CENTER_DEPTH if absf(x - CENTER.x) < 0.01 else 0.0
		_items[i]["home"] = Transform3D(b, Vector3(x, y, z * 0.6 + absf(x - CENTER.x) * 0.18 - deeper))
		_items[i]["depth"] = 1.0 + z * 6.0


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_layout()
	_open_t = 0.0
	_veil.visible = true
	_veil.global_transform = _anchor * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.35))
	create_tween().tween_property(_veil_mat, "albedo_color:a", 0.5, 0.35).set_trans(Tween.TRANS_SINE)
	_selected = -1
	_hover = -1
	for i in _items.size():
		var it: Dictionary = _items[i]
		var root: Node3D = it["root"]
		root.remove_meta("intro_done")
		var home: Transform3D = it["home"]
		# вылетают из куба по очереди: проявляются крошечными прямо в кубе и плавно летят на место
		root.visible = true
		root.global_transform = _launch_xf()
		root.scale = Vector3.ONE * FLY_SCALE
		var mat: ShaderMaterial = it["mat"]
		mat.set_shader_parameter("fade", 0.0)
		var delay := 0.06 * i
		it["delay"] = delay
		it["fly"] = 0.0
		var tw := create_tween().set_parallel()
		tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.18).set_delay(delay).set_trans(Tween.TRANS_SINE)
		tw.tween_method(func(v: float): it["fly"] = v, 0.0, 1.0, FLY_TIME).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		(it["body"] as StaticBody3D).collision_layer = 1 << (LAYER - 1)
	Sfx.play("card_slide", -8)


func close() -> void:
	_cancel_panel_drag()
	if not is_open:
		return
	if _selected >= 0:
		_selected = -1
		game_released.emit()
	is_open = false
	create_tween().tween_property(_veil_mat, "albedo_color:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	for i in _items.size():
		var it: Dictionary = _items[i]
		var mat: ShaderMaterial = it["mat"]
		var cur: float = mat.get_shader_parameter("fade")
		# улетают обратно в куб и гаснут уже внутри него
		var d := 0.03 * (_items.size() - i)
		var tw := create_tween().set_parallel()
		(
			tw
			. tween_method(func(v: float): it["fly"] = v, float(it.get("fly", 1.0)), 0.0, FLY_TIME * 0.8)
			. set_delay(d)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
		(
			tw
			. tween_method(func(v: float): mat.set_shader_parameter("fade", v), cur, 0.0, 0.15)
			. set_delay(d + FLY_TIME * 0.8 - 0.12)
			. set_trans(Tween.TRANS_SINE)
		)
		(it["body"] as StaticBody3D).collision_layer = 0
		(it["label"] as Label3D).modulate.a = 0.0
	get_tree().create_timer(FLY_TIME * 0.8 + 0.03 * _items.size() + 0.1).timeout.connect(
		func():
			if not is_open:
				_veil.visible = false
				for it2 in _items:
					(it2["root"] as Node3D).visible = false
	)
	Sfx.play("card_slide", -10)


## Выбранная панель подлетает ближе (левее центра — справа карточка игры), остальные расступаются.
func select(i: int) -> void:
	if i == _selected:
		return
	_selected = i
	Sfx.play("card_place", -6)
	game_selected.emit(_items[i]["game"])


## Соседняя игра (стрелки, колесо), как листание коробок в шкафу.
func step(dir: int) -> void:
	if _selected >= 0:
		select(posmod(_selected + dir, _items.size()))


func deselect() -> void:
	if _selected < 0:
		return
	_selected = -1
	game_released.emit()


func _panel_at(screen: Vector2) -> int:
	var from := camera.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * 10.0, 1 << (LAYER - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	for i in _items.size():
		if _items[i]["body"] == hit["collider"]:
			return i
	return -1


func _launcher_at(screen: Vector2) -> bool:
	var from := camera.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * 10.0, 1 << (LAYER - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == _launch_body


## Порядок VR-окон личный и не связан с расстановкой коробок.
func _load_order() -> void:
	var file := ConfigFile.new()
	if file.load(ORDER_FILE) != OK and file.load("res://hub/defaults/game_panels.cfg") != OK:
		return  # своего порядка нет — берём стартовый из игры, нет и его — по умолчанию
	var saved: Variant = file.get_value("panels", "order", [])
	var order: Array = saved if saved is Array else []
	var sorted: Array = []
	for id in order:
		for item: Dictionary in _items:
			if item.game.id == id and not sorted.has(item):
				sorted.append(item)
	for item: Dictionary in _items:
		if not sorted.has(item):
			sorted.append(item)
	_items = sorted


func _cancel_panel_drag() -> void:
	if _panel_drag >= 0:
		_items[_panel_drag].body.collision_layer = (1 << (LAYER - 1)) if is_open else 0
		_items[_panel_drag].mat.set_shader_parameter("rim", Color("2ef2ff"))
	_panel_press = -1
	_panel_drag = -1
	_panel_hold = 0.0


func _swap_panels(source: int, target: int) -> void:
	var item: Dictionary = _items[source]
	_items[source] = _items[target]
	_items[target] = item
	_editor_tile.reparent(_items[0].root, false)
	var dimensions: Vector2 = (_items[0].mesh.mesh as QuadMesh).size
	_editor_tile.position = Vector3(-dimensions.x * 0.5 - 0.047, dimensions.y * 0.5 - 0.0375, 0.004)
	_layout()
	var file := ConfigFile.new()
	file.set_value("panels", "order", _items.map(func(entry): return str(entry.game.id)))
	file.save(ORDER_FILE)
	Sfx.play("card_place", -12)


func _unhandled_input(e: InputEvent) -> void:
	if input_locked:
		return
	if is_open and e is InputEventMouse:
		_panel_point = e.position
		if (
			e is InputEventMouseButton
			and e.button_index == MOUSE_BUTTON_LEFT
			and not e.pressed
			and _panel_press >= 0
		):
			var source := _panel_press
			var was_drag := _panel_drag >= 0
			var target := _panel_at(e.position)
			_cancel_panel_drag()
			if was_drag and target >= 0 and target != source:
				_swap_panels(source, target)
			elif not was_drag:
				select(source)
			get_viewport().set_input_as_handled()
			return
	if is_open and is_instance_valid(_editor_tile) and _editor_tile.visible and e is InputEventMouse:
		var origin := camera.project_ray_origin(e.position)
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + camera.project_ray_normal(e.position) * 10.0, 1 << (LAYER - 1)
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == _editor_body:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				close()
				editor_requested.emit()
			get_viewport().set_input_as_handled()
			return
	# квадратик-кнопка — и при закрытых окошках
	if e is InputEventMouseMotion:
		var over := _launcher_at(e.position)
		if over != _launch_hover:
			_launch_hover = over
			if over:
				Sfx.play("hover", -14, 0.1, 0.05)
		if over:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			get_viewport().set_input_as_handled()
			return
	elif (
		e is InputEventMouseButton
		and e.pressed
		and e.button_index == MOUSE_BUTTON_LEFT
		and _launcher_at(e.position)
	):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if e is InputEventMouseMotion:
		var h := _panel_at(e.position)
		if h != _hover:
			_hover = h
			if h >= 0:
				Sfx.play("hover", -14, 0.1, 0.05)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h >= 0 else Input.CURSOR_ARROW)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			var h := _panel_at(e.position)
			if h >= 0:
				_panel_press = h
				_panel_hold = 0.0
			elif _selected >= 0:
				deselect()
			else:
				close()
		elif e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _selected >= 0:
			step(1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			if _selected >= 0:
				deselect()
			else:
				close()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and e.keycode in [KEY_ESCAPE, KEY_BACKSPACE]:
		if _selected >= 0:
			deselect()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif (
		e is InputEventKey
		and e.pressed
		and _selected >= 0
		and e.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	):
		step(1 if e.keycode in [KEY_RIGHT, KEY_DOWN] else -1)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _panel_press >= 0 and _panel_drag < 0 and _selected < 0:
		_panel_hold += delta
		if _panel_hold >= 0.4:
			_panel_drag = _panel_press
			_items[_panel_drag].body.collision_layer = 0
			_items[_panel_drag].mat.set_shader_parameter("rim", Color("61f5a0"))
	if is_instance_valid(_editor_tile):
		_editor_tile.visible = is_open and not input_locked and _selected < 0
		_editor_body.collision_layer = (1 << (LAYER - 1)) if _editor_tile.visible else 0
		_editor_mat.set_shader_parameter(
			"fade", float((_items[0]["mat"] as ShaderMaterial).get_shader_parameter("fade"))
		)
	_t += delta
	_open_t += delta
	if _launch_mat:
		var lg: float = _launch_mat.get_shader_parameter("glow")
		var want := 1.0 if (is_open or _launch_hover) else 0.6 + 0.2 * sin(_t * 1.2)  # в покое — мягко «дышит» светом
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
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var m := mp / Vector2(vp.get_visible_rect().size) - Vector2(0.5, 0.5)
	var k := 1.0 - exp(-delta * 7.0)
	var fwd := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	for i in _items.size():
		var it: Dictionary = _items[i]
		var root: Node3D = it["root"]
		var home: Transform3D = it["home"]
		var depth: float = it["depth"]
		var mat: ShaderMaterial = it["mat"]
		var target: Transform3D
		var target_scale := 1.0
		var glow := 0.0
		if not root.visible:
			continue
		if i == _panel_drag:
			var origin := camera.project_ray_origin(_panel_point)
			var plane := Plane(_anchor.basis.z, _anchor.origin)
			var at: Variant = plane.intersects_ray(origin, camera.project_ray_normal(_panel_point))
			if at != null:
				root.global_position = at + _anchor.basis.z * 0.05
			mat.set_shader_parameter("glow", 1.0)
			continue
		if _selected == i and is_open:
			# ближе к игроку, по центру между панелью пати и карточкой игры; чуть повёрнута к карточке, слегка «дышит»
			var pos := camera.global_position + fwd * 0.7 + right * 0.0 + up * 0.0
			var b := Basis(right, up, -fwd).rotated(up, -0.1)
			target = Transform3D(b, pos + up * sin(_t * 1.6) * 0.004)
			target_scale = 1.3
			glow = 1.0
			# слегка поворачивается за курсором (мягче, чем при наведении: отсчёт — от всего экрана)
			var sp_sel := camera.unproject_position(root.global_position)
			var dv_sel := (mp - sp_sel) / (vp.get_visible_rect().size.y * 0.4)
			it["tilt"] = (it["tilt"] as Vector2).lerp(
				Vector2(clampf(dv_sel.x, -1, 1), clampf(dv_sel.y, -1, 1)), k
			)
			var tl_sel: Vector2 = it["tilt"]
			target.basis = target.basis * Basis.from_euler(Vector3(tl_sel.y * 0.16, tl_sel.x * 0.2, 0))
		else:
			# параллакс: вся группа плывёт за курсором, ближние панели — сильнее
			var off := Vector3(-m.x * 0.05 * depth, m.y * 0.035 * depth, 0)
			var bob := Vector3(0, sin(_t * 0.9 + it["seed"]) * 0.004, 0)
			var spread := Vector3.ZERO
			if _selected >= 0:
				# выбрана другая — расступаемся назад и в стороны
				spread = Vector3(home.origin.x * 0.25, home.origin.y * 0.15, -0.35)
			target = _anchor * Transform3D(home.basis, home.origin + off + bob + spread)
			# наклон к курсору при наведении (3D tilt)
			var tilt := Vector2.ZERO
			if _hover == i:
				var sp := camera.unproject_position(root.global_position)
				var dv := (mp - sp) / (vp.get_visible_rect().size.y * 0.12)
				tilt = Vector2(clampf(dv.x, -1, 1), clampf(dv.y, -1, 1))
				target_scale = 1.06
				glow = 0.7
			it["tilt"] = (it["tilt"] as Vector2).lerp(tilt, k)
			var tl: Vector2 = it["tilt"]
			target.basis = target.basis * Basis.from_euler(Vector3(tl.y * 0.22, tl.x * 0.28, 0))
		var fly: float = it.get("fly", 1.0)
		if fly < 1.0:
			# полёт из куба (или обратно): по траектории от куба к месту, без «догона»
			var xf := _launch_xf().interpolate_with(target, fly)
			root.global_transform = xf
			root.scale = Vector3.ONE * lerpf(FLY_SCALE, target_scale, fly)
		else:
			root.global_transform = root.global_transform.interpolate_with(target, k)
			root.scale = root.scale.lerp(Vector3.ONE * target_scale, k)
		# постер внутри стекла — свой параллакс (глубже стекла)
		var tl2: Vector2 = it["tilt"]
		mat.set_shader_parameter("shift", Vector2(-m.x * 0.02 + tl2.x * 0.012, m.y * 0.02 - tl2.y * 0.01))
		var cur_g: float = mat.get_shader_parameter("glow")
		mat.set_shader_parameter("glow", lerpf(cur_g, glow, k))
		# тень повторяет прозрачность стекла; у наведённой/выбранной — дальше и мягче (пластинка «приподнялась»)
		var smat: ShaderMaterial = it["smat"]
		smat.set_shader_parameter("fade", mat.get_shader_parameter("fade"))
		var lift := 1.0 + float(mat.get_shader_parameter("glow")) * 0.9
		(it["shadow"] as MeshInstance3D).position = SHADOW_OFF * lift
		smat.set_shader_parameter("spread", 0.15 + 0.07 * (lift - 1.0))
		# другие панели при выбранной — гаснут
		if is_open:
			var want_fade := 0.35 if (_selected >= 0 and _selected != i) else 1.0
			var cur_f: float = mat.get_shader_parameter("fade")
			if not root.has_meta("intro_done") and cur_f >= 0.99:
				root.set_meta("intro_done", true)
			if root.has_meta("intro_done"):
				mat.set_shader_parameter("fade", lerpf(cur_f, want_fade, k))
		# название — над наведённой (и над выбранной)
		var label: Label3D = it["label"]
		var la := 1.0 if is_open and i == _hover and _selected < 0 else 0.0  # у выбранной название — в карточке справа
		label.modulate.a = lerpf(label.modulate.a, la, k)
		label.outline_modulate.a = label.modulate.a * 0.85


