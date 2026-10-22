class_name K12Tavern
extends ColorRect
## Фон: пол таверны и (по желанию) овальный стол. Стол всегда по центру по горизонтали.

const TABLE_Y := 300.0
const TABLE_RADII := Vector2(600, 255)
const RIM := 34.0
const LEATHER := 10.0

var pirate := false:  # «Перудо»: стол — карта сокровищ с канатом
	set(v):
		pirate = v
		_update()
var show_table := true:
	set(v):
		show_table = v
		_update()


func _init(with_table: bool = true) -> void:
	show_table = with_table


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/king_of_12/ui/tavern.gdshader")
	mat.set_shader_parameter("planks", load("res://games/king_of_12/art/env/dark_wooden_planks_diff_1k.jpg"))
	mat.set_shader_parameter("wood", load("res://games/king_of_12/art/env/dark_wood_diff_1k.jpg"))
	mat.set_shader_parameter("leather", load("res://games/king_of_12/art/env/brown_leather_albedo_1k.jpg"))
	mat.set_shader_parameter("rim_width", RIM)
	mat.set_shader_parameter("leather_width", LEATHER)
	material = mat
	resized.connect(_update)
	_update()


func table_center() -> Vector2:
	return Vector2(size.x / 2.0 if size.x > 0 else 640.0, TABLE_Y)


func felt_radii() -> Vector2:
	return TABLE_RADII - Vector2.ONE * (RIM + LEATHER)


func _update() -> void:
	if material == null:
		return
	material.set_shader_parameter("rect_size", size)
	material.set_shader_parameter("show_table", show_table)
	material.set_shader_parameter("pirate", pirate)
	material.set_shader_parameter("table_center", table_center())
	material.set_shader_parameter("table_radii", TABLE_RADII)
