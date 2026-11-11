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
signal game_editor_requested
signal board_requested(screen_point: Vector2)  # клик по доске друзей (своя или в комнате друга)
signal board_moved(center: Vector2, bid: int)  # свою доску bid перевесили (центр на задней стене, м)
signal board_held  # свою доску зажали — над ней смайлик (hub/sticker_ui.gd)
signal poster_add_requested  # кнопка плаката в редакторе шкафа — повесить новый (hub/poster_ui.gd)
signal poster_held(slot: int)  # плакат зажали — над ним значок галереи (hub/poster_ui.gd)
signal poster_moved(slot: int, center: Vector2)  # плакат перевесили (центр на стене, м)  # свою доску перевесили (центр на задней стене, x/y в метрах)

const HINT := "ЛКМ — открыть игру · Удерживайте ЛКМ для переноса · ПКМ — выделить"

const W := 6.0  # ширина комнаты
const H := 2.8  # высота
const ROOM_FRONT := 2.18
const FRONT_WALL_LAYER := 1 << 19
const CEILING_LAYER := 1 << 17
const LEFT_WALL_LAYER := 1 << 16
const BACK := -2.0  # задняя стена (z)
# шкаф: 4 ячейки по вертикали, 1 по горизонтали
const CELL_H := 0.36  # высота ячейки
const CELL_D := ShelfConfig.CELL_DEPTH  # общая глубина геометрии и проверки вместимости
const BOARD := 0.03
const ROWS := 4
const PER_CELL := 4  # коробок в ячейке — впритык к задней стенке; ширина шкафа считается по самой широкой ячейке
const SHELF_SCALE := 0.95  # шкаф вместе с коробками крупнее (масштаб от пола у стены)
const CAMERA_FOV := 52.0
const BOXED_ROWS := 3  # ячеек с коробками (в последней — ещё «Перудо»), ниже — «Coming soon»
## Какие коробки на какой полке (сверху вниз, слева направо).
const SHELF_LAYOUT := [
	["blood_on_the_clocktower", "machi_koro", "wavelength", "hues_and_cues", "dangerous_words", "king_of_12", "not_a_hat", "khorom"],
	["ready_set_bet", "tip_top", "tip_top_18", "gloom", "gloomier", "stillion", "poker"],
	["word_slam", "brodilka", "phantom_ink", "four_souls", "the_gang", "things_in_rings", "the_mind"],
]
const SHELF_X := 0.25
const PERUDO_SPACE := 0.17  # место под набор «Перудо» во второй ячейке

const ShelfOrder := preload("res://hub/shelf_layout.gd")
const BOX_HOLD := 0.32  # с: удержание на коробке — взять её и переставлять (06.11: было 0,45 — отзывчивее)
const DRAG_LIFT := 0.07  # м: взятая коробка выдвигается из шкафа к игроку
const PublicRoom := preload("res://hub/public_room.gd")
var remote_view := false
var remote_follow := true
var _remote_zoom := 1.0
var _local_room: Dictionary = {}
var _remote_selected := ""
var _remote_editor := false

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
var sticker_board: Node3D  # hub/sticker_board.gd — доска, с которой сейчас работают (последняя нажатая)
var boards: Dictionary = {}  # номер доски → узел; 0 — основная, остальные добавлены в редакторе шкафа
var board_dragging := false  # свою доску переносят по стене
var _board_cam_saved: Variant = null  # куда вернуть камеру после приближения к доске
var _board_homes: Dictionary = {}  # номер доски → где её повесили (сохранено); висит в ближайшем свободном от шкафа месте
## Пока комната только построена (вход в хаб, возврат из игры), доска сразу встаёт на место, без проезда
## от стандартного места через всю стену (09.11). Потом — снова плавно (шкаф в редакторе шире/уже).
var _board_snap_frames := 30
var _wall_decor: Array = []  # [Rect2 на задней стене (x, y), глубина, на которой доска их перекрывает]
var posters: Array = []  # hub/wall_poster.gd — плакаты на задней стене
var poster_dragging: Node3D = null  # плакат, который сейчас переносят
var _poster_press: Node3D = null  # нажали на плакат: удержание — перенос и значок галереи
var _poster_hold := 0.0
var _poster_grab := Vector3.ZERO
const BOARD_EXTENT := Vector2(0.56, 0.48)  # доска с рамой и полочкой (м)
var _board_press := false  # нажали на доску: короткий клик — панель, удержание — перенос
var _board_hold := 0.0
var _board_grab := Vector3.ZERO
const BOARD_AT := Vector3(1.13, 1.02, BACK + 0.012)
var panels: GamePanels  # «окошки игр» (стеклянный куб на шкафу)
var shelf_top_right := Vector3.ZERO  # место на крышке шкафа у правого края (куб-кнопка окошек игр)
var _hover: GameBox
var _cam_home := Transform3D.IDENTITY
var _t := 0.0
var _tv_title: Label
var _tv_channel := 0
var _lamp_color := 0
## Кубик-рубильник на телевизоре — антистресс главного меню: три тумблера с лампочками, кнопка и колёсико.
## Мяч-попрыгун — второй антистресс меню: лежит на полу, его хватают мышью и бросают, он скачет по полу,
## стенам, шкафу, тумбе и телевизору. Физика своя (один шарик), без физического движка.
const BALL_R := 0.04
const BALL_HOME := Vector3(-0.42, 0.62, -1.1)  # отсюда он в начале падает и сам ложится у нижнего края кадра
const BALL_FRONT := -0.95  # невидимая стенка перед камерой: ближе мяч был бы слишком крупным
const BALL_BOUNCE := 0.8
var _ball: Node3D
var _ball_body: StaticBody3D
var _window_sill_bounds: AABB
var _basket: Node3D
var _ball_v := Vector3.ZERO
var _ball_held := false
var _ball_plane := -1.2  # глубина, на которой мяч ведут за курсором
var _ball_asleep := false
var _ball_view := ""
var ball_on := true  # мяч включают и выключают кнопкой в редакторе шкафа (user://room_props.cfg)
const FIDGET_SCALE := 1.35  # крупнее настоящего: по ручкам должно быть легко попасть
const FIDGET_COLORS := [Color("ff3ea5"), Color("2ef2ff"), Color("ffe14d")]
var _fidget: Dictionary = {}
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
var _drag_backup: Dictionary = {}
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
var _drag_surface: Dictionary = {}
## Раскладка всех ящиков с переносимой коробкой, если её вставка сдвигает лишнее цепочкой в соседние.
var _drag_cascade: Array = []
## Выделенная коробка выдвинута из шкафа и висит перед ним: её место заняли соседи, в «полёте» её
## переворачивают кнопкой и затем удержанием ведут на новое место. Клик мимо — возвращается на прежнее.
const LIFT_OUT := 0.11  # насколько дальше обычного переноса коробка выдвигается к игроку
var _lift_box: GameBox
var _lift_from := Vector2i(-1, -1)
var _lift_mode := 1  # положение до выдвижения
var _lift_floor := Vector3.ZERO  # где стояла: центр по X, низ по Y
var _lift_backup: Dictionary = {}
## Отмена в редакторе шкафа (Ctrl+Z): снимки черновика до каждого изменения.
var _undo_stack: Array = []
var _undo_last: Dictionary = {}
var _undo_clock := 0.0
## Время на табло видеомагнитофона: каждый клик — следующее «красивое» время.
const VCR_TIMES: Array[String] = ["0:00", "0:07", "1:11", "2:22", "2:23", "2:28", "3:22", "3:33", "4:20", "4:30", "4:44", "5:55", "6:07"]
var _alarm_clock: Label3D
var _alarm_second := -1
var _vcr_clock: Label3D
var _vcr_time := 0
var _env: Environment
var _key: SpotLight3D
var _extra_lights: Array = []  # второстепенные лампы — выключаются на низком качестве  # шкаф и коробки — общий масштаб SHELF_SCALE  # контровой — сзади-справа, очерчивает кромки


func _ready() -> void:
	_environment()
	_room()
	_furniture()
	_shelf()
	_wall_shelves()
	_wall_door()
	_add_shelf_figurine()
	_prepare_layout()
	_init_custom_shelf()
	_lights()
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.position = Vector3(SHELF_X - 0.1, 0.9, 0.12)
	add_child(camera)
	camera.look_at(Vector3(SHELF_X, 0.84, BACK + 0.2))
	_cam_home = camera.transform
	camera.current = true
	_basket = preload("res://hub/room_basket.gd").new()
	_basket.room = self
	add_child(_basket)
	panels = GamePanels.new()
	add_child(panels)
	panels.setup(
		camera, boxes.filter(func(b): return not b.is_figurine()).map(func(b): return b.game), shelf_top_right
	)
	panels.editor_requested.connect(open_shelf_editor)
	_make_shelf_ui()
	_frame_shelf()
	camera.fov = _shelf_camera_fov()
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
	var depth := ROOM_FRONT - BACK
	var middle := (ROOM_FRONT + BACK) * 0.5
	var wall := _mat(Color("7f6bc4"), 0.95)
	_box(Vector3(W, H, 0.1), Vector3(0, H / 2.0, BACK - 0.05), wall)  # задняя
	var left_wall := _box(Vector3(0.1, H, depth), Vector3(-W / 2.0, H / 2.0, middle), wall)
	left_wall.layers = LEFT_WALL_LAYER
	_box(Vector3(0.1, H, depth), Vector3(W / 2.0, H / 2.0, middle), wall)  # правая
	var ceiling := _mat(wall.albedo_color, wall.roughness, Color("35376e"), 0.36)
	var ceiling_mesh := _box(Vector3(W, 0.1, depth), Vector3(0, H + 0.05, middle), ceiling)
	ceiling_mesh.layers = CEILING_LAYER
	var carpet := _mat(Color.WHITE, 1.0)
	carpet.albedo_texture = _noise_tex(Color("1c2150"), Color("2c2f6e"), 0.12)
	carpet.uv1_scale = Vector3(6, 4, 1)
	_box(Vector3(W, 0.1, depth), Vector3(0, -0.05, middle), carpet)  # пол
	# плинтус
	_box(Vector3(W, 0.08, 0.02), Vector3(0, 0.04, BACK + 0.01), _mat(Color("d8cff5")))
	_window()
	_stars()
	_posters()
	sticker_board = _make_board(0)


const CITY := "res://hub/art/city.png"
var _city_view: ShaderMaterial
var _city_blend: Tween


## Ночной город (небо, силуэты домов, огни окон) — генерируется один раз (tools/bake_hub.gd) и хранится файлом.
static func city_image(seed_value: int = 90) -> Image:
	var img := Image.create(512, 384, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
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


func _front_city_image() -> Image:
	var source: Texture2D = load(CITY) if ResourceLoader.exists(CITY) else null
	var image := source.get_image() if source != null else city_image()
	if image.is_compressed():
		image.decompress()
	for house: Rect2i in [Rect2i(235, 326, 16, 58), Rect2i(251, 347, 15, 37), Rect2i(270, 315, 16, 69)]:
		image.fill_rect(house, Color("251437"))
		for y in range(house.position.y + 8, house.end.y - 3, 11):
			image.fill_rect(Rect2i(house.position.x + 3, y, 2, 3), Color("e4ad73"))
			image.fill_rect(Rect2i(house.end.x - 5, y + 2, 2, 3), Color("8db2d0"))
	return image


## За боковым окном виден пролёт моста между домами и ближним берегом.
static func side_city_image() -> Image:
	var image := city_image(213)
	var steel := Color("160f32")
	var rim := Color("50436b")
	var amber := Color("ffd17e")
	# Открытое пространство между левой рамой и городской застройкой.
	for y in range(210, 384):
		var sky := Color("251048").lerp(Color("c0447a"), pow(y / 384.0, 2.2))
		image.fill_rect(Rect2i(0, y, 160, 1), sky)
	var deck := 329
	var left_tower := 43
	var right_tower := 77
	var tower_top := 285
	# Опоры и полотно перекрывают дальние дома.
	for x: int in [left_tower, right_tower]:
		image.fill_rect(Rect2i(x - 3, tower_top, 6, 384 - tower_top), steel)
		image.fill_rect(Rect2i(x - 3, tower_top, 1, deck - tower_top), rim)
		image.fill_rect(Rect2i(x - 4, tower_top, 8, 3), steel)
		image.fill_rect(Rect2i(x - 1, tower_top - 2, 2, 2), Color("ff8276"))
	image.fill_rect(Rect2i(0, deck, 97, 7), steel)
	image.fill_rect(Rect2i(0, deck, 97, 1), rim)
	# Несущий трос провисает между опорами. Подвесы идут вертикально до дороги.
	for x in range(97):
		var y: int
		if x < left_tower:
			y = roundi(lerpf(float(deck - 5), float(tower_top + 6), float(x) / left_tower))
		elif x > right_tower:
			y = roundi(lerpf(float(tower_top + 6), float(deck - 5), float(x - right_tower) / (96 - right_tower)))
		else:
			var span := float(x - left_tower) / (right_tower - left_tower)
			y = tower_top + 6 + roundi(23.0 * 4.0 * span * (1.0 - span))
		image.fill_rect(Rect2i(x, y, 1, 3), steel)
		if x % 8 == 0:
			image.fill_rect(Rect2i(x, y + 2, 1, deck - y - 2), rim)
		if x % 7 == 0:
			image.fill_rect(Rect2i(x, deck + 3, 2, 1), amber)
	# Разновысокие силуэты у правого конца моста повторяют рисунок дальних кварталов.
	var houses: Array[Rect2i] = [Rect2i(96, 298, 15, 86), Rect2i(107, 281, 19, 103),
		Rect2i(121, 309, 15, 75), Rect2i(133, 293, 21, 91)]
	var lights := RandomNumberGenerator.new()
	lights.seed = 67
	for house: Rect2i in houses:
		var facade := Color("120a24").lerp(Color("2a1340"), lights.randf())
		image.fill_rect(house, facade)
		for k in range(9):
			var x := lights.randi_range(house.position.x + 2, house.end.x - 3)
			var y := lights.randi_range(house.position.y + 6, house.end.y - 4)
			var color := amber if lights.randf() < 0.7 else Color("8fd8ff")
			image.fill_rect(Rect2i(x, y, 2, 3), color)
	return image


func _window() -> void:
	var c := Vector3(-1.75, 1.62, BACK + 0.02)
	var size := Vector2(1.25, 0.95)
	# Окно с рамой, подоконником и жалюзи выступает от стены до ~0.11 м: доска поверх него висит впереди.
	_wall_decor.append([Rect2(Vector2(c.x, c.y) - size / 2.0 - Vector2(0.07, 0.06), size + Vector2(0.14, 0.12)), BACK + 0.14])
	# ночной город за окном: готовая картинка (hub/art/city.png), если её нет — рисуем на лету
	var tex: Texture2D = ImageTexture.create_from_image(_front_city_image())
	_city_view = ShaderMaterial.new()
	_city_view.shader = preload("res://hub/window_city.gdshader")
	_city_view.set_shader_parameter("side_view", 0.0)
	_city_view.set_shader_parameter("front_city", tex)
	_city_view.set_shader_parameter("side_city", ImageTexture.create_from_image(side_city_image()))
	_quad(size, c, Vector3.ZERO, _city_view)
	var frame := _mat(Color("efe9ff"), 0.6)
	_box(Vector3(size.x + 0.08, 0.05, 0.06), c + Vector3(0, size.y / 2.0, 0.02), frame)
	var sill := _box(Vector3(size.x + 0.12, 0.05, 0.12), c + Vector3(0, -size.y / 2.0, 0.05), frame)
	_window_sill_bounds = sill.transform * sill.get_aabb()
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
	for point: Vector2 in [Vector2(0.32, 2.48), Vector2(0.08, 2.22), Vector2(0.17, 1.94),
			Vector2(-0.12, 2.60), Vector2(-0.32, 1.96), Vector2(-0.37, 2.27),
			Vector2(-0.55, 2.49), Vector2(-0.71, 2.03), Vector2(-0.83, 2.31),
			Vector2(-1.01, 1.89), Vector2(-1.12, 2.55), Vector2(-1.25, 1.55),
			Vector2(-1.30, 2.16), Vector2(-1.58, 2.38), Vector2(-1.72, 1.94), Vector2(-1.80, 2.59),
			Vector2(-0.95, 1.41), Vector2(-0.57, 1.51), Vector2(-0.33, 1.37)]:
		var star := _glow_label("★", Vector3(-W * 0.5 + 0.055, point.y, point.x), rng.randi_range(40, 70), Color("7dffc8"), "regular", 0.0016)
		star.rotation.y = PI * 0.5
		star.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.6, 0.6))
		star.modulate = Color(0.55, 1.1, 0.85)
	var moon := _glow_label("☾", Vector3(-0.85, 1.42, BACK + 0.005), 70, Color("7dffc8"), "regular", 0.0016)
	moon.modulate = Color(0.55, 1.1, 0.85)


## Три плаката — отдельные узлы (hub/wall_poster.gd): их можно перевесить и заменить своей картинкой.
const POSTER_LAYER := 0.005  # м между слоями плакатов (до 12 плакатов — не дальше 6 см от стены)
const POSTER_DEFAULTS := [
	["res://games/ready_set_bet/art/cover.jpg", Vector2(1.05, 1.55), 0.03],
	["res://hub/art/posters/coin_heap.png", Vector2(1.62, 1.66), -0.04],
	["res://games/stillion/art/bg_circus_approved.png", Vector2(2.15, 1.5), 0.02],
]


