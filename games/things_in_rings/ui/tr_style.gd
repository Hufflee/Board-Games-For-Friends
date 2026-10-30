extends RefCounted
## Своя бумажная комиксная палитра: чернильный контур, коралл и цветные кольца.

const FONT := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")
const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")
const RINGS := [Color("4c9fc2"), Color("e4b73b"), Color("dc5960")]

static func ink() -> Color:
	return Color("e8ded0") if Prefs.dark_theme() else Color("322c37")

static func paper() -> Color:
	return Color("302a36") if Prefs.dark_theme() else Color("f1e6d2")

static func muted() -> Color:
	return Color("aaa3ab") if Prefs.dark_theme() else Color("625d68")

static func box(color: Color = Color.TRANSPARENT, pad: int = 16) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = paper() if color == Color.TRANSPARENT else color
	b.border_color = Color(ink(), 0.6)
	b.border_width_left = 3
	b.border_width_top = 2
	b.border_width_right = 2
	b.border_width_bottom = 4
	b.set_corner_radius_all(8)
	b.set_content_margin_all(pad)
	b.shadow_color = Color(0.1, 0.06, 0.12, 0.16)
	b.shadow_size = 4
	b.shadow_offset = Vector2(0, 4)
	return b

static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = weighted(FONT, 650)
	t.default_font_size = 16
	t.set_color("font_color", "Label", ink())
	t.set_color("default_color", "RichTextLabel", ink())
	t.set_stylebox("panel", "PanelContainer", box())
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", box(paper().lightened(0.08) if state == "hover" else paper(), 8))
		t.set_color("font_" + state + "_color", "Button", muted() if state == "disabled" else ink())
	t.set_color("font_color", "Button", ink())
	t.set_type_variation("SelectedButton", "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "SelectedButton", box(Color("4c9fc2"), 8))
		t.set_color("font_" + state + "_color", "SelectedButton", Color("241e29"))
	t.set_color("font_color", "SelectedButton", Color("241e29"))
	# Выбранный вариант — тихая подложка в тон кольца, а не заливка главной кнопки.
	t.set_type_variation("PickedButton", "Button")
	var picked := box(paper().lerp(Color("4c9fc2"), 0.32), 8)
	picked.border_color = Color("4c9fc2")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "PickedButton", picked)
		t.set_color("font_" + state + "_color", "PickedButton", ink())
	t.set_color("font_color", "PickedButton", ink())
	return t

## Выбор из нескольких вариантов: как UISel.pick, но выбранное — тихой подложкой (главная кнопка остаётся одна).
static func pick(b: Button, on: bool) -> void:
	UISel.pick(b, on)
	if on:
		b.theme_type_variation = "PickedButton"

## Подпись раздела: основной шрифт, прописные, приглушённо — заголовок экрана остаётся один.
static func section(text: String) -> Label:
	var l := label(text.to_upper(), 12, muted())
	l.add_theme_font_override("font", weighted(FONT, 800))
	return l

static func label(text: String, size: int = 16, color: Color = Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink() if color == Color.TRANSPARENT else color)
	return l

static func heading(text: String) -> Label:
	var l := label(text, 28)
	l.add_theme_font_override("font", weighted(HEAD, 700))
	return l

static func weighted(base: Font, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f

static func button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = 40
	return b

static func column(gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func row(gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

## Русские категории интерфейса; изображения оригинальных карт не изменяем.
static func category_name(category: String) -> String:
	return {"Attribute": "Признак", "Context": "Контекст", "Word": "Название"}.get(category, category)

## Прозрачный PNG-контур поверх оригинала, включая общую руку.
static func outline(parent: Control) -> void:
	var border := TextureRect.new()
	border.name = "CardOutline"
	border.texture = load("res://games/things_in_rings/art/card_outline.png")
	border.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	border.stretch_mode = TextureRect.STRETCH_SCALE
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
