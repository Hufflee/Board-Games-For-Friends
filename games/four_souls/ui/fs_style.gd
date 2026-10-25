class_name FSStyle
extends RefCounted
## Подвал Айзека: обожжённая бумага, тёмное дерево и красный акцент.
const H1 := 30
const BODY := 18
const CAP := 14
const GOLD := Color("c65b4b")
const COAL := Color("251b19")
const PAPER := Color("ebddbe")
static func font(kind: String = "regular") -> Font:
	return GLStyle.font(kind)
static func ink() -> Color:
	return PAPER
static func surface() -> Color:
	return Color("30221e")
static func box(color: Color, border: Color = GOLD) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.border_color = Color(border, 0.6)
	b.set_border_width_all(1)
	b.set_corner_radius_all(4)
	b.set_content_margin_all(12)
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = BODY
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font("title"))
	for kind in ["Label", "CheckBox", "RichTextLabel", "LineEdit"]:
		t.set_color("font_color", kind, ink())
	t.set_color("default_color", "RichTextLabel", ink())
	for kind in ["PanelContainer", "ConfirmPanel", "PopupMenu"]:
		t.set_stylebox("panel", kind, box(surface()))
	for kind in ["Button", "OptionButton"]:
		t.set_font("font", kind, font("title"))
		for state in ["normal", "pressed", "hover", "disabled"]:
			t.set_stylebox(state, kind, box(surface().lightened(0.07) if state == "hover" else surface(), GOLD if state != "disabled" else Color("69736c")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, kind, ink())
		t.set_color("font_disabled_color", kind, Color(ink(), 0.4))
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", box(surface()))
	t.set_stylebox("focus", "LineEdit", box(surface(), GOLD))
	t.set_color("caret_color", "LineEdit", ink())
	t.set_color("font_placeholder_color", "LineEdit", Color(ink(), 0.5))
	t.set_stylebox("panel", "TooltipPanel", box(COAL))
	t.set_color("font_color", "TooltipLabel", PAPER)
	t.set_type_variation("PrimaryButton", "Button")
	for state in ["normal", "pressed", "hover"]:
		t.set_stylebox(state, "PrimaryButton", box(GOLD.lightened(0.1) if state == "hover" else GOLD))
		t.set_color("font_" + ("color" if state == "normal" else state + "_color"), "PrimaryButton", COAL)
	t.set_type_variation("SelectedButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "SelectedButton", box(GOLD))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(state, "SelectedButton", COAL)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	return t
static func label(text: String, size: int = BODY, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink())
	if title:
		l.add_theme_font_override("font", font("title"))
	return l
static func button(text: String, size: int = BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 40
	return b
static func primary(text: String) -> Button:
	var b := button(text)
	b.theme_type_variation = "PrimaryButton"
	return b
static func vbox(gap: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v
static func hbox(gap: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(surface())
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
class Backdrop extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1a1211"))
		# Каменные стены и сходящиеся доски пола: рисунок остаётся тише карт и текста.
		var ink := FSStyle.ink()
		var horizon := size.y * 0.66
		for row in range(0, int(horizon / 68.0) + 1):
			var y := row * 68.0
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(ink, 0.045), 2, true)
			for x in range(-160, int(size.x) + 160, 160):
				var shifted := float(x + (80 if row % 2 else 0))
				draw_line(Vector2(shifted, y), Vector2(shifted, y + 68), Color(ink, 0.035), 2, true)
		var vanishing := Vector2(size.x * 0.52, horizon)
		for i in range(-6, 8):
			draw_line(vanishing, Vector2(size.x * 0.5 + i * size.x * 0.18, size.y), Color(ink, 0.035), 2, true)
		for i in range(1, 6):
			var y := lerpf(horizon, size.y, pow(i / 5.0, 1.7))
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(ink, 0.035), 2, true)
		# Арка в глубине и небольшие трещины вместо отвлекающих предметов.
		var arch := Vector2(size.x * 0.56, horizon - 120)
		draw_arc(arch, 100, PI, TAU, 48, Color(ink, 0.045), 18, true)
		for side in [-1, 1]:
			draw_line(arch + Vector2(side * 100, 0), arch + Vector2(side * 100, 120), Color(ink, 0.045), 18, true)
