class_name TMStyle
extends RefCounted
## Рисованный дайнер 60-х: две темы, единые панели и числовые карты.

const GREEN := Color("183d35")
const GOLD := Color("d69b49")
const PAPER := Color("e5d6b8")
const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")
const FONT := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")

static func dark() -> bool:
	return Prefs.dark_theme()

static func ink() -> Color:
	return PAPER if dark() else GREEN

static func panel_color() -> Color:
	return Color("19382f") if dark() else Color("deceb0")

static func box(color: Color = Color.TRANSPARENT, pad: int = 16) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = panel_color() if color == Color.TRANSPARENT else color
	b.set_content_margin_all(pad)
	b.set_corner_radius_all(8)
	b.set_border_width_all(1)
	b.border_color = b.bg_color.darkened(0.2)
	b.shadow_color = Color(0.04, 0.1, 0.08, 0.22)
	b.shadow_size = 4
	b.shadow_offset = Vector2(0, 3)
	return b

static func theme() -> Theme:
	var t := Theme.new()
	var body := FontVariation.new()
	body.base_font = FONT
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	t.default_font = body
	t.default_font_size = 16
	t.set_color("font_color", "Label", ink())
	t.set_color("default_color", "RichTextLabel", ink())
	t.set_stylebox("panel", "PanelContainer", box())
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "Button", box(panel_color().lightened(0.08) if state == "hover" else panel_color(), 10))
		t.set_color("font_" + ("color" if state == "normal" else state + "_color"), "Button", ink().darkened(0.3) if state == "disabled" else ink())
	t.set_type_variation("SelectedButton", "Button")
	t.set_stylebox("normal", "SelectedButton", box(GOLD, 10))
	t.set_color("font_color", "SelectedButton", GREEN)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", HEAD)
	return t

static func label(text: String, font_size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l

static func heading(text: String, font_size: int = 28) -> Label:
	var l := label(text, font_size)
	l.add_theme_font_override("font", HEAD)
	return l

static func button(text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

static func primary(text: String) -> Button:
	var b := button(text)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, box(GOLD.lightened(0.08) if state == "hover" else GOLD, 12))
		b.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), GREEN)
	return b

static func column(gap: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func row(gap: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func face(number: int, big_size: int = 48, small_size: int = 16) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(PAPER, 8))
	var col := column(0)
	panel.add_child(col)
	var small := heading(str(number), small_size)
	small.add_theme_color_override("font_color", GREEN)
	col.add_child(small)
	var big := heading(str(number), big_size)
	big.add_theme_color_override("font_color", GREEN)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(big)
	var corner := heading(str(number), small_size)
	corner.add_theme_color_override("font_color", GREEN)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(corner)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in col.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

static func back(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_style_box(box(GREEN, 0), rect)
	for i in range(1, 7):
		var radius := minf(rect.size.x, rect.size.y) * float(i) / 15.0
		ci.draw_arc(rect.get_center(), radius, 0, TAU, 64, Color(GOLD, 0.6), 1.0, true)
	ci.draw_line(Vector2(rect.get_center().x, rect.position.y + 8), Vector2(rect.get_center().x, rect.end.y - 8), GOLD, 1.0)

class PanicCard extends Control:
	const HAND := preload("res://games/the_mind/art/panic_hand.svg")
	var _icon: TextureRect

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 80)
		_icon = TextureRect.new()
		_icon.texture = HAND
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icon.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_icon)
		resized.connect(_layout_icon)
		_layout_icon()

	func _layout_icon() -> void:
		if is_instance_valid(_icon):
			var diameter := minf(size.x * 0.76, size.y * 0.62)
			_icon.size = Vector2.ONE * diameter
			_icon.position = Vector2(size.x * 0.5, size.y * 0.6) - _icon.size * 0.5
		queue_redraw()

	func _draw() -> void:
		draw_style_box(TMStyle.box(TMStyle.PAPER, 0), Rect2(Vector2.ZERO, size))
		var k := minf(size.x / 64.0, size.y / 80.0)
		draw_string(TMStyle.HEAD, Vector2(0, 18 * k), "ПАНИКА", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(12 * k), TMStyle.GREEN)

class Background extends Control:
	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		var path := "res://games/the_mind/art/diner.png"
		if ResourceLoader.exists(path):
			var art := TextureRect.new()
			art.texture = load(path)
			art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(art)
			if not TMStyle.dark():
				var veil := ColorRect.new()
				veil.color = Color(TMStyle.PAPER, 0.9)
				veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
				veil.anchor_top = 0.4
				veil.mouse_filter = MOUSE_FILTER_IGNORE
				add_child(veil)
		var top_veil := ColorRect.new()
		top_veil.color = Color(0.06, 0.14, 0.11, 0.8) if TMStyle.dark() else Color(TMStyle.PAPER, 0.94)
		top_veil.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
		top_veil.offset_bottom = 48
		top_veil.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(top_veil)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("152a26") if TMStyle.dark() else TMStyle.PAPER)