func _posters() -> void:
	# Узлы для всех возможных плакатов (hub/stickers.gd: POSTERS_MAX); добавленные игроком (номер 3+) пока скрыты.
	for i in preload("res://hub/stickers.gd").POSTERS_MAX:
		var entry: Array = POSTER_DEFAULTS[i % POSTER_DEFAULTS.size()]
		var poster: Node3D = preload("res://hub/wall_poster.gd").new()
		poster.setup(i, str(entry[0]), float(entry[2]) * (1.0 if i < POSTER_DEFAULTS.size() else -0.7))
		poster.visible = i < POSTER_DEFAULTS.size()
		add_child(poster)
		var at: Vector2 = entry[1]
		poster.position = Vector3(at.x, at.y, BACK + 0.012)
		posters.append(poster)


## Какие плакаты висят (номера); остальные скрыты и не ловят клики.
func show_posters(slots: Array) -> void:
	for slot in posters.size():
		var poster: Node3D = posters[slot]
		var on := slots.has(slot)
		if poster.visible != on:
			if not on and poster == poster_dragging:
				_end_poster_drag()
			poster.set_shown(on)


## Новая доска друзей (узел); положение задаёт set_board_position.
func _make_board(bid: int) -> Node3D:
	var board: Node3D = preload("res://hub/sticker_board.gd").new()
	board.board_id = bid
	board.position = BOARD_AT
	board.set_meta("fresh", true)  # первое размещение — сразу на место, без проезда через стену
	add_child(board)
	boards[bid] = board
	return board


## Доски в комнате на экране — ровно эти номера (своя комната или комната друга).
func sync_boards(ids: Array) -> void:
	for bid: Variant in boards.keys():
		if not ids.has(int(bid)):
			var board: Node3D = boards[bid]
			if board == sticker_board and board_dragging:
				board_dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			boards.erase(bid)
			_board_homes.erase(bid)
			board.queue_free()
	for bid: Variant in ids:
		if not boards.has(int(bid)):
			_make_board(int(bid))
	if not is_instance_valid(sticker_board) or not boards.values().has(sticker_board):
		sticker_board = boards[ids[0]] if not ids.is_empty() else null


## Кнопка доски в редакторе шкафа: ещё одна пустая доска друзей на свободном месте стены.
func add_friend_board() -> void:
	var bid: int = Net.stickers.add_board(free_wall_spot(BOARD_EXTENT))
	if bid >= 0:
		Sfx.play("card_place", -6, 0.08)
		shelf_hint.emit("Новая доска друзей · её можно перевесить, а удержанием — снять")


func active_board_id() -> int:
	return int(sticker_board.board_id) if is_instance_valid(sticker_board) else -1


## Доска под курсором (или null).
func _board_at(point: Vector2) -> Node3D:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 20, 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or str(hit.collider.get_meta("room_prop", "")) != "board":
		return null
	return boards.get(int(hit.collider.get_meta("board_id", 0)), null)


## Свободное место на стене для новой доски/плаката размера extent: не на шкафу, окне, других досках и плакатах.
func free_wall_spot(extent: Vector2) -> Vector2:
	var taken: Array = [shelf_wall_rect()]
	for decor: Array in _wall_decor:
		taken.append(decor[0])
	for board: Variant in boards.values():
		if is_instance_valid(board):
			taken.append(Rect2(Vector2(board.position.x, board.position.y) - BOARD_EXTENT / 2.0, BOARD_EXTENT))
	for poster: Node3D in posters:
		if poster.visible:
			taken.append(poster.wall_rect())
	var best := Vector2(0.0, 1.6)
	var best_hits := 1 << 20
	for row: float in [1.6, 1.1, 2.05, 0.75]:
		for step in 11:
			var x := (float(step) - 5.0) * 0.46
			var spot := Vector2(clampf(x, -W / 2.0 + extent.x / 2.0 + 0.05, W / 2.0 - extent.x / 2.0 - 0.05), row)
			var rect := Rect2(spot - extent / 2.0, extent).grow(0.03)
			var hits := 0
			for other: Rect2 in taken:
				if other.size != Vector2.ZERO and rect.intersects(other):
					hits += 1
			if hits < best_hits:
				best_hits = hits
				best = spot
			if hits == 0:
				return spot
	return best


# --- Мебель ---------------------------------------------------------------------------

