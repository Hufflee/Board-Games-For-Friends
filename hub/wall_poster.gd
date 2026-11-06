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
var picture: Texture2D
var picture_key := ""  # что сейчас показано: путь стандартной картинки или хэш своей
var _quad: MeshInstance3D
var _frame: MeshInstance3D
var _shape: BoxShape3D
var _material: StandardMaterial3D


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
func set_picture(texture: Texture2D, key: String) -> void:
	picture = texture
	picture_key = key
	var aspect := clampf(float(texture.get_width()) / maxf(1.0, float(texture.get_height())), ASPECT_RANGE.x, ASPECT_RANGE.y)
	var size := Vector2(sqrt(AREA * aspect), sqrt(AREA / aspect))
	(_quad.mesh as QuadMesh).size = size
	_material.albedo_texture = texture
	_material.emission_texture = texture
	(_frame.mesh as BoxMesh).size = Vector3(size.x + BORDER * 2.0, size.y + BORDER * 2.0, 0.005)
	_shape.size = Vector3(size.x + BORDER * 2.0, size.y + BORDER * 2.0, 0.03)
	_quad.set_meta("poster_source", key)


## Плакат с рамкой на стене (x, y; без учёта небольшого наклона).
func wall_size() -> Vector2:
	var size: Vector2 = (_quad.mesh as QuadMesh).size if is_instance_valid(_quad) else Vector2(0.46, 0.34)
	return size + Vector2.ONE * BORDER * 2.0


func wall_rect() -> Rect2:
	var extent := wall_size()
	return Rect2(Vector2(position.x, position.y) - extent / 2.0, extent)
