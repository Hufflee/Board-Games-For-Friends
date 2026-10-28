class_name NeonRoom
extends Node3D
## 3D-комната главного меню: детская 90-х ночью в неоновом свете. Всё собрано из примитивов
## (без Blender): стены, окно с ночным городом, кровать, тумбочка, ЭЛТ-телевизор, лавовая лампа,
## светящиеся звёзды и шкаф для настольных игр 4×1. Мебель — «мягкие» параллелепипеды (soft_box.gdshader:
## скруглённые кромки, дерево с волокнами, лак), экран телевизора — выпуклое стекло с развёрткой.
## Выбор коробки — лучом из камеры; сигналы — для слоя интерфейса.

signal box_selected(game: Dictionary)
signal shelf_hint(text: String)
signal box_released
signal editor_mode_changed(on:bool)

const HINT := "Нажмите на коробку, чтобы открыть · Удерживайте для выделения, затем удерживайте снова для переноса"

const W := 6.0  # ширина комнаты
const H := 2.8  # высота
const BACK := -2.0  # задняя стена (z)
# шкаф: 4 ячейки по вертикали, 1 по горизонтали
const CELL_H := 0.36  # высота ячейки
const CELL_D := ShelfConfig.CELL_DEPTH  # общая глубина геометрии и проверки вместимости
const BOARD := 0.03
const ROWS := 4
const PER_CELL := 4  # коробок в ячейке — впритык к задней стенке; ширина шкафа считается по самой широкой ячейке
const SHELF_SCALE := 0.95  # шкаф вместе с коробками крупнее (масштаб от пола у стены)
const BOXED_ROWS := 3  # ячеек с коробками (в последней — ещё «Перудо»), ниже — «Coming soon»
## Какие коробки на какой полке (сверху вниз, слева направо).
const SHELF_LAYOUT := [
	["wavelength", "hues_and_cues", "dangerous_words", "king_of_12", "not_a_hat"],
	["ready_set_bet", "tip_top_18", "gloom", "gloomier", "stillion"],
	["word_slam", "brodilka", "phantom_ink", "four_souls", "the_gang"],
]
const SHELF_X := 0.25
const PERUDO_SPACE := 0.17  # место под набор «Перудо» во второй ячейке

const ShelfOrder := preload("res://hub/shelf_layout.gd")
const BOX_HOLD := 0.45  # с: удержание на коробке — взять её и переставлять
const DRAG_LIFT := 0.07  # м: взятая коробка выдвигается из шкафа к игроку
var _pressed_box: GameBox
var _hold_time := 0.0
var _drag_box: GameBox  # коробка в руке (перестановка)
var _drag_from := Vector2i(-1, -1)  # полка и место, откуда взяли: туда вернётся, если поставить некуда
var _drag_to := Vector2i(-1, -1)  # куда встанет при отпускании (полка −1 — на этой полке нет места)
var _drag_at := Vector3.ZERO  # точка под курсором в координатах шкафа
var _rows: Array = []  # полки: списки GameBox слева направо (личная раскладка)
var _row_info: Array = []  # полки в координатах шкафа: {left, right, floor, back}
var _cups: GameBox  # набор «Перудо»; после начальной сборки размещается общей раскладкой
var _inner_right := 0.0
var _cups_z := 0.0
var camera: Camera3D
var boxes: Array = []  # GameBox
var focused: GameBox
var panels: GamePanels  # «окошки игр» (стеклянный куб на шкафу)
var shelf_top_right := Vector3.ZERO  # место на крышке шкафа у правого края (куб-кнопка окошек игр)
var _hover: GameBox
var _cam_home := Transform3D.IDENTITY
var _t := 0.0
var _tv_title: Label
var _tv_channel := 0
var _lamp_color := 0
var _lava: Array = []  # капли лавовой лампы
var _blink: Label  # «PRESS START» на экране телевизора (мигает)
var _sign: Label3D
var _row_x := 0.0
var _lava_base := 1.33
var _present: SpotLight3D  # ключевой свет на игру в руках — сверху-слева, чтобы был объём
var _rim: SpotLight3D
var _shelf_root: Node3D
var _cabinet:Dictionary={}
var _box_modes:Dictionary={}
var _editor_on:=false
var _editor_backup:Dictionary={}
var _editor_preferences: Array = []
var _editor_preference_geometry: Dictionary = {}
var _editor_box_press := false
var _figure_preview_x := 1.0
var _editor_ui:Control
var _edge_overlay:Control
var _edge_drag:Dictionary={}
var _edge_hover:Dictionary={}
var _pose_button:Button
var _shelf_placeholders:Dictionary={}
var _selected_box: GameBox
var _hold_handled := false
var _press_selected := false
var _press_screen:=Vector2.ZERO
var _drag_original_mode:=1
var _env: Environment
var _key: SpotLight3D
var _extra_lights: Array = []  # второстепенные лампы — выключаются на низком качестве  # шкаф и коробки — общий масштаб SHELF_SCALE  # контровой — сзади-справа, очерчивает кромки


func _ready() -> void:
	_environment()
	_room()
	_furniture()
	_shelf()
	_add_shelf_figurine()
	_prepare_layout()
	_init_custom_shelf()
	_lights()
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.position = Vector3(SHELF_X - 0.1, 0.9, 0.12)
	add_child(camera)
	camera.look_at(Vector3(SHELF_X, 0.84, BACK + 0.2))
	_cam_home = camera.transform
	camera.current = true
	panels = GamePanels.new()
	add_child(panels)
	panels.setup(
		camera, boxes.filter(func(b): return not b.is_figurine()).map(func(b): return b.game), shelf_top_right
	)
	panels.editor_requested.connect(open_shelf_editor)
	_make_shelf_ui()
	if FileAccess.file_exists(ShelfConfig.FILE):
		_frame_shelf()
	# «презентационный» свет от камеры: слабый всегда, ярче — когда коробка в руках
	_present = SpotLight3D.new()
	_present.light_color = Color("fff3fb")
	_present.light_energy = 0.0
	_present.spot_range = 3.0
	_present.spot_angle = 28.0
	_present.shadow_enabled = true
	_present.position = Vector3(-0.55, 0.45, -0.15)
	camera.add_child(_present)
	_rim = SpotLight3D.new()
	_rim.light_color = Color("7fe8ff")
	_rim.light_energy = 0.0
	_rim.spot_range = 3.0
	_rim.spot_angle = 30.0
	_rim.position = Vector3(0.55, 0.25, -1.45)
	camera.add_child(_rim)
	Prefs.changed.connect(_apply_quality)
	_apply_quality()


## Качество графики (Prefs.graphics): 0 — без теней и SSAO, без второстепенных ламп; 1 — тень только
## от главного света; 2 — всё. Масштаб 3D и потолок кадров задаёт Prefs.
func _apply_quality() -> void:
	var q: int = Prefs.graphics
	_env.ssao_enabled = q >= 2
	_env.fog_enabled = q >= 2
	_key.shadow_enabled = q >= 1
	_present.shadow_enabled = q >= 2
	for l in _extra_lights:
		(l as Light3D).visible = q >= 1
	_rim.visible = q >= 1


# --- Окружение и свет ----------------------------------------------------------------

func _environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07040f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a2470")
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.05
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 1.6
	env.ssao_power = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color("2a1550")
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _lights() -> void:
	# общий фиолетовый свет под потолком
	_omni(Vector3(0, 2.5, -0.6), Color("7a4dff"), 1.1, 7.0)
	# розовый — от лавовой лампы и неона
	var pink := _omni(Vector3(1.55, 1.35, BACK + 0.45), Color("ff3ea5"), 1.1, 2.4)
	# тени у точечного света — самые дорогие (6 направлений), у розовой лампы их нет
	# бирюзовый — от телевизора
	_extra_lights.append(_omni(Vector3(1.6, 0.95, BACK + 0.9), Color("2ef2ff"), 0.9, 2.4))
	# холодный лунный из окна
	var moon := SpotLight3D.new()
	moon.light_color = Color("7fa8ff")
	moon.light_energy = 2.2
	moon.spot_range = 5.0
	moon.spot_angle = 35.0
	moon.position = Vector3(-1.7, 1.7, BACK + 0.15)
	add_child(moon)
	moon.look_at(Vector3(-1.4, 0.0, -0.3))
	# мягкий свет на шкаф спереди-сверху — чтобы обложки читались
	var key := SpotLight3D.new()
	key.light_color = Color("ffd9f2")
	key.light_energy = 0.9
	key.spot_range = 4.0
	key.spot_angle = 30.0
	_key = key
	key.position = Vector3(SHELF_X - 0.9, 2.3, -0.5)  # сверху-слева: свет скользит по корешкам
	add_child(key)
	key.look_at(Vector3(SHELF_X, 0.9, BACK + 0.2))
	# слабый заполняющий справа-снизу: тени от ключевого не проваливаются в черноту
	var fill := SpotLight3D.new()
	fill.light_color = Color("b9a0ff")
	fill.light_energy = 0.5
	fill.spot_range = 4.0
	fill.spot_angle = 35.0
	fill.position = Vector3(SHELF_X + 0.9, 0.6, -0.2)
	add_child(fill)
	fill.look_at(Vector3(SHELF_X, 0.85, BACK + 0.2))
	_extra_lights.append(fill)