func _furniture() -> void:
	# кровать вдоль левой стены: каркас, матрас, одеяло, подушка
	_soft(Vector3(1.0, 0.26, 2.1), Vector3(-2.45, 0.13, BACK + 1.05), "wood_dark", Color("3a2a66"))
	_soft(Vector3(0.96, 0.14, 2.0), Vector3(-2.45, 0.33, BACK + 1.05), "fabric", Color("d8d2ff"), self, Vector3.ZERO, 0.05)
	_soft(Vector3(1.04, 0.09, 1.5), Vector3(-2.45, 0.43, BACK + 1.38), "fabric", Color("5a55e0"), self, Vector3(0, 0, 0.02), 0.04)
	_soft(Vector3(0.66, 0.12, 0.34), Vector3(-2.45, 0.46, BACK + 0.26), "fabric", Color("c9c3ff"), self, Vector3(0.12, 0, 0), 0.055)
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
	var clock := _glow_label("00:00", Vector3(-1.617, 0.545, BACK + 0.342), 32, Color("ff3030"), "pixel", 0.0008)
	_alarm_clock = clock
	_update_alarm_clock()
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
	_tv_corner(TV_X)
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
	title.text = "РЕДАКТОР"
	title.add_theme_font_override("font", HubStyle.font("pixel"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(510, 60)
	title.position = Vector2(0, 124)
	vp.add_child(title)
	_blink = Label.new()
	_blink.text = "СОЗДАТЬ ИГРУ"
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
	_vcr_clock = led
	var room_prefs := ConfigFile.new()
	if room_prefs.load("user://room_props.cfg") == OK:
		_vcr_time = maxi(0, VCR_TIMES.find(str(room_prefs.get_value("room", "vcr_time", "0:00"))))
	led.text = VCR_TIMES[_vcr_time]
	_add_room_prop("vcr", Vector3(tv_x + 0.05, 0.38, z + 0.02), Vector3(0.42, 0.09, 0.3))
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
	_ball_make()
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
	var cups: Array = HubGames.all().filter(func(g): return g["id"] == "perudo")
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
	# Пользовательские коробки передаём общему упаковщику ShelfConfig вместе со встроенными.
	for game: Dictionary in HubGames.all():
		if not game.get("custom", false):
			continue
		var custom_box: GameBox = make.call(game, n)
		n += 1
		_shelf_root.add_child(custom_box)
		boxes.append(custom_box)
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
	# Фигурки из Tripo AI (ShelfFigurine.TRIPO) встают на свободное место, как новая игра (нет места — шкаф расширяется).
	for fig: Array in [["shelf_mummy", "Мумия", Vector3(0.17, 0.25, 0.13) / 1.5], ["shelf_fighter", "Боец", Vector3(0.14, 0.26, 0.16)], ["shelf_anime", "Девочка", Vector3(0.19, 0.27, 0.2) / 1.5]]:
		var item := ShelfFigurine.new()
		item.game = {"id": fig[0], "title": fig[1], "shelf": false}
		item.size = fig[2]
		_shelf_root.add_child(item)
		boxes.append(item)


func _shelf_id(box: GameBox) -> String:
	return str(box.get_meta("shelf_id", str(box.game.id)))


func _shelf_sizes() -> Dictionary:
	var sizes: Dictionary = {}
	for box: GameBox in boxes:
		sizes[_shelf_id(box)] = _figure_cabinet_extent(box) if box.is_figurine() else box.size
	return sizes


func _shelf_ids() -> Array:
	var ids: Array = _rows.map(func(row): return (row as Array).map(func(box): return _shelf_id(box)))
	# выдвинутая коробка числится на прежнем месте: сохранение и снимок для друзей её не теряют
	if _lift_box != null and _drag_box == null and _lift_from.x >= 0 and _lift_from.x < ids.size():
		var cell_ids: Array = ids[_lift_from.x]
		cell_ids.insert(mini(_lift_from.y, cell_ids.size()), _shelf_id(_lift_box))
	return ids


func _box_extent(box: GameBox) -> Vector3:
	return ShelfConfig.item_extent(_shelf_id(box), box.size, int(_box_modes.get(_shelf_id(box), 1)))


func _box_basis(box: GameBox) -> Basis:
	if box.is_figurine():
		return Basis(Vector3.UP, float(_cabinet.get("figure_yaw", {}).get(_shelf_id(box), 0.0)))
	return ShelfConfig.item_basis(_shelf_id(box), int(_box_modes.get(_shelf_id(box), 1)))


## Радиус охватывает фигурку при любом развороте: углы не заходят на куб или лампу.
func _figure_cabinet_extent(box: GameBox) -> Vector3:
	var orientation := _box_basis(box)
	return orientation.x.abs() * box.size.x + orientation.y.abs() * box.size.y + orientation.z.abs() * box.size.z


func _figure_radius(box: GameBox) -> float:
	return Vector2(box.size.x, box.size.z).length() * 0.5


## Места для фигурок вне шкафа: верх телевизора и тумба по бокам от него, верх шкафа.
const FIGURE_SURFACES := ["tv", "stand_left", "stand_right", "cabinet"]
const WALL_SHELVES := {"wall_lower": 1.10, "wall_upper": 1.72}
const WALL_SHELF_DEPTH := 0.45
const WALL_SHELF_BACK := -1.84
const WALL_SHELF_FRONT := 0.05
var _wall_shelf_lights: Dictionary = {}


var _looking_left := false
var _ball_camera_paused := false
var _transfer_button: Button


func left_wall_view() -> bool:
	return _looking_left


func can_turn_room() -> bool:
	return not remote_view and not _editor_on and not board_focused() and focused == null and _drag_box == null and not _ball_held


func look_left_wall(on: bool) -> void:
	if not can_turn_room() or _looking_left == on:
		return
	_clear_shelf_selection()
	_looking_left = on
	if on:
		_ball_camera_paused = true
	if is_instance_valid(_city_view):
		if _city_blend != null and _city_blend.is_valid():
			_city_blend.kill()
		_city_blend = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var blend := float(_city_view.get_shader_parameter("side_view"))
		_city_blend.tween_method(_set_city_blend, blend, 1.0 if on else 0.0, 0.22)
	var previous := camera.transform
	_frame_shelf()
	camera.transform = previous


func _set_city_blend(value: float) -> void:
	_city_view.set_shader_parameter("side_view", value)


func _wall_door() -> void:
	var section := Node3D.new()
	add_child(section)
	var wall_left := -W * 0.5 + 0.05
	var jamb := wall_left + 0.33
	var face_z := ROOM_FRONT
	var width := 0.83
	var height := 2.07
	var wall_right := W * 0.5 - 0.05
	var wall := _mat(Color("7f6bc4"), 0.95)
	var trim := _mat(Color("382446"))
	var leaf := _mat(Color("634454"), 0.85, Color("633b29"), 0.26)
	var recess := _mat(Color("8e7362"), 1.0)
	# Стена собрана вокруг проёма. Утопленная заглушка за створкой скрывает пространство за дверью.
	_box(Vector3(jamb - wall_left, H, 0.12), Vector3((wall_left + jamb) * 0.5, H * 0.5, face_z), wall, section)
	_box(Vector3(wall_right - jamb - width, H, 0.12), Vector3((jamb + width + wall_right) * 0.5, H * 0.5, face_z), wall, section)
	_box(Vector3(width, H - height, 0.12), Vector3(jamb + width * 0.5, (H + height) * 0.5, face_z), wall, section)
	# Короткая ниша за дверью принимает свет лампы и закрывает обзор дальше проёма.
	var recess_depth := 1.18
	# Откосы начинаются за рамой, чтобы совпадающие поверхности не мерцали.
	var recess_center := Vector3(jamb + width * 0.5, 0.0, face_z + 0.064 + recess_depth * 0.5)
	for x: float in [jamb - 0.040, jamb + width + 0.040]:
		_box(Vector3(0.07, H, recess_depth), Vector3(x, H * 0.5, recess_center.z), recess, section)
	_box(Vector3(width, 0.07, recess_depth), recess_center + Vector3(0, H + 0.035, 0), recess, section)
	_box(Vector3(width, 0.06, recess_depth + 0.064), recess_center - Vector3(0, 0.03, 0.032), recess, section)
	_box(Vector3(width, H, 0.05), recess_center + Vector3(0, H * 0.5, recess_depth * 0.5), recess, section)
	# Наличники выступают перед плоскостью стены. Вертикальные планки заканчиваются у нижней грани верхней.
	var trim_depth := 0.024
	var trim_front := face_z - 0.060 - trim_depth * 0.5
	var jamb_height := height - 0.035
	for x: float in [jamb, jamb + width]:
		_box(Vector3(0.07, jamb_height, trim_depth), Vector3(x, jamb_height * 0.5, trim_front), trim, section)
	_box(Vector3(width + 0.07, 0.07, trim_depth), Vector3(jamb + width * 0.5, height, trim_front), trim, section)
	var hinge := Node3D.new()
	section.add_child(hinge)
	hinge.position = Vector3(jamb + width - 0.035, 0.025, face_z - 0.02)
	hinge.rotation.y = -0.27
	_box(Vector3(width - 0.075, height - 0.08, 0.055), Vector3(-(width - 0.075) * 0.5, (height - 0.08) * 0.5, 0.0), leaf, hinge)
	_box(Vector3(0.075, 0.02, 0.05), Vector3(-width + 0.19, 0.97, -0.045), _mat(Color("bb8d52"), 0.38), hinge)
	var bulb := OmniLight3D.new()
	section.add_child(bulb)
	bulb.position = Vector3(jamb + 0.29, height + 0.12, face_z + 0.46)
	bulb.light_color = Color("ff781f")
	bulb.light_energy = 2.45
	bulb.light_cull_mask = 0xffffffff & ~CEILING_LAYER
	bulb.omni_range = 3.8
	bulb.omni_attenuation = 1.1
	bulb.shadow_enabled = true
	bulb.shadow_blur = 2.8
	for mesh: MeshInstance3D in section.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = FRONT_WALL_LAYER


func _wall_shelves() -> void:
	var center_x := -W * 0.5 + 0.05 + WALL_SHELF_DEPTH * 0.5
	var length := WALL_SHELF_FRONT - WALL_SHELF_BACK
	var line_material := _mat(Color("a2a7c1"), 0.5)
	for surface: String in WALL_SHELVES:
		var top: float = WALL_SHELVES[surface]
		_soft(Vector3(WALL_SHELF_DEPTH, BOARD, length),
			Vector3(center_x, top - BOARD * 0.5, WALL_SHELF_BACK + length * 0.5),
			"wood_dark", Color("2a1d42"), self)
		var edge := Vector3(center_x + WALL_SHELF_DEPTH * 0.5 - 0.018, top, WALL_SHELF_FRONT - 0.025)
		var anchor := Vector3(-W * 0.5 + 0.055, top + 0.32, edge.z)
		var line := _cyl(0.002, 0.002, edge.distance_to(anchor), (edge + anchor) * 0.5, line_material)
		line.basis = Basis(Quaternion(Vector3.UP, (anchor - edge).normalized()))
		_wall_shelf_light(surface, top, center_x, length)


func _wall_shelf_light(surface: String, top: float, center_x: float, length: float) -> void:
	var center_z := WALL_SHELF_BACK + length * 0.5
	var edge_x := center_x + WALL_SHELF_DEPTH * 0.5 - 0.012
	var tint := Color("f9cda4")
	var strip := _box(Vector3(0.011, 0.004, length - 0.065),
		Vector3(edge_x, top + 0.002, center_z), _mat(tint, 0.55, tint, 1.15))
	var lights: Array[SpotLight3D] = []
	for i in 5:
		var lamp := SpotLight3D.new()
		add_child(lamp)
		lamp.position = Vector3(edge_x + 0.030, top + 0.025, WALL_SHELF_BACK + length * (float(i) + 0.5) / 5.0)
		lamp.look_at(lamp.position + Vector3(-0.74, 1.0, 0.0))
		lamp.light_color = tint
		lamp.light_energy = 0.36
		lamp.light_specular = 0.15
		lamp.light_cull_mask = 0xffffffff & ~LEFT_WALL_LAYER
		lamp.spot_range = 0.60
		lamp.spot_angle = 52.0
		lamp.spot_angle_attenuation = 0.8
		lights.append(lamp)
	# Стена получает сплошной горизонтальный отсвет, а предметы — направленный свет снизу.
	var wash := _wall_shelf_wash(top, center_z, length, tint)
	_wall_shelf_lights[surface] = {"strip": strip, "wash": wash, "lights": lights, "on": true}
	_add_room_prop(surface, Vector3(center_x, top - BOARD * 0.5, center_z),
		Vector3(WALL_SHELF_DEPTH, BOARD + 0.025, length))
	var prefs := ConfigFile.new()
	prefs.load("user://room_props.cfg")
	_set_wall_shelf_light(surface, bool(prefs.get_value("shelf_lights", surface, true)))


func _wall_shelf_wash(top: float, center_z: float, length: float, tint: Color) -> Node3D:
	var wash := Node3D.new()
	add_child(wash)
	var height := 0.60
	var wall_x := -W * 0.5 + 0.052
	var corner_z := BACK + 0.005
	var near_z := center_z + length * 0.5 + 0.52
	var strip_x := wall_x + WALL_SHELF_DEPTH - 0.014
	var emitter := Vector3(strip_x, top + 0.006, center_z)
	# У каждой стены своя нормаль. Освещённость меняется на стыке так же, как у площадного источника.
	var main_center := Vector3(wall_x, top + height * 0.5, (near_z + corner_z) * 0.5)
	var main_width := near_z - corner_z
	_add_shelf_wash_plane(wash, main_center, Vector3.FORWARD, Vector3.RIGHT, main_width, height, emitter, length, tint)
	var return_width := 0.76
	var return_center := Vector3(wall_x + return_width * 0.5, main_center.y, corner_z)
	_add_shelf_wash_plane(wash, return_center, Vector3.RIGHT, Vector3.BACK, return_width, height, emitter, length, tint)
	return wash


func _add_shelf_wash_plane(parent: Node3D, center: Vector3, horizontal: Vector3, normal: Vector3,
		width: float, height: float, emitter: Vector3, length: float, tint: Color) -> void:
	var image := Image.create(144, 64, false, Image.FORMAT_RGBA8)
	var aim := Vector3(-0.61, 0.79, 0.0).normalized()
	const SAMPLES := 24
	var step := (length - 0.065) / SAMPLES
	for y in image.get_height():
		var up := 1.0 - float(y) / float(image.get_height() - 1)
		var vertical := lerpf(0.21, 1.0, smoothstep(0.0, 0.035, up)) * (1.0 - smoothstep(0.52, 1.0, up))
		for x in image.get_width():
			var u := float(x) / float(image.get_width() - 1)
			var point := center + horizontal * (width * (u - 0.5)) + Vector3.UP * (height * (up - 0.5))
			var received := 0.0
			for i in SAMPLES:
				var sample := emitter + Vector3.BACK * (step * (float(i) + 0.5 - SAMPLES * 0.5))
				var ray := point - sample
				var distance_squared := ray.length_squared()
				var direction := ray / sqrt(distance_squared)
				var beam := smoothstep(0.44, 0.96, aim.dot(direction))
				received += beam * maxf(0.0, -normal.dot(direction)) * step / distance_squared
			var end_distance := width * (u if normal == Vector3.RIGHT else 1.0 - u)
			var outer_fade := smoothstep(0.0, 0.20, end_distance)
			var base_light := 0.035 * (1.0 - smoothstep(0.0, 0.16, up)) * minf(received, 1.0)
			var alpha := ((1.0 - exp(-received * 0.15)) * vertical + base_light) * outer_fade
			image.set_pixel(x, y, Color(tint, alpha))
	var material := ShaderMaterial.new()
	material.shader = preload("res://hub/shelf_wash.gdshader")
	material.set_shader_parameter("wash_texture", ImageTexture.create_from_image(image))
	material.set_shader_parameter("shelf_wall", normal == Vector3.RIGHT)
	var rotation := Vector3(0.0, PI * 0.5, 0.0) if normal == Vector3.RIGHT else Vector3.ZERO
	var plane := _quad(Vector2(width, height), center, rotation, material, parent)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _set_wall_shelf_light(surface: String, on: bool) -> void:
	var shelf: Dictionary = _wall_shelf_lights[surface]
	shelf.on = on
	var strip: MeshInstance3D = shelf.strip
	var material := strip.material_override as StandardMaterial3D
	material.emission_enabled = on
	material.albedo_color = Color("f9cda4") if on else Color("423746")
	(shelf.wash as Node3D).visible = on
	for lamp: SpotLight3D in shelf.lights:
		lamp.visible = on
	var anchors: Dictionary = _cabinet.get("figure_surfaces", {})
	for box: GameBox in boxes:
		var anchor: Dictionary = anchors.get(_shelf_id(box), {})
		if anchor.get("surface", "") == surface:
			box.set_wall_shelf_finish(on)


func _toggle_wall_shelf_light(surface: String) -> void:
	var on := not bool(_wall_shelf_lights[surface].on)
	_set_wall_shelf_light(surface, on)
	var prefs := ConfigFile.new()
	prefs.load("user://room_props.cfg")
	prefs.set_value("shelf_lights", surface, on)
	prefs.save("user://room_props.cfg")
	shelf_hint.emit("Подсветка полки включена" if on else "Подсветка полки выключена")


func _wall_item_extent(box: GameBox) -> Vector3:
	if box.is_figurine():
		var diameter := 2.0 * _figure_radius(box)
		return Vector3(diameter, box.size.y, diameter) * SHELF_SCALE
	var ext := _box_extent(box) * SHELF_SCALE
	return Vector3(ext.z, ext.y, ext.x)


func _wall_span(box: GameBox, surface: String) -> Array[Vector3]:
	var ext := _wall_item_extent(box)
	var edge := -W * 0.5 + 0.05 + WALL_SHELF_DEPTH
	var setback := 0.025 if box.is_figurine() else minf(0.067, WALL_SHELF_DEPTH - ext.x)
	var x := edge - setback - ext.x * 0.5
	var y := float(WALL_SHELVES[surface]) + ext.y * 0.5
	var inset := ext.z * 0.5 + 0.025
	return [Vector3(x, y, WALL_SHELF_BACK + inset), Vector3(x, y, WALL_SHELF_FRONT - inset)]


func _wall_home(box: GameBox, anchor: Dictionary) -> Transform3D:
	var span := _wall_span(box, str(anchor.surface))
	var point := span[0].lerp(span[1], float(anchor.x))
	return Transform3D(_box_basis(box).rotated(Vector3.UP, PI * 0.5), _shelf_root.to_local(point))


func _wall_item_fits(box: GameBox, surface: String, point_z: float) -> bool:
	var ext := _wall_item_extent(box)
	if ext.x > WALL_SHELF_DEPTH - 0.025 or ext.z + 0.05 >= WALL_SHELF_FRONT - WALL_SHELF_BACK:
		return false
	if surface == "wall_lower" and ext.y > float(WALL_SHELVES.wall_upper) - float(WALL_SHELVES.wall_lower) - BOARD:
		return false
	for other: GameBox in boxes:
		if other == box:
			continue
		var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(other), {})
		if anchor.get("surface", "") != surface:
			continue
		var other_z := _shelf_root.to_global(_wall_home(other, anchor).origin).z
		if absf(point_z - other_z) < (ext.z + _wall_item_extent(other).z) * 0.5 + 0.008:
			return false
	return true


func _wall_drop(screen: Vector2) -> bool:
	for surface: String in WALL_SHELVES:
		var span := _wall_span(_drag_box, surface)
		if span[1].z <= span[0].z:
			continue
		var a := camera.unproject_position(span[0])
		var b := camera.unproject_position(span[1])
		var segment := b - a
		var screen_share := clampf((screen - a).dot(segment) / maxf(0.001, segment.length_squared()), 0.0, 1.0)
		if screen.distance_to(a.lerp(b, screen_share)) > 32.0:
			continue
		var ray := camera.project_ray_normal(screen)
		if absf(ray.x) < 0.0001:
			continue
		var origin := camera.project_ray_origin(screen)
		var z := origin.z + ray.z * ((span[0].x - origin.x) / ray.x)
		var share := clampf(inverse_lerp(span[0].z, span[1].z, z), 0.0, 1.0)
		var point := span[0].lerp(span[1], share)
		var fits := _wall_item_fits(_drag_box, surface, point.z)
		_drag_surface = {"surface": surface, "x": share}
		_drag_at = _shelf_root.to_local(point)
		_drag_to = _drag_from if fits else Vector2i(-1, -1)
		_drag_cascade = []
		_reflow(true)
		_drag_box.set_swap_highlight(true, fits)
		Input.set_default_cursor_shape(Input.CURSOR_DRAG if fits else Input.CURSOR_FORBIDDEN)
		shelf_hint.emit("Отпустите, чтобы поставить на полку" if fits else "Здесь предмет не помещается")
		return true
	return false
const TV_X := 1.6  # телевизор и тумба (_tv_corner)
const STAND_TOP := 0.6325  # верх тумбы под телевизором
const STAND_HALF := 0.43  # полуширина крышки тумбы
const TV_HALF := 0.3  # полуширина корпуса телевизора


func _figure_surface_span(box: GameBox, surface: String) -> Array[Vector3]:
	var radius := _figure_radius(box)
	if surface in ["stand_left", "stand_right"]:
		# тумба рядом с телевизором: полоска между краем крышки и корпусом; по диагонали
		# фигурка не влезает — берём её круглую подставку (0.06)
		var inv := _shelf_root.global_transform.affine_inverse()
		var r := 0.06 * SHELF_SCALE + 0.004
		var y := STAND_TOP + box.size.y * SHELF_SCALE * 0.5
		var z := BACK + 0.44
		if surface == "stand_left":
			return [inv * Vector3(TV_X - STAND_HALF + r, y, z), inv * Vector3(TV_X - TV_HALF - r, y, z)]
		return [inv * Vector3(TV_X + TV_HALF + r, y, z), inv * Vector3(TV_X + STAND_HALF - r, y, z)]
	if surface == "tv":
		# Левая часть верха телевизора свободна от лавовой лампы справа.
		var inv := _shelf_root.global_transform.affine_inverse()
		return [inv * Vector3(1.30 + radius * SHELF_SCALE, 1.095 + box.size.y * SHELF_SCALE * 0.5, BACK + 0.39),
			inv * Vector3(1.68 - radius * SHELF_SCALE, 1.095 + box.size.y * SHELF_SCALE * 0.5, BACK + 0.39)]
	var full_width: float = ShelfConfig.full_width(_cabinet)
	var top: float = 0.06 + ShelfConfig.full_height(_cabinet)
	return [Vector3(SHELF_X - full_width * 0.5 + radius + 0.008, top + box.size.y * 0.5, BACK + 0.21),
		Vector3(SHELF_X + full_width * 0.5 - 0.07 - 0.055 / SHELF_SCALE - radius - 0.008, top + box.size.y * 0.5, BACK + 0.21)]


func _figure_surface_position(box: GameBox, surface: String, fraction: float) -> Vector3:
	var span := _figure_surface_span(box, surface)
	return span[0].lerp(span[1], clampf(fraction, 0.0, 1.0))


func _rotate_figure(direction: int) -> void:
	if remote_view or _selected_box == null or not _selected_box.is_figurine():
		return
	if not _cabinet.has("figure_yaw"):
		_cabinet.figure_yaw = {}
	var id := _shelf_id(_selected_box)
	var previous := float(_cabinet.figure_yaw.get(id, 0.0))
	_cabinet.figure_yaw[id] = wrapf(previous + direction * PI / 12.0, -PI, PI)
	if not _cabinet.get("figure_surfaces", {}).has(id):
		for cell in _rows.size():
			if (_rows[cell] as Array).has(_selected_box) and (_figure_cabinet_extent(_selected_box).z > CELL_D + 0.0005 or _row_overflows(_rows[cell], cell)):
				_cabinet.figure_yaw[id] = previous
				shelf_hint.emit("В этом положении фигурке тесно")
				return
	_reflow(false)
	if not _editor_on:
		_save_shelf()
	shelf_hint.emit("Колесо мыши ↕, Q, E — повернуть · удерживайте ЛКМ для переноса")


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
	_lift_box = null  # состояние задаёт места всех коробок, выдвинутая тоже встаёт по нему
	_cabinet = state.config.duplicate(true)
	_box_modes = state.poses.duplicate(true)
	var by_id: Dictionary = {}
	for box: GameBox in boxes:
		by_id[_shelf_id(box)] = box
	_rows = []
	for ids: Array in state.placements:
		_rows.append(ids.map(func(id): return by_id[id]))
	_rebuild_shelf_geometry()


func _rebuild_shelf_geometry() -> void:
	_hover = null
	for box: GameBox in boxes:
		box.stop_shelf_motion()
	for child in _shelf_root.get_children():
		if child is GameBox and boxes.has(child):
			continue
		# В комнате друга свои коробки игрока спрятаны (их нет в boxes), но вернутся при возврате домой:
		# их не удаляем, иначе дома ссылки на удалённые коробки (ошибки, а в сборке — краш).
		if child is GameBox and not _local_room.is_empty() and (_local_room.boxes as Array).has(child):
			continue
		_shelf_root.remove_child(child)
		child.queue_free()
	var rows: int = int(_cabinet.rows)
	# Шкаф по ячейкам (ShelfConfig.shelf_cells): перегородки у каждого ряда свои, полки — по ячейкам,
	# поэтому объединённые ячейки (без перегородки или без куска полки) строятся как есть.
	var cells: Array = ShelfConfig.shelf_cells(_cabinet)
	var full_width: float = ShelfConfig.full_width(_cabinet)
	var full_height: float = ShelfConfig.full_height(_cabinet)
	var base_y := 0.06
	var z: float = BACK + CELL_D * 0.5 + 0.01
	var left: float = SHELF_X - full_width * 0.5
	var inner_left := left + BOARD
	var inner_width: float = full_width - 2 * BOARD
	var level_y: Array = []  # низ каждой доски-полки снизу вверх (уровень 0 — дно)
	var y_cursor := base_y
	for level in rows + 1:
		level_y.append(y_cursor)
		if level < rows:
			y_cursor += BOARD + ShelfConfig.row_height(_cabinet, rows - 1 - level)
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
	for side in [-1.0, 1.0]:
		_soft(
			Vector3(BOARD, full_height, CELL_D),
			Vector3(SHELF_X + side * (full_width - BOARD) * 0.5, base_y + full_height * 0.5, z),
			"wood_dark",
			wood,
			_shelf_root
		)
	var strip := _mat(Color("ff3ea5"), 0.3, Color("ff3ea5"), 2.6)
	var shelf_board := func(x0: float, x1: float, level: int) -> void:
		var y: float = float(level_y[level]) + BOARD * 0.5
		_soft(Vector3(x1 - x0, BOARD, CELL_D), Vector3((x0 + x1) * 0.5, y, z), "wood_dark", wood, _shelf_root)
		_box(
			Vector3(maxf(0.01, x1 - x0 - 0.02), 0.005, 0.005),
			Vector3((x0 + x1) * 0.5, y + BOARD * 0.5 - 0.004, z + CELL_D * 0.5 + 0.002),
			strip,
			_shelf_root
		)
	shelf_board.call(left, left + full_width, 0)
	shelf_board.call(left, left + full_width, rows)
	_row_info = []
	_shelf_placeholders = {}
	for cell in cells.size():
		var c: Dictionary = cells[cell]
		var row: int = int(c.row)
		var bottom_row: int = row + int(c.span) - 1
		var width: float = float(c.w)
		var height: float = ShelfConfig.cell_height(_cabinet, cell)
		var x: float = inner_left + float(c.x)
		var floor_y: float = float(level_y[rows - 1 - bottom_row]) + BOARD
		# перегородка справа — только на высоту этой ячейки
		if float(c.x) + width < inner_width - 0.002:
			_soft(Vector3(BOARD, height, CELL_D), Vector3(x + width + BOARD * 0.5, floor_y + height * 0.5, z), "wood_dark", wood, _shelf_root)
		# кусок полки под ячейкой (кроме дна) — от середины левой перегородки до середины правой
		if bottom_row < rows - 1:
			shelf_board.call(x - BOARD * 0.5, x + width + BOARD * 0.5, rows - 1 - bottom_row)
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
			bottom_row == ROWS - 1
			and absf(float(c.x)) < 0.002
			and cell < _rows.size()
			and (_rows[cell] as Array).is_empty()
			and cell != int(_cabinet.cups)
		):
			_make_shelf_placeholder(cell, x, floor_y, width, height, bottom_row == rows - 1)
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
	if remote_view:
		return ERR_UNAUTHORIZED
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
	if not ShelfConfig.has_cells(proposed):
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
	if not ShelfConfig.has_cells(proposed) and (
		not is_equal_approx(float(proposed.width), float(result.config.width))
		or not is_equal_approx(float(proposed.height), float(result.config.height))
	):
		return "Достигнут предел размера шкафа: оставлено место для тумбы, скейтборда и куба."
	return ""


func _frame_shelf() -> void:
	if not is_instance_valid(camera):
		return
	if _looking_left and not remote_view and not _editor_on:
		_cam_home = Transform3D(Basis.IDENTITY, Vector3(0.19, 1.44, -1.15)).looking_at(Vector3(-2.70, 1.33, -0.43))
		return
	var width: float = ShelfConfig.full_width(_cabinet) * SHELF_SCALE
	var height: float = ShelfConfig.full_height(_cabinet) * SHELF_SCALE
	# Кадр зависит только от шкафа: куда поставили фигурку (ТВ, верх шкафа, ячейка), камеру не двигает.
	var aspect: float = (
		get_viewport().get_visible_rect().size.x / maxf(1, get_viewport().get_visible_rect().size.y)
	)
	var tangent: float = tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var distance: float = maxf(
		1.7,
		maxf(
			(height + 0.18) / (2 * tangent * 0.80),
			width / (2 * tangent * aspect * 0.86)
		)
	)
	var aim: Vector3 = (
		_shelf_root.global_transform * Vector3(SHELF_X, 0.06 + height / (2 * SHELF_SCALE), BACK + 0.18)
	)
	camera.global_position = aim + Vector3(0, 0.03, distance)
	camera.look_at(aim)
	_cam_home = camera.transform


## Масштаб меняет угол обзора, сохраняя точку съёмки и перспективу комнаты.
func _shelf_camera_fov() -> float:
	if _looking_left and not remote_view and not _editor_on and not board_focused():
		return 56.0
	if board_focused():
		return CAMERA_FOV
	var zoom := _remote_zoom if remote_view else Prefs.shelf_camera_zoom
	var tangent := tan(deg_to_rad(CAMERA_FOV) * 0.5) / zoom
	if not (remote_view and _remote_editor):
		# Оставляем запас под габариты куба и покачивание камеры. Старая настройка
		# сохраняется, но кадр не может закрыть единственный вход в редактор.
		var point := _cam_home.affine_inverse() * shelf_top_right
		var depth := maxf(0.1, -point.z - 0.12)
		var viewport_size := get_viewport().get_visible_rect().size
		var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
		var vertical := (absf(point.y) + 0.14) / depth
		var horizontal := (absf(point.x) + 0.14) / (depth * maxf(0.1, aspect))
		tangent = maxf(tangent, maxf(vertical, horizontal))
	return rad_to_deg(2.0 * atan(tangent))


