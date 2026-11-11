extends Node3D
## Плакат на стене комнаты хаба (NeonRoom). Картинку можно заменить своей фотографией (hub/poster_ui.gd):
## белая рамка подстраивается под пропорции картинки, а площадь плаката всегда одна и та же — большая
## фотография не делает плакат больше, а только чётче. Плакат можно перевесить удержанием (как доску друзей).
## Клик/удержание — декор room_prop «poster» (слой 8), номер плаката — meta poster_slot.

const AREA := 0.46 * 0.34  # м²: «средний размер» плаката
const ASPECT_RANGE := Vector2(0.4, 2.5)
const BORDER := 0.015  # белая рамка с каждой стороны

var slot := 0
var default_path := ""
var tilt := 0.0  # небольшой наклон «как повесили»
var picture: Resource
var picture_key := ""  # что сейчас показано: путь стандартной картинки или хэш своей
var size_scale := 1.0  # 1 — обычный плакат, до 2 — вдвое больше (по стороне)
var _quad: MeshInstance3D
var _frame: MeshInstance3D
var _shape: BoxShape3D
var _material: StandardMaterial3D
var _animation: SpriteFrames
var _frame_index := 0
var _frame_time := 0.0


func setup(index: int, path: String, angle: float) -> void:
	slot = index
	default_path = path
	tilt = angle


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.roughness = 0.6
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.25
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_quad.material_override = _material
	_quad.position.z = 0.001
	add_child(_quad)
	_frame = MeshInstance3D.new()
	_frame.mesh = BoxMesh.new()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f6f0ff")
	white.roughness = 0.7
	_frame.material_override = white
	_frame.position.z = -0.004
	add_child(_frame)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.set_meta("room_prop", "poster")
	body.set_meta("poster_slot", slot)
	_shape = BoxShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	body.add_child(collider)
	add_child(body)
	rotation.z = tilt
	show_default()


func show_default() -> void:
	if picture_key == default_path:
		return
	var texture: Texture2D = load(default_path) if ResourceLoader.exists(default_path) else null
	if texture != null:
		set_picture(texture, default_path)


## Новая картинка: пропорции — от картинки, площадь — постоянная.
func set_picture(source: Resource, key: String) -> void:
	if source != picture:
		_animation = source as SpriteFrames
		_frame_index = 0
		_frame_time = 0.0
		set_process(_animation != null)
	picture = source
	picture_key = key
	var texture := _animation.get_frame_texture(&"default", _frame_index) if _animation != null else source as Texture2D
	var aspect := clampf(float(texture.get_width()) / maxf(1.0, float(texture.get_height())), ASPECT_RANGE.x, ASPECT_RANGE.y)
	var size := Vector2(sqrt(AREA * aspect), sqrt(AREA / aspect)) * size_scale
	(_quad.mesh as QuadMesh).size = size
	_set_frame_texture(texture)
	(_frame.mesh as BoxMesh).size = Vector3(size.x + BORDER * 2.0, size.y + BORDER * 2.0, 0.005)
	_shape.size = Vector3(size.x + BORDER * 2.0, size.y + BORDER * 2.0, 0.03)
	_quad.set_meta("poster_source", key)


func _process(delta: float) -> void:
	if _animation == null or not is_visible_in_tree():
		return
	_frame_time += minf(delta, 0.25)
	var duration := _animation.get_frame_duration(&"default", _frame_index)
	var next := _frame_index
	while _frame_time >= duration:
		_frame_time -= duration
		next = (next + 1) % _animation.get_frame_count(&"default")
		duration = _animation.get_frame_duration(&"default", next)
	if next != _frame_index:
		_frame_index = next
		_set_frame_texture(_animation.get_frame_texture(&"default", _frame_index))


func _set_frame_texture(texture: Texture2D) -> void:
	_material.albedo_texture = texture
	_material.emission_texture = texture
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if texture.has_alpha() else BaseMaterial3D.TRANSPARENCY_DISABLED


## Размер плаката (1..2): площадь растёт, пропорции картинки те же.
func set_size_scale(scale: float) -> void:
	if is_equal_approx(scale, size_scale) or picture == null:
		size_scale = scale
		return
	size_scale = scale
	set_picture(picture, picture_key)


## Плакат с рамкой на стене (x, y; без учёта небольшого наклона).
func wall_size() -> Vector2:
	var size: Vector2 = (_quad.mesh as QuadMesh).size if is_instance_valid(_quad) else Vector2(0.46, 0.34)
	return size + Vector2.ONE * BORDER * 2.0


func wall_rect() -> Rect2:
	var extent := wall_size()
	return Rect2(Vector2(position.x, position.y) - extent / 2.0, extent)
