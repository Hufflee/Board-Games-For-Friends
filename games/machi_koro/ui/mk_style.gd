extends RefCounted
## Две темы Мачи Коро: бумага/бирюза, ровные кнопки и цветные точки игроков.

const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")
const BODY := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")
const ACCENT := Color("278c93")

static func dark() -> bool:
	return Prefs.dark_theme()

static func ink() -> Color:
	return Color("e1e6db") if dark() else Color("183c44")

static func muted() -> Color:
	return Color("9cb8b7") if dark() else Color("5b7373")

static func background() -> Color:
	return Color("122c35") if dark() else Color("eee6d5")

static func surface() -> Color:
	return Color("1c3c45") if dark() else Color("f5efdf")

static func box(color: Color = Color.TRANSPARENT, pad: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = surface() if color == Color.TRANSPARENT else color
	style.border_color = style.bg_color.darkened(0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(pad)
	style.shadow_color = Color(0.03, 0.1, 0.12, 0.13)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style

static func theme() -> Theme:
	var t := Theme.new()
	var body := FontVariation.new()
	body.base_font = BODY
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	t.default_font = body
	t.default_font_size = 18
	for type: String in ["Label", "Button", "CheckBox", "OptionButton"]:
		t.set_color("font_color", type, ink())
	t.set_color("default_color", "RichTextLabel", ink())
	t.set_stylebox("panel", "PanelContainer", box())
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var color := surface().lightened(0.05) if state == "hover" else surface().darkened(0.06) if state == "pressed" else surface()
		t.set_stylebox(state, "Button", box(color, 10))
		t.set_color("font_" + ("color" if state == "normal" else state + "_color"), "Button", muted() if state == "disabled" else ink())
	t.set_type_variation("QuietButton", "Button")
	t.set_type_variation("SelectedButton", "Button")
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", HEAD)
	t.set_color("font_color", "ConfirmPanel", ink())
	for state: String in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(state, "SelectedButton", box(ACCENT.lightened(0.1) if state == "hover" else ACCENT, 10))
		t.set_color("font_" + ("color" if state == "normal" else state + "_color"), "SelectedButton", Color("f1f3e7"))
	return t

static func label(text: String, font_size: int = 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", ink())
	return node

static func heading(text: String, font_size: int = 28) -> Label:
	var node := label(text, font_size)
	node.add_theme_font_override("font", HEAD)
	return node

static func button(text: String, font_size: int = 18) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return node

static func primary(text: String) -> Button:
	var node := button(text)
	node.theme_type_variation = "SelectedButton"
	return node

static func row(gap: int = 8) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node

static func column(gap: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