func reset_shelf_camera() -> void:
	if remote_view:
		return
	Prefs.shelf_camera_zoom = 1.0
	Prefs.save()
	if is_instance_valid(_editor_ui):
		_editor_ui.call("sync_zoom")
	shelf_hint.emit("Приближение камеры сброшено")


func set_shelf_camera_zoom(value: float) -> void:
	if not _editor_on or remote_view:
		return
	Prefs.shelf_camera_zoom = clampf(value, Prefs.SHELF_ZOOM_MIN, Prefs.SHELF_ZOOM_MAX)


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
	_pose_button.pressed.connect(func():
		if is_instance_valid(_selected_box) and _selected_box.is_figurine():
			_rotate_figure(1)
		else:
			_cycle_box_pose())
	add_child(_pose_button)
	_transfer_button = HubStyle.button("", 14)
	_transfer_button.custom_minimum_size = Vector2(46, 44)
	_transfer_button.hide()
	_transfer_button.pressed.connect(_transfer_selected)
	add_child(_transfer_button)


func open_shelf_editor() -> void:
	if remote_view:
		return
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
	_undo_stack = []
	_undo_last = _editor_state()
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
	Prefs.save()
	_editor_on = false
	panels.input_locked = false
	_edge_overlay.visible = false
	_editor_ui.queue_free()
	_editor_ui = null
	_frame_shelf()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	editor_mode_changed.emit(false)


func _cycle_box_pose() -> void:
	if remote_view:
		return
	if _selected_box == null or _selected_box.is_figurine() or _drag_box != null:
		return
	var id := _shelf_id(_selected_box)
	var old: int = int(_box_modes.get(id, 1))
	_box_modes[id] = (1 - old) if _selected_box.is_cups() else (old + 1) % 4
	if _selected_box == _lift_box:
		# выдвинутую коробку крутят свободно: поместится ли она, решается, когда её ставят
		Sfx.play("card_slide", -12)
		_update_pose_button()
		shelf_hint.emit("Положение выбрано. Удерживайте коробку и ведите её на место — или кликните мимо, чтобы вернуть на прежнее")
		return
	var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(id, {})
	var surface := str(anchor.get("surface", ""))
	if WALL_SHELVES.has(surface):
		var target := _shelf_root.to_global(_wall_home(_selected_box, anchor).origin)
		if not _wall_item_fits(_selected_box, surface, target.z):
			_box_modes[id] = old
			shelf_hint.emit("В этом положении коробке тесно на полке.")
			return
		_reflow(true)
		_update_pose_button()
		_finish_pose_change()
		return
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


## Черновик редактора целиком — для отмены.
func _editor_state() -> Dictionary:
	return {
		"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true),
		"preferences": _editor_preferences.duplicate(true), "preference_geometry": _editor_preference_geometry.duplicate(true),
	}


func can_undo_shelf() -> bool:
	return _editor_on and not _undo_stack.is_empty()


## Ctrl+Z и кнопка «Отменить» в редакторе шкафа: вернуть черновик на шаг назад.
func undo_shelf_edit() -> void:
	if not _editor_on:
		return
	_cancel_drag()
	_edge_drag = {}
	if _undo_stack.is_empty():
		shelf_hint.emit("Отменять нечего")
		return
	var state: Dictionary = _undo_stack.pop_back()
	_apply_shelf_state(state)
	_editor_preferences = (state.preferences as Array).duplicate(true)
	_editor_preference_geometry = (state.preference_geometry as Dictionary).duplicate(true)
	_undo_last = _editor_state()
	_editor_ui.call("sync", "Изменение отменено")
	_frame_shelf()
	Sfx.play("card_slide", -10)


## Изменилось ли что-то в черновике с прошлой проверки — тогда прежний вид уходит в стопку отмены.
func _watch_undo(delta: float) -> void:
	_undo_clock += delta
	if _undo_clock < 0.25:
		return
	_undo_clock = 0.0
	if _drag_box != null or _lift_box != null or not _edge_drag.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var now := _editor_state()
	if now == _undo_last:
		return
	_undo_stack.append(_undo_last)
	if _undo_stack.size() > 60:
		_undo_stack.pop_front()
	_undo_last = now


## Старые «свободные места» переводятся в общий порядок соседей только ручным жестом.
func _adopt_neighbor_order() -> void:
	if bool(_cabinet.get("neighbor_order", false)):
		return
	var by_id: Dictionary = {}
	for box: GameBox in boxes:
		by_id[_shelf_id(box)] = box
	for cell in _rows.size():
		var ids := ShelfConfig.visible_order(_shelf_ids()[cell], _shelf_sizes(), _box_modes, _cabinet)
		_rows[cell] = ids.map(func(id): return by_id[id])
	_cabinet.neighbor_order = true


## Коробка выдвигается из шкафа: соседи занимают её место, она висит перед полкой.
func _lift(b: GameBox) -> void:
	if remote_view or b.is_figurine():
		return
	var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(b), {})
	if WALL_SHELVES.has(anchor.get("surface", "")):
		return
	_lift_backup = {"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true)}
	_adopt_neighbor_order()
	_lift_from = Vector2i(-1, -1)
	for r in _rows.size():
		var i: int = (_rows[r] as Array).find(b)
		if i >= 0:
			_lift_from = Vector2i(r, i)
			(_rows[r] as Array).remove_at(i)
			break
	if _lift_from.x < 0:
		_lift_backup = {}
		return
	_lift_mode = int(_box_modes.get(_shelf_id(b), 1))
	_lift_floor = b.home.origin - Vector3(0, _box_extent(b).y * 0.5, 0)
	_lift_box = b
	_reflow(true)
	Sfx.play("card_slide", -12)


## Выделение снято без переноса: коробка возвращается на прежнее место (в новом положении, если влезает).
func _settle_lift() -> void:
	var b := _lift_box
	if b == null:
		return
	_lift_box = null
	var id := _shelf_id(b)
	var mode := int(_box_modes.get(id, 1))
	var turned := mode != _lift_mode
	var cell := clampi(_lift_from.x, 0, _rows.size() - 1)
	var row: Array = _rows[cell]
	var index := mini(_lift_from.y, row.size())
	var candidate: Array = row.duplicate()
	candidate.insert(index, b)
	var info: Dictionary = _row_info[cell]
	var occupied := ShelfConfig.item_occupied(id, b.size, mode)
	var fits := (
		float(_layout_row(candidate, cell).width) <= float(info.right) - float(info.left) + 0.0005
		and occupied.y <= float(info.get("height", CELL_H)) + 0.0005
		and occupied.z <= CELL_D + 0.0005
	)
	if not fits:
		# так на прежнем месте тесно — возвращаем и место, и положение
		var backup := _lift_backup
		_lift_backup = {}
		_apply_shelf_state(backup)
		if turned:
			shelf_hint.emit("В этом положении коробке тесно на прежнем месте — вернул как было. Удерживайте её, чтобы поставить в другое место.")
		return
	_lift_backup = {}
	row.insert(index, b)
	_reflow(true)
	Sfx.play("card_place", -10)
	if turned:
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
		_selected_box != null and _drag_box == null
	)
	_transfer_button.visible = _pose_button.visible
	if not _pose_button.visible:
		return
	var ext := _box_extent(_selected_box)
	var at := _selected_box.global_position + Vector3.UP * (ext.y * SHELF_SCALE * 0.5 + 0.045)
	var screen := camera.unproject_position(at)
	_pose_button.position = (screen - Vector2(23, 44)).clamp(
		Vector2(8, 70), get_viewport().get_visible_rect().size - Vector2(104, 52)
	)
	_transfer_button.position = _pose_button.position + Vector2(50, 0)
	var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(_selected_box), {})
	var on_wall := WALL_SHELVES.has(anchor.get("surface", ""))
	_transfer_button.icon = ShelfIcons.icon(-3 if on_wall else -2)
	_transfer_button.tooltip_text = "Вернуть в шкаф" if on_wall else ("Перенести на верхнюю полку" if _selected_box.is_figurine() else "Перенести на нижнюю полку")
	if _selected_box.is_figurine():
		_pose_button.icon = ShelfIcons.icon(-4)
		_pose_button.tooltip_text = "Повернуть фигурку"
		return
	_pose_button.icon = ShelfIcons.icon(int(_box_modes.get(_shelf_id(_selected_box), 1)))
	_pose_button.tooltip_text = [
		"Обложкой к вам · нажмите: поставить боком",
		"Боком к вам · нажмите: положить",
		"Лёжа, корешком к вам · нажмите: показать крышку",
		"Лёжа, крышкой к вам · нажмите: поставить обложкой"
	][int(_box_modes.get(_shelf_id(_selected_box), 1))]


## Быстрый перенос использует те же места и проверку габаритов, что и перетаскивание.
func _transfer_selected() -> void:
	var box := _selected_box
	if remote_view or not is_instance_valid(box) or _drag_box != null:
		return
	var start := box.transform
	_settle_lift()
	var id := _shelf_id(box)
	var anchors: Dictionary = _cabinet.get_or_add("figure_surfaces", {})
	var old: Dictionary = anchors.get(id, {})
	var source := str(old.get("surface", ""))
	var destination := "Предмет на полке у левой стены"
	if WALL_SHELVES.has(source):
		if _return_to_cabinet(box, old):
			destination = "Предмет в шкафу"
		elif box.is_figurine() and _return_figure_to_surface(box):
			var surface := str(anchors[id].surface)
			destination = "Фигурка на шкафу" if surface == "cabinet" else ("Фигурка на телевизоре" if surface == "tv" else "Фигурка на тумбе")
		else:
			shelf_hint.emit("Нет свободного места для фигурки" if box.is_figurine() else "В шкафу нет места")
			return
	else:
		var surface := "wall_upper" if box.is_figurine() else "wall_lower"
		var span := _wall_span(box, surface)
		var found := false
		var extent := _wall_item_extent(box)
		var candidates: Array[float] = [span[0].z]
		for other: GameBox in boxes:
			var anchor: Dictionary = anchors.get(_shelf_id(other), {})
			if anchor.get("surface", "") == surface:
				var point := _shelf_root.to_global(_wall_home(other, anchor).origin)
				candidates.append(point.z + (_wall_item_extent(other).z + extent.z) * 0.5 + 0.009)
		candidates.sort()
		for z: float in candidates:
			if z > span[1].z or not _wall_item_fits(box, surface, z):
				continue
			anchors[id] = {"surface": surface, "x": inverse_lerp(span[0].z, span[1].z, z)}
			found = true
			break
		if not found:
			shelf_hint.emit("На этой полке нет места")
			return
		(_cabinet.get("figure_cells", {}) as Dictionary).erase(id)
	_reflow(false)
	_animate_transfer(box, start)
	_finish_pose_change()
	if _editor_on:
		_editor_preferences = _shelf_ids()
		_editor_ui.call("sync")
	shelf_hint.emit(destination)


func _return_figure_to_surface(box: GameBox) -> bool:
	var anchors: Dictionary = _cabinet.figure_surfaces
	for surface: String in ["cabinet", "tv", "stand_left", "stand_right"]:
		var span := _figure_surface_span(box, surface)
		if span[1].x < span[0].x:
			continue
		var occupants: Array[Vector2] = []
		for other: GameBox in boxes:
			if other == box:
				continue
			var anchor: Dictionary = anchors.get(_shelf_id(other), {})
			if anchor.get("surface", "") != surface:
				continue
			var center := _figure_surface_position(other, surface, float(anchor.x)).x
			var clearance := _figure_radius(box) + _figure_radius(other) + 0.009
			occupants.append(Vector2(center - clearance, center + clearance))
		occupants.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		var x := span[0].x
		for interval: Vector2 in occupants:
			if x < interval.x:
				break
			x = maxf(x, interval.y)
		if x > span[1].x:
			continue
		var width := span[1].x - span[0].x
		var share := (x - span[0].x) / width if width > 0.0001 else 0.0
		var id := _shelf_id(box)
		anchors[id] = {"surface": surface, "x": share}
		(_cabinet.get("figure_cells", {}) as Dictionary).erase(id)
		return true
	return false


func _return_to_cabinet(box: GameBox, old: Dictionary) -> bool:
	if _place_in_cabinet(box, old):
		return true
	var id := _shelf_id(box)
	if box.is_figurine():
		var rotations: Dictionary = _cabinet.get_or_add("figure_yaw", {})
		var saved: Variant = rotations.get(id)
		var yaw := float(rotations.get(id, 0.0))
		# Сначала пробуем ближайшие повороты, по 15° в каждую сторону.
		for step in range(1, 13):
			for direction: int in [-1, 1]:
				rotations[id] = wrapf(yaw + direction * step * PI / 12.0, -PI, PI)
				if _place_in_cabinet(box, old):
					return true
		if saved == null:
			rotations.erase(id)
		else:
			rotations[id] = saved
	else:
		var mode := int(_box_modes.get(id, 1))
		var count := 2 if box.is_cups() else 4
		for step in range(1, count):
			_box_modes[id] = (mode + step) % count
			if _place_in_cabinet(box, old):
				return true
		_box_modes[id] = mode
	return false


func _place_in_cabinet(box: GameBox, old: Dictionary) -> bool:
	var id := _shelf_id(box)
	var ext := _figure_cabinet_extent(box) if box.is_figurine() else ShelfConfig.item_occupied(id, box.size, int(_box_modes.get(id, 1)))
	var anchors: Dictionary = _cabinet.figure_surfaces
	var field := "figure_cells" if box.is_figurine() else "box_positions"
	var shares: Dictionary = _cabinet.get_or_add(field, {})
	var saved_share: Variant = shares.get(id)
	var best := Vector2i(-1, -1)
	var best_x := INF
	var best_share := 0.0
	for cell in _rows.size():
		var info: Dictionary = _row_info[cell]
		if ext.y > float(info.height) + 0.0005 or ext.z > CELL_D + 0.0005:
			continue
		var capacity := float(info.right) - float(info.left)
		var row: Array = _rows[cell].filter(func(item): return item != box)
		var layout := _layout_row(row, cell)
		var occupied: Array[Vector2] = []
		for pile: Dictionary in layout.piles:
			occupied.append(Vector2(float(pile.x), float(pile.x) + float(pile.width)))
		for item: GameBox in row:
			if item.is_figurine() and not anchors.has(_shelf_id(item)):
				var home: Transform3D = layout.boxes[_shelf_id(item)]
				var half_width := _figure_cabinet_extent(item).x * 0.5
				occupied.append(Vector2(home.origin.x - half_width, home.origin.x + half_width))
		occupied.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		occupied.append(Vector2(capacity, capacity))
		var left := 0.0
		for interval: Vector2 in occupied:
			if interval.x - left >= ext.x - 0.0005:
				break
			left = maxf(left, interval.y)
		if left + ext.x > capacity + 0.0005 or float(info.left) + left >= best_x - 0.0005:
			continue
		var insert := ShelfOrder.pile_insert_index(layout.piles, row.map(func(item): return _shelf_id(item)), left + ext.x * 0.5)
		var share := left / maxf(0.001, capacity - ext.x) if box.is_figurine() else (left + ext.x * 0.5) / capacity
		row.insert(insert, box)
		anchors.erase(id)
		shares[id] = clampf(share, 0.0, 1.0)
		var placed := _layout_row(row, cell)
		anchors[id] = old
		if float(placed.width) <= capacity + 0.0005:
			best = Vector2i(cell, insert)
			best_x = float(info.left) + left
			best_share = shares[id]
		if saved_share == null:
			shares.erase(id)
		else:
			shares[id] = saved_share
	if best.x < 0:
		if saved_share == null:
			shares.erase(id)
		else:
			shares[id] = saved_share
		return _try_cabinet_stack(box, old)
	anchors.erase(id)
	shares[id] = best_share
	for row: Array in _rows:
		row.erase(box)
	(_rows[best.x] as Array).insert(best.y, box)
	return true


func _try_cabinet_stack(box: GameBox, old: Dictionary) -> bool:
	if box.is_figurine() or int(_box_modes.get(_shelf_id(box), 1)) not in [0, 2, 3]:
		return false
	var id := _shelf_id(box)
	var ext := ShelfConfig.item_occupied(id, box.size, int(_box_modes[id]))
	if ext.z > CELL_D + 0.0005:
		return false
	var anchors: Dictionary = _cabinet.figure_surfaces
	anchors.erase(id)
	for cell in _rows.size():
		var info: Dictionary = _row_info[cell]
		var row: Array = _rows[cell].filter(func(item): return item != box)
		for index in range(1, row.size() + 1):
			var candidate := row.duplicate()
			candidate.insert(index, box)
			var layout := _layout_row(candidate, cell)
			var home: Transform3D = layout.boxes[id]
			if home.origin.y <= ext.y * 0.5 + 0.0005 or float(layout.width) > float(info.right) - float(info.left) + 0.0005:
				continue
			for source_row: Array in _rows:
				source_row.erase(box)
			_rows[cell] = candidate
			return true
	anchors[id] = old
	return false


func _animate_transfer(box: GameBox, start: Transform3D) -> void:
	var finish := box.home
	box.transform = start
	var aisle := maxf(start.origin.z, finish.origin.z) + 0.18
	var out := Transform3D(start.basis, Vector3(start.origin.x, start.origin.y + 0.08, aisle))
	var near := Transform3D(finish.basis, Vector3(finish.origin.x, finish.origin.y + 0.08, aisle))
	var motion := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(box, "transform", out, 0.18)
	motion.tween_property(box, "transform", near, 0.42)
	motion.tween_property(box, "transform", finish, 0.19)
	box.set_meta("slide", motion)


