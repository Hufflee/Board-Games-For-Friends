class_name TGStyle
extends RefCounted
## 2D-оформление The Gang: тёмный стол, бумажные панели и золотой акцент.

static var BG := Color("142c32")
static var PANEL := Color("203c42")
static var INK := Color("ede6d1")
static var MUTED := Color("a6b6b1")
static var GOLD := Color("e5ba61")
const ROUND_COLORS := [Color("e7e5da"), Color("e4bd52"), Color("d57c42"), Color("c4544d")]
const FONT := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")
const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")

static func box(color: Color = Color.TRANSPARENT, padding: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL if color == Color.TRANSPARENT else color
	sb.border_color = MUTED * Color(1, 1, 1, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	sb.shadow_color = Color(0.02, 0.06, 0.07, 0.25)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func theme() -> Theme:
	var dark := Prefs.dark_theme()
	BG = Color("142c32") if dark else Color("ded5bc")
	PANEL = Color("203c42") if dark else Color("f0e7d0")
	INK = Color("ede6d1") if dark else Color("243a39")
	MUTED = Color("b0c1ba") if dark else Color("51645e")
	GOLD = Color("e5ba61") if dark else Color("a56823")
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
			var inset := float(i) * 30.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2.ONE * inset * 2.0), Color(TGStyle.MUTED, 0.12), false, 1.0)
