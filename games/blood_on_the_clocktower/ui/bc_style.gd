class_name BCStyle
extends RefCounted
## Тёмная мини-дизайн-система Clocktower. Не зависит от глобальной светлой темы.

const BG := Color("131e2b")
const PANEL := Color("1d2b3a")
const INSET := Color("172432")
const INK := Color("f0e3cc")
const MUTED := Color("b8b9b8")
const LINE := Color("435360")
const ACCENT := Color("81364a")
## Цвета команд — только для подписи стороны игрока.
const GOOD := Color("8db4e0")
const EVIL := Color("e07f8c")
const H1 := 28
const BODY := 18
const SMALL := 15

static func font(title: bool = false) -> Font:
	if title:
		return load("res://editor/fonts/extra/yesevaone/font.ttf")
	var body := FontVariation.new()
	body.base_font = load("res://editor/fonts/Nunito-Variable.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	return body

static func box(color: Color = PANEL, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color(LINE, 0.6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.01, 0.02, 0.04, 0.18)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 3)
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = font()
	result.default_font_size = BODY
	for type: String in ["Label", "Button", "LineEdit", "CheckBox", "OptionButton", "ItemList"]:
		result.set_color("font_color", type, INK)
	result.set_color("default_color", "RichTextLabel", INK)
	result.set_stylebox("panel", "PanelContainer", box())
	result.set_stylebox("panel", "ItemList", box(INSET))
	result.set_stylebox("selected", "ItemList", box(ACCENT))
	result.set_stylebox("selected_focus", "ItemList", box(ACCENT))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		result.set_stylebox(state, "Button", box(PANEL.lightened(0.08) if state == "hover" else (INSET if state == "pressed" else PANEL)))
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_stylebox("normal", "LineEdit", box(INSET))
	result.set_stylebox("focus", "LineEdit", box(INSET.lightened(0.08)))
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	return result

static func label(text: String, size: int = BODY, color: Color = INK, title: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_color_override("font_color", color)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_font_override("font", font(title))
	return node

static func button(text: String, size: int = BODY) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.custom_minimum_size.y = 40
	return node

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(ACCENT))
	button.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.1)))
	button.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.1)))
	button.add_theme_stylebox_override("disabled", box(INSET))


## Пары цветов для проверки интерфейса.
static func contrast_pairs() -> Array:
	return [
		[INK, PANEL, "текст панели", false],
		[INK, ACCENT, "номинация", false],
	]

const BOOK_INK_FADED := Color(0.17, 0.11, 0.07, 0.62)
const BOOK_INK_RED := Color("7a1a1a")
const BOOK_INK_BLUE := Color("1f3550")
const BOOK_INK := Color("2b1b12")
const BOOK_DIM := Color(0.02, 0.02, 0.04, 0.66)