func _shelf_edges() -> Array:
	var lines: Array = []
	var rows: int = int(_cabinet.rows)
	var cells: Array = ShelfConfig.shelf_cells(_cabinet)
	var width: float = ShelfConfig.full_width(_cabinet)
	var height: float = ShelfConfig.full_height(_cabinet)
	var left: float = SHELF_X - width * 0.5
	var inner_left := left + BOARD
	var inner_width := width - 2 * BOARD
	var z: float = BACK + CELL_D + 0.016
	var level_y: Array = []
	var y_cursor := 0.06
	for level in rows + 1:
		level_y.append(y_cursor)
		if level < rows:
			y_cursor += BOARD + ShelfConfig.row_height(_cabinet, rows - 1 - level)
	for side in [-1, 1]:
		var x: float = SHELF_X + side * width * 0.5
		lines.append(
			{"kind": "width", "index": side, "a": Vector3(x, 0.06, z), "b": Vector3(x, 0.06 + height, z)}
		)
	# дно и крыша — во всю ширину; средние полки — кусками под каждой ячейкой (тянется вся полка ряда,
	# правый клик убирает только этот кусок)
	for level in [0, rows]:
		var y: float = float(level_y[level]) + BOARD * 0.5
		lines.append({"kind": "height", "index": level, "a": Vector3(left, y, z), "b": Vector3(left + width, y, z)})
	for i in cells.size():
		var c: Dictionary = cells[i]
		var bottom: int = int(c.row) + int(c.span) - 1
		var x0: float = inner_left + float(c.x)
		var x1: float = x0 + float(c.w)
		var floor_y: float = float(level_y[rows - 1 - bottom]) + BOARD
		var cell_h: float = ShelfConfig.cell_height(_cabinet, i)
		if bottom < rows - 1:
			var level: int = rows - 1 - bottom
			var y: float = float(level_y[level]) + BOARD * 0.5
			lines.append({"kind": "height", "index": level, "above": i, "a": Vector3(x0, y, z), "b": Vector3(x1, y, z)})
		# перегородка справа — своя у ячейки (09.11)
		if float(c.x) + float(c.w) < inner_width - 0.002:
			var px := x1 + BOARD * 0.5
			lines.append({"kind": "seg", "index": i, "a": Vector3(px, floor_y, z), "b": Vector3(px, floor_y + cell_h, z)})
		# убранные куски полки в высокой ячейке — пунктиром, нажатие возвращает
		for k in range(1, int(c.span)):
			var level_k: int = rows - int(c.row) - k
			var yk: float = float(level_y[level_k]) + BOARD * 0.5
			lines.append({"kind": "ghost", "index": i * 16 + k, "cell": i, "top": k, "a": Vector3(x0, yk, z), "b": Vector3(x1, yk, z)})
	for edge: Dictionary in lines:
		edge.a = camera.unproject_position(_shelf_root.global_transform * edge.a)
		edge.b = camera.unproject_position(_shelf_root.global_transform * edge.b)
	return lines


## Правка ячеек редактора (объединить / разделить): новые ячейки, коробки по новым номерам.
func _apply_cells(result: Dictionary) -> void:
	if result.is_empty():
		_editor_ui.call("sync", "Так не получится: объединять можно соседние ячейки одинаковой ширины (по вертикали) или одного ряда.")
		return
	var before := _editor_preferences.duplicate(true)
	_editor_preferences = result.placements
	var message := request_shelf_geometry(result.config)
	if message != "":
		_editor_preferences = before
	_editor_ui.call("sync", message)


## Правый клик в редакторе: по перегородке / куску полки — убрать (две ячейки → одна);
## внутри ячейки — поставить перегородку посередине.
func _cells_right_click(screen: Vector2) -> void:
	var edge := _edge_at(screen)
	var point := _shelf_point(screen)
	var cells: Array = ShelfConfig.shelf_cells(_cabinet)
	var prefs := _shelf_ids()
	if not edge.is_empty() and edge.kind == "seg":
		var a: int = int(edge.index)
		var b := -1
		for n: int in ShelfConfig.right_neighbors(cells, a):
			var info: Dictionary = _row_info[n]
			if point.y >= float(info.floor) - BOARD and point.y <= float(info.floor) + float(info.height) + BOARD:
				b = n
		_apply_cells(ShelfConfig.merge_cells(_cabinet, prefs, a, b) if b >= 0 else {})
		return
	if not edge.is_empty() and edge.kind == "height" and edge.has("above"):
		var a: int = int(edge.above)
		var ca: Dictionary = cells[a]
		var b := -1
		for i in cells.size():
			var c: Dictionary = cells[i]
			if int(c.row) == int(ca.row) + int(ca.span) and float(_row_info[i].left) <= point.x and float(_row_info[i].right) >= point.x:
				b = i
		_apply_cells(ShelfConfig.merge_cells(_cabinet, prefs, a, b) if b >= 0 else {})
		return
	if not edge.is_empty():
		return
	for i in _row_info.size():
		var info: Dictionary = _row_info[i]
		if point.x >= float(info.left) and point.x <= float(info.right) and point.y >= float(info.floor) and point.y <= float(info.floor) + float(info.height):
			_apply_cells(ShelfConfig.split_cell(_cabinet, prefs, i, true, 0))
			return


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
		if edge.kind == "ghost":
			_edge_overlay.draw_dashed_line(edge.a, edge.b, HubStyle.YELLOW if hot else Color(HubStyle.CYAN, 0.45), 2.0, 8.0)
			continue
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
	var cols: int = int(original.cols)
	var rows: int = int(original.rows)
	var widths: Array = range(cols).map(func(c): return ShelfConfig.col_width(original, c))
	var heights: Array = range(rows).map(func(r): return ShelfConfig.row_height(original, r))
	if _edge_drag.kind == "width" and ShelfConfig.has_cells(original):
		# свои ячейки: внешний край — крайние ячейки каждого ряда
		var moved := ShelfConfig.move_outer(original, int(_edge_drag.index), delta.x * 2.0)
		if moved.is_empty():
			return
		config = moved
	elif _edge_drag.kind == "seg":
		# перегородка одной ячейки — только её ряд(ы)
		var moved := ShelfConfig.move_divider(original, int(_edge_drag.index), delta.x)
		if moved.is_empty():
			_editor_ui.call("sync", "Эту перегородку не сдвинуть: справа высокая ячейка на несколько рядов.")
			return
		config = moved
	elif _edge_drag.kind == "width":
		# внешний край — все колонки на одинаковую величину
		var d: float = delta.x * int(_edge_drag.index) * 2.0 / cols
		config.width = float(original.width) + d
		config.col_widths = widths.map(func(w): return float(w) + d)
	elif _edge_drag.kind == "col":
		# перегородка — меняются только две соседние колонки, ширина шкафа та же
		var c: int = int(_edge_drag.index)
		var d: float = clampf(delta.x, ShelfConfig.MIN_WIDTH - float(widths[c - 1]), float(widths[c]) - ShelfConfig.MIN_WIDTH)
		widths[c - 1] = float(widths[c - 1]) + d
		widths[c] = float(widths[c]) - d
		config.col_widths = widths
	else:
		var level: int = int(_edge_drag.index)
		if level == 0 or level == rows:
			# дно и крыша — все полки на одинаковую величину
			var dh: float = delta.y / (float(level) if level > 0 else -float(rows))
			config.height = float(original.height) + dh
			config.row_heights = heights.map(func(h): return float(h) + dh)
		else:
			# средняя полка — меняются только ряд под ней и ряд над ней (ряды считаются сверху)
			var below: int = rows - level
			var above: int = rows - 1 - level
			var dy: float = clampf(delta.y, ShelfConfig.MIN_HEIGHT - float(heights[below]), float(heights[above]) - ShelfConfig.MIN_HEIGHT)
			heights[below] = float(heights[below]) + dy
			heights[above] = float(heights[above]) - dy
			config.row_heights = heights
	var message := request_shelf_geometry(config)
	_editor_ui.call("sync", message)


# --- Выбор мышью ----------------------------------------------------------------------

## Отдельный слой декора: не перехватывает лучи коробок и редактора.
func _ball_make() -> void:
	_ball = Node3D.new()
	_ball.position = BALL_HOME
	add_child(_ball)
	var skin := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_R
	sphere.height = BALL_R * 2.0
	skin.mesh = sphere
	# Полоса нанесена на резину и видна при вращении мяча.
	var rubber := _mat(Color.WHITE, 0.86)
	rubber.metallic_specular = 0.22
	var colors := Image.create(8, 96, false, Image.FORMAT_RGB8)
	colors.fill(Color("ab5575"))
	colors.fill_rect(Rect2i(0, 45, colors.get_width(), 6), Color("c2a0a8"))
	rubber.albedo_texture = ImageTexture.create_from_image(colors)
	skin.material_override = rubber
	skin.rotation_degrees.z = 24.0
	_ball.add_child(skin)
	_ball_body = StaticBody3D.new()
	_ball_body.collision_layer = 8
	_ball_body.collision_mask = 0
	_ball_body.set_meta("room_prop", "ball")
	var shape := CollisionShape3D.new()
	var grip := SphereShape3D.new()
	grip.radius = BALL_R * 1.5  # хватать чуть легче, чем попасть в сам мяч
	shape.shape = grip
	_ball_body.add_child(shape)
	_ball.add_child(_ball_body)
	var saved := ConfigFile.new()
	if saved.load("user://room_props.cfg") == OK:
		ball_on = bool(saved.get_value("ball", "on", true))
	_apply_ball_on()


## Мяч в комнате есть / нет (кнопка в редакторе шкафа). Включили снова — появляется на своём месте.
func set_ball_enabled(on: bool) -> void:
	if on == ball_on:
		return
	ball_on = on
	if on and is_instance_valid(_ball):
		_ball.position = BALL_HOME
		_ball_v = Vector3.ZERO
		_ball_asleep = false
	_apply_ball_on()
	var saved := ConfigFile.new()
	saved.load("user://room_props.cfg")
	saved.set_value("ball", "on", on)
	saved.save("user://room_props.cfg")


func _apply_ball_on() -> void:
	if not is_instance_valid(_ball):
		return
	_ball.visible = ball_on
	_ball_body.collision_layer = 8 if ball_on and not _ball_camera_paused else 0
	if not ball_on and _ball_held:
		_ball_held = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Препятствия для мяча: [нижний угол, верхний угол] в координатах комнаты.
func _ball_blocks() -> Array:
	var blocks: Array = [
		[Vector3(TV_X - STAND_HALF - 0.02, 0.0, BACK), Vector3(TV_X + STAND_HALF + 0.02, STAND_TOP, BACK + 0.56)],
		[Vector3(TV_X - TV_HALF, STAND_TOP, BACK), Vector3(TV_X + TV_HALF, STAND_TOP + 0.47, BACK + 0.56)],
		# тумбочка с будильником слева (ящик 0,45 × 0,5 × 0,4 у стены, с ручками и часами сверху)
		[Vector3(-1.7 - 0.24, 0.0, BACK), Vector3(-1.7 + 0.24, 0.6, BACK + 0.49)],
		[_window_sill_bounds.position, _window_sill_bounds.end],
		# кровать вдоль левой стены: каркас с матрасом и одеялом
		[Vector3(-W * 0.5, 0.0, BACK), Vector3(-1.93, 0.5, BACK + 2.13)],
	]
	if is_instance_valid(_shelf_root) and not _row_info.is_empty():
		var left := INF
		var right := -INF
		var top := 0.0
		var back := float(_row_info[0].back)
		for info: Dictionary in _row_info:
			left = minf(left, float(info.left))
			right = maxf(right, float(info.get("outer_right", info.right)))
			top = maxf(top, float(info.floor) + float(info.get("height", CELL_H)))
		var low := _shelf_root.to_global(Vector3(left - 0.03, 0.0, back))
		var high := _shelf_root.to_global(Vector3(right + 0.03, top + 0.03, back + CELL_D))
		# Запас у боковин и передней кромки закрывает карманы, в которых мяч исчезал за шкафом.
		blocks.append([Vector3(low.x - BALL_R * 2.0, 0.0, BACK),
			Vector3(high.x + BALL_R * 2.0, high.y, high.z + BALL_R * 2.0)])
	return blocks


func _ball_grab() -> void:
	if not is_instance_valid(_ball):
		return
	_ball_held = true
	_ball_asleep = false
	_ball_v = Vector3.ZERO
	_ball_plane = clampf(_ball.position.z, BACK + 0.6, BALL_FRONT - BALL_R)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	shelf_hint.emit("Мяч-попрыгун · размахнитесь и отпустите")


## Отпустили: мяч летит туда, куда вели, и немного вглубь комнаты — чтобы ударился о стену.
func _ball_throw() -> void:
	_ball_held = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var speed := _ball_v.length()
	if speed > 7.5:
		_ball_v = _ball_v / speed * 7.5
	_ball_v.z -= minf(speed, 7.5) * 0.45
	shelf_hint.emit(HINT)


func _ball_step(delta: float) -> void:
	if not is_instance_valid(_ball) or not ball_on:
		return
	if _ball_camera_paused:
		var returned := camera.transform.basis.z.dot(_cam_home.basis.z) > 0.998 and camera.position.distance_to(_cam_home.origin) < 0.08
		if board_focused() or (_looking_left and not _editor_on and not remote_view) or not returned:
			_ball_body.collision_layer = 0
			return
		_ball_camera_paused = false
		_ball_body.collision_layer = 8
	# камера сдвинулась (редактор шкафа, размер окна) — спящий мяч мог остаться за кадром: будим
	var view_key := "%s|%s|%s" % [camera.global_transform, camera.fov, get_viewport().get_visible_rect().size]
	if view_key != _ball_view:
		_ball_view = view_key
		_ball_asleep = false
	if _ball_held:
		# мяч ведут за курсором по плоскости на своей глубине; скорость запоминаем для броска
		var mouse := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var ray := camera.project_ray_normal(mouse)
		if absf(ray.z) > 0.0001:
			var target := origin + ray * ((_ball_plane - origin.z) / ray.z)
			target.x = clampf(target.x, -W * 0.5 + BALL_R, W * 0.5 - BALL_R)
			target.y = clampf(target.y, BALL_R, H - BALL_R)
			# и в руке мяч не уходит за край кадра
			var seen := get_viewport().get_visible_rect().size
			var shown := camera.unproject_position(target).clamp(Vector2(24, 24), seen - Vector2(24, 24))
			var back_ray := camera.project_ray_normal(shown)
			if absf(back_ray.z) > 0.0001:
				target = camera.project_ray_origin(shown) + back_ray * ((_ball_plane - camera.project_ray_origin(shown).z) / back_ray.z)
			var next := _ball.position.lerp(target, 1.0 - exp(-delta * 28.0))
			if delta > 0.0:
				_ball_v = _ball_v.lerp((next - _ball.position) / delta, 0.35)
			_ball.position = next
		return
	if _ball_asleep:
		return
	# Края экрана — тоже стенки: пол комнаты почти весь ниже кадра, и мяч терялся бы из виду.
	# Плоскости обзора камеры (кроме ближней и дальней), нормали разворачиваем внутрь кадра.
	var inside := camera.global_position - camera.global_transform.basis.z * 1.5
	var edges: Array[Plane] = []
	var frustum := camera.get_frustum()
	var bottom := Plane(Vector3.UP, 0.0)  # нижний край кадра — он работает как пол
	for index in range(2, frustum.size()):
		var plane: Plane = frustum[index]
		if plane.distance_to(inside) < 0.0:
			plane = -plane
		if plane.normal.y > 0.6:
			bottom = plane
		else:
			edges.append(plane)
	var blocks := _ball_blocks()
	var steps := 3
	var dt := minf(delta, 1.0 / 30.0) / steps
	var supported := false
	for step in steps:
		_ball_v.y -= 9.8 * dt
		var at := _ball.position + _ball_v * dt
		var contacts: Array = []  # [нормаль внутрь, на сколько вытолкнуть]
		var rim_contact: Array = _basket.rim_contact(at, _ball_v, BALL_R) if is_instance_valid(_basket) else []
		if not rim_contact.is_empty():
			contacts.append(rim_contact)
		# пол: настоящий или нижний край кадра на этой глубине — что выше (горизонтальный, мяч с него не скатывается)
		var floor_y := BALL_R
		if bottom.normal.y > 0.6:
			floor_y = maxf(floor_y, (bottom.d - bottom.normal.x * at.x - bottom.normal.z * at.z) / bottom.normal.y + BALL_R * 1.3)
		if at.y < floor_y:
			contacts.append([Vector3.UP, floor_y - at.y])
		if at.y > H - BALL_R:
			contacts.append([Vector3.DOWN, at.y - (H - BALL_R)])
		if at.x < -W * 0.5 + BALL_R:
			contacts.append([Vector3.RIGHT, -W * 0.5 + BALL_R - at.x])
		if at.x > W * 0.5 - BALL_R:
			contacts.append([Vector3.LEFT, at.x - (W * 0.5 - BALL_R)])
		if at.z < BACK + BALL_R:
			contacts.append([Vector3.BACK, BACK + BALL_R - at.z])
		if at.z > BALL_FRONT - BALL_R:
			contacts.append([Vector3.FORWARD, at.z - (BALL_FRONT - BALL_R)])
		for edge: Plane in edges:
			var room_left := edge.distance_to(at) - BALL_R * 1.3
			if room_left < 0.0:
				contacts.append([edge.normal, -room_left])
		# мебель: шар против ящика
		for block: Array in blocks:
			var low: Vector3 = block[0]
			var high: Vector3 = block[1]
			var nearest := at.clamp(low, high)
			var gap := at - nearest
			var distance := gap.length()
			if distance >= BALL_R:
				continue
			if distance > 0.0001:
				contacts.append([gap / distance, BALL_R - distance])
			else:
				# оказался внутри — выталкиваем через ближайшую грань (вверх, к игроку или вбок)
				var exits := [[Vector3.UP, high.y - at.y], [Vector3.BACK, high.z - at.z], [Vector3.LEFT, at.x - low.x], [Vector3.RIGHT, high.x - at.x]]
				exits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
				contacts.append([exits[0][0], float(exits[0][1]) + BALL_R])
		var hit := 0.0
		for contact: Array in contacts:
			var normal: Vector3 = contact[0]
			at += normal * float(contact[1])
			var into := _ball_v.dot(normal)
			if into >= 0.0:
				continue
			if -into > 0.7:
				hit = maxf(hit, -into)
				_ball_v -= normal * into * (1.0 + BALL_BOUNCE)
			else:
				_ball_v -= normal * into  # слабый удар — просто останавливаемся об опору
				if normal.y > 0.35:
					supported = true
					_ball_v *= exp(-dt * 2.2)  # катится по опоре и замедляется
		# мяч крутится в сторону движения
		var travel := at - _ball.position
		var flat := Vector3(travel.x, 0, travel.z)
		if flat.length() > 0.00001:
			_ball.rotate(Vector3.UP.cross(flat).normalized(), flat.length() / BALL_R)
		if is_instance_valid(_basket) and rim_contact.is_empty():
			_basket.check_ball(_ball.position, at, BALL_R)
		_ball.position = at
		if hit > 0.7:
			Sfx.play("chip", clampf(-24.0 + hit * 3.2, -24.0, -6.0), 0.12, 0.06)
	if supported and _ball_v.length() < 0.06:
		_ball_v = Vector3.ZERO
		_ball_asleep = true


