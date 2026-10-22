class_name HCBackdrop
extends ColorRect
## Фон Hues and Cues: тёплая бумага с мягкими цветными пятнами (шейдер).
## painted — бумага для акварели и кляксы краски по углам (сам Hues and Cues; Word Slam — без клякс).

var painted := false


func _init(with_paint: bool = false) -> void:
	painted = with_paint


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://games/hues_and_cues/ui/hc_backdrop.gdshader")
	m.set_shader_parameter("painted", painted)
	m.set_shader_parameter("base", Vector3(HCStyle.BG.r, HCStyle.BG.g, HCStyle.BG.b))
	if HCStyle.dark:
		m.set_shader_parameter("strength", 0.08)
	material = m
