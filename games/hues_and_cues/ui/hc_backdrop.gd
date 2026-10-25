class_name HCBackdrop
extends ColorRect
## Фон Hues and Cues: тёплая бумага с мягкими цветными пятнами (шейдер).
## painted — бумага для акварели и кляксы краски по углам (сам Hues and Cues; Word Slam — без клякс);
## кляксы слегка двигаются за мышью (параллакс).

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
	set_process(true)


## Параллакс клякс и мягких пятен за мышью: плавно догоняем положение курсора.
var _par := Vector2.ZERO


func _process(delta: float) -> void:
	var vs := get_viewport_rect().size
	if vs.x <= 0.0:
		return
	var m := get_viewport().get_mouse_position()
	var want := ((m / vs) * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)
	var k := 1.0 - exp(-delta * 4.0)
	var nxt := _par.lerp(want, k)
	if nxt.distance_to(_par) > 0.0005:
		_par = nxt
		(material as ShaderMaterial).set_shader_parameter("parallax", _par)