## Кубик-рубильник: коробочка 20×10×12 см, все ручки — на передней стенке.
func _fidget_cube(at: Vector3) -> void:
	var cube := Node3D.new()
	cube.position = at
	cube.scale = Vector3.ONE * FIDGET_SCALE
	add_child(cube)
	var shell := _mat(Color("3a3348"), 0.55)
	_box(Vector3(0.2, 0.1, 0.12), Vector3.ZERO, shell, cube)
	_box(Vector3(0.186, 0.086, 0.004), Vector3(0, 0, 0.061), _mat(Color("211c2b"), 0.7), cube)
	var saved := ConfigFile.new()
	saved.load("user://room_props.cfg")
	var toggles: Array = []
	for i in 3:
		var x := -0.066 + i * 0.04
		_box(Vector3(0.022, 0.038, 0.004), Vector3(x, -0.012, 0.064), _mat(Color("0f0d14"), 0.6), cube)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, -0.012, 0.066)
		cube.add_child(pivot)
		var lever_mat := _mat(Color("d8d2e6"), 0.3)
		lever_mat.metallic = 0.6
		_box(Vector3(0.009, 0.03, 0.009), Vector3(0, 0.011, 0.006), lever_mat, pivot)
		var bulb := _cyl(0.0065, 0.0065, 0.006, Vector3(x, 0.03, 0.064), _mat(Color("17131f"), 0.4), cube)
		bulb.rotation_degrees.x = 90
		var on := bool(saved.get_value("fidget", "toggle%d" % i, false))
		toggles.append({"pivot": pivot, "bulb": bulb, "on": on})
		_add_room_prop("fidget_toggle%d" % i, at + Vector3(x, -0.004, 0.07) * FIDGET_SCALE, Vector3(0.036, 0.08, 0.03) * FIDGET_SCALE)
	var cap := _cyl(0.017, 0.017, 0.012, Vector3(0.056, 0.016, 0.068), _mat(Color("e0453c"), 0.35), cube)
	cap.rotation_degrees.x = 90
	var socket := _cyl(0.021, 0.021, 0.004, Vector3(0.056, 0.016, 0.063), _mat(Color("0f0d14"), 0.6), cube)
	socket.rotation_degrees.x = 90
	_add_room_prop("fidget_button", at + Vector3(0.056, 0.018, 0.072) * FIDGET_SCALE, Vector3(0.046, 0.044, 0.03) * FIDGET_SCALE)
	var wheel := Node3D.new()
	wheel.position = Vector3(0.056, -0.026, 0.058)
	cube.add_child(wheel)
	var rim := _cyl(0.016, 0.016, 0.03, Vector3.ZERO, _mat(Color("8a8498"), 0.45), wheel)
	rim.rotation_degrees.z = 90
	for notch in 6:
		var angle := TAU * notch / 6.0
		_box(Vector3(0.031, 0.004, 0.004), Vector3(0, cos(angle) * 0.0155, sin(angle) * 0.0155), _mat(Color("2a2438"), 0.6), wheel, Vector3(angle, 0, 0))
	_add_room_prop("fidget_wheel", at + Vector3(0.056, -0.028, 0.07) * FIDGET_SCALE, Vector3(0.05, 0.04, 0.03) * FIDGET_SCALE)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.03, 0.14)
	glow.omni_range = 0.7
	glow.shadow_enabled = false
	cube.add_child(glow)
	_fidget = {"toggles": toggles, "cap": cap, "wheel": wheel, "glow": glow, "hue": float(saved.get_value("fidget", "hue", 0.0)), "show": false}
	_fidget_refresh(false)


## Лампочки и свет кубика по состоянию тумблеров; колёсико сдвигает оттенок всех лампочек.
func _fidget_refresh(animate: bool) -> void:
	var toggles: Array = _fidget.toggles
	var mix := Color(0, 0, 0)
	var lit := 0
	for i in toggles.size():
		var toggle: Dictionary = toggles[i]
		var base: Color = FIDGET_COLORS[i]
		var color := Color.from_hsv(fposmod(base.h + float(_fidget.hue), 1.0), base.s, base.v)
		var on := bool(toggle.on)
		(toggle.bulb as MeshInstance3D).material_override = _mat(color if on else Color("17131f"), 0.4, color, 2.6 if on else 0.0)
		var tilt := -0.55 if on else 0.55
		var pivot: Node3D = toggle.pivot
		if animate:
			create_tween().tween_property(pivot, "rotation:x", tilt, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			pivot.rotation.x = tilt
		if on:
			mix += color
			lit += 1
	var glow: OmniLight3D = _fidget.glow
	glow.light_color = mix / float(lit) if lit > 0 else Color.WHITE
	glow.light_energy = 0.35 * lit


func _fidget_save() -> void:
	var saved := ConfigFile.new()
	saved.load("user://room_props.cfg")
	for i in (_fidget.toggles as Array).size():
		saved.set_value("fidget", "toggle%d" % i, bool(_fidget.toggles[i].on))
	saved.set_value("fidget", "hue", float(_fidget.hue))
	saved.save("user://room_props.cfg")


## Щелчок по ручке кубика. Тумблер — лампочка, кнопка — «бегущие огни», колёсико крутят колесом мыши.
func _fidget_use(kind: String) -> void:
	if _fidget.is_empty():
		return
	if kind.begins_with("fidget_toggle"):
		var toggle: Dictionary = _fidget.toggles[int(kind.trim_prefix("fidget_toggle"))]
		toggle.on = not bool(toggle.on)
		_fidget_refresh(true)
		_fidget_save()
		Sfx.play("click", -8.0 if bool(toggle.on) else -11.0, 0.02)
		shelf_hint.emit("Кубик-рубильник · щёлк")
	elif kind == "fidget_button":
		var cap: MeshInstance3D = _fidget.cap
		var press := create_tween()
		press.tween_property(cap, "position:z", 0.062, 0.05)
		press.tween_property(cap, "position:z", 0.068, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play("chip", -7.0)
		# бегущие огни: лампочки по очереди вспыхивают и возвращаются к своему состоянию
		if not bool(_fidget.show):
			_fidget.show = true
			var before: Array = (_fidget.toggles as Array).map(func(toggle): return bool(toggle.on))
			var chase := create_tween()
			for step in 9:
				chase.tween_callback(func():
					for i in (_fidget.toggles as Array).size():
						_fidget.toggles[i].on = i == step % 3
					_fidget_refresh(false))
				chase.tween_interval(0.07)
			chase.tween_callback(func():
				for i in (_fidget.toggles as Array).size():
					_fidget.toggles[i].on = before[i]
				_fidget.show = false
				_fidget_refresh(true))
		shelf_hint.emit("Кубик-рубильник · кнопка")
	elif kind == "fidget_wheel":
		shelf_hint.emit("Кубик-рубильник · крутите колёсико колесом мыши")


## Колёсико кубика: шаг колеса мыши — щелчок и новый оттенок лампочек.
func _fidget_spin(direction: int) -> void:
	if _fidget.is_empty() or bool(_fidget.show):
		return
	var wheel: Node3D = _fidget.wheel
	create_tween().tween_property(wheel, "rotation:x", wheel.rotation.x + direction * TAU / 12.0, 0.08)
	_fidget.hue = fposmod(float(_fidget.hue) + direction / 24.0, 1.0)
	_fidget_refresh(false)
	_fidget_save()
	Sfx.play("hover", -9.0, 0.03, 0.02)


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


## Точка задней стены (плоскость доски) под курсором.
func _wall_point(point: Vector2) -> Variant:
	var plane := Plane(Vector3.BACK, BOARD_AT.z)
	return plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))


func _begin_board_drag(point: Vector2) -> void:
	var hit: Variant = _wall_point(point)
	if hit == null or not is_instance_valid(sticker_board):
		return
	board_dragging = true
	_board_grab = sticker_board.position - (hit as Vector3)
	sticker_board.scale = Vector3.ONE * 1.04
	Sfx.play("card_shove", -8, 0.05)
	shelf_hint.emit("Доска друзей · ведите по стене и отпустите, чтобы повесить · крестик над ней — снять доску")
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	board_held.emit()


func _drag_board(point: Vector2) -> void:
	var hit: Variant = _wall_point(point)
	if hit == null:
		return
	var at := (hit as Vector3) + _board_grab
	var center := preload("res://hub/stickers.gd").clamp_board_pos(Vector2(at.x, at.y))
	sticker_board.position = Vector3(center.x, center.y, _board_depth(center, sticker_board))


func _end_board_drag() -> void:
	board_dragging = false
	if not is_instance_valid(sticker_board):
		return
	sticker_board.scale = Vector3.ONE
	Sfx.play("card_place", -8, 0.05)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	shelf_hint.emit(HINT if not _editor_on else "Доска друзей повешена")
	# Бросили на шкаф — повесится в ближайшем свободном месте, его и сохраняем.
	var spot := board_free_spot(Vector2(sticker_board.position.x, sticker_board.position.y))
	_board_homes[active_board_id()] = spot
	board_moved.emit(spot, active_board_id())


## Глубина доски: вплотную к стене, но поверх окна и постеров, если заходит на них (доска всегда перекрывает их).
func _board_depth(center: Vector2, board: Node3D = null) -> float:
	var rect := Rect2(center - BOARD_EXTENT / 2.0, BOARD_EXTENT)
	var depth := BOARD_AT.z
	for decor: Array in _wall_decor:
		if rect.intersects(decor[0]):
			depth = maxf(depth, float(decor[1]))
	for poster: Node3D in posters:
		if is_instance_valid(poster) and poster.visible and rect.intersects(poster.wall_rect().grow(0.02)):
			depth = maxf(depth, poster.position.z + 0.016)
	# Доски друг на друге: доска с большим номером висит поверх пересекающейся с меньшим, без мерцания.
	if board != null:
		var ids := boards.keys()
		ids.sort()
		for bid: Variant in ids:
			var other: Node3D = boards[bid]
			if int(bid) >= int(board.board_id) or not is_instance_valid(other):
				continue
			if rect.intersects(Rect2(Vector2(other.position.x, other.position.y) - BOARD_EXTENT / 2.0, BOARD_EXTENT)):
				depth = maxf(depth, other.position.z + 0.03)
	return depth


## Плакат на стене: вплотную, но поверх окна, если заходит на него.
func _poster_depth(rect: Rect2) -> float:
	var depth := BACK + 0.012
	for decor: Array in _wall_decor:
		if rect.intersects(decor[0]):
			depth = maxf(depth, float(decor[1]))
	return depth


## Центр плаката в пределах стены.
func clamp_poster(poster: Node3D, center: Vector2) -> Vector2:
	var half: Vector2 = poster.wall_size() / 2.0
	return Vector2(clampf(center.x, -W / 2.0 + half.x + 0.03, W / 2.0 - half.x - 0.03), clampf(center.y, half.y + 0.12, H - half.y - 0.03))


## Повесить плакат (своя комната — из сохранения, у друга — где повесил он). Во время переноса не трогаем.
## layer — слой плаката (0 — нижний): каждый слой на 8 мм ближе, пересекающиеся плакаты не мерцают.
func set_poster_position(slot: int, center: Vector2, layer: int = -1) -> void:
	if slot < 0 or slot >= posters.size():
		return
	var poster: Node3D = posters[slot]
	if poster == poster_dragging:
		return
	if layer < 0:
		layer = slot  # порядок по умолчанию
	var at := clamp_poster(poster, center)
	poster.position = Vector3(at.x, at.y, _poster_depth(Rect2(at - poster.wall_size() / 2.0, poster.wall_size())) + layer * POSTER_LAYER)


func poster_default_position(slot: int) -> Vector2:
	return POSTER_DEFAULTS[slot % POSTER_DEFAULTS.size()][1]


func _poster_at(point: Vector2) -> Node3D:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 20, 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or str(hit.collider.get_meta("room_prop", "")) != "poster":
		return null
	var slot := int(hit.collider.get_meta("poster_slot", -1))
	return posters[slot] if slot >= 0 and slot < posters.size() else null


func _begin_poster_drag(poster: Node3D, point: Vector2) -> void:
	var hit: Variant = _wall_point(point)
	if hit == null:
		return
	poster_dragging = poster
	_poster_grab = poster.position - (hit as Vector3)
	poster.scale = Vector3.ONE * 1.04
	Sfx.play("card_shove", -8, 0.05)
	shelf_hint.emit("Плакат · ведите по стене и отпустите · значки над ним: картинка, размер, крестик — снять")
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	poster_held.emit(int(poster.slot))


func _drag_poster(point: Vector2) -> void:
	var hit: Variant = _wall_point(point)
	if hit == null or poster_dragging == null:
		return
	var at := clamp_poster(poster_dragging, Vector2((hit as Vector3).x + _poster_grab.x, (hit as Vector3).y + _poster_grab.y))
	poster_dragging.position = Vector3(at.x, at.y, _poster_depth(Rect2(at - poster_dragging.wall_size() / 2.0, poster_dragging.wall_size())) + posters.size() * POSTER_LAYER)


func _end_poster_drag() -> void:
	var poster := poster_dragging
	poster_dragging = null
	if not is_instance_valid(poster):
		return
	poster.scale = Vector3.ONE
	Sfx.play("card_place", -8, 0.05)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	shelf_hint.emit(HINT if not _editor_on else "Плакат повешен")
	poster_moved.emit(int(poster.slot), Vector2(poster.position.x, poster.position.y))


## Камера подлетает к доске (наклеить другу / разобрать свою) и возвращается обратно. Плавно — через _cam_home.
func focus_board(on: bool) -> void:
	if not is_instance_valid(sticker_board) or not is_instance_valid(camera):
		return
	if on:
		if _board_cam_saved == null:
			_board_cam_saved = _cam_home
			_ball_camera_paused = true
			if _ball_held:
				_ball_held = false
				_ball_v = Vector3.ZERO
		var center := sticker_board.global_position
		var eye := center + Vector3(0.0, 0.02, 0.78)
		var view := Transform3D(Basis.IDENTITY, eye)
		_cam_home = view.looking_at(center, Vector3.UP)
	elif _board_cam_saved != null:
		_cam_home = _board_cam_saved
		_board_cam_saved = null


func board_focused() -> bool:
	return _board_cam_saved != null


## Повесить доску (своя — из сохранения, в комнате друга — где её повесил друг). Во время переноса не трогаем.
## Место доски — сохранённое игроком (center), но если там шкаф, доска висит в ближайшем свободном месте.
## Пересчитывается постоянно: в редакторе шкаф стал шире — доска отъезжает, сузили обратно — возвращается.
func set_board_position(center: Vector2, bid: int = 0) -> void:
	var board: Node3D = boards.get(bid, null)
	if not is_instance_valid(board) or (board_dragging and board == sticker_board):
		return
	_board_homes[bid] = center
	# Комната только построена или доска новая — сразу на место, первый же кадр без прыжка.
	if _board_snap_frames > 0 or board.get_meta("fresh", false):
		board.remove_meta("fresh")
		var target := board_free_spot(center)
		board.position = Vector3(target.x, target.y, _board_depth(target, board))


## Прямоугольник шкафа на задней стене (x, y в метрах; с кубом окошек на крыше и небольшим зазором).
func shelf_wall_rect() -> Rect2:
	if not is_instance_valid(_shelf_root) or _cabinet.is_empty():
		return Rect2()
	var cols: int = int(_cabinet.cols)
	var rows: int = int(_cabinet.rows)
	var full_width: float = ShelfConfig.full_width(_cabinet)
	var full_height: float = ShelfConfig.full_height(_cabinet)
	var left: float = SHELF_X - full_width * 0.5
	var a := _shelf_root.transform * Vector3(left, 0.0, BACK)
	var b := _shelf_root.transform * Vector3(left + full_width, 0.06 + full_height + 0.16, BACK)  # 0.16 — стеклянный куб
	return Rect2(Vector2(a.x, a.y), Vector2(b.x - a.x, b.y - a.y)).grow(0.03)


