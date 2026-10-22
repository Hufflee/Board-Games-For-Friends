class_name GameBox
extends Node3D
## Игра в шкафу. Обычно — коробка: стоит вертикально, как книга, торцом к игроку.
## Лицевая сторона (+X) — обложка, задняя (−X) — оборот, торец (+Z) — корешок с названием.
## Картинки берутся из hub/covers/<id>_front|_back|_spine.(png|jpg); если их нет — цветная коробка с надписью.
## «Перудо» — не коробка, а набор кожаных стаканчиков с кубиками (face_z: к игроку повёрнута сторона +Z).
## Наведение — выезжает и светится; выбор — плавно летит к камере лицом к игроку.

const COVERS := "res://hub/covers/"
const META := "res://hub/covers/meta.cfg"
const SOFT := preload("res://hub/soft_box.gdshader")
const CUP_COLORS := [Color("4a2c1e"), Color("e8b21c"), Color("2f9e3a"), Color("e8642a"), Color("c8262c"), Color("2f64c8")]

var game: Dictionary
var size := Vector3(0.075, 0.30, 0.30)  # толщина (x), высота (y), глубина (z)
var color := Color("6b3fa0")
var home := Transform3D.IDENTITY  # место в шкафу
var hovered := false
var focused := false
var brightness := 0.5  # средняя яркость обложки: светлые коробки в руках подсвечиваем слабее
var face_z := false  # к игроку поворачивать сторону +Z (а не обложку +X)
var dim := false  # затемнённая заглушка «Coming soon» (нижняя стопка)

var _glow_mats: Array = []  # [материал, «пик» свечения при наведении]
## Тёмные торцы, которые на полке теряются, — чуть светлее (множитель к картинке).
const SPINE_BOOST := {"hues_and_cues": 1.35}

var _face_mats: Array = []  # материалы картинок — показываются без света комнаты, когда игра в руках
var _halo: MeshInstance3D
var _tween: Tween
var _glow := 0.0


func setup(g: Dictionary, box_size: Vector3, box_color: Color) -> void:
	game = g
	size = box_size
	color = box_color
	if is_cups():
		face_z = true
		size = Vector3(0.38, 0.17, 0.2)
		return
	# размеры — по картинкам: обложка задаёт высоту и ширину (бо́льшая сторона = box_size.y), торец — толщину
	var id := str(g.get("id", ""))
	var front := cover_texture(id, "front")
	if front:
		var asp := float(front.get_width()) / front.get_height()
		if asp >= 1.0:
			size.z = box_size.y
			size.y = box_size.y / asp
		else:
			size.y = box_size.y
			size.z = box_size.y * asp
	var spine := cover_texture(id, "spine")
	if spine:
		size.x = clampf(size.y * spine.get_width() / spine.get_height(), 0.03, 0.12)
	if g.has("thickness"):
		size.x = float(g["thickness"])  # толщина задана явно (обложка торца может быть не в пропорции)


## Коробка-заглушка «Coming soon» (белый шум) — для выбора не предназначена.
func is_soon() -> bool:
	return str(game.get("id", "")) == "soon"


## Переключили вариант игры (Тип Топ / для взрослых, Gloom / Gloomier) — другие обложки на той же коробке.
func set_variant(g: Dictionary) -> void:
	if is_cups() or is_soon() or str(g.get("id", "")) == str(game.get("id", "")):
		return
	game = g
	color = g.get("color", color)
	for ch in get_children():
		if not ch is StaticBody3D:
			remove_child(ch)
			ch.queue_free()
	_glow_mats.clear()
	_build_box()
	_set_glow(_glow)


func is_cups() -> bool:
	return str(game.get("id", "")) == "perudo"


func _ready() -> void:
	if is_soon():
		_build_soon()
		return
	if is_cups():
		_build_cups()
	else:
		_build_box()
	# коллизия для выбора мышью
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0 if is_cups() else 0.0
	sb.add_child(cs)
	sb.set_meta("game_box", self)
	add_child(sb)


