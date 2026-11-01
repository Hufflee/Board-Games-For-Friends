class_name CGStyle
extends RefCounted
## Общий 2D-стиль стола и оболочки редактора: шрифты хаба, фиолетовый и бирюзовый.

const HEAD := preload("res://hub/art/fonts/RussoOne-Regular.ttf")
const BODY := preload("res://games/custom/ui/cg_body.tres")

static func dark() -> bool:
	return Prefs.dark_theme()

static func bg() -> Color:
	return Color("171322") if dark() else Color("e9e5ef")

static func panel() -> Color:
	return Color("292235") if dark() else Color("d9d2e4")

static func ink() -> Color:
	return Color("e4ddec") if dark() else Color("30263f")

static func accent() -> Color:
	return Color("65cfcc") if dark() else Color("187d82")

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 16
	for type: String in ["Button", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			result.set_stylebox(state, type, box(panel().lightened(0.06) if state == "hover" else panel(), 12))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(state, type, ink())
		result.set_color("font_disabled_color", type, ink().lerp(panel(), 0.55))
	for state: String in ["normal", "focus", "read_only"]:
		result.set_stylebox(state, "LineEdit", box(panel().darkened(0.08), 8))
	for state: String in ["font_color", "font_placeholder_color", "caret_color"]:
		result.set_color(state, "LineEdit", ink())
	result.set_color("selection_color", "LineEdit", Color(accent(), 0.35))
	result.set_stylebox("panel", "PopupMenu", box(panel()))
	result.set_stylebox("hover", "PopupMenu", box(panel().lightened(0.1)))
	result.set_color("font_color", "PopupMenu", ink())
	result.set_color("font_hover_color", "PopupMenu", ink())
	result.set_color("font_color", "Label", ink())
	return result

static func box(color: Color, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.border_color = color.darkened(0.16)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.06, 0.04, 0.09, 0.14)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style

static func label(text: String, size: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", BODY)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", ink())
	return item

static func heading(text: String, size: int = 24) -> Label:
	var item := label(text, size)
	item.add_theme_font_override("font", HEAD)
	return item

static func button(text: String, size: int = 16) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 40
	item.add_theme_font_override("font", BODY)
	item.add_theme_font_size_override("font_size", size)
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		item.add_theme_stylebox_override(mode, box(panel().lightened(0.06) if mode == "hover" else panel(), 12))
	for mode in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(mode, ink())
	item.add_theme_color_override("font_disabled_color", ink().lerp(panel(), 0.55))
	return item

static func primary(text: String, size: int = 16) -> Button:
	var item := button(text, size)
	item.add_theme_stylebox_override("normal", box(accent()))
	item.add_theme_stylebox_override("hover", box(accent().lightened(0.1)))
	item.add_theme_color_override("font_color", bg())
	item.add_theme_color_override("font_hover_color", bg())
	return item

static func column(gap: int = 16) -> VBoxContainer:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", gap)
	return item

static func row(gap: int = 8) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", gap)
	return item

static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func value_text(value: Variant) -> String:
	if value is float and is_equal_approx(value, round(value)):
		return str(int(value))
	return str(value)

static func card_back(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_style_box(box(Color("40334e"), 0), rect)
	var inset := rect.grow(-12)
	canvas.draw_rect(inset, Color("8e7ba7"), false, 2)
	canvas.draw_line(inset.position, inset.end, Color("8e7ba7"), 2)
	canvas.draw_line(Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), Color("8e7ba7"), 2)

class TokenFace extends Control:
	var data: Dictionary
	func _init(fields: Dictionary) -> void:
		data = fields
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.44
		var color := Color.from_string(str(data.get("color", "#65cfcc")), CGStyle.accent())
		draw_circle(center + Vector2(0, 3), radius, Color(0.05, 0.04, 0.08, 0.2))
		match str(data.get("shape", "circle")):
			"square": draw_style_box(CGStyle.box(color, 0), Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2))
			"hex":
				var points := PackedVector2Array()
				for i in 6:
					points.append(center + Vector2.from_angle(TAU * i / 6.0) * radius)
				draw_colored_polygon(points, color)
			_: draw_circle(center, radius, color)
		var label := CGStyle.value_text(data.get("value", 1))
		var font_size := 32 if CGStyle.HEAD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x < size.x * 0.8 else 16
		draw_string(CGStyle.HEAD, Vector2(0, center.y + font_size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color("30263f"))

class CardFace extends Control:
	var data: Dictionary
	var art_texture: Texture2D
	var custom_font: Font
	var _art: TextureRect
	func _init(fields: Dictionary) -> void:
		data = fields
		mouse_filter = MOUSE_FILTER_IGNORE
	func _ready() -> void:
		if art_texture != null:
			_art = TextureRect.new()
			_art.texture = art_texture
			_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_art.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(_art)
			resized.connect(_place_art)
			_place_art()
	func _place_art() -> void:
		if is_instance_valid(_art):
			_art.position = Vector2(8, 32)
			_art.size = Vector2(maxf(1, size.x - 16), maxf(1, size.y - 48))
	func _draw() -> void:
		var paper := Color("ded7c8")
		draw_style_box(CGStyle.box(paper, 0), Rect2(Vector2.ZERO, size))
		var title := CGStyle.value_text(data.get("title", data.get("name", data.get("rank", "Карта"))))
		var number := CGStyle.value_text(data.get("rank", data.get("value", "")))
		draw_string(custom_font if custom_font != null else CGStyle.BODY, Vector2(10, 24), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 16, Color("30263f"))
		draw_string(custom_font if custom_font != null else CGStyle.HEAD, Vector2(0, size.y * 0.58), number, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color("30263f"))
		var text := str(data.get("text", ""))
		if not text.is_empty():
			draw_multiline_string(CGStyle.BODY, Vector2(10, size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 16, 3, Color("30263f"))
