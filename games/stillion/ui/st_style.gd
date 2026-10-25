class_name STStyle
extends RefCounted
## Мини-дизайн-система «Стиллиона»: мультфильмы 30-х (rubber hose) — кремовая бумага, толстый чёрный контур,
## тень со сдвигом, горчичный и красный акценты; поверх экрана — плёнка (зерно, виньетка, мерцание).
## Заголовки — Underdog (рукописный), текст — Nunito. Светлая и тёмная тема (Prefs.theme_mode).

const ART := "res://games/stillion/art/"
const H1 := 34
const H2 := 22
const BODY := 18
const CAP := 14

const INK := Color("1c1a17")  # контур и текст на бумаге
const PAPER := Color("f3e3c2")
const RED := Color("c8322b")
const MUSTARD := Color("e8b33a")
const BLUE := Color("3d74b6")
const GREEN := Color("4f9a4a")
## Редкость ответа: цвет плашки (Общеизвестно / Школьник / Умник / Эрудит).
const RARITY_COLORS := {"c": Color("7cc6ea"), "s": Color("2d4f9e"), "u": Color("8a4cc2"), "e": Color("d0342c")}  # голубой / тёмно-синий / фиолетовый / красный

static var _fonts := {}
static var _theme: Theme
static var _theme_dark := false


static func dark() -> bool:
	return Prefs.theme_mode == "dark"


## Бумага панелей и текст на ней (в тёмной теме — тёмный картон и кремовый текст).
static func paper() -> Color:
	return Color("2b231c") if dark() else PAPER


static func ink() -> Color:
	return Color("f1e2c4") if dark() else INK


static func muted() -> Color:
	return Color(ink(), 0.62)


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		if kind == "title":
			_fonts[kind] = load(ART + "fonts/Underdog-Regular.ttf")
		else:
			var f := FontVariation.new()
			f.base_font = load(ART + "fonts/Nunito-Variable.ttf")
			f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 850 if kind == "bold" else 650}
			_fonts[kind] = f
	return _fonts[kind]


## Мультяшная плашка (STInkBox): заливка с зерном бумаги, неровный чернильный контур, тень со сдвигом вниз-вправо.
static func box(fill: Color, radius: int = 14, border: int = 3, shadow: int = 5, pad: int = 14, gloss := false) -> STInkBox:
	var b := STInkBox.new()
	b.bg_color = fill
	b.border_color = INK if not dark() else Color("0c0a08")
	b.set_border_width_all(border)
	b.set_corner_radius_all(radius)
	b.shadow_color = Color(0, 0, 0, 0.55 if dark() else 0.85)
	b.shadow_offset = Vector2(shadow, shadow)
	b.gloss = gloss
	b.set_content_margin_all(pad)
	return b