static func soft_material(half: Vector3, rad: float, col: Color, rough: float = 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SOFT
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("radius", rad)
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("albedo2", col.darkened(0.3))
	m.set_shader_parameter("roughness", rough)
	return m


# --- Коробка --------------------------------------------------------------------------

func _build_box() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	# цвет кромок — средний цвет края обложки, чтобы по краю не было цветной «рамки»
	var front := cover_texture(str(game.get("id", "")), "front")
	if front:
		# цвет края и яркость обложки — из заранее посчитанного файла (tools/bake_hub.gd), иначе — на лету
		var meta := ConfigFile.new()
		var id2 := str(game.get("id", ""))
		if meta.load(META) == OK and meta.has_section_key(id2, "edge"):
			color = meta.get_value(id2, "edge")
			brightness = meta.get_value(id2, "luma")
		else:
			color = _edge_color(front)
			brightness = _mean_luma(front)
	var mat := soft_material(size / 2.0, 0.003, color, 0.55)
	mat.set_shader_parameter("emission_color", color)
	body.material_override = mat
	_glow_mats.append([mat, 0.35])
	add_child(body)
	# лицевая сторона, оборот, корешок (чуть меньше грани — чтобы скруглённые кромки коробки были видны)
	var inset := 0.0015
	_face("front", Vector3(size.x / 2.0 + 0.0008, 0, 0), Vector3(0, PI / 2.0, 0), Vector2(size.z - inset, size.y - inset), true)
	_face("back", Vector3(-size.x / 2.0 - 0.0008, 0, 0), Vector3(0, -PI / 2.0, 0), Vector2(size.z - inset, size.y - inset), false)
	_face("spine", Vector3(0, 0, size.z / 2.0 + 0.0008), Vector3.ZERO, Vector2(size.x - inset, size.y - inset), false)
	# неоновый ореол при наведении (его подхватывает glow окружения)
	_halo = MeshInstance3D.new()
	var hm := SphereMesh.new()  # шейдер переносит вершины на скруглённую коробку
	hm.radial_segments = 64
	hm.rings = 32
	_halo.mesh = hm
	_halo.custom_aabb = AABB(-size / 2.0 - Vector3.ONE * 0.03, size + Vector3.ONE * 0.06)
	var hmat := ShaderMaterial.new()
	hmat.shader = preload("res://hub/halo.gdshader")
	hmat.set_shader_parameter("half_size", size / 2.0)
	hmat.set_shader_parameter("color", color.lightened(0.3))
	hmat.set_shader_parameter("strength", 0.0)
	_halo.material_override = hmat
	add_child(_halo)


func _build_soon() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = preload("res://hub/tv_static.gdshader")
	m.set_shader_parameter("half_size", size / 2.0)
	m.set_shader_parameter("speed", 20.0 + randf() * 8.0)
	if dim:
		m.set_shader_parameter("energy", 0.04)
		m.set_shader_parameter("albedo_mul", 0.05)
	body.material_override = m
	add_child(body)
	# чёткая надпись по центру: на торце (вдоль) и на лицевой стороне
	for spec in [[Vector3(0, 0, size.z / 2.0 + 0.0015), Vector3(0, 0, PI / 2.0), size.y], [Vector3(size.x / 2.0 + 0.0015, 0, 0), Vector3(0, PI / 2.0, 0), size.z]]:
		var l := Label3D.new()
		l.text = "COMING SOON"
		l.font = HubStyle.font("title")
		l.font_size = 56
		l.outline_size = 18
		l.modulate = Color(0.55, 0.55, 0.6) if dim else Color.WHITE
		l.outline_modulate = Color(0, 0, 0, 0.95)
		l.shaded = false
		var span: float = spec[2]
		l.pixel_size = minf(0.0006, span * 0.8 / 560.0)
		l.position = spec[0]
		l.rotation = spec[1]
		add_child(l)


static func _mean_luma(t: Texture2D) -> float:
	var img := t.get_image()
	if img == null:
		return 0.5
	if img.is_compressed():
		img.decompress()
	var sum := 0.0
	var n := 0
	for y in range(4, img.get_height(), maxi(1, img.get_height() / 24)):
		for x in range(4, img.get_width(), maxi(1, img.get_width() / 24)):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxi(n, 1)


static func _edge_color(t: Texture2D) -> Color:
	var img := t.get_image()
	if img == null:
		return Color("444444")
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for k in 24:
		var f := k / 23.0
		for p in [Vector2i(int(f * (w - 1)), 2), Vector2i(int(f * (w - 1)), h - 3), Vector2i(2, int(f * (h - 1))), Vector2i(w - 3, int(f * (h - 1)))]:
			sum += img.get_pixelv(p)
			n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n)