## Ближайшее к center место на стене, где доска не заходит на шкаф (слева, справа или над ним).
func board_free_spot(center: Vector2) -> Vector2:
	var clamp_pos := func(p: Vector2) -> Vector2: return preload("res://hub/stickers.gd").clamp_board_pos(p)
	var spot: Vector2 = clamp_pos.call(center)
	var shelf := shelf_wall_rect()
	var half := BOARD_EXTENT / 2.0
	if shelf.size == Vector2.ZERO or not Rect2(spot - half, BOARD_EXTENT).intersects(shelf):
		return spot
	var best := spot
	var best_distance := INF
	for candidate: Vector2 in [
		Vector2(shelf.position.x - half.x, spot.y),  # левее шкафа
		Vector2(shelf.end.x + half.x, spot.y),  # правее шкафа
		Vector2(spot.x, shelf.end.y + half.y),  # над шкафом
	]:
		var fitted: Vector2 = clamp_pos.call(candidate)
		if Rect2(fitted - half, BOARD_EXTENT).intersects(shelf):
			continue  # упёрлось в край стены — места нет
		var distance := fitted.distance_to(center)
		if distance < best_distance:
			best = fitted
			best_distance = distance
	return best


func _room_prop_at(point: Vector2) -> String:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 20, 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return str(hit.collider.get_meta("room_prop", "")) if not hit.is_empty() else ""


func _use_room_prop(kind: String) -> void:
	_clear_shelf_selection()
	if _wall_shelf_lights.has(kind):
		_toggle_wall_shelf_light(kind)
		Sfx.play("click", -12)
		return
	if kind.begins_with("fidget"):
		_fidget_use(kind)
		return
	if kind == "ball":
		_ball_grab()
		return
	if kind == "tv":
		game_editor_requested.emit()
	elif kind == "lamp":
		_lamp_color = (_lamp_color + 1) % 3
		var tint: Color = [Color("ff3ea5"), Color("35e6d1"), Color("ffaf44")][_lamp_color]
		for blob: MeshInstance3D in _lava:
			var material := blob.material_override as StandardMaterial3D
			material.albedo_color = tint
			material.emission = tint
		shelf_hint.emit("Лавовая лампа · новый цвет")
	elif kind == "vcr" and is_instance_valid(_vcr_clock):
		_vcr_time = (_vcr_time + 1) % VCR_TIMES.size()
		_vcr_clock.text = VCR_TIMES[_vcr_time]
		var room_prefs := ConfigFile.new()
		room_prefs.load("user://room_props.cfg")  # не стирать остальное (кубик, мяч)
		room_prefs.set_value("room", "vcr_time", VCR_TIMES[_vcr_time])
		room_prefs.save("user://room_props.cfg")
		shelf_hint.emit("Видеомагнитофон · " + VCR_TIMES[_vcr_time])
	Sfx.play("click", -12)


