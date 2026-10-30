extends RefCounted
## «Хором!»: мини-дизайн-система. Тетрадная бумага, чернила, коралловый акцент и синяя подсветка совпадений.
## Шрифты: Oswald — заголовки, Nunito — текст. Размеры: 28 / 16 / 12.

const FONT := preload("res://games/dangerous_words/art/fonts/Nunito-Variable.ttf")
const HEAD := preload("res://games/brodilka/art/fonts/Oswald-Variable.ttf")
const ACCENT := Color("e0794f")  # главное действие, ход, ведущий
const MATCH := Color("5b7fe0")  # подсветка похожего ответа
const GOOD := Color("4caf6e")  # засчитанный ответ
const BAD := Color("e0525e")  # снятый ответ («Белая ворона»)

static func dark() -> bool:
	return Prefs.dark_theme()

static func ink() -> Color:
	return Color("ebe4d8") if dark() else Color("2f2b33")

static func muted() -> Color:
	return Color("a39daa") if dark() else Color("6b6570")

static func paper() -> Color:
	return Color("2f2b36") if dark() else Color("fbf6ec")

static func page() -> Color:
	return Color("1f1c25") if dark() else Color("e9e1d3")

## Линейка тетради.
static func rule_line() -> Color:
	return Color(MATCH, 0.22 if dark() else 0.3)

static func box(color: Color = Color.TRANSPARENT, pad: int = 16, radius: int = 10) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = paper() if color == Color.TRANSPARENT else color
	# Обводка в тон заливке, без светлого контура: в тёмной теме цвет текста (кремовый) давал светлый ободок
	# и светлые «серпы» в нижних углах, где толстый нижний край загибается. Свет сверху — нижний край темнее.
	var fill := b.bg_color if b.bg_color.a > 0.0 else paper()
	b.border_color = fill.darkened(0.35 if dark() else 0.18)
	b.set_border_width_all(1)
	b.border_width_bottom = 3
	b.anti_aliasing_size = 0.75
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	b.shadow_color = Color(0, 0, 0, 0.18)
	b.shadow_size = 6
	b.shadow_offset = Vector2(0, 3)
	return b

static func weighted(base: Font, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f

static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = weighted(FONT, 650)
	t.default_font_size = 16
	t.set_color("font_color", "Label", ink())
	t.set_stylebox("panel", "PanelContainer", box())
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", box(paper().lightened(0.06) if state == "hover" else paper(), 8, 8))
		t.set_color("font_" + state + "_color", "Button", muted() if state == "disabled" else ink())
	t.set_color("font_color", "Button", ink())
	t.set_type_variation("SelectedButton", "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := ACCENT.lightened(0.08) if state == "hover" else ACCENT
		t.set_stylebox(state, "SelectedButton", box(fill.darkened(0.25) if state == "disabled" else fill, 8, 8))
		t.set_color("font_" + state + "_color", "SelectedButton", Color("231d1a"))
	t.set_color("font_color", "SelectedButton", Color("231d1a"))
	t.set_type_variation("PickedButton", "Button")
	var picked := box(paper().lerp(ACCENT, 0.28), 8, 8)
	picked.border_color = ACCENT
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "PickedButton", picked)
		t.set_color("font_" + state + "_color", "PickedButton", ink())
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0)
	field.set_content_margin_all(4)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", ink())
	t.set_color("font_placeholder_color", "LineEdit", Color(muted(), 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	return t

static func pick(b: Button, on: bool) -> void:
	UISel.pick(b, on)
	if on:
		b.theme_type_variation = "PickedButton"

static func label(text: String, size: int = 16, color: Color = Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink() if color == Color.TRANSPARENT else color)
	return l

static func heading(text: String, size: int = 28) -> Label:
	var l := label(text, size)
	l.add_theme_font_override("font", weighted(HEAD, 700))
	return l

static func section(text: String) -> Label:
	var l := label(text.to_upper(), 12, muted())
	l.add_theme_font_override("font", weighted(FONT, 800))
	return l

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

## Плоский фон-страница: без картинок, подходит и для итогов.
static func paint_backdrop(surface: CanvasItem, dimensions: Vector2) -> void:
	surface.draw_rect(Rect2(Vector2.ZERO, dimensions), page())
	var step := 32.0
	var y := step
	while y < dimensions.y:
		surface.draw_line(Vector2(0, y), Vector2(dimensions.x, y), Color(MATCH, 0.05), 1.0)
		y += step
	surface.draw_line(Vector2(72, 0), Vector2(72, dimensions.y), Color(BAD, 0.08), 2.0)