func _omni(pos: Vector3, c: Color, energy: float, r: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = r
	add_child(l)
	return l


# --- Примитивы ------------------------------------------------------------------------

func _mat(c: Color, rough: float = 0.85, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## «Мягкий» бокс: скруглённые кромки и фактура. look: wood_dark / wood_light / plastic / plastic_light / fabric / metal.
func _soft(size: Vector3, pos: Vector3, look: String, col: Color, parent: Node3D = self, rot: Vector3 = Vector3.ZERO, rad: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if rad < 0.0:
		rad = clampf(minf(size.x, minf(size.y, size.z)) * 0.25, 0.003, 0.03)
	var m := GameBox.soft_material(size / 2.0, rad, col, 0.5)
	match look:
		"wood_dark", "wood_light":
			m.set_shader_parameter("albedo2", col.darkened(0.35 if look == "wood_dark" else 0.22))
			m.set_shader_parameter("grain", 1.0)
			m.set_shader_parameter("grain_scale", 30.0)
			var longest := Vector3(0, 1, 0)
			if size.x >= size.y and size.x >= size.z:
				longest = Vector3(1, 0, 0)
			elif size.z >= size.y:
				longest = Vector3(0, 0, 1)
			m.set_shader_parameter("grain_dir", longest)
			m.set_shader_parameter("roughness", 0.42)
			m.set_shader_parameter("clearcoat_amount", 0.55)
		"plastic":
			m.set_shader_parameter("roughness", 0.35)
			m.set_shader_parameter("clearcoat_amount", 0.3)
			m.set_shader_parameter("grain", 0.15)
			m.set_shader_parameter("grain_scale", 200.0)
		"plastic_light":
			m.set_shader_parameter("roughness", 0.45)
			m.set_shader_parameter("grain", 0.1)
			m.set_shader_parameter("grain_scale", 200.0)
		"fabric":
			m.set_shader_parameter("roughness", 0.95)
			m.set_shader_parameter("grain", 0.6)
			m.set_shader_parameter("grain_scale", 90.0)
			m.set_shader_parameter("grain_dir", Vector3(0, 0, 0))
			m.set_shader_parameter("edge_shade", 0.3)
		"metal":
			m.set_shader_parameter("roughness", 0.3)
			m.set_shader_parameter("metallic", 0.8)
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 32
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _quad(size: Vector2, pos: Vector3, rot: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _glow_label(text: String, pos: Vector3, size: int, c: Color, kind: String = "title", pixel: float = 0.002) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = HubStyle.font(kind)
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6)  # ярче 1 — подхватит glow
	l.outline_size = 0
	l.position = pos
	l.shaded = false
	add_child(l)
	return l


func _noise_tex(c1: Color, c2: Color, freq: float = 0.05, size: int = 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = size
	nt.height = size
	nt.seamless = true
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	nt.color_ramp = g
	return nt


# --- Комната --------------------------------------------------------------------------

func _room() -> void:
	var wall := _mat(Color("7f6bc4"), 0.95)
	_box(Vector3(W, H, 0.1), Vector3(0, H / 2.0, BACK - 0.05), wall)  # задняя
	_box(Vector3(0.1, H, 4.0), Vector3(-W / 2.0, H / 2.0, 0), wall)  # левая
	_box(Vector3(0.1, H, 4.0), Vector3(W / 2.0, H / 2.0, 0), wall)  # правая
	_box(Vector3(W, 0.1, 4.0), Vector3(0, H + 0.05, 0), _mat(Color("2a1f45")))  # потолок
	var carpet := _mat(Color.WHITE, 1.0)
	carpet.albedo_texture = _noise_tex(Color("1c2150"), Color("2c2f6e"), 0.12)
	carpet.uv1_scale = Vector3(6, 4, 1)
	_box(Vector3(W, 0.1, 4.0), Vector3(0, -0.05, 0), carpet)  # пол
	# плинтус
	_box(Vector3(W, 0.08, 0.02), Vector3(0, 0.04, BACK + 0.01), _mat(Color("d8cff5")))
	_window()
	_stars()
	_posters()


const CITY := "res://hub/art/city.png"


## Ночной город (небо, силуэты домов, огни окон) — генерируется один раз (tools/bake_hub.gd) и хранится файлом.
static func city_image() -> Image:
	var img := Image.create(512, 384, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	for y in 384:
		var t := y / 384.0
		var sky := Color("251048").lerp(Color("c0447a"), pow(t, 2.2))
		for x in 512:
			img.set_pixel(x, y, sky)
	for b in 40:
		var bw := rng.randi_range(14, 46)
		var bh := rng.randi_range(40, 170)
		var bx := rng.randi_range(-10, 512)
		var bc := Color("120a24").lerp(Color("2a1340"), rng.randf())
		for y in range(384 - bh, 384):
			for x in range(bx, mini(bx + bw, 512)):
				if x >= 0:
					img.set_pixel(x, y, bc)
		for k in rng.randi_range(4, 18):
			var wx := bx + rng.randi_range(2, bw - 4)
			var wy := 384 - rng.randi_range(6, bh - 4)
			var wc := Color("ffd27a") if rng.randf() < 0.7 else Color("8fd8ff")
			for dy in 3:
				for dx in 2:
					if wx + dx >= 0 and wx + dx < 512 and wy + dy < 384:
						img.set_pixel(wx + dx, wy + dy, wc)
	return img


func _window() -> void:
	var c := Vector3(-1.75, 1.62, BACK + 0.02)
	var size := Vector2(1.25, 0.95)
	# ночной город за окном: готовая картинка (hub/art/city.png), если её нет — рисуем на лету
	var tex: Texture2D = load(CITY) if ResourceLoader.exists(CITY) else ImageTexture.create_from_image(city_image())
	var city := StandardMaterial3D.new()
	city.albedo_texture = tex
	city.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	city.albedo_color = Color(1.25, 1.1, 1.25)
	_quad(size, c, Vector3.ZERO, city)
	var frame := _mat(Color("efe9ff"), 0.6)
	_box(Vector3(size.x + 0.08, 0.05, 0.06), c + Vector3(0, size.y / 2.0, 0.02), frame)
	_box(Vector3(size.x + 0.12, 0.05, 0.12), c + Vector3(0, -size.y / 2.0, 0.05), frame)
	_box(Vector3(0.05, size.y, 0.06), c + Vector3(-size.x / 2.0, 0, 0.02), frame)
	_box(Vector3(0.05, size.y, 0.06), c + Vector3(size.x / 2.0, 0, 0.02), frame)
	_box(Vector3(0.035, size.y, 0.05), c + Vector3(0, 0, 0.02), frame)
	# жалюзи на верхней половине
	var slat := _mat(Color("e8e2fa"), 0.5)
	for i in 14:
		_box(Vector3(size.x, 0.022, 0.012), c + Vector3(0, size.y / 2.0 - 0.02 - i * 0.034, 0.05), slat, self, Vector3(deg_to_rad(-25), 0, 0))


func _stars() -> void:
	# светящиеся в темноте звёзды на стене (как наклейки)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots := [Vector2(-1.05, 1.32), Vector2(-0.75, 1.12), Vector2(-0.55, 0.98), Vector2(-0.95, 0.98), Vector2(-0.25, 1.08),
		Vector2(-0.68, 0.8), Vector2(-1.2, 1.12), Vector2(-0.18, 0.88), Vector2(-0.42, 0.78), Vector2(0.95, 1.78)]
	for p in spots:
		var s := _glow_label("★", Vector3(p.x, p.y, BACK + 0.005), rng.randi_range(40, 80), Color("7dffc8"), "regular", 0.0016)
		s.rotation.z = rng.randf_range(-0.6, 0.6)
		s.modulate = Color(0.55, 1.1, 0.85)
	var moon := _glow_label("☾", Vector3(-0.85, 1.42, BACK + 0.005), 70, Color("7dffc8"), "regular", 0.0016)
	moon.modulate = Color(0.55, 1.1, 0.85)


func _poster(tex_path: String, pos: Vector3, size: Vector2, rot_z: float = 0.0) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex_path)
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = 0.25
	var q := _quad(size, pos, Vector3(0, 0, rot_z), m)
	q.set_meta("poster_source", tex_path)
	_box(Vector3(size.x + 0.03, size.y + 0.03, 0.005), pos + Vector3(0, 0, -0.004), _mat(Color("f6f0ff")))
	q.position.z += 0.001


func _posters() -> void:
	_poster("res://games/ready_set_bet/art/cover.jpg", Vector3(1.05, 1.55, BACK + 0.012), Vector2(0.46, 0.46), 0.03)
	_poster("res://hub/art/posters/coin_heap.png", Vector3(1.62, 1.66, BACK + 0.012), Vector2(0.46, 0.322), -0.04)
	_poster("res://games/stillion/art/bg_circus_approved.png", Vector3(2.15, 1.5, BACK + 0.012), Vector2(0.46, 0.259), 0.02)


# --- Мебель ---------------------------------------------------------------------------

func _furniture() -> void:
	# кровать вдоль левой стены: каркас, матрас, одеяло, подушка
	_soft(Vector3(1.0, 0.26, 2.1), Vector3(-2.45, 0.13, -0.85), "wood_dark", Color("3a2a66"))
	_soft(Vector3(0.96, 0.14, 2.0), Vector3(-2.45, 0.33, -0.85), "fabric", Color("d8d2ff"), self, Vector3.ZERO, 0.05)
	_soft(Vector3(1.04, 0.09, 1.5), Vector3(-2.45, 0.43, -0.52), "fabric", Color("5a55e0"), self, Vector3(0, 0, 0.02), 0.04)
	_soft(Vector3(0.66, 0.12, 0.34), Vector3(-2.45, 0.46, -1.64), "fabric", Color("c9c3ff"), self, Vector3(0.12, 0, 0), 0.055)
	# тумбочка у изголовья: ящик с ручкой, лампа, часы
	var ns := Vector3(-1.7, 0.0, BACK + 0.25)
	_soft(Vector3(0.45, 0.5, 0.4), ns + Vector3(0, 0.25, 0), "wood_light", Color("e0a646"), self, Vector3.ZERO, 0.02)
	_soft(Vector3(0.38, 0.17, 0.02), ns + Vector3(0, 0.36, 0.205), "wood_light", Color("eab35a"), self, Vector3.ZERO, 0.008)
	_soft(Vector3(0.38, 0.17, 0.02), ns + Vector3(0, 0.15, 0.205), "wood_light", Color("eab35a"), self, Vector3.ZERO, 0.008)
	for y in [0.36, 0.15]:
		var knob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.03
		knob.mesh = sm
		knob.material_override = _mat(Color("c8c0d8"), 0.25)
		knob.position = ns + Vector3(0, y, 0.222)
		add_child(knob)
	_soft(Vector3(0.17, 0.075, 0.08), Vector3(-1.62, 0.54, BACK + 0.3), "plastic", Color("232026"), self, Vector3(-0.15, 0.2, 0), 0.012)
	var clock := _glow_label("17:14", Vector3(-1.617, 0.545, BACK + 0.342), 40, Color("ff3030"), "pixel", 0.0011)
	clock.rotation = Vector3(-0.15, 0.2, 0)
	clock.modulate = Color(2.2, 0.3, 0.3)
	# лампа: основание, стойка, абажур
	var metal := _mat(Color("b8b8c8"), 0.25)
	metal.metallic = 0.7
	_cyl(0.05, 0.06, 0.02, Vector3(-1.82, 0.51, BACK + 0.2), metal)
	_cyl(0.008, 0.008, 0.34, Vector3(-1.82, 0.68, BACK + 0.2), metal)
	var shade := _cyl(0.04, 0.1, 0.12, Vector3(-1.78, 0.86, BACK + 0.24), _mat(Color("c8c8d8"), 0.3, Color("ffe8b0"), 0.6))
	shade.rotation_degrees.z = -25
	_extra_lights.append(_omni(Vector3(-1.72, 0.78, BACK + 0.3), Color("ffd29a"), 0.7, 1.4))
	_tv_corner(1.6)
	# скейтборд у стены
	var deck := Node3D.new()
	deck.position = Vector3(-1.05, 0.4, BACK + 0.1)
	deck.rotation_degrees = Vector3(-10, 0, -12)
	add_child(deck)
	# дека: низ с неоновым рисунком (к игроку), сверху — шершавая шкурка
	var board := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.1
	cap.height = 0.78
	cap.radial_segments = 48
	board.mesh = cap
	board.scale = Vector3(1.0, 1.0, 0.07)
	var art := StandardMaterial3D.new()
	# чистый неоновый градиент с лёгкой подсветкой (потёртый вариант — _deck_art(), пока отключён)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.5, 0.65, 1.0])
	grad.colors = PackedColorArray([Color("ff3ea5"), Color("7a2bd6"), Color("120a24"), Color("2ef2ff"), Color("ffe14d")])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	art.albedo_texture = gt
	art.roughness = 0.95
	art.specular = 0.1
	art.emission_enabled = true
	art.emission_texture = gt
	art.emission_energy_multiplier = 0.25
	board.material_override = art
	deck.add_child(board)
	var grip := MeshInstance3D.new()
	grip.mesh = cap
	grip.scale = Vector3(0.985, 0.995, 0.03)
	grip.position.z = -0.008
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("141418")
	gm.roughness = 1.0
	gm.normal_enabled = true
	gm.normal_texture = GameBox._leather_normal()
	gm.normal_scale = 0.6
	gm.uv1_scale = Vector3(4, 12, 1)
	grip.material_override = gm
	deck.add_child(grip)
	# подвески: площадка, амортизаторы, широкий хэнгер с осью; колёса — полиуретан с подшипником
	var steel := _mat(Color("c9c9d6"), 0.25)
	steel.metallic = 0.85
	var dark_steel := _mat(Color("3a3a44"), 0.35)
	dark_steel.metallic = 0.8
	var urethane := StandardMaterial3D.new()
	urethane.albedo_color = Color("ff6a3d")
	urethane.roughness = 0.55
	urethane.rim_enabled = true
	urethane.rim = 0.2
	var bushing := _mat(Color("ffd23d"), 0.6)
	var wheel_mesh := _wheel_mesh()
	for wy in [-0.25, 0.25]:
		var inward := -signf(wy)
		_soft(Vector3(0.056, 0.078, 0.008), Vector3(0, wy, 0.011), "metal", Color("b8b8c8"), deck, Vector3.ZERO, 0.003)
		_soft(Vector3(0.03, 0.03, 0.016), Vector3(0, wy - inward * 0.01, 0.022), "metal", Color("a8a8b8"), deck, Vector3.ZERO, 0.006)
		var b := _cyl(0.011, 0.011, 0.012, Vector3(0, wy + inward * 0.012, 0.022), bushing, deck)
		b.rotation_degrees.x = 90
		var pin := _cyl(0.004, 0.004, 0.04, Vector3(0, wy + inward * 0.012, 0.032), steel, deck)
		pin.rotation_degrees.x = 90
		_soft(Vector3(0.104, 0.02, 0.02), Vector3(0, wy, 0.042), "metal", Color("c0c0cc"), deck, Vector3.ZERO, 0.008)
		_soft(Vector3(0.046, 0.03, 0.024), Vector3(0, wy + inward * 0.004, 0.036), "metal", Color("c0c0cc"), deck, Vector3.ZERO, 0.009)
		var axle := _cyl(0.004, 0.004, 0.18, Vector3(0, wy, 0.042), steel, deck)
		axle.rotation_degrees.z = 90
		for side in [-1.0, 1.0]:
			var wx: float = side * 0.069
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = urethane
			wheel.position = Vector3(wx, wy, 0.042)
			if side < 0:
				wheel.rotation_degrees.y = 180
			deck.add_child(wheel)
			# подшипник в выемке и гайка оси
			var bearing := _cyl(0.0105, 0.0105, 0.004, Vector3(wx + side * 0.012, wy, 0.042), dark_steel, deck)
			bearing.rotation_degrees.z = 90
			var race := _cyl(0.005, 0.005, 0.005, Vector3(wx + side * 0.0135, wy, 0.042), steel, deck)
			race.rotation_degrees.z = 90
			var nut := _cyl(0.0045, 0.0045, 0.006, Vector3(wx + side * 0.018, wy, 0.042), steel, deck)
			nut.rotation_degrees.z = 90


## Потёртый низ деки: неоновый градиент с царапинами и сколами до дерева (сильнее у носа и хвоста),
## плюс карта нормалей, чтобы царапины ловили свет. [albedo, normal]
static func _deck_art() -> Array:
	var w := 512  # по ширине детальнее: царапины идут поперёк
	var h := 512
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.5, 0.65, 1.0])
	grad.colors = PackedColorArray([Color("ff3ea5"), Color("7a2bd6"), Color("120a24"), Color("2ef2ff"), Color("ffe14d")])
	var wood := Color("d9b47c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wear := PackedFloat32Array()  # 0 — краска цела, 1 — голое дерево
	wear.resize(w * h)
	var height := PackedFloat32Array()
	height.resize(w * h)
	# царапины поперёк доски: большое пятно от центра влево, к краю оно сужается и редеет —
	# до самого края доходит лишь пара штрихов. Краска стёрта не до конца — видны и рисунок, и дерево.
	# На капсуле середина видимой стороны — u = 0.5, левый край — u = 0.25.
	var edge := w * 0.25
	for n in 220:
		var dv := clampf(rng.randfn(0.0, 0.035), -0.08, 0.08)
		var len := edge * (0.45 + 0.55 * pow(rng.randf(), 3.0)) * (1.0 - minf(absf(dv) / 0.14, 0.75))
		var p := Vector2(rng.randf_range(0.485, 0.53) * w, (0.5 + dv) * h)
		var ang := PI + rng.randf_range(-0.12, 0.12)
		var bend := rng.randf_range(-0.0008, 0.0008)
		var amt := rng.randf_range(0.2, 0.5)
		for t in int(len):
			var q := p + Vector2(cos(ang + bend * t), sin(ang + bend * t)) * t
			var fade := sin(PI * float(t) / len)
			# сглаженная линия: вес делится между двумя соседними строками
			var fy := floorf(q.y)
			for k in 2:
				var wgt: float = 1.0 - (q.y - fy) if k == 0 else q.y - fy
				var i := posmod(int(q.x), w) + clampi(int(fy) + k, 0, h - 1) * w
				wear[i] = maxf(wear[i], amt * (0.4 + 0.6 * fade) * wgt)
				height[i] = minf(height[i], -0.6 * fade * wgt)
	# нос и хвост стёрты сильнее: мелкие сколы у самых концов
	for n in 160:
		var v := rng.randf()
		v = v * v * 0.09 if rng.randf() < 0.5 else 1.0 - v * v * 0.09
		var c := Vector2(rng.randf() * w, v * h)
		var r := rng.randf_range(1.0, 3.5)
		var amt := rng.randf_range(0.35, 0.6)
		for yy in range(int(c.y - r), int(c.y + r) + 1):
			for xx in range(int(c.x - r), int(c.x + r) + 1):
				if Vector2(xx, yy).distance_to(c) / r < 1.0 - rng.randf() * 0.35:
					var i := posmod(xx, w) + clampi(yy, 0, h - 1) * w
					wear[i] = maxf(wear[i], amt)
					height[i] = minf(height[i], -0.4)
	# (добавлено после — чтобы не сдвинуть случайные числа уже нравящегося пятна)
	# несколько царапин от центра вправо и маленькое пятно внизу, у хвоста: штрихи вправо-вниз
	for n in 9:
		_scratch(wear, height, w, h, rng, Vector2(rng.randf_range(0.47, 0.515) * w, (0.5 + rng.randfn(0.0, 0.035)) * h),
			rng.randf_range(-0.12, 0.12), edge * rng.randf_range(0.2, 0.6))
	for n in 90:
		_scratch(wear, height, w, h, rng, Vector2(rng.randf_range(0.47, 0.52) * w, (0.73 + rng.randfn(0.0, 0.02)) * h),
			0.45 + rng.randf_range(-0.12, 0.12), edge * (0.35 + 0.75 * pow(rng.randf(), 1.5)))
	# сглаживаем края царапин (иначе вблизи видна «лесенка» пикселей)
	wear = _blur(wear, w, h)
	height = _blur(height, w, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var base := grad.sample(float(y) / (h - 1))
		# хвост стоит на полу: к нему свет почти не доходит — плавное затемнение от нижней подвески
		var floor_shade := 0.65 * smoothstep(0.62, 1.0, float(y) / (h - 1))
		for x in w:
			var i := x + y * w
			var grain := rng.randf_range(-0.04, 0.04)
			height[i] += grain * 0.5
			var col := base.lerp(wood.darkened(rng.randf() * 0.15), wear[i]).darkened(floor_shade)
			img.set_pixel(x, y, col.lightened(grain) if grain > 0 else col.darkened(-grain))
	var nimg := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var dx := height[posmod(x + 1, w) + y * w] - height[posmod(x - 1, w) + y * w]
			var dy := height[x + mini(y + 1, h - 1) * w] - height[x + maxi(y - 1, 0) * w]
			var nrm := Vector3(-dx * 2.0, -dy * 2.0, 1.0).normalized()
			nimg.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	nimg.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(nimg)]


## Одна царапина: штрих от p под углом ang, тоньше к концам; краска стёрта не до конца.
## Массивы меняются на месте (Packed*Array передаются по ссылке).
static func _scratch(wear: PackedFloat32Array, height: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator, p: Vector2, ang: float, len: float) -> void:
	var bend := rng.randf_range(-0.0008, 0.0008)
	var amt := rng.randf_range(0.2, 0.5)
	for t in int(len):
		var q := p + Vector2(cos(ang + bend * t), sin(ang + bend * t)) * t
		var fade := sin(PI * float(t) / len)
		var fy := floorf(q.y)
		for k in 2:
			var wgt: float = 1.0 - (q.y - fy) if k == 0 else q.y - fy
			var i := posmod(int(q.x), w) + clampi(int(fy) + k, 0, h - 1) * w
			wear[i] = maxf(wear[i], amt * (0.4 + 0.6 * fade) * wgt)
			height[i] = minf(height[i], -0.6 * fade * wgt)


static func _blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		var y0 := maxi(y - 1, 0) * w
		var y1 := y * w
		var y2 := mini(y + 1, h - 1) * w
		for x in w:
			var xl := posmod(x - 1, w)
			var xr := posmod(x + 1, w)
			out[x + y1] = (4.0 * src[x + y1] + 2.0 * (src[xl + y1] + src[xr + y1] + src[x + y0] + src[x + y2]) + src[xl + y0] + src[xr + y0] + src[xl + y2] + src[xr + y2]) / 16.0
	return out


## Колесо скейта, ось вдоль X (наружная сторона — +X): профиль вращения с закруглённой кромкой,
## плоской беговой дорожкой, выемкой под подшипник снаружи и конусом сердечника изнутри.
static func _wheel_mesh() -> ArrayMesh:
	var h := 0.016
	var r := 0.027
	var e := 0.007  # радиус скругления кромки
	# полосы профиля (x, радиус): внутри полосы нормали сглажены, между полосами — острая грань
	var strips: Array = []
	strips.append([Vector2(-h + 0.004, 0.0), Vector2(-h + 0.004, 0.009)])
	strips.append([Vector2(-h + 0.004, 0.009), Vector2(-h, 0.014)])
	var main: Array = [Vector2(-h, 0.014)]
	for i in 9:
		var a := PI - i * PI / 16.0
		main.append(Vector2(-h + e, r - e) + Vector2(cos(a), sin(a)) * e)
	for i in 9:
		var a := PI / 2.0 - i * PI / 16.0
		main.append(Vector2(h - e, r - e) + Vector2(cos(a), sin(a)) * e)
	main.append(Vector2(h, 0.013))
	strips.append(main)
	strips.append([Vector2(h, 0.013), Vector2(h - 0.004, 0.0115)])
	strips.append([Vector2(h - 0.004, 0.0115), Vector2(h - 0.004, 0.0)])
	var seg := 40
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip in strips:
		var n2: Array = []
		for i in strip.size():
			var t: Vector2 = strip[mini(i + 1, strip.size() - 1)] - strip[maxi(i - 1, 0)]
			n2.append(Vector2(-t.y, t.x).normalized())
		for i in strip.size() - 1:
			for j in seg:
				var quad: Array = []
				for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var p: Vector2 = strip[k[0]]
					var nn: Vector2 = n2[k[0]]
					var th: float = TAU * k[1] / seg
					quad.append([Vector3(p.x, p.y * cos(th), p.y * sin(th)), Vector3(nn.x, nn.y * cos(th), nn.y * sin(th))])
				for tri in [[0, 1, 2], [0, 2, 3]]:
					var a: Vector3 = quad[tri[0]][0]
					var b: Vector3 = quad[tri[1]][0]
					var c: Vector3 = quad[tri[2]][0]
					var cr := (b - a).cross(c - a)
					if cr.length_squared() < 1e-14:
						continue
					var order: Array = tri
					# Godot: лицевая сторона — обход по часовой, нормаль креста смотрит внутрь
					if cr.dot(quad[tri[0]][1] + quad[tri[1]][1] + quad[tri[2]][1]) > 0:
						order = [tri[0], tri[2], tri[1]]
					for v in order:
						st.set_normal(quad[v][1])
						st.add_vertex(quad[v][0])
	return st.commit()

## Тумба с открытыми полками (видеомагнитофон, приставка, кассеты), ЭЛТ-телевизор и лавовая лампа.
## Картинка экрана телевизора: «НАСТОЛКИ» и мигающее «PRESS START» пиксельным шрифтом на прозрачном фоне
## (фон кинескопа рисует шейдер). Размер — в пропорциях стекла 0.51 × 0.38.
func _tv_picture() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(510, 380)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var title := Label.new()
	_tv_title = title
	title.text = "НАСТОЛКИ"
	title.add_theme_font_override("font", HubStyle.font("pixel"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(510, 60)
	title.position = Vector2(0, 124)
	vp.add_child(title)
	_blink = Label.new()
	_blink.text = "PRESS START"
	_blink.add_theme_font_override("font", HubStyle.font("pixel"))
	_blink.add_theme_font_size_override("font_size", 24)
	_blink.add_theme_color_override("font_color", Color(0.55, 1.0, 1.0))
	_blink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blink.size = Vector2(510, 40)
	_blink.position = Vector2(0, 244)
	vp.add_child(_blink)
	return vp


func _tv_corner(tv_x: float) -> void:
	var z := BACK + 0.28
	var dark := Color("1d1630")
	# тумба: верх, бока, полка, задняя стенка, цоколь
	_soft(Vector3(0.86, 0.035, 0.5), Vector3(tv_x, 0.615, z), "wood_dark", dark)
	_soft(Vector3(0.035, 0.6, 0.5), Vector3(tv_x - 0.4125, 0.3, z), "wood_dark", dark)
	_soft(Vector3(0.035, 0.6, 0.5), Vector3(tv_x + 0.4125, 0.3, z), "wood_dark", dark)
	_soft(Vector3(0.8, 0.03, 0.48), Vector3(tv_x, 0.32, z), "wood_dark", dark)
	_soft(Vector3(0.8, 0.05, 0.48), Vector3(tv_x, 0.04, z), "wood_dark", dark)
	_soft(Vector3(0.8, 0.6, 0.02), Vector3(tv_x, 0.3, z - 0.24), "wood_dark", dark.darkened(0.3))
	# видеомагнитофон и приставка на полках
	_soft(
		Vector3(0.42, 0.09, 0.3),
		Vector3(tv_x + 0.05, 0.38, z + 0.02),
		"plastic",
		Color("2c2a33"),
		self,
		Vector3.ZERO,
		0.01
	)
	_soft(
		Vector3(0.24, 0.012, 0.02),
		Vector3(tv_x + 0.02, 0.39, z + 0.172),
		"plastic",
		Color("0a0a0c"),
		self,
		Vector3.ZERO,
		0.003
	)
	var led := _glow_label(
		"0:00", Vector3(tv_x + 0.2, 0.395, z + 0.171), 24, Color("40ff70"), "pixel", 0.0009
	)
	led.modulate = Color(0.5, 2.0, 0.7)
	_soft(
		Vector3(0.3, 0.07, 0.22),
		Vector3(tv_x - 0.15, 0.1, z + 0.05),
		"plastic_light",
		Color("bcb8c8"),
		self,
		Vector3(0, 0.15, 0),
		0.02
	)
	for k in 4:
		_soft(
			Vector3(0.025, 0.19, 0.11),
			Vector3(tv_x + 0.18 + k * 0.03, 0.165, z + 0.12),
			"plastic",
			[Color("101018"), Color("2a1a40"), Color("101018"), Color("402020")][k],
			self,
			Vector3(0, 0, -0.05 * k),
			0.004
		)
	# телевизор: корпус со скруглёнными углами, кинескоп сзади, рамка, выпуклый экран, кнопки
	var tv_y := 0.86
	var tvz := BACK + 0.32
	var body_col := Color("2a2438")
	_soft(
		Vector3(0.6, 0.47, 0.32),
		Vector3(tv_x, tv_y, tvz + 0.06),
		"plastic",
		body_col,
		self,
		Vector3.ZERO,
		0.045
	)
	_soft(
		Vector3(0.44, 0.34, 0.24),
		Vector3(tv_x, tv_y + 0.01, tvz - 0.17),
		"plastic",
		body_col.darkened(0.15),
		self,
		Vector3.ZERO,
		0.06
	)
	_soft(
		Vector3(0.52, 0.39, 0.02),
		Vector3(tv_x - 0.03, tv_y + 0.01, tvz + 0.225),
		"plastic",
		Color("17131f"),
		self,
		Vector3.ZERO,
		0.03
	)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.51, 0.38)  # стекло — почти на всю тёмную пластину проёма (0.52 × 0.39), без тёмной полосы вокруг картинки
	q.subdivide_width = 16
	q.subdivide_depth = 12
	screen.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://hub/crt_screen.gdshader")
	# что показывает экран — рисуется в отдельную картинку, а шейдер кинескопа её изгибает,
	# раздвигает по каналам и прочерчивает строками (надписи — часть картинки, а не поверх стекла)
	sm.set_shader_parameter("screen_tex", _tv_picture().get_texture())
	sm.set_shader_parameter("aspect", q.size.x / q.size.y)
	screen.material_override = sm
	screen.position = Vector3(tv_x - 0.03, tv_y + 0.01, tvz + 0.236)
	add_child(screen)
	_add_room_prop("tv", screen.position, Vector3(0.53, 0.4, 0.035))
	for k in 3:
		var btn := _cyl(
			0.008,
			0.008,
			0.01,
			Vector3(tv_x + 0.262, tv_y - 0.05 - k * 0.04, tvz + 0.225),
			_mat(Color("8a8498"), 0.3)
		)
		btn.rotation_degrees.x = 90
	# лавовая лампа на телевизоре
	var lamp := Vector3(tv_x + 0.18, tv_y + 0.27, tvz)
	_add_room_prop("lamp", lamp + Vector3(0, 0.2, 0), Vector3(0.14, 0.42, 0.14))
	var metal := _mat(Color("8a8aa0"), 0.25)
	metal.metallic = 0.7
	_cyl(0.04, 0.07, 0.1, lamp, metal)
	var glass := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.035
	gc.bottom_radius = 0.06
	gc.height = 0.3
	gc.radial_segments = 32
	glass.mesh = gc
	var gm := _mat(Color(0.35, 0.2, 0.9, 0.5), 0.05, Color("5a2bff"), 1.2)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = gm
	glass.position = lamp + Vector3(0, 0.2, 0)
	add_child(glass)
	_lava_base = glass.position.y
	_cyl(0.025, 0.035, 0.05, lamp + Vector3(0, 0.375, 0), metal)
	for i in 4:
		var blob := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.022 + 0.006 * i
		bs.height = bs.radius * 2.4
		blob.mesh = bs
		blob.material_override = _mat(Color("ff3ea5"), 0.2, Color("ff3ea5"), 3.0)
		blob.position = glass.position + Vector3(0, -0.1 + i * 0.06, 0)
		add_child(blob)
		_lava.append(blob)


# --- Шкаф и коробки -------------------------------------------------------------------

func _shelf() -> void:
	_shelf_root = Node3D.new()
	var pivot := Vector3(SHELF_X, 0.0, BACK)
	_shelf_root.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * SHELF_SCALE), pivot - pivot * SHELF_SCALE)
	add_child(_shelf_root)
	var wood := Color("2a1d42")
	var rows := ROWS
	var palette := [Color("e0a83a"), Color("b8402e"), Color("3a7bd5"), Color("6b3fa0"), Color("2ea86b"), Color("d4392b"), Color("e86f3c")]
	# 1) коробки (размеры — по обложкам): по полкам — SHELF_LAYOUT, в последней ячейке ещё «Перудо»
	var cups: Array = HubGames.LIST.filter(func(g): return g["id"] == "perudo")
	var make := func(g: Dictionary, i: int) -> GameBox:
		var b := GameBox.new()
		b.setup(g, Vector3(float(g.get("thickness", 0.07)), 0.3, 0.3), g.get("color", palette[i % palette.size()]))  # свой цвет коробки — из HubGames
		return b
	var soon_box := func() -> GameBox:
		var b := GameBox.new()
		b.setup({"id": "soon", "title": "Coming soon"}, Vector3(0.06, 0.3, 0.28), Color.WHITE)
		return b
	# раскладка — явно по полкам (SHELF_LAYOUT), в последней ячейке справа ещё «Перудо»
	var cells: Array = []
	var n := 0
	for r in BOXED_ROWS:
		var row: Array = []
		for id in SHELF_LAYOUT[r]:
			row.append(make.call(HubGames.by_id(id), n))
			n += 1
		cells.append(row)
	for r in BOXED_ROWS - 1:
		while cells[r].size() < PER_CELL:
			cells[r].append(soon_box.call())
	var inner_w := 0.0
	for r in BOXED_ROWS:
		var w := 0.0
		for b in cells[r]:
			w += b.size.x
		if r == BOXED_ROWS - 1 and not cups.is_empty():
			w += PERUDO_SPACE
		inner_w = maxf(inner_w, w)
	inner_w += 0.006
	var inner := Vector3(inner_w, CELL_H, CELL_D)
	var total_h := rows * inner.y + (rows + 1) * BOARD
	var w := inner.x + 2.0 * BOARD
	var z := BACK + inner.z / 2.0 + 0.01
	var base_y := 0.06
	# крышка шкафа у правого края — там стоит стеклянный куб (кнопка окошек игр)
	shelf_top_right = _shelf_root.transform * Vector3(SHELF_X + w / 2.0 - 0.07, base_y + total_h + BOARD * 0.5, z + 0.02)
	_soft(Vector3(w - 0.02, base_y, inner.z - 0.02), Vector3(SHELF_X, base_y / 2.0, z - 0.01), "wood_dark", wood.darkened(0.25), _shelf_root)  # цоколь
	_soft(Vector3(BOARD, total_h, inner.z), Vector3(SHELF_X - w / 2.0 + BOARD / 2.0, base_y + total_h / 2.0, z), "wood_dark", wood, _shelf_root)
	_soft(Vector3(BOARD, total_h, inner.z), Vector3(SHELF_X + w / 2.0 - BOARD / 2.0, base_y + total_h / 2.0, z), "wood_dark", wood, _shelf_root)
	_soft(Vector3(w, total_h, 0.012), Vector3(SHELF_X, base_y + total_h / 2.0, BACK + 0.012), "wood_dark", wood.darkened(0.45), _shelf_root)
	var strip := _mat(Color("ff3ea5"), 0.3, Color("ff3ea5"), 2.6)
	var floor_of := func(row: int) -> float:
		return base_y + (rows - 1 - row) * (inner.y + BOARD) + BOARD
	for i in rows + 1:
		var y := base_y + i * (inner.y + BOARD) + BOARD / 2.0
		var full := i == 0 or i == rows
		_soft(Vector3(w if full else inner.x, BOARD, inner.z), Vector3(SHELF_X, y, z), "wood_dark", wood, _shelf_root)
		# неоновая полоска по переднему краю полки
		_box(Vector3(inner.x - 0.01, 0.005, 0.005), Vector3(SHELF_X, y + BOARD / 2.0 - 0.004, z + inner.z / 2.0 + 0.002), strip, _shelf_root)
	# 3) коробки впритык слева направо, задом к задней стенке шкафа
	var front_z := z + inner.z / 2.0 - 0.01
	var back_z := BACK + 0.012 + 0.012
	# полки для перестановки коробок; справа на нижней — место под «Перудо»
	_row_info.clear()
	for r in BOXED_ROWS:
		var right := SHELF_X + inner.x / 2.0 - 0.003 - (PERUDO_SPACE if r == BOXED_ROWS - 1 and not cups.is_empty() else 0.0)
		_row_info.append({"left": SHELF_X - inner.x / 2.0 + 0.003, "right": right, "floor": floor_of.call(r), "back": back_z})
	var x_end := 0.0
	for r in BOXED_ROWS:
		var x := SHELF_X - inner.x / 2.0 + 0.003
		for b in cells[r]:
			_shelf_root.add_child(b)
			var t := Transform3D(Basis.IDENTITY, Vector3(x + b.size.x / 2.0, floor_of.call(r) + b.size.y / 2.0, back_z + b.size.z / 2.0))
			x += b.size.x
			b.home = t
			b.transform = t
			if not b.is_soon():
				boxes.append(b)
		x_end = x
	# 4) «Перудо» — в оставшемся месте второй ячейки: набор повёрнут вглубь и уменьшен, в руках — полный размер
	for g in cups:
		var b := GameBox.new()
		b.setup(g, Vector3.ONE, Color("c8262c"))
		_shelf_root.add_child(b)
		_cups = b
		_inner_right = SHELF_X + inner.x / 2.0
		_cups_z = z + 0.01
		_place_cups(x_end, false)
		boxes.append(b)
	# 5) нижняя ячейка — стопка затемнённых коробок «Coming soon», лёжа
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for r in range(BOXED_ROWS, rows):
		var y: float = floor_of.call(r)
		while true:
			var thick := rng.randf_range(0.045, 0.07)
			if y + thick > floor_of.call(r) + inner.y - 0.015:
				break
			var b := GameBox.new()
			b.setup({"id": "soon", "title": "Coming soon"}, Vector3.ONE, Color.WHITE)
			b.size = Vector3(thick, inner.x - rng.randf_range(0.01, 0.03), rng.randf_range(0.22, 0.3))
			b.dim = true
			_shelf_root.add_child(b)
			# лёжа: толщина — по вертикали, длинная сторона — поперёк ячейки
			var lying := Basis(Vector3(0, 0, 1), -PI / 2.0).rotated(Vector3.UP, rng.randf_range(-0.05, 0.05))
			b.transform = Transform3D(lying, Vector3(SHELF_X + rng.randf_range(-0.004, 0.004), y + thick / 2.0, front_z - b.size.z / 2.0 - rng.randf_range(0.0, 0.03)))
			b.home = b.transform
			y += thick


# --- Личный редактор шкафа -----------------------------------------------------------
## Фигурка участвует в той же личной раскладке и проверке места, что и коробки.
func _add_shelf_figurine() -> void:
	var figure := ShelfFigurine.new()
	_shelf_root.add_child(figure)
	boxes.append(figure)
	var andy := ShelfFigurine.new()
	andy.game = {"id": "shelf_andy", "title": "Энди", "shelf": false}
	andy.size = Vector3(0.15, 0.152, 0.30)
	_shelf_root.add_child(andy)
	boxes.append(andy)


func _shelf_id(box: GameBox) -> String:
	return str(box.get_meta("shelf_id", str(box.game.id)))


func _shelf_sizes() -> Dictionary:
	var sizes: Dictionary = {}
	for box: GameBox in boxes:
		sizes[_shelf_id(box)] = box.size
	return sizes


func _shelf_ids() -> Array:
	return _rows.map(func(row): return (row as Array).map(func(box): return _shelf_id(box)))


func _box_extent(box: GameBox) -> Vector3:
	return ShelfConfig.item_extent(_shelf_id(box), box.size, int(_box_modes.get(_shelf_id(box), 1)))


func _box_basis(box: GameBox) -> Basis:
	return ShelfConfig.item_basis(_shelf_id(box), int(_box_modes.get(_shelf_id(box), 1)))


func _init_custom_shelf() -> void:
	# При первом запуске сохраняем явно заданные ряды. Фигурка расширяет исходную
	# ячейку, а не запускает сортировку всех игр упаковщиком по убыванию ширины.
	var required_width := 0.0
	for cell in _rows.size():
		var row_width := ShelfConfig.GAP
		for box: GameBox in _rows[cell]:
			row_width += ShelfConfig.item_extent(_shelf_id(box), box.size, 1).x
		required_width = maxf(required_width, row_width)
	var defaults: Dictionary = {
		"rows": ROWS,
		"cols": 1,
		"width": maxf(required_width, float(_row_info[0].right) - float(_row_info[0].left) + ShelfConfig.GAP),
		"height": CELL_H,
		"cups": BOXED_ROWS - 1
	}
	var result := ShelfConfig.load_state(defaults, _shelf_ids(), _shelf_sizes())
	if result.ok:
		_apply_shelf_state(result)


func _apply_shelf_state(state: Dictionary) -> void:
	_cabinet = state.config.duplicate(true)
	_box_modes = state.poses.duplicate(true)
	var by_id: Dictionary = {}
	for box: GameBox in boxes:
		by_id[_shelf_id(box)] = box
	_rows = []
	for ids: Array in state.placements:
		if ids.has("shelf_girl"):
			ids = ids.duplicate()
			ids.erase("shelf_girl")
			ids.append("shelf_girl")
		_rows.append(ids.map(func(id): return by_id[id]))
	_rebuild_shelf_geometry()


func _rebuild_shelf_geometry() -> void:
	_hover = null
	for box: GameBox in boxes:
		box.stop_shelf_motion()
	for child in _shelf_root.get_children():
		if child is GameBox and boxes.has(child):
			continue
		_shelf_root.remove_child(child)
		child.queue_free()
	var rows: int = int(_cabinet.rows)
	var cols: int = int(_cabinet.cols)
	var width: float = float(_cabinet.width)
	var height: float = float(_cabinet.height)
	var full_width: float = cols * width + (cols + 1) * BOARD
	var full_height: float = rows * height + (rows + 1) * BOARD
	var base_y := 0.06
	var z: float = BACK + CELL_D * 0.5 + 0.01
	var left: float = SHELF_X - full_width * 0.5
	var wood := Color("2a1d42")
	_soft(
		Vector3(full_width - 0.02, base_y, CELL_D - 0.02),
		Vector3(SHELF_X, base_y * 0.5, z - 0.01),
		"wood_dark",
		wood.darkened(0.25),
		_shelf_root
	)
	_soft(
		Vector3(full_width, full_height, 0.012),
		Vector3(SHELF_X, base_y + full_height * 0.5, BACK + 0.012),
		"wood_dark",
		wood.darkened(0.45),
		_shelf_root
	)
	for column in cols + 1:
		_soft(
			Vector3(BOARD, full_height, CELL_D),
			Vector3(left + BOARD * 0.5 + column * (width + BOARD), base_y + full_height * 0.5, z),
			"wood_dark",
			wood,
			_shelf_root
		)
	var strip := _mat(Color("ff3ea5"), 0.3, Color("ff3ea5"), 2.6)
	for level in rows + 1:
		var y: float = base_y + BOARD * 0.5 + level * (height + BOARD)
		_soft(Vector3(full_width, BOARD, CELL_D), Vector3(SHELF_X, y, z), "wood_dark", wood, _shelf_root)
		_box(
			Vector3(full_width - 0.02, 0.005, 0.005),
			Vector3(SHELF_X, y + BOARD * 0.5 - 0.004, z + CELL_D * 0.5 + 0.002),
			strip,
			_shelf_root
		)
	_row_info = []
	_shelf_placeholders = {}
	for row in rows:
		for column in cols:
			var cell: int = row * cols + column
			var x: float = left + BOARD + column * (width + BOARD)
			var floor_y: float = base_y + BOARD + (rows - 1 - row) * (height + BOARD)
			var outer_right: float = x + width - 0.003
			_row_info.append(
				{
					"left": x + 0.003,
					"right": outer_right,
					"outer_right": outer_right,
					"floor": floor_y,
					"back": BACK + 0.024,
					"height": height
				}
			)
			if (
				row == ROWS - 1
				and column == 0
				and (_rows[cell] as Array).is_empty()
				and cell != int(_cabinet.cups)
			):
				_make_shelf_placeholder(cell, x, floor_y, width, height, row == rows - 1 and column == 0)
	_inner_right = left + full_width - BOARD
	_cups_z = z + 0.01
	shelf_top_right = (
		_shelf_root.global_transform
		* Vector3(left + full_width - 0.07, base_y + full_height + BOARD * 0.5, z + 0.02)
	)
	_reflow(false)
	if is_instance_valid(panels):
		panels.move_launcher(shelf_top_right)


## Нижняя левая ячейка заполнена стопкой, как в исходном шкафу; декор уступает место настоящей игре.
func _make_shelf_placeholder(
	cell: int, x: float, floor_y: float, width: float, height: float, _stack: bool
) -> void:
	var holder := Node3D.new()
	_shelf_root.add_child(holder)
	_shelf_placeholders[cell] = holder
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var y := 0.0
	while y + 0.045 <= height - 0.012:
		var thickness := minf(rng.randf_range(0.045, 0.07), height - 0.012 - y)
		var soon := GameBox.new()
		soon.setup({"id": "soon", "title": "Coming soon"}, Vector3.ONE, Color.WHITE)
		var depth := rng.randf_range(0.22, 0.30)
		var box_width := maxf(0.1, width - rng.randf_range(0.03, 0.065))
		soon.size = Vector3(thickness, box_width, depth)
		soon.dim = true
		holder.add_child(soon)
		var max_angle := minf(0.05, 0.025 / box_width) * ShelfConfig.SCATTER
		var angle := rng.randf_range(-max_angle, max_angle)
		var dx := rng.randf_range(-0.004, 0.004) * ShelfConfig.SCATTER
		var z := BACK + CELL_D - depth * 0.5 - rng.randf_range(0.012, 0.035) * ShelfConfig.SCATTER
		soon.transform = Transform3D(
			ShelfConfig.pose_basis(2).rotated(Vector3.UP, angle),
			Vector3(x + width * 0.5 + dx, floor_y + y + thickness * 0.5, z)
		)
		soon.home = soon.transform
		y += thickness
	if holder.get_child_count() > 1:
		var remove: Node3D = holder.get_child(0)
		for child: Node3D in holder.get_children():
			if child.position.x < remove.position.x:
				remove = child
		holder.remove_child(remove)
		remove.queue_free()
		var level := floor_y
		for child: GameBox in holder.get_children():
			child.position.y = level + child.size.x * 0.5
			child.home = child.transform
			level += child.size.x


func _save_shelf() -> Error:
	# Автоматическое уплотнение не забывает исходные места даже после «Готово» и перезапуска.
	_cabinet.layout_preferences = _editor_preferences.duplicate(true) if _editor_on else _shelf_ids()
	_cabinet.layout_preference_cols = (
		int(_editor_preference_geometry.get("cols", _cabinet.cols)) if _editor_on else int(_cabinet.cols)
	)
	_cabinet.layout_preference_cups = (
		int(_editor_preference_geometry.get("cups", _cabinet.cups)) if _editor_on else int(_cabinet.cups)
	)
	return ShelfConfig.save_state(_cabinet, _shelf_ids(), _box_modes)


func request_shelf_geometry(geometry: Dictionary) -> String:
	if not _editor_on:
		return ""
	var proposed := geometry.duplicate(true)
	var old_cols: int = int(_editor_preference_geometry.get("cols", _cabinet.cols))
	var old_cup: int = int(_editor_preference_geometry.get("cups", _cabinet.cups))
	var new_cols: int = clampi(int(proposed.cols), 1, 6)
	var cup_row: int = old_cup / old_cols
	var cup_column: int = old_cup % old_cols
	proposed.cups = (
		cup_row * new_cols + cup_column
		if cup_column < new_cols and cup_row < int(proposed.rows)
		else int(proposed.rows) * new_cols - 1
	)
	var result := ShelfConfig.solve(proposed, _editor_preferences, _shelf_sizes(), _box_modes, old_cols)
	if not result.ok:
		return str(result.message)
	_apply_shelf_state(result)
	if _edge_drag.is_empty():
		_frame_shelf()
	if (
		not is_equal_approx(float(proposed.width), float(result.config.width))
		or not is_equal_approx(float(proposed.height), float(result.config.height))
	):
		return "Достигнут предел размера шкафа: оставлено место для тумбы, скейтборда и куба."
	return ""


func _frame_shelf() -> void:
	if not is_instance_valid(camera):
		return
	var width: float = (
		(int(_cabinet.cols) * float(_cabinet.width) + (int(_cabinet.cols) + 1) * BOARD) * SHELF_SCALE
	)
	var height: float = (
		(int(_cabinet.rows) * float(_cabinet.height) + (int(_cabinet.rows) + 1) * BOARD) * SHELF_SCALE
	)
	var aspect: float = (
		get_viewport().get_visible_rect().size.x / maxf(1, get_viewport().get_visible_rect().size.y)
	)
	var tangent: float = tan(deg_to_rad(camera.fov) * 0.5)
	var distance: float = maxf(
		1.7,
		maxf(
			(height + 0.18) / (2 * tangent * 0.80),
			width / (2 * tangent * aspect * (0.62 if _editor_on else 0.86))
		)
	)
	var aim: Vector3 = (
		_shelf_root.global_transform * Vector3(SHELF_X, 0.06 + height / (2 * SHELF_SCALE), BACK + 0.18)
	)
	var shift: float = width * 0.16 if _editor_on else 0.0
	camera.global_position = aim + Vector3(shift, 0.03, distance)
	camera.look_at(aim + Vector3(shift, 0, 0))
	_cam_home = camera.transform


func _make_shelf_ui() -> void:
	_edge_overlay = Control.new()
	_edge_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_overlay.visible = false
	_edge_overlay.draw.connect(_draw_shelf_edges)
	add_child(_edge_overlay)
	_pose_button = HubStyle.button("", 14)
	_pose_button.custom_minimum_size = Vector2(46, 44)
	_pose_button.visible = false
	_pose_button.pressed.connect(_cycle_box_pose)
	add_child(_pose_button)


func open_shelf_editor() -> void:
	if _editor_on:
		return
	_cancel_drag()
	release()
	for box: GameBox in boxes:
		box.stop_shelf_motion()
	_editor_backup = {
		"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true)
	}
	var preferences: Variant = _cabinet.get("layout_preferences", _shelf_ids())
	_editor_preferences = preferences.duplicate(true) if preferences is Array else _shelf_ids()
	_editor_preference_geometry = _cabinet.duplicate(true)
	_editor_preference_geometry.cols = maxi(1, int(_cabinet.get("layout_preference_cols", _cabinet.cols)))
	_editor_preference_geometry.cups = int(_cabinet.get("layout_preference_cups", _cabinet.cups))
	_editor_on = true
	panels.input_locked = true
	_editor_ui = load("res://hub/shelf_editor.gd").new()
	_editor_ui.set("room", self)
	add_child(_editor_ui)
	_edge_overlay.visible = true
	_reflow(false)
	_frame_shelf()
	editor_mode_changed.emit(true)


func finish_shelf_editor(save: bool) -> void:
	if not _editor_on:
		return
	_cancel_drag()
	_edge_drag = {}
	if not save:
		_apply_shelf_state(_editor_backup)
	elif _save_shelf() != OK:
		_editor_ui.call("sync", "Не удалось сохранить шкаф. Попробуйте ещё раз.")
		return
	_editor_on = false
	panels.input_locked = false
	_edge_overlay.visible = false
	_editor_ui.queue_free()
	_editor_ui = null
	_frame_shelf()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	editor_mode_changed.emit(false)


func _cycle_box_pose() -> void:
	if _selected_box == null or _selected_box.is_figurine() or _drag_box != null:
		return
	var id := _shelf_id(_selected_box)
	var old: int = int(_box_modes.get(id, 1))
	_box_modes[id] = (1 - old) if _selected_box.is_cups() else (old + 1) % 4
	# Сначала проверяем только новую позу в реальных ячейках: свободное место не должно
	# зависеть от того, в каком порядке общий упаковщик рассматривает другие коробки.
	var source_cell := -1
	for cell in _rows.size():
		if (_rows[cell] as Array).has(_selected_box):
			source_cell = cell
			break
	var extent := ShelfConfig.item_occupied(id, _selected_box.size, int(_box_modes[id]))
	var destinations: Array = [source_cell]
	for cell in _rows.size():
		if cell != source_cell:
			destinations.append(cell)
	for cell: int in destinations:
		if cell < 0:
			continue
		var candidate: Array = _rows[cell].duplicate()
		if cell != source_cell:
			candidate.append(_selected_box)
		var info: Dictionary = _row_info[cell]
		var layout := _layout_row(candidate, cell)
		if (
			extent.y > float(info.height) + 0.0005
			or extent.z > CELL_D + 0.0005
			or float(layout.width) > float(info.right) - float(info.left) + 0.0005
		):
			continue
		if cell != source_cell:
			(_rows[source_cell] as Array).erase(_selected_box)
			_rows[cell].append(_selected_box)
		_reflow(true)
		_update_pose_button()
		_finish_pose_change()
		return
	var state := ShelfConfig.solve(_cabinet, _shelf_ids(), _shelf_sizes(), _box_modes, int(_cabinet.cols))
	if not state.ok:
		_box_modes[id] = old
		shelf_hint.emit("В этом положении коробке тесно. Освободите место или увеличьте полки.")
		return
	_apply_shelf_state(state)
	_selected_box.set_swap_highlight(true)
	_update_pose_button()
	_finish_pose_change()


## В редакторе поза — часть черновика: «Отмена» откатывает, «Готово» сохраняет.
func _finish_pose_change() -> void:
	if _editor_on:
		_editor_preferences = _shelf_ids()
		_editor_preference_geometry = _cabinet.duplicate(true)
		shelf_hint.emit("Положение изменено. Нажмите Готово для сохранения")
	elif _save_shelf() != OK:
		shelf_hint.emit("Положение изменено, но не удалось сохранить шкаф")


func _update_pose_button() -> void:
	_pose_button.visible = (
		_selected_box != null and not _selected_box.is_figurine() and _drag_box == null
	)
	if not _pose_button.visible:
		return
	var ext := _box_extent(_selected_box)
	var at := _selected_box.global_position + Vector3.UP * (ext.y * SHELF_SCALE * 0.5 + 0.045)
	var screen := camera.unproject_position(at)
	_pose_button.position = (screen - Vector2(23, 44)).clamp(
		Vector2(8, 70), get_viewport().get_visible_rect().size - Vector2(54, 52)
	)
	_pose_button.icon = ShelfIcons.icon(int(_box_modes.get(_shelf_id(_selected_box), 1)))
	_pose_button.tooltip_text = [
		"Обложкой к вам · нажмите: поставить боком",
		"Боком к вам · нажмите: положить",
		"Лёжа, корешком к вам · нажмите: показать крышку",
		"Лёжа, крышкой к вам · нажмите: поставить обложкой"
	][int(_box_modes.get(_shelf_id(_selected_box), 1))]


func _shelf_edges() -> Array:
	var lines: Array = []
	var rows: int = int(_cabinet.rows)
	var cols: int = int(_cabinet.cols)
	var width: float = cols * float(_cabinet.width) + (cols + 1) * BOARD
	var height: float = rows * float(_cabinet.height) + (rows + 1) * BOARD
	var left: float = SHELF_X - width * 0.5
	var z: float = BACK + CELL_D + 0.016
	for side in [-1, 1]:
		var x: float = SHELF_X + side * width * 0.5
		lines.append(
			{"kind": "width", "index": side, "a": Vector3(x, 0.06, z), "b": Vector3(x, 0.06 + height, z)}
		)
	for level in rows + 1:
		var y: float = 0.06 + BOARD * 0.5 + level * (float(_cabinet.height) + BOARD)
		lines.append(
			{"kind": "height", "index": level, "a": Vector3(left, y, z), "b": Vector3(left + width, y, z)}
		)
	for edge: Dictionary in lines:
		edge.a = camera.unproject_position(_shelf_root.global_transform * edge.a)
		edge.b = camera.unproject_position(_shelf_root.global_transform * edge.b)
	return lines


func _edge_at(screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance := 12.0
	for edge: Dictionary in _shelf_edges():
		var point := Geometry2D.get_closest_point_to_segment(screen, edge.a, edge.b)
		var next: float = screen.distance_to(point)
		if next < distance:
			best = edge
			distance = next
	return best


func _draw_shelf_edges() -> void:
	if not _editor_on:
		return
	for edge: Dictionary in _shelf_edges():
		var hot: bool = (
			(not _edge_hover.is_empty() and edge.kind == _edge_hover.kind and edge.index == _edge_hover.index)
			or (not _edge_drag.is_empty() and edge.kind == _edge_drag.kind and edge.index == _edge_drag.index)
		)
		_edge_overlay.draw_line(edge.a, edge.b, Color(HubStyle.CYAN, 0.10), 10, true)
		_edge_overlay.draw_line(
			edge.a, edge.b, HubStyle.YELLOW if hot else Color(HubStyle.CYAN, 0.72), 4 if hot else 2, true
		)


func _shelf_point(screen: Vector2) -> Vector3:
	var inverse := _shelf_root.global_transform.affine_inverse()
	var origin: Vector3 = inverse * camera.project_ray_origin(screen)
	var direction: Vector3 = inverse.basis * camera.project_ray_normal(screen)
	return (
		origin + direction * ((BACK + CELL_D + 0.016 - origin.z) / direction.z)
		if absf(direction.z) > 0.00001
		else Vector3.ZERO
	)


func _begin_edge_drag(edge: Dictionary, screen: Vector2) -> void:
	_edge_drag = edge.duplicate(true)
	_edge_drag["point"] = _shelf_point(screen)
	_edge_drag["state"] = {
		"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true)
	}


func _resize_shelf_edge(screen: Vector2) -> void:
	var delta: Vector3 = _shelf_point(screen) - Vector3(_edge_drag.point)
	var original: Dictionary = _edge_drag.state.config
	var config: Dictionary = _cabinet.duplicate(true)
	if _edge_drag.kind == "width":
		config.width = float(original.width) + delta.x * int(_edge_drag.index) * 2.0 / int(original.cols)
	else:
		var level: int = int(_edge_drag.index)
		config.height = (
			float(original.height) + delta.y / (float(level) if level > 0 else -float(original.rows))
		)
	var message := request_shelf_geometry(config)
	_editor_ui.call("sync", message)


# --- Выбор мышью ----------------------------------------------------------------------

## Отдельный слой декора: не перехватывает лучи коробок и редактора.
func _add_room_prop(kind: String, at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = at
	body.set_meta("room_prop", kind)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _room_prop_at(point: Vector2) -> String:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 20, 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return str(hit.collider.get_meta("room_prop", "")) if not hit.is_empty() else ""


func _use_room_prop(kind: String) -> void:
	_clear_shelf_selection()
	if kind == "tv":
		_tv_channel = (_tv_channel + 1) % 3
		_tv_title.text = ["НАСТОЛКИ", "PLAYER ONE", "GOOD GAME"][_tv_channel]
		_blink.text = ["PRESS START", "READY?", "PLAY AGAIN"][_tv_channel]
		shelf_hint.emit("Телевизор · канал %d" % (_tv_channel + 1))
	elif kind == "lamp":
		_lamp_color = (_lamp_color + 1) % 3
		var tint: Color = [Color("ff3ea5"), Color("35e6d1"), Color("ffaf44")][_lamp_color]
		for blob: MeshInstance3D in _lava:
			var material := blob.material_override as StandardMaterial3D
			material.albedo_color = tint
			material.emission = tint
		shelf_hint.emit("Лавовая лампа · новый цвет")
	Sfx.play("click", -12)


func _box_at(screen_pos: Vector2) -> GameBox:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 20.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)  # только коробки (окошки игр — на своём слое)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Object = hit["collider"]
	return col.get_meta("game_box") if col.has_meta("game_box") else null


func _input(event: InputEvent) -> void:
	if _editor_on:
		if _editor_box_press and _pressed_box != null:
			if event is InputEventMouseMotion:
				if _drag_box == null and event.position.distance_to(_press_screen) > 6.0:
					_start_drag()
				if _drag_box != null:
					_drag_update(event.position)
				get_viewport().set_input_as_handled()
				return
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_LEFT
				and not event.pressed
			):
				_editor_box_press = false
				if _drag_box != null:
					_finish_drag(_pointer_clear())
				_pressed_box = null
				get_viewport().set_input_as_handled()
				return
		if not _edge_drag.is_empty():
			if event is InputEventMouseMotion:
				_resize_shelf_edge(event.position)
				get_viewport().set_input_as_handled()
				return
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_LEFT
				and not event.pressed
			):
				_edge_drag = {}
				_frame_shelf()
				get_viewport().set_input_as_handled()
				return
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				var state: Dictionary = _edge_drag.state
				_edge_drag = {}
				_apply_shelf_state(state)
				_editor_ui.call("sync")
				_frame_shelf()
				get_viewport().set_input_as_handled()
				return
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if _drag_box != null or _selected_box != null:
				_cancel_drag()
				get_viewport().set_input_as_handled()
				return
			finish_shelf_editor(false)
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and not _editor_on
		and _selected_box != null
		and _drag_box == null
	):
		if _pose_button.visible and _pose_button.get_global_rect().has_point(event.position):
			return
		if _pointer_clear() and _box_at(event.position) == _selected_box:
			_pressed_box = _selected_box
			_press_selected = true
			_hold_handled = false
			_hold_time = 0.0
			get_viewport().set_input_as_handled()
			return
		var next_box := _box_at(event.position) if _pointer_clear() else null
		_clear_shelf_selection()
		if next_box != null:
			_selected_box = next_box
			_pressed_box = next_box
			_press_selected = true
			_hold_handled = false
			_hold_time = 0.0
			get_viewport().set_input_as_handled()
			return
		if _pointer_clear():
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and _pressed_box != null
	):
		var pressed := _pressed_box
		_pressed_box = null
		if _drag_box != null:
			_finish_drag(_pointer_clear())
		elif _hold_handled:
			pass  # первое удержание только выделяет; отпускание не снимает зелёную рамку
		elif _press_selected:
			_clear_shelf_selection()
		elif _box_at(event.position) == pressed and _pointer_clear():
			focus(pressed)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag()


