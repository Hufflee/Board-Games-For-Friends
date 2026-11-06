extends Control
## Слои видимого лица карты: один 2D-холст для редактора, стола и крупного просмотра.
var fields: Dictionary = {}
var reader: RefCounted
var body_font: Font
var _surface: Control

class Ellipse extends Control:
	var color := Color.WHITE
	func _draw() -> void:
		draw_set_transform(size * 0.5, 0, size * 0.5)
		draw_circle(Vector2.ZERO, 1.0, color, true, -1, true)

func setup(data: Dictionary, assets: RefCounted, font: Font) -> void:
	fields = data
	reader = assets
	body_font = font
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	_surface = Control.new()
	_surface.mouse_filter = MOUSE_FILTER_IGNORE
	var dimensions: Array = fields.get("canvas_size", [504, 704])
	_surface.size = Vector2(float(dimensions[0]), float(dimensions[1]))
	add_child(_surface)
	for index in fields.get("layers", []).size():
		var data_layer: Dictionary = fields.layers[index]
		if not data_layer.get("visible", true):
			continue
		var rect: Array = data_layer.get("rect", [0, 0, 504, 704])
		var layer := Control.new()
		layer.name = "CardLayer%d" % index
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		layer.clip_contents = true
		layer.position = Vector2(float(rect[0]), float(rect[1]))
		layer.size = Vector2(float(rect[2]), float(rect[3]))
		layer.pivot_offset = layer.size / 2
		layer.rotation_degrees = float(data_layer.get("rotation", 0))
		layer.scale = Vector2(-1 if data_layer.get("flip_x", false) else 1, -1 if data_layer.get("flip_y", false) else 1)
		layer.modulate.a = float(data_layer.get("opacity", 1))
		_surface.add_child(layer)
		var color := Color.from_string(str(data_layer.get("color", "#30263f")), Color("30263f"))
		var content: Control
		match str(data_layer.kind):
			"fill":
				if data_layer.get("shape", "rect") == "ellipse":
					var ellipse := Ellipse.new()
					ellipse.color = color
					content = ellipse
				else:
					var fill := ColorRect.new()
					fill.color = color
					content = fill
			"frame":
				# Рамка: обводка цветом слоя, внутри — своя заливка (пустая — прозрачно).
				var frame := Panel.new()
				var style := StyleBoxFlat.new()
				var inside := str(data_layer.get("fill", ""))
				style.bg_color = Color.from_string(inside, Color.TRANSPARENT) if not inside.is_empty() else Color.TRANSPARENT
				style.border_color = color
				style.set_border_width_all(int(data_layer.get("border", 16)))
				style.set_corner_radius_all(int(data_layer.get("radius", 24)))
				style.anti_aliasing = true
				frame.add_theme_stylebox_override("panel", style)
				content = frame
			"image":
				var image := TextureRect.new()
				image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				image.stretch_mode = TextureRect.STRETCH_SCALE
				image.texture = reader.image(str(data_layer.get("asset", ""))) if reader != null else null
				content = image
			"text":
				var text := Label.new()
				text.text = str(data_layer.get("text", ""))
				text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				text.clip_text = true
				text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if data_layer.get("align", "left") == "center" else (HORIZONTAL_ALIGNMENT_RIGHT if data_layer.get("align") == "right" else HORIZONTAL_ALIGNMENT_LEFT)
				var custom: Font = reader.font(str(data_layer.get("font", ""))) if reader != null else null
				text.add_theme_font_override("font", custom if custom != null else body_font)
				text.add_theme_font_size_override("font_size", int(data_layer.get("font_size", 64)))
				text.add_theme_color_override("font_color", color)
				content = text
			_:
				continue
		content.mouse_filter = MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		layer.add_child(content)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	if is_instance_valid(_surface):
		_surface.scale = size / _surface.size
