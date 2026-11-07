class_name ShelfFigurine
extends GameBox
## Личная фигурка на полке: статичная подготовленная поза, общее выделение и перенос, без запуска игры.

const MODEL := "res://hub/art/figurine/shelf_girl.glb"
## Фигурки из Tripo AI: цвет почищен tools/figures/fix_glb_colors.py; модель высотой 1, лицом к +Z.
const TRIPO := {
	"shelf_mummy": "res://hub/art/figurine/tripo_mummy.glb",
	"shelf_fighter": "res://hub/art/figurine/tripo_fighter.glb",
	"shelf_anime": "res://hub/art/figurine/tripo_anime.glb",
}


func _init() -> void:
	game = {"id": "shelf_girl", "title": "Фигурка", "shelf": false}
	size = Vector3(0.14, 0.285, 0.14)
	color = Color("73d7d4")
	face_z = true


func is_figurine() -> bool:
	return true


## Наведение подсвечивает основание, не сдвигая фигурку с фиксированной передней линии.
func set_hovered(on: bool) -> void:
	hovered = on
	_set_glow(0.8 if on else 0.0)


func _ready() -> void:
	var base := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.056
	cylinder.bottom_radius = 0.06
	cylinder.height = 0.012
	cylinder.radial_segments = 48
	base.mesh = cylinder
	base.position.y = -size.y * 0.5 + 0.006
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("172d37")
	material.roughness = 0.65
	material.emission_enabled = true
	material.emission = Color("407d82")
	material.emission_energy_multiplier = 0.0
	_glow_mats.append([material, 0.3])
	base.material_override = material
	add_child(base)
	var andy := str(game.id) == "shelf_andy"
	if TRIPO.has(str(game.id)):
		var figure: Node3D = load(TRIPO[game.id]).instantiate()
		figure.scale = Vector3.ONE * (size.y - 0.014)
		figure.rotation.y = -0.25 if str(game.id) == "shelf_fighter" else 0.0
		figure.position.y = -size.y * 0.5 + 0.012
		add_child(figure)
		var shape_body := StaticBody3D.new()
		shape_body.collision_layer = 1
		shape_body.collision_mask = 0
		shape_body.set_meta("game_box", self)
		for node: MeshInstance3D in figure.find_children("*", "MeshInstance3D", true, false):
			if node.mesh != null:
				var surface := CollisionShape3D.new()
				surface.shape = node.mesh.create_trimesh_shape()
				surface.transform = global_transform.affine_inverse() * node.global_transform if is_inside_tree() else figure.transform * node.transform
				shape_body.add_child(surface)
		add_child(shape_body)
		return
	var model: Node3D = load("res://hub/art/figurine/andy.glb" if andy else MODEL).instantiate()
	model.scale = Vector3.ONE * (0.14 if andy else 0.27)
	model.rotation.y = 0.15 if andy else -0.10
	model.position.y = -size.y * 0.5 + 0.012
	add_child(model)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("game_box", self)
	if andy:
		# Точная поверхность вместо широкого блока: пустота возле хвоста не ловит мышь.
		for node: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
			if node.mesh == null:
				continue
			var surface := CollisionShape3D.new()
			surface.shape = node.mesh.create_trimesh_shape()
			surface.transform = global_transform.affine_inverse() * node.global_transform
			body.add_child(surface)
		add_child(body)
		return
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
