class_name HubStyle
extends RefCounted

const ACCENT_FX := preload("res://hub/ui_accent_fx.gd")
## Неоновое ретро: базовый стиль главного меню и общего интерфейса.
## Тёмно-фиолетовые полупрозрачные панели, неоновые рамки (розовый / бирюзовый) со свечением,
## шрифты: заголовки — Russo One, текст — Exo 2, пиксельные акценты — Press Start 2P (OFL, с кириллицей).

const BG := Color("0b0614")
const PANEL := Color(0.07, 0.04, 0.13, 0.86)
const PINK := Color("ff3ea5")
const CYAN := Color("2ef2ff")
const VIOLET := Color("9b5cff")
const YELLOW := Color("ffe14d")
const TEXT := Color("f3eaff")
const MUTED := Color("a99cc9")

const FONT_DIR := "res://hub/art/fonts/"

static var _fonts := {}


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var file: String = {"title": "RussoOne-Regular.ttf", "pixel": "PressStart2P-Regular.ttf"}.get(kind, "Exo2-Variable.ttf")
		var f: FontFile = load(FONT_DIR + file)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = f
		if kind in ["regular", "medium", "bold"]:
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			fv.variation_opentype = {wght: {"regular": 450, "medium": 600, "bold": 750}[kind]}
		_fonts[kind] = fv
	return _fonts[kind]


## Панель: тёмное стекло с неоновой рамкой и свечением.
static func box(color: Color = PANEL, radius: int = 10, border: Color = VIOLET, border_w: int = 2, glow: float = 0.45) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if glow > 0.0:
		sb.shadow_color = Color(border, glow)
		sb.shadow_size = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


## Неоновая надпись: светлая сердцевина и цветное свечение вокруг.
static func neon_label(text: String, size: int, color: Color = PINK, kind: String = "title") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color.lightened(0.55))
	l.add_theme_color_override("font_outline_color", Color(color, 0.85))
	l.add_theme_constant_override("outline_size", maxi(3, size / 9))
	l.add_theme_color_override("font_shadow_color", Color(color, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", maxi(8, size / 3))
	return l


static var _theme: Theme


## Тема неонового ретро: кнопки, поля ввода, флажки, подсказки, прокрутка.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 16
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("medium"))
		t.set_stylebox("normal", cls, box(Color(0.1, 0.05, 0.2, 0.8), 8, Color(VIOLET, 0.8), 2, 0.25))
		t.set_stylebox("hover", cls, box(Color(0.16, 0.06, 0.28, 0.9), 8, PINK, 2, 0.7))
		t.set_stylebox("pressed", cls, box(Color(0.22, 0.05, 0.3, 0.95), 8, CYAN, 2, 0.7))
		t.set_stylebox("disabled", cls, box(Color(0.08, 0.05, 0.14, 0.6), 8, Color(MUTED, 0.3), 1, 0.0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, PINK.lightened(0.45))
		t.set_color("font_pressed_color", cls, CYAN.lightened(0.4))
		t.set_color("font_disabled_color", cls, Color(MUTED, 0.5))
	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.02, 0.09, 0.85), 8, Color(VIOLET, 0.6), 2, 0.0))
	t.set_stylebox("focus", "LineEdit", box(Color(0.04, 0.02, 0.09, 0.9), 8, CYAN, 2, 0.5))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	t.set_color("caret_color", "LineEdit", CYAN)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", PINK.lightened(0.4))
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", PINK.lightened(0.4))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, 8, VIOLET, 1, 0.3))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.2, 0.06, 0.3), 6, PINK, 0, 0.0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.03, 0.12, 0.95), 6, CYAN, 1, 0.3))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var scroll := box(Color(1, 1, 1, 0.04), 4, Color.TRANSPARENT, 0, 0.0)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(Color(VIOLET, 0.7), 4, Color.TRANSPARENT, 0, 0.0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(PINK, 4, Color.TRANSPARENT, 0, 0.0))
	t.set_stylebox("slider", "HSlider", box(Color(0.1, 0.05, 0.2), 4, VIOLET, 1, 0.0))
	t.set_stylebox("grabber_area", "HSlider", box(PINK, 4, Color.TRANSPARENT, 0, 0.3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CYAN, 4, Color.TRANSPARENT, 0, 0.3))
	_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(Color(PINK, 0.85), 8, PINK.lightened(0.3), 2, 0.6)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", Color.WHITE)
	# второстепенное/опасное действие и окно подтверждения (LeaveGuard)
	t.set_type_variation("QuietButton", "Button")
	t.set_stylebox("normal", "QuietButton", box(Color(0.08, 0.05, 0.14, 0.6), 8, Color(MUTED, 0.4), 1, 0.0))
	t.set_stylebox("hover", "QuietButton", box(Color(0.2, 0.05, 0.12, 0.8), 8, PINK, 2, 0.4))
	t.set_stylebox("pressed", "QuietButton", box(Color(0.2, 0.05, 0.12, 0.8), 8, PINK, 2, 0.4))
	t.set_color("font_color", "QuietButton", MUTED)
	t.set_color("font_hover_color", "QuietButton", PINK.lightened(0.3))
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(PANEL, 12, VIOLET, 2, 0.5)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", TEXT)
	return t


static func label(text: String, size: int = 16, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, weight: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != "regular":
		l.add_theme_font_override("font", font(weight))
	l.horizontal_alignment = align
	return l


static func button(text: String, size: int = 16, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -6))
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.play("hover", -18, 0.05, 0.06))
	return b


## Главная кнопка: розовый неон.
static func primary(text: String, size: int = 18, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.add_theme_stylebox_override("normal", box(Color(0.35, 0.04, 0.24, 0.9), 10, PINK, 2, 0.6))
	b.add_theme_stylebox_override("hover", box(Color(0.5, 0.06, 0.33, 0.95), 10, PINK.lightened(0.3), 2, 0.9))
	b.add_theme_stylebox_override("pressed", box(Color(0.25, 0.03, 0.2, 0.95), 10, CYAN, 2, 0.8))
	b.add_theme_font_override("font", font("title"))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	ACCENT_FX.sheen(b)
	return b


static func panel(border: Color = VIOLET) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(PANEL, 12, border, 2, 0.45)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()