static func cover_texture(id: String, part: String) -> Texture2D:
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p := "%s%s_%s.%s" % [COVERS, id, part, ext]
		if ResourceLoader.exists(p):
			return load(p)
	if part == "front":
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var p := "%s%s.%s" % [COVERS, id, ext]
			if ResourceLoader.exists(p):
				return load(p)
	return null


func _face(part: String, pos: Vector3, rot: Vector3, quad: Vector2, big_title: bool) -> void:
	var tex := cover_texture(str(game.get("id", "")), part)
	if tex != null:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = quad
		m.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		if part == "spine":
			var k: float = SPINE_BOOST.get(str(game.get("id", "")), 1.0)
			mat.albedo_color = Color(k, k, k)
		mat.roughness = 0.45
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.disable_fog = true
		_face_mats.append(mat)
		m.material_override = mat
		m.position = pos
		m.rotation = rot
		add_child(m)
		return
	# нет картинки — надпись прямо на коробке
	var l := Label3D.new()
	l.text = str(game.get("title", "")) if part != "back" else str(game.get("players", ""))
	l.font = HubStyle.font("title")
	l.font_size = 64 if big_title else 40
	l.pixel_size = 0.0009 if big_title else 0.0007
	l.outline_size = 10
	l.modulate = Color.WHITE
	l.outline_modulate = color.darkened(0.6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = (quad.x if part != "spine" else quad.y) / l.pixel_size * 0.9
	l.position = pos + pos.normalized() * 0.001
	l.rotation = rot
	if part == "spine":
		l.rotation = Vector3(0, 0, PI / 2.0)  # вдоль корешка, снизу вверх
	add_child(l)


# --- «Перудо»: кожаные стаканчики с кубиками ------------------------------------------
# Начало координат — на полу посередине, стаканчики в ряд вдоль X, кубики — спереди (+Z).

func _build_cups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var xs := [-0.13, -0.045, 0.045, 0.13]
	var placed: Array[Vector3] = []  # кубики, уже стоящие на полке
	for i in xs.size():
		var c: Color = CUP_COLORS[[0, 1, 2, 5][i]]
		var tipped := i == 0  # первый лежит на боку, как на референсе
		var cup := _cup(c)
		cup.position = Vector3(xs[i], 0.0, -0.02 + rng.randf_range(-0.012, 0.012))
		if tipped:
			cup.rotation = Vector3(0, 0.5, deg_to_rad(68))
			cup.position += Vector3(0.02, 0.034, 0.015)
		else:
			cup.rotation.y = rng.randf_range(-0.6, 0.6)
		add_child(cup)
		# кубики того же цвета у основания; на полке не пересекаются (в т.ч. с кубиками соседей)
		var base_die: Vector3
		for k in 3:
			var die := _die(c if c != CUP_COLORS[0] else Color("1a1a1a"), Color.WHITE if c != CUP_COLORS[1] else Color("1a1a1a"))
			if k == 2 and i % 2 == 1:
				# кубик на кубике: ровно сверху первого, с лёгким сдвигом
				die.position = base_die + Vector3(rng.randf_range(-0.003, 0.003), 0.026, rng.randf_range(-0.003, 0.003))
			else:
				die.position = _free_spot(rng, xs[i], placed)
				placed.append(die.position)
				if k == 0:
					base_die = die.position
			die.rotation = Vector3(0, rng.randf_range(-PI, PI), 0)
			add_child(die)


## Место для кубика у стаканчика (x0 — его центр), не ближе диагонали кубика к уже стоящим —
## при любом повороте кубики не залезают друг на друга.
func _free_spot(rng: RandomNumberGenerator, x0: float, placed: Array[Vector3]) -> Vector3:
	var p := Vector3.ZERO
	for attempt in 60:
		p = Vector3(x0 + rng.randf_range(-0.04, 0.04), 0.013, rng.randf_range(0.05, 0.1))
		var ok := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < 0.039:
				ok = false
				break
		if ok:
			break
	return p


## Стаканчик: усечённый конус (открытым краем вниз), прошитые ободки и шов сбоку, кожа.
func _cup(c: Color) -> Node3D:
	var root := Node3D.new()
	var h := 0.13
	var r_top := 0.033
	var r_bot := 0.042
	var leather := StandardMaterial3D.new()
	leather.albedo_color = c
	leather.roughness = 0.62
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.25
	leather.clearcoat_roughness = 0.4
	leather.normal_enabled = true
	leather.normal_texture = _leather_normal()
	leather.normal_scale = 0.35
	leather.uv1_scale = Vector3(3, 2, 1)
	leather.emission_enabled = true
	leather.emission = c
	leather.emission_energy_multiplier = 0.0
	_glow_mats.append([leather, 0.25])
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 40
	cm.cap_bottom = false  # открытый край снизу
	body.mesh = cm
	body.material_override = leather
	body.position.y = h / 2.0
	root.add_child(body)
	# внутренняя сторона — тёмная
	var inner := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = r_top - 0.003
	im.bottom_radius = r_bot - 0.003
	im.height = h - 0.004
	im.radial_segments = 40
	im.cap_bottom = false
	im.flip_faces = true
	inner.mesh = im
	var dark := StandardMaterial3D.new()
	dark.albedo_color = c.darkened(0.7)
	dark.roughness = 0.9
	inner.material_override = dark
	inner.position.y = h / 2.0
	root.add_child(inner)
	# ободки-валики у дна и у края
	var rim_mat := leather.duplicate() as StandardMaterial3D
	rim_mat.albedo_color = c.darkened(0.12)
	for spec in [[r_top - 0.001, h - 0.006], [r_bot - 0.0005, 0.004]]:
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = spec[0] - 0.0035
		tm.outer_radius = spec[0] + 0.0035
		tm.rings = 32
		rim.mesh = tm
		rim.material_override = rim_mat
		rim.position.y = spec[1]
		root.add_child(rim)
	# шов — пунктир стежков по образующей конуса
	var stitch := StandardMaterial3D.new()
	stitch.albedo_color = c.lightened(0.35)
	stitch.roughness = 0.8
	var steps := 11
	for k in steps:
		var t := (k + 0.5) / steps
		var y := 0.012 + t * (h - 0.026)
		var r := lerpf(r_bot, r_top, y / h) + 0.0006
		var st := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.0022, 0.0055, 0.0012)
		st.mesh = sm
		st.material_override = stitch
		st.position = Vector3(0, y, r)
		st.rotation.x = -atan((r_bot - r_top) / h)
		root.add_child(st)
	return root