func add_room_basket() -> void:
	if not remote_view and is_instance_valid(_basket):
		_basket.install()


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
	if remote_view:
		return
	if _ball_held:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_ball_throw()
		if event is InputEventMouse:
			get_viewport().set_input_as_handled()
			return
	if _selected_box != null and _selected_box.is_figurine() and _drag_box == null:
		var direction := 0
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				direction = -1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				direction = 1
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_Q:
				direction = -1
			elif event.keycode == KEY_E:
				direction = 1
		if direction != 0:
			_rotate_figure(direction)
			get_viewport().set_input_as_handled()
			return
	if _editor_on:
		if event is InputEventKey and event.pressed and not event.echo and event.is_command_or_control_pressed() \
				and (event.keycode == KEY_Z or event.physical_keycode == KEY_Z):
			undo_shelf_edit()
			get_viewport().set_input_as_handled()
			return
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
		if (_pose_button.visible and _pose_button.get_global_rect().has_point(event.position)
				or _transfer_button.visible and _transfer_button.get_global_rect().has_point(event.position)):
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
			pass  # удержание уже обработано, короткий клик не открывает игру
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
	if _editor_on and _pointer_clear() and _edge_drag.is_empty() and _drag_box == null and not _editor_box_press \
			and poster_dragging == null and not board_dragging and event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := 0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05
			set_shelf_camera_zoom(snappedf(Prefs.shelf_camera_zoom + step, 0.05))
			_editor_ui.call("sync_zoom")
			get_viewport().set_input_as_handled()
			return
	# Плакат переносят — ведём по стене до отпускания.
	if poster_dragging != null:
		if event is InputEventMouseMotion:
			_drag_poster(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_poster_drag()
		get_viewport().set_input_as_handled()
		return
	if _poster_press != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_poster_press = null  # короткий клик по плакату ничего не делает
		get_viewport().set_input_as_handled()
		return
	if not remote_view and focused == null and not (panels and panels.is_open) and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var poster := _poster_at(event.position)
		if poster != null:
			if _editor_on:
				_begin_poster_drag(poster, event.position)
			else:
				_poster_press = poster
				_poster_hold = 0.0
			get_viewport().set_input_as_handled()
			return
	# Доска стикеров: перенос идёт — ведём её по стене до отпускания.
	if board_dragging:
		if event is InputEventMouseMotion:
			_drag_board(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_board_drag()
		get_viewport().set_input_as_handled()
		return
	if _board_press and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_board_press = false  # короткий клик по своей доске — панель доски
		board_requested.emit(event.position)
		get_viewport().set_input_as_handled()
		return
	# Доска кликается и в своей комнате, и в комнате друга (там на неё и клеят). Свою можно перевесить:
	# в редакторе шкафа — сразу перетаскиванием, вне редактора — удержанием.
	if (focused == null or remote_view) and not (panels and panels.is_open) and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _room_prop_at(event.position) == "board":
		var pressed_board := _board_at(event.position)
		if pressed_board != null and not board_focused():
			sticker_board = pressed_board
		if remote_view:
			board_requested.emit(event.position)
		elif _editor_on:
			_begin_board_drag(event.position)
		else:
			_board_press = true
			_board_hold = 0.0
		get_viewport().set_input_as_handled()
		return
	if remote_view:
		if not remote_follow and event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var box := _box_at(event.position)
				if box != null and not box.is_figurine():
					focus(box)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				release()
		return
	if _editor_on:
		if event is InputEventMouseMotion:
			_edge_hover = _edge_at(event.position)
			Input.set_default_cursor_shape(
				(
					Input.CURSOR_ARROW
					if _edge_hover.is_empty()
					else (Input.CURSOR_HSIZE if _edge_hover.kind in ["width", "seg"] else (Input.CURSOR_POINTING_HAND if _edge_hover.kind == "ghost" else Input.CURSOR_VSIZE))
				)
			)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cells_right_click(event.position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var edge := _edge_at(event.position)
			if not edge.is_empty() and edge.kind == "ghost":
				_apply_cells(ShelfConfig.split_cell(_cabinet, _shelf_ids(), int(edge.cell), false, int(edge.top)))
			elif not edge.is_empty():
				_begin_edge_drag(edge, event.position)
			else:
				var box := _box_at(event.position)
				if box != null:
					if box != _lift_box:
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
	if focused == null and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _room_prop_at(event.position).begins_with("fidget"):
		_fidget_spin(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		get_viewport().set_input_as_handled()
		return
	if focused == null and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _room_prop_at(event.position) == "tv":
		_tv_channel = posmod(_tv_channel + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 3)
		_tv_title.text = ["РЕДАКТОР", "PLAYER ONE", "GOOD GAME"][_tv_channel]
		_blink.text = ["СОЗДАТЬ ИГРУ", "READY?", "PLAY AGAIN"][_tv_channel]
		shelf_hint.emit("Телевизор · канал%d · нажмите для редактора" % (_tv_channel + 1))
		get_viewport().set_input_as_handled()
		return
	if (
		focused == null
		and _drag_box == null
		and event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var prop := _room_prop_at(event.position)
		if not prop.is_empty() and (not _wall_shelf_lights.has(prop) or _box_at(event.position) == null):
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
				if _drag_box == null and focused == null and _pointer_clear():
					var picked := _box_at(event.position)
					if picked != null:
						_pressed_box = null
						_select_shelf_box(picked)
						get_viewport().set_input_as_handled()
						return
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


## Обновляет положение коробок, стопок и предметов на отдельных полках.
func _reflow(animate: bool) -> void:
	for r in _rows.size():
		var info: Dictionary = _row_info[r]
		var cascade := _drag_box != null and not _drag_cascade.is_empty()
		var row: Array = (_drag_cascade[r] if cascade else _rows[r]).duplicate()
		if _drag_box != null and _drag_to.x == r and not cascade and not WALL_SHELVES.has(_drag_surface.get("surface", "")):
			row.insert(_drag_to.y, _drag_box)
		var layout := _layout_row(row, r)
		if _shelf_placeholders.has(r):
			(_shelf_placeholders[r] as Node3D).visible = float(layout.width) < 0.001
		for b: GameBox in row:
			if b == _drag_box:
				continue
			var home: Transform3D = layout.boxes[_shelf_id(b)]
			home.origin += Vector3(float(info.left), float(info.floor), float(info.back))
			var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(b), {})
			var on_wall := WALL_SHELVES.has(anchor.get("surface", ""))
			b.set_wall_shelf_finish(on_wall and bool(_wall_shelf_lights.get(str(anchor.get("surface", "")), {}).get("on", false)))
			if on_wall:
				home = _wall_home(b, anchor)
			elif b.is_figurine():
				home.basis = _box_basis(b)
				if not anchor.is_empty():
					home.origin = _figure_surface_position(b, str(anchor.surface), float(anchor.x))
			_set_home(b, home, animate)
	_update_wall_shelf_shadows()


func _update_wall_shelf_shadows() -> void:
	var anchors: Dictionary = _cabinet.get("figure_surfaces", {})
	for surface: String in _wall_shelf_lights:
		var silhouettes := PackedVector4Array()
		for box: GameBox in boxes:
			var anchor: Dictionary = anchors.get(_shelf_id(box), {})
			if box == _drag_box or anchor.get("surface", "") != surface:
				continue
			var extent := _wall_item_extent(box)
			var at := _shelf_root.to_global(_wall_home(box, anchor).origin)
			silhouettes.append(Vector4(at.z, float(WALL_SHELVES[surface]), extent.z, minf(0.58, extent.y * 1.55)))
			if silhouettes.size() == 16:
				break
		var count := silhouettes.size()
		silhouettes.resize(16)
		var wash: Node3D = _wall_shelf_lights[surface].wash
		var main_plane := wash.get_child(0) as MeshInstance3D
		var material := main_plane.material_override as ShaderMaterial
		material.set_shader_parameter("silhouettes", silhouettes)
		material.set_shader_parameter("silhouette_count", count)


## Единая раскладка стопок для изображения, проверки вместимости и переноса.
func _layout_row(row: Array, cell: int) -> Dictionary:
	var entering := _shelf_id(_drag_box) if _drag_box != null and _drag_surface.is_empty() else ""
	var layout := ShelfConfig.row_layout(
		row.map(func(box): return _shelf_id(box)),
		ShelfConfig.sizes_on_shelf(_cabinet, _shelf_sizes(), entering),
		_box_modes,
		float(_row_info[cell].get("height", CELL_H)),
		ShelfConfig.figure_ratios(_cabinet),
		float(_row_info[cell].right) - float(_row_info[cell].left)
	)
	var positions: Dictionary = _cabinet.get("box_positions", {})
	if positions.is_empty():
		return layout
	var info: Dictionary = _row_info[cell]
	var capacity := float(info.right) - float(info.left)
	var limit := capacity
	var piles: Array = layout.piles
	for index in range(piles.size() - 1, -1, -1):
		var pile: Dictionary = piles[index]
		var left := float(pile.x)
		var width := float(pile.width)
		for box: GameBox in row:
			if not box.is_figurine() or _cabinet.get("figure_surfaces", {}).has(_shelf_id(box)):
				continue
			var home: Transform3D = layout.boxes[_shelf_id(box)]
			var obstacle := home.origin.x - _figure_cabinet_extent(box).x * 0.5
			if obstacle >= left + width - 0.0005:
				limit = minf(limit, obstacle)
		var share := -1.0
		for id: String in pile.ids:
			if positions.has(id):
				share = float(positions[id])
				break
		if share >= 0.0:
			var placed := clampf(share * capacity - width * 0.5, left, maxf(left, limit - width))
			for id: String in pile.ids:
				var home: Transform3D = layout.boxes[id]
				home.origin.x += placed - left
				layout.boxes[id] = home
			pile.x = placed
			layout.width = maxf(float(layout.width), placed + width)
		limit = float(pile.x)
	return layout


## Первое удержание оставляет коробку на полке и открывает кнопку положения.
func _select_shelf_box(box: GameBox) -> void:
	_clear_shelf_selection()
	_selected_box = box
	box.stop_shelf_motion()
	box.transform = box.home
	box.set_swap_highlight(true)
	_hover = null
	_update_pose_button()
	if box.is_figurine():
		shelf_hint.emit("Колесо мыши ↕, Q, E — повернуть · удерживайте ЛКМ для переноса")
		return
	_lift(box)
	shelf_hint.emit("Коробка выделена · кнопки меняют положение или переносят на полку · удерживайте ЛКМ для переноса")


func _clear_shelf_selection() -> void:
	_settle_lift()
	if is_instance_valid(_selected_box):
		_selected_box.set_swap_highlight(false)
	_selected_box = null
	if is_instance_valid(_pose_button):
		_pose_button.visible = false
		_transfer_button.visible = false


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
	tw.tween_property(b, "transform", home, 0.12)
	b.set_meta("slide", tw)


## Удержание сработало: коробка снимается с полки и едет за курсором.
func _start_drag() -> void:
	if remote_view:
		return
	var b := _pressed_box
	_drag_surface = {}
	_hold_handled = true
	_drag_cascade = []
	if b != null and b == _lift_box:
		# коробка уже выдвинута: с полки она снята, отмена вернёт её туда, где стояла до выдвижения
		_drag_backup = _lift_backup
		_drag_original_mode = _lift_mode
		_drag_from = Vector2i(_lift_from.x, mini(_lift_from.y, (_rows[_lift_from.x] as Array).size()))
		_lift_box = null
		_lift_backup = {}
	else:
		_settle_lift()
		_drag_backup = {
			"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true)
		}
		_adopt_neighbor_order()
		_drag_original_mode = int(_box_modes.get(_shelf_id(b), 1))
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
	if b.is_figurine():
		shelf_hint.emit("Ведите фигурку на полку, шкаф, телевизор или тумбу. Отпустите, чтобы поставить")
	# Предмет вне шкафа при захвате остаётся на своём месте.
	if b.is_figurine() or WALL_SHELVES.has((_cabinet.get("figure_surfaces", {}).get(_shelf_id(b), {}) as Dictionary).get("surface", "")):
		var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(b), {})
		if _drag_surface.is_empty() and not anchor.is_empty():
			_drag_surface = anchor.duplicate()
			_drag_at = b.home.origin
			_drag_to = _drag_from
			_drag_cascade = []
			_reflow(true)
	_update_pose_button()


## Курсор двигается с коробкой: какая полка ближе и между какими коробками она встанет.
func _wall_drag_only() -> bool:
	if _drag_box == null:
		return false
	var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(_drag_box), {})
	return WALL_SHELVES.has(anchor.get("surface", "")) or (_looking_left and not _editor_on)


func _drag_update(screen: Vector2) -> void:
	if _drag_box == null:
		return
	_drag_surface = {}
	if _wall_drop(screen):
		return
	if _wall_drag_only():
		var span := _wall_span(_drag_box, "wall_lower")
		var origin := camera.project_ray_origin(screen)
		var ray := camera.project_ray_normal(screen)
		if absf(ray.x) > 0.0001:
			var plane_x := span[0].x + DRAG_LIFT
			_drag_at = _shelf_root.to_local(origin + ray * ((plane_x - origin.x) / ray.x))
		_drag_to = Vector2i(-1, -1)
		_drag_cascade = []
		_reflow(true)
		_drag_box.set_swap_highlight(true, false)
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		shelf_hint.emit("Ведите предмет к одной из настенных полок")
		return
	if _drag_box.is_figurine():
		for surface: String in FIGURE_SURFACES:
			var span := _figure_surface_span(_drag_box, surface)
			if span[1].x < span[0].x:
				continue
			var a := camera.unproject_position(_shelf_root.to_global(span[0]))
			var b := camera.unproject_position(_shelf_root.to_global(span[1]))
			var delta := b - a
			var fraction := clampf((screen - a).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
			# попадание — по всей высоте фигурки на экране (держат и за голову, и за подставку)
			var half_h := a.distance_to(camera.unproject_position(_shelf_root.to_global(span[0] + Vector3(0, _drag_box.size.y * 0.5, 0))))
			if screen.distance_to(a.lerp(b, fraction)) < maxf(42.0, half_h + 16.0):
				# Доля на экране искажена перспективой: место берём по лучу в плоскости поверхности.
				var inv_root := _shelf_root.global_transform.affine_inverse()
				var ray_o := inv_root * camera.project_ray_origin(screen)
				var ray_d := inv_root.basis * camera.project_ray_normal(screen)
				if absf(ray_d.z) > 0.0001 and span[1].x - span[0].x > 0.0001:
					var hit := ray_o + ray_d * ((span[0].z - ray_o.z) / ray_d.z)
					fraction = clampf((hit.x - span[0].x) / (span[1].x - span[0].x), 0.0, 1.0)
				var point := _figure_surface_position(_drag_box, surface, fraction)
				var clear := true
				for other: GameBox in boxes:
					if other == _drag_box or not other.is_figurine():
						continue
					var anchor: Dictionary = _cabinet.get("figure_surfaces", {}).get(_shelf_id(other), {})
					if anchor.get("surface", "") == surface:
						clear = clear and absf(other.home.origin.x - point.x) >= _figure_radius(other) + _figure_radius(_drag_box) + 0.008
				if clear:
					_drag_surface = {"surface": surface, "x": fraction}
					_drag_at = point
					_drag_to = _drag_from
					_drag_cascade = []
					_reflow(true)
					_drag_box.set_swap_highlight(true, true)
					return
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
				(_drag_at.x - midpoint.x) / maxf(0.1, float(cell.right) - float(cell.left)),
				(_drag_at.y - midpoint.y) / float(cell.get("height", CELL_H))
			)
			. length_squared()
		)
		if distance < nearest:
			nearest = distance
			r = k
	var row: Array = _rows[r]
	var info: Dictionary = _row_info[r]
	var figure_changed := false
	if _drag_box.is_figurine():
		# Фигурка не привязана к краю ячейки: стоит там, куда её ведут, коробки обтекают её.
		var capacity: float = float(info.right) - float(info.left)
		var figure_width := _figure_cabinet_extent(_drag_box).x
		var share: float = clampf((_drag_at.x - float(info.left) - figure_width * 0.5) / maxf(0.001, capacity - figure_width), 0.0, 1.0)
		if not _cabinet.has("figure_cells"):
			_cabinet.figure_cells = {}
		var id := _shelf_id(_drag_box)
		figure_changed = absf(float(_cabinet.figure_cells.get(id, -1.0)) - share) > 0.01
		_cabinet.figure_cells[id] = share
	var layout := _layout_row(row, r)
	var index := ShelfOrder.pile_insert_index(
		layout.piles, row.map(func(box): return _shelf_id(box)), _drag_at.x - float(info.left)
	)
	if not _drag_box.is_figurine():
		var positions: Dictionary = _cabinet.get_or_add("box_positions", {})
		var id := _shelf_id(_drag_box)
		var share := clampf(inverse_lerp(float(info.left), float(info.right), _drag_at.x), 0.0, 1.0)
		figure_changed = absf(float(positions.get(id, -1.0)) - share) > 0.001
		positions[id] = share
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
	var cascade: Array = []
	if (
		not fits
		and occupied.y <= float(info.get("height", CELL_H)) + 0.0005
		and occupied.z <= CELL_D + 0.0005
	):
		cascade = _cascade_rows(r, index)
		fits = not cascade.is_empty()
	var to := Vector2i(r, index) if fits else Vector2i(-1, -1)
	if to == _drag_to and cascade == _drag_cascade and not figure_changed:
		return
	_drag_to = to
	_drag_cascade = cascade
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


## Ящик переполнен: лишние предметы по цепочке уходят в соседние ящики (сначала вперёд, затем назад).
## Переносимая коробка и стаканчики Перудо остаются на месте; пусто — места во всём шкафу не хватает.
func _cascade_rows(cell: int, index: int) -> Array:
	for direction: int in [1, -1]:
		var trial: Array = []
		for row: Array in _rows:
			trial.append(row.duplicate())
		(trial[cell] as Array).insert(index, _drag_box)
		var at := cell
		var ok := true
		while _row_overflows(trial[at], at):
			var next := at + direction
			if next < 0 or next >= trial.size():
				ok = false
				break
			var row: Array = trial[at]
			var pick := -1
			var order: Array = range(row.size() - 1, -1, -1) if direction > 0 else range(row.size())
			for k: int in order:
				var item: GameBox = row[k]
				if item != _drag_box and not item.is_cups() and not _cabinet.get("figure_surfaces", {}).has(_shelf_id(item)):
					pick = k
					break
			if pick < 0:
				ok = false
				break
			var moved: GameBox = row[pick]
			var height := ShelfConfig.item_occupied(_shelf_id(moved), moved.size, int(_box_modes.get(_shelf_id(moved), 1))).y
			if height > float(_row_info[next].get("height", CELL_H)) + 0.0005:
				ok = false
				break
			row.remove_at(pick)
			if direction > 0:
				(trial[next] as Array).insert(0, moved)
			else:
				(trial[next] as Array).append(moved)
			at = next
		if ok:
			return trial
	return []


func _row_overflows(row: Array, cell: int) -> bool:
	var info: Dictionary = _row_info[cell]
	return float(_layout_row(row, cell).width) > float(info.right) - float(info.left) + 0.0005


## Отпустили: коробка встаёт в щель (или возвращается, если поставить некуда / отпустили над интерфейсом).
func _finish_drag(ok: bool) -> void:
	var b := _drag_box
	if not ok or _drag_to.x < 0:
		_box_modes[_shelf_id(b)] = _drag_original_mode
	var to := _drag_to if ok and _drag_to.x >= 0 else _drag_from
	var moved: bool = (
		to != _drag_from
		or int(_box_modes.get(_shelf_id(b), 1)) != _drag_original_mode
		or not bool(_drag_backup.get("config", {}).get("neighbor_order", false))
	)
	if ok and _drag_to.x >= 0:
		if not _cabinet.has("figure_surfaces"):
			_cabinet.figure_surfaces = {}
		var id := _shelf_id(b)
		var old_anchor: Dictionary = _cabinet.figure_surfaces.get(id, {})
		moved = moved or old_anchor != _drag_surface
		if _drag_surface.is_empty():
			_cabinet.figure_surfaces.erase(id)
		else:
			_cabinet.figure_surfaces[id] = _drag_surface.duplicate()
			(_cabinet.get("figure_cells", {}) as Dictionary).erase(id)  # на тумбе/ТВ — не в ячейке
		# Сдвинули фигурку по ячейке — это тоже перестановка (сохраняется).
		var old_config: Dictionary = _drag_backup.get("config", {})
		moved = moved or _cabinet.get("figure_cells", {}) != old_config.get("figure_cells", {})
		moved = moved or _cabinet.get("box_positions", {}) != old_config.get("box_positions", {})
	var cancelled := not ok or _drag_to.x < 0
	if not cancelled and not _drag_cascade.is_empty():
		_rows = _drag_cascade.duplicate()
		moved = true
	else:
		(_rows[to.x] as Array).insert(to.y, b)
	_drag_cascade = []
	_drag_box = null
	_drag_surface = {}
	if cancelled:
		_apply_shelf_state(_drag_backup)
		moved = false
	_drag_backup = {}
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
		if b.game.get("id", "") == game_id or b.game.get("variants", []).has(game_id):
			if b.game.get("id", "") != game_id:
				b.set_variant(HubGames.by_id(game_id))
			focus(b)
			return


## Часы компьютера игрока, а не время комнаты хоста или длительность игры.
func _update_alarm_clock() -> void:
	if not is_instance_valid(_alarm_clock):
		return
	var now := Time.get_time_dict_from_system()
	var second: int = now.hour * 3600 + now.minute * 60 + now.second
	if second == _alarm_second:
		return
	_alarm_second = second
	_alarm_clock.text = "%02d:%02d" % [now.hour, now.minute]

func _process(delta: float) -> void:
	_ball_step(delta)
	_update_alarm_clock()
	# Доска плавно едет к свободному месту (шкаф в редакторе стал шире/уже — отъезжает и возвращается).
	var snap := _board_snap_frames > 0
	_board_snap_frames = maxi(0, _board_snap_frames - 1)
	for bid: Variant in _board_homes:
		var board: Node3D = boards.get(bid, null)
		if not is_instance_valid(board) or (board_dragging and board == sticker_board):
			continue
		var target := board_free_spot(_board_homes[bid])
		var now := Vector2(board.position.x, board.position.y)
		var next := now.lerp(target, 1.0 - exp(-10.0 * delta)) if now.distance_to(target) > 0.002 and not snap else target
		board.position = Vector3(next.x, next.y, _board_depth(next, board))
	if _poster_press != null:
		_poster_hold += delta
		if _poster_hold >= BOX_HOLD:
			var poster := _poster_press
			_poster_press = null
			_begin_poster_drag(poster, get_viewport().get_mouse_position())
	if _board_press:
		_board_hold += delta
		if _board_hold >= BOX_HOLD:
			_board_press = false
			_begin_board_drag(get_viewport().get_mouse_position())
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
		_watch_undo(delta)
	if _pressed_box != null and _drag_box == null and not _hold_handled:
		_hold_time += delta
		if _hold_time >= BOX_HOLD:
			_hold_handled = true
			_start_drag()
	var floating: GameBox = _drag_box if _drag_box != null else _lift_box
	if floating != null:
		# взятая коробка плавно едет за курсором, выдвинутая из шкафа; выделенная — висит перед своим местом
		var carried := _drag_box != null
		var info: Dictionary = _row_info[0]
		var ext := _box_extent(floating)
		var lo: float = float(_row_info[_row_info.size() - 1].floor) + ext.y / 2.0
		var hi: float = float(info.floor) + ext.y / 2.0
		var drag_z: float = float(info.back) + ext.z * 0.5 + DRAG_LIFT
		if int(_box_modes.get(_shelf_id(floating), 1)) in [0, 1, 2, 3] or floating.is_cups():
			drag_z = float(info.back) + CELL_D - 0.024 - ext.z * 0.5 + DRAG_LIFT
		if floating.is_figurine():
			drag_z = float(info.back) + CELL_D - 0.024 - ext.z * 0.5
		var at := _drag_at if carried else _lift_floor + Vector3(0, ext.y * 0.5 + 0.012 + sin(_t * 2.4) * 0.004, 0)
		if not carried:
			drag_z += LIFT_OUT
		var want := Vector3(
			clampf(at.x, float(info.left) + ext.x / 2.0, _inner_right - 0.003 - ext.x / 2.0),
			clampf(at.y, lo, hi + 0.02),
			drag_z
		)
		var wall_pose := carried and (WALL_SHELVES.has(_drag_surface.get("surface", "")) or _wall_drag_only())
		if carried and (not _drag_surface.is_empty() or wall_pose):
			want = _drag_at
		floating.transform = floating.transform.interpolate_with(
			Transform3D(
				_box_basis(floating).rotated(Vector3.UP, PI * 0.5) if wall_pose else _box_basis(floating),
				want
			), 1.0 - exp(-delta * (32.0 if carried else 12.0))
		)
	_t += delta
	# лёгкое «дыхание» камеры и параллакс от мыши
	var vp := get_viewport()
	var m := vp.get_mouse_position() / Vector2(vp.get_visible_rect().size) - Vector2(0.5, 0.5)
	if not Prefs.parallax:
		m = Vector2.ZERO  # параллакс выключен в настройках
	var sway := Vector3(sin(_t * 0.35) * 0.008, sin(_t * 0.5) * 0.006, 0)
	var inside_front_wall := camera.position.z < ROOM_FRONT - 0.12
	camera.set_cull_mask_value(20, inside_front_wall)
	var target := _cam_home
	target.origin += sway
	target.basis = target.basis.rotated(Vector3.UP, -m.x * 0.03).rotated(
		target.basis.x.normalized(), -m.y * 0.02
	)
	camera.transform = camera.transform.interpolate_with(target, minf(1.0, delta * 3.0))
	camera.fov = lerpf(camera.fov, _shelf_camera_fov(), 1.0 - exp(-delta * 13.0))
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




## Снимок всегда собственный, даже если на экране временно показан чужой шкаф.
func public_snapshot() -> Dictionary:
	if remote_view:
		return _local_room.public.duplicate(true)
	# Взятый предмет временно отсутствует в _rows; публикуем последнее целое состояние.
	var state: Dictionary = _drag_backup if _drag_box != null else {
		"config": _cabinet, "placements": _shelf_ids(), "poses": _box_modes
	}
	var custom := {}
	for box: GameBox in boxes:
		var id := str(box.game.get("id", ""))
		if id.begins_with("custom:"):
			custom[id] = {"title": str(box.game.get("title", "Своя игра")).left(64), "size": [box.size.x, box.size.y, box.size.z]}
	var frame: Transform3D = _cam_home if _board_cam_saved == null else _board_cam_saved
	var orientation := frame.basis.get_rotation_quaternion()
	return PublicRoom.clean({
		"config": state.config, "placements": state.placements, "poses": state.poses,
		"selected": str(focused.game.get("id", "")) if focused != null else "",
		"editor": _editor_on, "custom": custom,
		"camera": {"zoom": Prefs.shelf_camera_zoom, "frame": [
			frame.origin.x, frame.origin.y, frame.origin.z, orientation.x, orientation.y, orientation.z, orientation.w
		]}
	})


func show_remote(snapshot: Dictionary, follow: bool = true) -> bool:
	var clean := PublicRoom.clean(snapshot)
	if clean.is_empty():
		return false
	# Фигурки друга, которых у нас нет (своя из мастерской, другая версия), пока не показываем —
	# убираем их из раскладки, остальное стоит как у него. Позже здесь можно скачивать модель.
	var known: Array = (_local_room.get("boxes", boxes) as Array).map(func(box): return _shelf_id(box))
	for r in clean.placements.size():
		clean.placements[r] = (clean.placements[r] as Array).filter(func(id): return not ShelfConfig.is_figure(id) or known.has(id))
	var ids: Array = []
	for row in clean.placements:
		ids.append_array(row)
	if not remote_view:
		if _editor_on:
			finish_shelf_editor(false)
		_cancel_drag()
		var variants: Dictionary = {}
		for box: GameBox in boxes:
			variants[_shelf_id(box)] = box.game.duplicate(true)
		_local_room = {
			"boxes": boxes.duplicate(), "remote_boxes": [], "custom": null,
			"variants": variants,
			"public": public_snapshot(),
			"state": {"config": _cabinet.duplicate(true), "placements": _shelf_ids(), "poses": _box_modes.duplicate(true)},
			"preferences": _editor_preferences.duplicate(true),
			"geometry": _editor_preference_geometry.duplicate(true), "camera": _cam_home
		}
		remote_view = true
		panels.deselect()
		panels.input_locked = true
	# Друг на другой версии: наших игр/фигурок, которых нет у него, в его шкафу не показываем
	# (вернутся домой — return_home покажет всё); появились у него после обновления — показываем снова.
	for box: GameBox in boxes.duplicate():
		var id := _shelf_id(box)
		if not id.begins_with("custom:") and not ids.has(id):
			if focused == box:
				release()
			box.hide()
			boxes.erase(box)
	for box: GameBox in _local_room.boxes:
		var id := _shelf_id(box)
		if not id.begins_with("custom:") and ids.has(id) and not boxes.has(box):
			box.show()
			boxes.append(box)
	var custom_changed: bool = _local_room.custom != clean.custom
	if custom_changed:
		if focused != null and _local_room.remote_boxes.has(focused):
			release()
		for box: GameBox in _local_room.remote_boxes:
			boxes.erase(box)
			box.free()
		_local_room.remote_boxes = []
		for box: GameBox in _local_room.boxes:
			if str(box.game.id).begins_with("custom:"):
				box.hide()
				boxes.erase(box)
		for id: String in clean.custom:
			var meta: Dictionary = clean.custom[id]
			var extent: Array = meta.size
			var box := GameBox.new()
			box.setup({"id": id, "title": meta.title, "custom": true, "remote": true, "players": "Игра друга", "time": "", "description": "", "scene": "", "box_size": Vector3(extent[0], extent[1], extent[2])}, Vector3(extent[0], extent[1], extent[2]), Color("655080"))
			_shelf_root.add_child(box)
			boxes.append(box)
			_local_room.remote_boxes.append(box)
		_local_room.custom = clean.custom.duplicate(true)
	remote_follow = follow
	_remote_zoom = float(clean.get("camera", {}).get("zoom", 1.0))
	var state_changed: bool = custom_changed or _cabinet != clean.config or _shelf_ids() != clean.placements or _box_modes != clean.poses
	if state_changed:
		var local_selected: String = _shelf_id(focused) if focused != null else ""
		var saved_camera := camera.transform
		var saved_home := _cam_home
		release()
		_clear_shelf_selection()
		_apply_shelf_state(clean)
		if remote_follow:
			_frame_shelf()
		else:
			camera.transform = saved_camera
			_cam_home = saved_home
			if local_selected != "":
				focus_id(local_selected)
	_remote_editor = clean.editor
	var frame: Array = clean.get("camera", {}).get("frame", [])
	if remote_follow and not frame.is_empty():
		var rotation := Quaternion(frame[3], frame[4], frame[5], frame[6])
		var owner_frame := Transform3D(Basis(rotation), Vector3(frame[0], frame[1], frame[2]))
		if board_focused():
			_board_cam_saved = owner_frame
		else:
			_cam_home = owner_frame
	if remote_follow and (state_changed or _remote_selected != clean.selected):
		release()
		if clean.selected != "":
			focus_id(clean.selected)
	_remote_selected = clean.selected
	return true


func return_home() -> void:
	if not remote_view:
		return
	release()
	_cancel_drag()
	remote_view = false
	panels.input_locked = false
	for box: GameBox in _local_room.remote_boxes:
		boxes.erase(box)
		box.free()
	boxes.assign(_local_room.boxes)
	for box: GameBox in boxes:
		box.show()
	for box: GameBox in boxes:
		if box.game != _local_room.variants[_shelf_id(box)]:
			box.set_variant(_local_room.variants[_shelf_id(box)])
	_apply_shelf_state(_local_room.state)
	_editor_preferences = _local_room.preferences.duplicate(true)
	_editor_preference_geometry = _local_room.geometry.duplicate(true)
	_cam_home = _local_room.camera
	camera.transform = _cam_home
	var selected: String = _local_room.public.selected
	_local_room = {}
	_remote_selected = ""
	if selected != "":
		focus_id(selected)
