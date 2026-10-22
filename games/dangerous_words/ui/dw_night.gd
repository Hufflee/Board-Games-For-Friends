class_name DWNight
extends ColorRect
## Фон «Опасных слов»: ночное небо (шейдер) и летучие мыши, пролетающие на фоне луны.

var _bats: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/dangerous_words/ui/dw_night.gdshader")
	material = mat
	resized.connect(func(): mat.set_shader_parameter("rect_size", size))
	mat.set_shader_parameter("rect_size", size)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	for i in 5:
		var b := Bat.new()
		layer.add_child(b)
		b.reset(self, true)
		_bats.append(b)


class Bat:
	extends Control
	var speed := 60.0
	var phase := 0.0
	var host: Control

	func reset(h: Control, anywhere: bool = false) -> void:
		host = h
		var w := h.size.x if h.size.x > 0 else 1280.0
		position = Vector2(randf_range(-200, w) if anywhere else -60.0, randf_range(30, 260))
		speed = randf_range(40, 90)
		scale = Vector2.ONE * randf_range(0.5, 1.1)
		phase = randf() * TAU
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		phase += delta * 9.0
		position += Vector2(speed, sin(phase * 0.3) * 12.0) * delta
		if host and position.x > host.size.x + 60:
			reset(host)
		queue_redraw()

	func _draw() -> void:
		var flap := sin(phase) * 7.0
		var c := Color(0.02, 0.0, 0.04, 0.9)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(-18, -6 - flap), Vector2(-12, 2), Vector2(-22, 4 - flap * 0.5), Vector2(-6, 6)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(18, -6 - flap), Vector2(12, 2), Vector2(22, 4 - flap * 0.5), Vector2(6, 6)]), c)
		draw_circle(Vector2(0, 2), 5, c)
		draw_circle(Vector2(-2, 1), 1.2, Color(1, 0.4, 0.1))
		draw_circle(Vector2(2, 1), 1.2, Color(1, 0.4, 0.1))