static var _leather_tex: Texture2D


static func _leather_normal() -> Texture2D:
	if _leather_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.08
		var nt := NoiseTexture2D.new()
		nt.noise = n
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 3.0
		_leather_tex = nt
	return _leather_tex


static var _pips: Texture2D


## Маска точек для BoxMesh (раскладка граней 3×2), точки 1–6.
static func _pips_texture() -> Texture2D:
	if _pips:
		return _pips
	var cell := 128
	var img := Image.create(cell * 3, cell * 2, false, Image.FORMAT_L8)
	var spots := {
		1: [Vector2(0.5, 0.5)],
		2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
		3: [Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(0.75, 0.75)],
		4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
		5: [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.5, 0.5), Vector2(0.25, 0.75), Vector2(0.75, 0.75)],
		6: [Vector2(0.27, 0.22), Vector2(0.73, 0.22), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.78), Vector2(0.73, 0.78)],
	}
	var faces := [1, 2, 3, 6, 5, 4]  # противоположные грани в сумме дают 7
	for f in 6:
		var ox := (f % 3) * cell
		var oy := (f / 3) * cell
		for y in cell:
			for x in cell:
				var p := Vector2(x + 0.5, y + 0.5) / cell
				var v := 0.0
				for s in spots[faces[f]]:
					v = maxf(v, clampf((0.1 - p.distance_to(s)) * cell * 0.5, 0.0, 1.0))
				img.set_pixel(ox + x, oy + y, Color(v, v, v))
	img.generate_mipmaps()
	_pips = ImageTexture.create_from_image(img)
	return _pips