func _pointer_clear() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	return control == null or control.mouse_filter == Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if _editor_on:
		if event is InputEventMouseMotion:
			_edge_hover = _edge_at(event.position)
			Input.set_default_cursor_shape(
				(
					Input.CURSOR_ARROW
					if _edge_hover.is_empty()
					else (Input.CURSOR_HSIZE if _edge_hover.kind == "width" else Input.CURSOR_VSIZE)
				)
			)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var edge := _edge_at(event.position)
			if not edge.is_empty():
				_begin_edge_drag(edge, event.position)
			else:
				var box := _box_at(event.position)
				if box != null:
					_select_shelf_box(box)
					_pressed_box = box
					_press_screen = event.position
					_hold_handled = true
					_editor_box_press = true
				else:
					_clear_shelf_selection()
		get_viewport().set_input_as_handled()
		return
	if panels and panels.is_open:
		return
	if (
		focused == null
		and _drag_box == null
		and event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var prop := _room_prop_at(event.position)
		if not prop.is_empty():
			_use_room_prop(prop)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if focused:
			return
		if _drag_box != null:
			_drag_update(event.position)
			return
		if _selected_box != null:
			return
		var b := _box_at(event.position)
		if b != _hover:
			if _hover:
				_hover.set_hovered(false)
			_hover = b
			if b:
				b.set_hovered(true)
		Input.set_default_cursor_shape(
			(
				Input.CURSOR_POINTING_HAND
				if b or not _room_prop_at(event.position).is_empty()
				else Input.CURSOR_ARROW
			)
		)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var b := _box_at(event.position)
				if focused == null and b:
					_pressed_box = b
					_press_screen = event.position
					_press_selected = false
					_hold_handled = false
					_hold_time = 0.0
				elif focused and b != focused:
					release()
			MOUSE_BUTTON_RIGHT:
				_cancel_drag()
				release()
			MOUSE_BUTTON_WHEEL_DOWN:
				step(1)
			MOUSE_BUTTON_WHEEL_UP:
				step(-1)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				release()
			KEY_RIGHT, KEY_DOWN:
				step(1)
			KEY_LEFT, KEY_UP:
				step(-1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_drag()
		if not _edge_drag.is_empty():
			var state: Dictionary = _edge_drag.state
			_edge_drag = {}
			_apply_shelf_state(state)
			if is_instance_valid(_editor_ui):
				_editor_ui.call("sync")


## Личная раскладка: сохранённый порядок коробок по полкам (или SHELF_LAYOUT).
func _prepare_layout() -> void:
	var by_id := {}
	var widths := {}
	for b: GameBox in boxes:
		b.set_meta("shelf_id", b.game.id)  # постоянный ID, независимо от выбранного варианта игры
		by_id[b.game.id] = b
		widths[b.game.id] = ShelfConfig.item_extent(str(b.game.id), b.size, 1).x
	var limits := _row_info.map(func(info): return float(info.right) - float(info.left))
	_rows.clear()
	var defaults := SHELF_LAYOUT.duplicate(true)
	defaults[2].append("shelf_girl")
	defaults[2].append("perudo")
	defaults[2].append("shelf_andy")
	for ids in ShelfOrder.load_rows(defaults, widths, limits):
		_rows.append((ids as Array).map(func(id): return by_id[id]))
	_reflow(false)


## Коробки впритык слева направо; на полке, куда целится взятая коробка, — щель под неё.
func _reflow(animate: bool) -> void:
	for r in _rows.size():
		var info: Dictionary = _row_info[r]
		var row: Array = _rows[r].duplicate()
		if _shelf_placeholders.has(r):
			(_shelf_placeholders[r] as Node3D).visible = (
				row.is_empty() and not (_drag_box != null and _drag_to.x == r)
			)
		if _drag_box != null and _drag_to.x == r:
			row.insert(_drag_to.y, _drag_box)
		var layout := _layout_row(row, r)
		for b: GameBox in row:
			if b == _drag_box:
				continue
			var home: Transform3D = layout.boxes[_shelf_id(b)]
			home.origin += Vector3(float(info.left), float(info.floor), float(info.back))
			_set_home(b, home, animate)


## Единая раскладка стопок для изображения, проверки вместимости и переноса.
func _layout_row(row: Array, cell: int) -> Dictionary:
	var positions: Dictionary = _cabinet.get("figure_positions", {"shelf_girl": float(_cabinet.get("figure_x", 1.0)), "shelf_andy": 0.65}).duplicate()
	if _drag_box != null and _drag_box.is_figurine():
		positions[_shelf_id(_drag_box)] = _figure_preview_x
	return ShelfConfig.row_layout(
		row.map(func(box): return _shelf_id(box)),
		_shelf_sizes(),
		_box_modes,
		float(_row_info[cell].get("height", CELL_H)),
		positions,
		float(_row_info[cell].right) - float(_row_info[cell].left)
	)


## Первое удержание оставляет коробку на полке и открывает кнопку положения.
func _select_shelf_box(box: GameBox) -> void:
	_clear_shelf_selection()
	_selected_box = box
	box.stop_shelf_motion()
	box.transform = box.home
	box.set_swap_highlight(true)
	_hover = null
	_update_pose_button()
	(
		shelf_hint
		. emit(
			"Выделено: кнопка меняет положение · Удерживайте коробку снова для переноса · Клик вне кнопки снимает выделение"
		)
	)


func _clear_shelf_selection() -> void:
	if is_instance_valid(_selected_box):
		_selected_box.set_swap_highlight(false)
	_selected_box = null
	if is_instance_valid(_pose_button):
		_pose_button.visible = false


## Набор «Перудо» — в свободном месте справа от коробок нижней полки, повёрнут вглубь и уменьшен.
func _place_cups(x_end: float, animate: bool) -> void:
	if _cups == null:
		return
	var cup_cell: int = int(_cabinet.get("cups", BOXED_ROWS - 1))
	var info: Dictionary = _row_info[cup_cell]
	var free_w: float = float(info.get("outer_right", _inner_right)) - x_end - 0.008
	var fit := minf(
		1.0,
		minf(
			free_w / _cups.size.z,
			minf((CELL_D - 0.02) / _cups.size.x, float(info.get("height", CELL_H)) / _cups.size.y)
		)
	)
	var basis := Basis(Vector3.UP, -PI / 2.0 + 0.25).scaled(Vector3.ONE * fit)
	_set_home(
		_cups, Transform3D(basis, Vector3(x_end + free_w / 2.0 + 0.004, float(info.floor), _cups_z)), animate
	)


func _set_home(b: GameBox, home: Transform3D, animate: bool) -> void:
	if b.home.is_equal_approx(home) and b.transform.is_equal_approx(home):
		return
	b.home = home
	if b == focused:
		return  # в руках у игрока — вернётся уже на новое место
	if not animate:
		b.transform = home
		return
	if b.has_meta("slide"):
		var old: Tween = b.get_meta("slide")
		if old.is_valid():
			old.kill()
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "transform", home, 0.2)
	b.set_meta("slide", tw)


## Удержание сработало: коробка снимается с полки и едет за курсором.
func _start_drag() -> void:
	var b := _pressed_box
	_drag_original_mode = int(_box_modes.get(_shelf_id(b), 1))
	_hold_handled = true
	_drag_from = Vector2i(-1, -1)
	for r in _rows.size():
		var i: int = (_rows[r] as Array).find(b)
		if i >= 0:
			_drag_from = Vector2i(r, i)
			(_rows[r] as Array).remove_at(i)
			break
	if _drag_from.x < 0:
		_pressed_box = null
		return
	_drag_box = b
	_figure_preview_x = float(_cabinet.get("figure_positions", {}).get(_shelf_id(b), _cabinet.get("figure_x", 1.0)))
	_selected_box = b
	_drag_to = _drag_from
	if _hover != null:
		_hover.set_hovered(false)
		_hover = null
	b.set_swap_highlight(true)
	b.stop_shelf_motion()
	Sfx.play("card_slide", -10)
	if b.is_figurine():
		b.position.z = b.home.origin.z
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	shelf_hint.emit("Ведите коробку вдоль полок — соседние раздвинутся. Отпустите, чтобы поставить")
	_drag_update(get_viewport().get_mouse_position())
	_update_pose_button()


## Курсор двигается с коробкой: какая полка ближе и между какими коробками она встанет.
func _drag_update(screen: Vector2) -> void:
	var inv := _shelf_root.global_transform.affine_inverse()
	var o := inv * camera.project_ray_origin(screen)
	var d := inv.basis * camera.project_ray_normal(screen)
	var ext := _box_extent(_drag_box)
	var zc: float = float(_row_info[0].back) + ext.z / 2.0 + DRAG_LIFT
	if int(_box_modes.get(_shelf_id(_drag_box), 1)) in [0, 1, 2, 3] or _drag_box.is_cups():
		zc = float(_row_info[0].back) + CELL_D - 0.024 - ext.z * 0.5 + DRAG_LIFT
	if _drag_box.is_figurine():
		zc = float(_row_info[0].back) + CELL_D - 0.024 - ext.z * 0.5
	if absf(d.z) < 0.0001:
		return
	_drag_at = o + d * ((zc - o.z) / d.z)
	var r := 0
	var nearest := INF
	for k in _row_info.size():
		var cell: Dictionary = _row_info[k]
		var midpoint := Vector2(
			(float(cell.left) + float(cell.right)) * 0.5,
			float(cell.floor) + float(cell.get("height", CELL_H)) * 0.5
		)
		var distance: float = (
			Vector2(
				(_drag_at.x - midpoint.x) / maxf(0.1, float(_cabinet.get("width", 1.0))),
				(_drag_at.y - midpoint.y) / float(cell.get("height", CELL_H))
			)
			. length_squared()
		)
		if distance < nearest:
			nearest = distance
			r = k
	var row: Array = _rows[r]
	var info: Dictionary = _row_info[r]
	if _drag_box.is_figurine():
		var width: float = float(info.right) - float(info.left)
		_figure_preview_x = clampf(
			(_drag_at.x - float(info.left) - ext.x * 0.5) / maxf(0.001, width - ext.x), 0.0, 1.0
		)
		var candidate: Array = row.duplicate()
		candidate.append(_drag_box)
		var arranged := _layout_row(candidate, r)
		var fits: bool = float(arranged.width) <= width + 0.0005 and ext.y <= float(info.height) + 0.0005
		_drag_to = Vector2i(r, row.size()) if fits else Vector2i(-1, -1)
		_drag_at.x = float(info.left) + ext.x * 0.5 + _figure_preview_x * maxf(0.0, width - ext.x)
		_reflow(true)
		_drag_box.set_swap_highlight(true, fits)
		return
	var layout := _layout_row(row, r)
	var index := ShelfOrder.pile_insert_index(
		layout.piles, row.map(func(box): return _shelf_id(box)), _drag_at.x - float(info.left)
	)
	var candidate: Array = row.duplicate()
	candidate.insert(index, _drag_box)
	var fit_layout := _layout_row(candidate, r)
	var occupied := ShelfConfig.item_occupied(
		_shelf_id(_drag_box), _drag_box.size, int(_box_modes.get(_shelf_id(_drag_box), 1))
	)
	var fits := (
		float(fit_layout.width) <= float(info.right) - float(info.left) + 0.0005
		and occupied.y <= float(info.get("height", CELL_H)) + 0.0005
		and occupied.z <= CELL_D + 0.0005
	)
	var to := Vector2i(r, index) if fits else Vector2i(-1, -1)
	if to == _drag_to:
		return
	_drag_to = to
	_reflow(true)
	_drag_box.set_swap_highlight(true, fits)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG if fits else Input.CURSOR_FORBIDDEN)
	shelf_hint.emit(
		(
			"Ведите коробку вдоль полок — соседние раздвинутся. Отпустите, чтобы поставить"
			if fits
			else "На этой полке нет места — отпустите, и коробка вернётся"
		)
	)
	Sfx.play("hover", -16, 0.1, 0.05)


