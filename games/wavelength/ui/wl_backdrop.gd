extends ColorRect


## Волны двух полушарий; центр концентрических линий следует оси игровой шкалы.
var dial: WLDial
var _motion := Vector2.ZERO
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://games/wavelength/ui/wl_backdrop.gdshader")
	paint.set_shader_parameter("paper", HCStyle.BG)
	paint.set_shader_parameter("ink", HCStyle.INK)
	material = paint


func _process(delta: float) -> void:
	if size.y <= 0.0:
		return
	var center := size * 0.5
	if is_instance_valid(dial):
		center = get_global_transform().affine_inverse() * (dial.get_global_transform() * dial._center())
	_motion = preload("res://hub/cursor_parallax.gd").step(self, _motion, delta)
	var paint := material as ShaderMaterial
	paint.set_shader_parameter("surface_size", size)
	paint.set_shader_parameter("ring_center", center)
	paint.set_shader_parameter("motion", _motion)