static func theme() -> Theme:
	if _theme and _theme_dark == dark():
		return _theme
	_theme_dark = dark()
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = BODY
	for kind in ["Label", "CheckBox", "RichTextLabel", "LineEdit"]:
		t.set_color("font_color", kind, ink())
	t.set_color("default_color", "RichTextLabel", ink())
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("font_color", "ConfirmPanel", ink())
	for kind in ["PanelContainer", "ConfirmPanel", "PopupPanel"]:
		t.set_stylebox("panel", kind, box(paper()))
	for kind in ["Button", "OptionButton"]:
		t.set_font("font", kind, font("bold"))
		t.set_stylebox("normal", kind, box(paper(), 10, 3, 3, 10))
		t.set_stylebox("hover", kind, box(paper().lerp(MUSTARD, 0.35), 10, 3, 3, 10, true))
		t.set_stylebox("pressed", kind, box(paper().lerp(MUSTARD, 0.55), 10, 3, 0, 10))
		var dis := box(Color(paper(), 0.6), 10, 2, 0, 10)
		dis.border_color = Color(ink(), 0.35)
		t.set_stylebox("disabled", kind, dis)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, kind, ink())
		t.set_color("font_disabled_color", kind, Color(ink(), 0.4))
	t.set_type_variation("PrimaryButton", "Button")
	for state in ["normal", "hover", "pressed"]:
		t.set_stylebox(state, "PrimaryButton", box(RED.lightened(0.12 if state == "hover" else 0.0), 12, 3, 0 if state == "pressed" else 4, 12, state != "pressed"))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "PrimaryButton", PAPER)
	t.set_type_variation("SelectedButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "SelectedButton", box(MUSTARD, 10, 3, 3, 10, true))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(state, "SelectedButton", INK)
	t.set_type_variation("QuietButton", "Button")
	for state in ["normal", "hover", "pressed"]:
		var q := box(Color(0, 0, 0, 0), 10, 2, 0, 10)
		q.border_color = Color(ink(), 0.5 if state == "normal" else 0.9)
		t.set_stylebox(state, "QuietButton", q)
	t.set_stylebox("normal", "LineEdit", box(Color("fffaf0") if not dark() else Color("1d1813"), 10, 3, 0, 12))
	t.set_stylebox("focus", "LineEdit", box(Color("fffaf0") if not dark() else Color("1d1813"), 10, 4, 0, 12))
	t.set_stylebox("read_only", "LineEdit", box(Color(paper(), 0.5), 10, 2, 0, 12))
	t.set_color("caret_color", "LineEdit", RED)
	t.set_color("font_placeholder_color", "LineEdit", Color(ink(), 0.45))
	t.set_font("font", "LineEdit", font("bold"))
	t.set_stylebox("panel", "TooltipPanel", box(paper(), 8, 2, 2, 8))
	t.set_color("font_color", "TooltipLabel", ink())
	var grab := box(MUSTARD, 6, 2, 0, 4)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(ink(), 0.1)
	track.set_corner_radius_all(6)
	t.set_stylebox("scroll", "VScrollBar", track)
	_theme = t
	return t


static func label(text: String, size: int = BODY, color: Color = Color(0, 0, 0, 0), align := HORIZONTAL_ALIGNMENT_LEFT, kind: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color if color.a > 0.0 else ink())
	if kind != "regular":
		l.add_theme_font_override("font", font(kind))
	return l


static func title(text: String, size: int = H1) -> Label:
	return label(text, size, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, "title")


static func button(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -8))
	return b


static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.theme_type_variation = "PrimaryButton"
	b.custom_minimum_size.y = 48
	return b


static func panel(pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(paper(), 16, 4, 6, pad))
	return p


static func vbox(gap: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


static func hbox(gap: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Плашка редкости ответа.
static func rarity_chip(rarity: String, text: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(RARITY_COLORS.get(rarity, PAPER), 8, 2, 2, 6))
	var l := label(text if text != "" else STQuestions.RARITY_NAMES.get(rarity, ""), CAP, INK if rarity == "c" else PAPER, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	p.add_child(l)
	return p


## Чат из общего кода — в цвета бумаги.
static func restyle_chat(chat: Control) -> void:
	var apply := func():
		chat.add_theme_stylebox_override("panel", box(paper(), 12, 3, 4, 10))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", ink())
	if chat.is_node_ready():
		apply.call()
	else:
		chat.ready.connect(apply)


## Одобренный рисованный цирк; для запасного оформления остаются мультяшные лучи.
class Backdrop extends Control:
	var image := "bg_circus_approved.png"

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path := STStyle.ART + image
		if ResourceLoader.exists(path):
			var tr := TextureRect.new()
			tr.texture = load(path)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if STStyle.dark():
				tr.modulate = Color(0.55, 0.5, 0.45)
			add_child(tr)
		resized.connect(queue_redraw)

	func _draw() -> void:
		if get_child_count() > 0:
			return
		var c := size * Vector2(0.5, 0.55)
		var base := Color("3a2d22") if STStyle.dark() else Color("f0d9a4")
		var ray := Color("4a3a2b") if STStyle.dark() else Color("e9c77e")
		draw_rect(Rect2(Vector2.ZERO, size), base)
		var r := size.length()
		for i in 24:
			if i % 2 == 0:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r]), ray)


## Общая плёнка меню, лобби и стола: отдельный шейдер мелкой ряби.
## Не читает экран, не сдвигает интерфейс и пропускает мышь к игровым элементам.
class FilmFX extends ColorRect:
	func _ready() -> void:
		# Выше динамических спрайтов, но ниже игровых окон (60) и паузы (70).
		z_as_relative = false
		z_index = 50
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://games/stillion/ui/st_film.gdshader")
		material = paint
