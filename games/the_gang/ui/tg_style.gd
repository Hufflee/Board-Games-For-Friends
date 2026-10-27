class_name TGStyle
extends RefCounted
## 2D-оформление The Gang: тёмный стол, бумажные панели и золотой акцент.

static var BG := Color("100e0b")
static var PANEL := Color("251e15")
static var INK := Color("ead99b")
static var MUTED := Color("b6a677")
static var GOLD := Color("d9bd65")
const RED := Color("a42c20")
const ROUND_COLORS := [Color("e7e5da"), Color("e4bd52"), Color("d57c42"), Color("c4544d")]
const FONT := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")
const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")

static func box(color: Color = Color.TRANSPARENT, padding: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL if color == Color.TRANSPARENT else color
	sb.border_color = Color(GOLD, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	sb.shadow_color = Color(0.02, 0.06, 0.07, 0.25)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func theme() -> Theme:
	# Одна тёмная палитра по коробке: уголь, латунь, приглушённый красный.
	var th := Theme.new()
	th.default_font = weighted_font(FONT, 650)
	th.default_font_size = 16
	th.set_color("font_color", "Label", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	th.set_stylebox("panel", "PanelContainer", box())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color := PANEL.lightened(0.10) if state == "hover" else PANEL
		th.set_stylebox(state, "Button", box(color, 10))
		th.set_color("font_" + state + "_color", "Button", MUTED if state == "disabled" else INK)
	th.set_color("font_color", "Button", INK)
	th.set_color("font_color", "OptionButton", INK)
	th.set_type_variation("SelectedButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		th.set_stylebox(state, "SelectedButton", box(GOLD, 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		th.set_color(state, "SelectedButton", BG)
	return th

static func weighted_font(base: Font, weight: int) -> FontVariation:
	var result := FontVariation.new()
	result.base_font = base
	result.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return result

static func label(text: String, size: int = 16, color: Color = Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK if color == Color.TRANSPARENT else color)
	return l

static func heading(text: String, size: int = 28) -> Label:
	var l := label(text, size)
	l.add_theme_font_override("font", weighted_font(HEAD, 600))
	return l

static func button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", size)
	return b

static func primary(text: String) -> Button:
	var b := button(text)
	b.add_theme_stylebox_override("normal", box(GOLD, 12))
	b.add_theme_stylebox_override("hover", box(GOLD.lightened(0.1), 12))
	b.add_theme_stylebox_override("pressed", box(GOLD.darkened(0.1), 12))
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	return b

static func column(gap: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func row(gap: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

class Background extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TGStyle.BG)
		for i in range(1, 3):
			var inset := float(i) * 10.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2.ONE * inset * 2.0), Color(TGStyle.GOLD, 0.35), false, 1.0)
		# Угловые веера и кольца сейфа повторяют геометрию обложки.
		for corner: Vector2 in [Vector2(20, 20), Vector2(size.x - 20, 20), Vector2(20, size.y - 20), size - Vector2(20, 20)]:
			var direction := (size * 0.5 - corner).normalized()
			for ray in range(-2, 3):
				draw_line(corner, corner + direction.rotated(ray * 0.15) * 82.0, Color(TGStyle.RED, 0.5), 2.0, true)
		var center := Vector2(size.x * 0.72, size.y * 0.53)
		for radius in [180.0, 190.0, 230.0]:
			draw_arc(center, radius, 0, TAU, 96, Color(TGStyle.GOLD, 0.06), 2.0, true)
		for spoke in 24:
			var direction := Vector2.from_angle(TAU * spoke / 24.0)
			draw_line(center + direction * 200, center + direction * 222, Color(TGStyle.GOLD, 0.09), 3.0, true)