## Кубик d6 со скруглёнными рёбрами (общий «мягкий» шейдер) и точками.
func _die(body: Color, pip: Color) -> MeshInstance3D:
	var d := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var s := 0.026
	bm.size = Vector3(s, s, s)
	d.mesh = bm
	var m := soft_material(bm.size / 2.0, 0.0035, body, 0.35)
	m.set_shader_parameter("clearcoat_amount", 0.6)
	m.set_shader_parameter("emission_color", body)
	_glow_mats.append([m, 0.5])
	m.set_shader_parameter("edge_shade", 0.1)
	m.set_shader_parameter("pips_tex", _pips_texture())
	m.set_shader_parameter("use_pips", 1.0)
	m.set_shader_parameter("pip_color", pip)
	d.material_override = m
	return d


# --- Анимации -------------------------------------------------------------------------

func _set_glow(v: float) -> void:
	_glow = v
	for pair in _glow_mats:
		var m: Material = pair[0]
		var e: float = v * float(pair[1])
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("emission_energy", e)
		else:
			(m as StandardMaterial3D).emission_energy_multiplier = e


## Подсветка при наведении: игра выезжает из шкафа и светится.
func set_hovered(on: bool) -> void:
	if hovered == on or focused:
		return
	hovered = on
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var out := home.translated(Vector3(0, 0.012, 0.07)) if on else home
	t.tween_property(self, "transform", out, 0.18)
	t.tween_method(_set_glow, _glow, 1.0 if on else 0.0, 0.18)
	if _halo:
		t.tween_property(_halo.material_override, "shader_parameter/strength", 0.35 if on else 0.0, 0.18)
	if on:
		Sfx.play("card_slide", -14, 0.08, 0.05)


## Вылететь к игроку: target — куда, лицом к камере.
func fly_to(target: Transform3D) -> void:
	focused = true
	hovered = false
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# сначала чуть вытянуть из шкафа, потом лететь
	var pull := home.translated(Vector3(0, 0.02, 0.18))
	_tween.tween_property(self, "transform", pull, 0.16)
	_tween.chain().tween_property(self, "transform", target, 0.55)
	if _halo:
		_tween.tween_property(_halo.material_override, "shader_parameter/strength", 0.0, 0.3)
	_tween.tween_method(_set_glow, _glow, 0.4, 0.3)
	if is_cups():
		Sfx.play("die_shake", -6)
	else:
		Sfx.play("card_shove", -8, 0.05)  # картон трётся о полку
		get_tree().create_timer(0.62).timeout.connect(func(): Sfx.play("card_place", -10, 0.05))


## Вернуться на своё место в шкаф.
func fly_home() -> void:
	focused = false
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var pull := home.translated(Vector3(0, 0.02, 0.18))
	_tween.tween_property(self, "transform", pull, 0.45)
	_tween.tween_property(self, "transform", home, 0.18)
	_tween.parallel().tween_method(_set_glow, _glow, 0.0, 0.2)
	Sfx.play("card_slide", -8)
