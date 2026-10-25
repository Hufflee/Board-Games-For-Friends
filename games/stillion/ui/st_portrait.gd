extends TextureRect
## Личный idle каждого персонажа: дыхание, покачивание верхней части и независимое моргание.
## Семь исходных персонажей используют первый одобренный лист без изменения его палитры.
const EYES := [
	Rect2(140, 126, 135, 100),
	Rect2(147, 121, 139, 111),
	Rect2(140, 184, 130, 95),
	Rect2(135, 126, 140, 100),
	Rect2(132, 103, 143, 111),
	Rect2(130, 150, 142, 92),
	Rect2(163, 112, 134, 106),
	Rect2(119, 47, 159, 123)
]
var index := 0
var _t := 0.0
var _paint: ShaderMaterial


func _ready() -> void:
	index = posmod(index, 8)
	texture = (
		load("res://games/stillion/art/contestants.png")
		if index == 1
		else load("res://games/stillion/art/contestants_original.png")
	)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint = ShaderMaterial.new()
	_paint.shader = preload("res://games/stillion/ui/st_portrait.gdshader")
	_paint.set_shader_parameter("blink_sheet", preload("res://games/stillion/art/contestants_blink.png"))
	_paint.set_shader_parameter("cell", Vector2(index % 4, index / 4))
	var eyes: Rect2 = EYES[index]
	_paint.set_shader_parameter(
		"eyes",
		Vector4(eyes.position.x / 384.0, eyes.position.y / 512.0, eyes.size.x / 384.0, eyes.size.y / 512.0)
	)
	_paint.set_shader_parameter("candle", index == 5)
	material = _paint
	_process(0.0)


func _process(delta: float) -> void:
	_t += delta
	if _paint == null:
		return
	var phase := _t + index * 1.73
	var blink_time := fposmod(phase, 3.5 + index * 0.21)
	var blink := clampf(1.0 - absf(blink_time - 2.9) / 0.12, 0.0, 1.0)
	_paint.set_shader_parameter("blink", blink)
	_paint.set_shader_parameter("breath", sin(phase * (1.9 + index * 0.07)) * 0.014)
	_paint.set_shader_parameter(
		"sway", sin(phase * (1.1 + index * 0.09)) * (0.009 if index in [3, 6] else 0.005)
	)
	_paint.set_shader_parameter("flicker", sin(phase * 8.0) * 0.04)