## Отпустили: коробка встаёт в щель (или возвращается, если поставить некуда / отпустили над интерфейсом).
func _finish_drag(ok: bool) -> void:
	var b := _drag_box
	if not ok or _drag_to.x < 0:
		_box_modes[_shelf_id(b)] = _drag_original_mode
	var to := _drag_to if ok and _drag_to.x >= 0 else _drag_from
	var moved: bool = to != _drag_from or int(_box_modes.get(_shelf_id(b), 1)) != _drag_original_mode
	if b.is_figurine() and ok and _drag_to.x >= 0:
		var positions: Dictionary = _cabinet.get("figure_positions", {"shelf_girl": float(_cabinet.get("figure_x", 1.0)), "shelf_andy": 0.65}).duplicate()
		moved = moved or not is_equal_approx(float(positions.get(_shelf_id(b), 1.0)), _figure_preview_x)
		positions[_shelf_id(b)] = _figure_preview_x
		_cabinet.figure_positions = positions
	(_rows[to.x] as Array).insert(to.y, b)
	_drag_box = null
	_drag_to = Vector2i(-1, -1)
	_pressed_box = null
	_hold_time = 0.0
	_hold_handled = true
	if is_instance_valid(_pose_button):
		_pose_button.visible = false
	b.set_swap_highlight(false)
	_clear_shelf_selection()
	_reflow(true)
	Sfx.play("card_place", -8)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var hint := HINT
	if moved and _editor_on:
		_editor_preferences = _shelf_ids()
		_editor_preference_geometry = _cabinet.duplicate(true)
		hint = "Новое место выбрано. Нажмите Готово для сохранения"
	elif moved:
		hint = (
			"Коробка переставлена"
			if _save_shelf() == OK
			else "Коробка переставлена, но раскладку не удалось сохранить"
		)
	shelf_hint.emit(hint)


