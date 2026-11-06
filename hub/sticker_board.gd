extends Node3D
## Маркерная доска (белая, в алюминиевой рамке) на стене комнаты хаба: на неё друзья клеят стикеры (в режиме наблюдения).
## Строится из примитивов; клик по ней — декор room_prop «board» (слой 8, как телевизор и лампа).
## show_stickers(list) — стикеры доски (hub/stickers.gd): [uid, id, u, v, поворот, автор, ник].

const StickerArt := preload("res://hub/stickers.gd")
const SIZE := Vector2(0.5, 0.38)  # м: белое поле без рамки
const SIDE := 0.38 * 0.27  # м: сторона стикера размера 1
const FRAME := 0.028
const MARKER_FONT := preload("res://hub/art/fonts/Neucha-Regular.ttf")

var _stickers: Node3D
var _shown: Array = []
var _shown_once := false
var _count: Label3D


func _ready() -> void:
	# Маркерная доска (по референсам владельца): белая глянцевая эмаль, алюминиевая рамка с серыми уголками,
	# полочка снизу с маркером.
	var surface := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(SIZE.x, SIZE.y, 0.012)
	surface.mesh = body
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color("f4f5f8")
	enamel.roughness = 0.42
	enamel.metallic_specular = 0.35
	enamel.emission_enabled = true  # в синем ночном свете комнаты белое не должно уходить в серо-фиолетовое
	enamel.emission = Color("eef0f6")
	enamel.emission_energy_multiplier = 0.18
	surface.material_override = enamel
	add_child(surface)
	var aluminium := StandardMaterial3D.new()
	aluminium.albedo_color = Color("c3c8cf")
	aluminium.metallic = 0.8
	aluminium.roughness = 0.32
	for side: Array in [[Vector3(0, SIZE.y / 2.0 + FRAME / 2.0, 0.006), Vector3(SIZE.x + FRAME * 2.0, FRAME, 0.022)],
			[Vector3(0, -SIZE.y / 2.0 - FRAME / 2.0, 0.006), Vector3(SIZE.x + FRAME * 2.0, FRAME, 0.022)],
			[Vector3(-SIZE.x / 2.0 - FRAME / 2.0, 0, 0.006), Vector3(FRAME, SIZE.y, 0.022)],
			[Vector3(SIZE.x / 2.0 + FRAME / 2.0, 0, 0.006), Vector3(FRAME, SIZE.y, 0.022)]]:
		_part(side[1], side[0], aluminium)
	var corner := StandardMaterial3D.new()
	corner.albedo_color = Color("6f7680")
	corner.roughness = 0.55
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			_part(Vector3(FRAME * 1.25, FRAME * 1.25, 0.026), Vector3(x * (SIZE.x / 2.0 + FRAME / 2.0), y * (SIZE.y / 2.0 + FRAME / 2.0), 0.008), corner)
	# Полочка под маркеры и сам маркер (белый корпус, чёрный колпачок).
	_part(Vector3(SIZE.x * 0.55, 0.012, 0.035), Vector3(0, -SIZE.y / 2.0 - FRAME - 0.004, 0.02), aluminium)
	var marker_body := StandardMaterial3D.new()
	marker_body.albedo_color = Color("f2f2f2")
	marker_body.roughness = 0.4
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("1d1f24")
	cap.roughness = 0.4
	_part(Vector3(0.085, 0.014, 0.014), Vector3(0.05, -SIZE.y / 2.0 - FRAME + 0.006, 0.026), marker_body)
	_part(Vector3(0.024, 0.016, 0.016), Vector3(0.0, -SIZE.y / 2.0 - FRAME + 0.006, 0.026), cap)
	# Подпись от руки чёрным маркером: рукописный Neucha, утолщённый, чуть наискосок.
	var marker := FontVariation.new()
	marker.base_font = MARKER_FONT
	marker.variation_embolden = 0.9
	var caption := Label3D.new()
	caption.text = "Доска друзей"
	caption.font = marker
	caption.font_size = 58
	caption.pixel_size = 0.00095
	caption.modulate = Color("16171b")
	caption.outline_size = 0
	caption.double_sided = false
	caption.rotation.z = 0.025
	caption.position = Vector3(0.0, SIZE.y / 2.0 - 0.036, 0.0064)
	add_child(caption)
	_count = Label3D.new()
	_count.font = marker
	_count.font_size = 40
	_count.pixel_size = 0.00095
	_count.modulate = Color("16171b")
	_count.outline_size = 0
	_count.position = Vector3(SIZE.x / 2.0 - 0.04, -SIZE.y / 2.0 + 0.028, 0.0064)
	add_child(_count)
	_stickers = Node3D.new()
	add_child(_stickers)
	var prop := StaticBody3D.new()
	prop.collision_layer = 8
	prop.collision_mask = 0
	prop.set_meta("room_prop", "board")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x + FRAME * 2.0, SIZE.y + FRAME * 2.0, 0.04)
	collider.shape = box
	prop.add_child(collider)
	add_child(prop)
	show_stickers([])


func _part(dimensions: Vector3, at: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	part.mesh = shape
	part.position = at
	part.material_override = material
	add_child(part)


func show_stickers(list: Array) -> void:
	if list == _shown and _stickers.get_child_count() == list.size():
		return
	# Новые стикеры (uid, которого не было) шлёпаются с анимацией; при первом показе доски — без неё.
	var known := {}
	for entry: Array in _shown:
		known[str(entry[0])] = true
	var animate := _shown_once
	_shown_once = true
	_shown = list.duplicate(true)
	for child in _stickers.get_children():
		_stickers.remove_child(child)
		child.free()
	var side := SIDE
	for i in list.size():
		var entry: Array = list[i]
		var k := float(entry[7]) if entry.size() > 7 else 1.0
		var at := Transform3D(Basis(Vector3.BACK, float(entry[4])), Vector3((float(entry[2]) - 0.5) * SIZE.x, (0.5 - float(entry[3])) * SIZE.y, 0.0065 + i * 0.0002))
		# Край стикера за белым полем (на рамке) обрезается.
		var quad := StickerArt.make_quad(str(entry[1]), side * k, at, Vector3(SIZE.x / 2.0, SIZE.y / 2.0, 1000.0))
		if quad != null:
			_stickers.add_child(quad)
			if animate and not known.has(str(entry[0])):
				StickerArt.slap(quad, Vector3.BACK)
	_count.text = "%d" % list.size() if not list.is_empty() else ""


## Точка экрана → доли белого поля (u, v от левого верхнего угла); мимо доски — (-1, -1).
func uv_at(camera: Camera3D, point: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(point)
	var normal := camera.project_ray_normal(point)
	var plane := Plane(global_transform.basis.z.normalized(), global_position + global_transform.basis.z.normalized() * 0.006)
	var hit: Variant = plane.intersects_ray(origin, normal)
	if hit == null:
		return Vector2(-1, -1)
	var local: Vector3 = global_transform.affine_inverse() * (hit as Vector3)
	var uv := Vector2(local.x / SIZE.x + 0.5, 0.5 - local.y / SIZE.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


## Центр доски на экране — для панели рядом с ней.
func screen_rect(camera: Camera3D) -> Rect2:
	var a := camera.unproject_position(global_transform * Vector3(-SIZE.x / 2.0, SIZE.y / 2.0, 0))
	var b := camera.unproject_position(global_transform * Vector3(SIZE.x / 2.0, -SIZE.y / 2.0, 0))
	return Rect2(a, b - a).abs()