func _cancel_drag() -> void:
	_editor_box_press = false
	if _drag_box != null:
		_finish_drag(false)
	_pressed_box = null
	_hold_time = 0.0
	_clear_shelf_selection()


## Коробка вылетает к игроку обложкой вперёд (чуть левее центра — справа карточка игры).
func focus(b: GameBox) -> void:
	if b.is_figurine():
		_select_shelf_box(b)
		return
	if focused == b:
		return
	if focused:
		focused.fly_home()
	if _hover:
		_hover.set_hovered(false)
		_hover = null
	focused = b
	var fwd := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var pos := camera.global_position + fwd * 0.68 - right * 0.1 - up * 0.02
	var basis: Basis
	if b.face_z:
		# набор стаканчиков: к игроку сторона +Z, чуть сверху — чтобы были видны кубики
		var z_axis := -fwd
		var x_axis := up.cross(z_axis).normalized()
		basis = Basis(x_axis, up, z_axis).rotated(right, 0.35).rotated(up, 0.12)
		pos -= up * (b.size.y * 0.55)
	else:
		# локальная +X коробки (обложка) смотрит на камеру
		var x_axis := -fwd
		var z_axis := x_axis.cross(up).normalized()
		basis = Basis(x_axis, up, z_axis).rotated(up, 0.18)
	b.fly_to(b.get_parent().global_transform.affine_inverse() * Transform3D(basis, pos))
	var aim := pos + up * (b.size.y * 0.5 if b.face_z else 0.0)
	_present.look_at(aim)
	_rim.look_at(aim)
	var t := create_tween().set_parallel()
	# светлые обложки (например, белая «Дюжина короля») подсвечиваем слабее, чтобы не пересвечивались
	var k := lerpf(1.0, 0.35, clampf((b.brightness - 0.35) / 0.45, 0.0, 1.0))
	t.tween_property(_present, "light_energy", 2.2 * k, 0.6)
	t.tween_property(_rim, "light_energy", 3.0 * k, 0.6)
	box_selected.emit(b.game)


func release() -> void:
	if focused == null:
		return
	focused.fly_home()
	focused = null
	var t := create_tween().set_parallel()
	t.tween_property(_present, "light_energy", 0.0, 0.5)
	t.tween_property(_rim, "light_energy", 0.0, 0.5)
	box_released.emit()


## Листание: следующая / предыдущая коробка.
func step(dir: int) -> void:
	if focused == null:
		return
	var games := boxes.filter(func(box): return not box.is_figurine())
	var i := games.find(focused)
	focus(games[posmod(i + dir, games.size())])


func focus_id(game_id: String) -> void:
	for b in boxes:
		if b.game.get("id", "") == game_id:
			focus(b)


func _process(delta: float) -> void:
	if (
		is_instance_valid(panels)
		and panels.is_open
		and (_drag_box != null or _pressed_box != null or _selected_box != null)
	):
		_cancel_drag()
	if is_instance_valid(_pose_button):
		_update_pose_button()
	if _editor_on:
		_edge_overlay.queue_redraw()
	if _pressed_box != null and _drag_box == null and not _hold_handled:
		_hold_time += delta
		if _hold_time >= BOX_HOLD:
			_hold_handled = true
			if _selected_box == _pressed_box:
				_start_drag()
			else:
				_select_shelf_box(_pressed_box)
	if _drag_box != null:
		# взятая коробка плавно едет за курсором, выдвинутая из шкафа
		var info: Dictionary = _row_info[0]
		var ext := _box_extent(_drag_box)
		var lo: float = float(_row_info[_row_info.size() - 1].floor) + ext.y / 2.0
		var hi: float = float(info.floor) + ext.y / 2.0
		var drag_z: float = float(info.back) + ext.z * 0.5 + DRAG_LIFT
		if int(_box_modes.get(_shelf_id(_drag_box), 1)) in [0, 1, 2, 3] or _drag_box.is_cups():
			drag_z = float(info.back) + CELL_D - 0.024 - ext.z * 0.5 + DRAG_LIFT
		if _drag_box.is_figurine():
			drag_z = float(info.back) + CELL_D - 0.024 - ext.z * 0.5
		var want := Vector3(
			clampf(_drag_at.x, float(info.left) + ext.x / 2.0, _inner_right - 0.003 - ext.x / 2.0),
			clampf(_drag_at.y, lo, hi),
			drag_z
		)
		_drag_box.transform = _drag_box.transform.interpolate_with(
			Transform3D(_box_basis(_drag_box), want), 1.0 - exp(-delta * 18.0)
		)
	_t += delta
	# лёгкое «дыхание» камеры и параллакс от мыши
	var vp := get_viewport()
	var m := vp.get_mouse_position() / Vector2(vp.get_visible_rect().size) - Vector2(0.5, 0.5)
	var sway := Vector3(sin(_t * 0.35) * 0.008, sin(_t * 0.5) * 0.006, 0)
	var target := _cam_home
	target.origin += sway
	target.basis = target.basis.rotated(Vector3.UP, -m.x * 0.03).rotated(
		target.basis.x.normalized(), -m.y * 0.02
	)
	camera.transform = camera.transform.interpolate_with(target, minf(1.0, delta * 3.0))
	# лавовая лампа
	for i in _lava.size():
		var b: MeshInstance3D = _lava[i]
		b.position.y = _lava_base - 0.1 + fposmod(_t * (0.035 + i * 0.008) + i * 0.07, 0.22)
	# мигающая надпись на экране и чуть мерцающая вывеска
	if _blink:
		_blink.visible = fmod(_t, 1.2) < 0.8
	if _sign:
		var f := 1.0 if fmod(_t, 7.3) > 0.12 else 0.45
		_sign.modulate = Color(HubStyle.PINK.r * 1.6, HubStyle.PINK.g * 1.6, HubStyle.PINK.b * 1.6) * f


