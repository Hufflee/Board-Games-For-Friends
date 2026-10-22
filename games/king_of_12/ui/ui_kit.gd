class_name K12UI
extends RefCounted
## Общий стиль «таверны»: цвета, шрифты, тема Godot и фабрики элементов.
##
## Шрифты (OFL): Ruslan Display — заголовки в духе старорусской вязи, Alegreya Sans — текст.
## Рамки (CC0): Kenney «Fantasy UI Borders», тонированные в золото.

const BG := Color("1d3b2f")
const BG_DARK := Color("142a21")
const PANEL := Color(0.08, 0.055, 0.035, 0.9)
const PANEL_LIGHT := Color("4a3423")
const GOLD := Color("e8c26a")
const GOLD_DARK := Color("a8833c")
const CREAM := Color("f6efdc")
const INK := Color("3a2a1c")
const CRYSTAL := Color("5fb4ef")
const CRYSTAL_DARK := Color("2a6fa8")
const RED := Color("d9534f")
const GREEN := Color("6fcf6f")
const MUTED := Color("b9b09a")

## Дизайн-система «таверны» (docs/styleboard_tavern.png): золото — акцент/CTA, сукно — стол, дерево — панели;
## крем — текст, MUTED — подписи; GREEN — только успех, RED — только провал; CRYSTAL — только «◆».
## Текст — 3 размера:
const H1 := 32
const BODY := 17
const CAP := 14

const FONT_DIR := "res://games/king_of_12/art/fonts/"
const UI_DIR := "res://games/king_of_12/art/ui/"

static var _art := {}
static var _theme: Theme
static var _fonts := {}
static var _frames := {}


static func art(card: String) -> Texture2D:
	if not _art.has(card):
		_art[card] = load("res://games/king_of_12/art/%s.png" % card)
	return _art[card]


# --- Шрифты --------------------------------------------------------------------

## Символы вроде ★ ♛ ◆ берутся из системного шрифта, если их нет в основном.
static func _symbols() -> SystemFont:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial Unicode MS", "DejaVu Sans"])
	return sf


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var file: String = {
			"regular": "AlegreyaSans-Regular.ttf",
			"bold": "AlegreyaSans-Bold.ttf",
			"title": "RuslanDisplay-Regular.ttf",
		}[kind]
		var f: FontFile = load(FONT_DIR + file)
		f.fallbacks = [_symbols()]
		# обычные (выровненные) цифры вместо «старинных»: 0 ПО, а не «о ПО»
		var fv := FontVariation.new()
		fv.base_font = f
		fv.opentype_features = {"lnum": 1, "pnum": 1}
		_fonts[kind] = fv
	return _fonts[kind]


# --- Рамки ---------------------------------------------------------------------

## Орнаментальная рамка (9-slice), тонированная в золото.
static func frame(kind: String = "ornate", tint: Color = Color(0.91, 0.76, 0.42, 0.95)) -> StyleBoxTexture:
	var key := "%s/%s" % [kind, tint.to_html()]
	if not _frames.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = load(UI_DIR + "frame_%s.png" % kind)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 16)
		sb.modulate_color = tint
		sb.draw_center = false
		_frames[key] = sb
	return _frames[key]


## Разделитель с золотым затуханием к краям — под заголовками.
static func divider(width: float = 320.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(UI_DIR + "divider.png")
	t.modulate = Color(GOLD, 0.85)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(width, 14)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# --- Тема ----------------------------------------------------------------------

## Тема всего приложения (ставится на корневое окно): шрифты, кнопки, поля, ползунки, подсказки.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 17
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("regular"))
	for cls in ["Button", "OptionButton", "CheckBox"]:
		t.set_font("font", cls, font("bold"))
	t.set_color("font_color", "Label", CREAM)
	t.set_color("default_color", "RichTextLabel", CREAM)

	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, _button_box("normal"))
		t.set_stylebox("hover", cls, _button_box("hover"))
		t.set_stylebox("pressed", cls, _button_box("pressed"))
		t.set_stylebox("disabled", cls, _button_box("disabled"))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, CREAM)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, GOLD)
		t.set_color("font_disabled_color", cls, Color("7d7466"))

	var edit := box(Color(0.05, 0.035, 0.02, 0.92), 6, GOLD_DARK, 1)
	var edit_focus := box(Color(0.06, 0.04, 0.025, 0.95), 6, GOLD, 2)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color(CREAM, 0.4))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))

	t.set_color("font_color", "CheckBox", CREAM)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	# одинаковые отступы во всех состояниях: иначе при наведении текст наезжает на галочку
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var cb := StyleBoxEmpty.new()
		cb.content_margin_left = 4
		cb.content_margin_right = 4
		cb.content_margin_top = 2
		cb.content_margin_bottom = 2
		t.set_stylebox(st, "CheckBox", cb)
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)

	var slider := box(Color(0.05, 0.035, 0.02, 0.9), 4, GOLD_DARK, 1)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	var fill := box(GOLD_DARK, 4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, 4))

	var scroll := box(Color(0, 0, 0, 0.25), 4)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(Color(GOLD_DARK, 0.8), 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD, 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, 4))

	var popup := box(Color(0.08, 0.055, 0.035, 0.98), 6, GOLD_DARK, 1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color("5a3c22"), 4))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", font("regular"))

	var tip := box(Color(0.96, 0.92, 0.82, 0.98), 6, GOLD_DARK, 2)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", font("regular"))
	t.set_font_size("font_size", "TooltipLabel", 15)
	_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(GOLD, 7, GOLD.lightened(0.3), 1)
	sel.content_margin_left = maxf(sel.content_margin_left, 12)
	sel.content_margin_right = maxf(sel.content_margin_right, 12)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", INK)
	# опасное/второстепенное действие (выход из партии): приглушено, при наведении — красным
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(0, 0, 0, 0.25), 7, Color(GOLD_DARK, 0.45), 1)
	var qh := box(Color(0.35, 0.06, 0.05, 0.55), 7, RED, 1)
	for sb in [qn, qh]:
		sb.content_margin_left = maxf(sb.content_margin_left, 12)
		sb.content_margin_right = maxf(sb.content_margin_right, 12)
		sb.content_margin_top = maxf(sb.content_margin_top, 6)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 6)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", MUTED)
	t.set_color("font_hover_color", "QuietButton", RED.lightened(0.25))
	t.set_color("font_pressed_color", "QuietButton", RED.lightened(0.25))
	# окно подтверждения (LeaveGuard)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(Color(0.09, 0.06, 0.04, 0.98), 10, GOLD_DARK, 2)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", CREAM)
	return t


static func _button_box(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 9
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 3
	match state:
		"normal":
			sb.bg_color = Color("3d2918")
			sb.border_color = GOLD_DARK
			sb.shadow_color = Color(0, 0, 0, 0.45)
			sb.shadow_size = 3
			sb.shadow_offset = Vector2(0, 2)
		"hover":
			sb.bg_color = Color("5c3d22")
			sb.border_color = GOLD
			sb.shadow_color = Color(GOLD, 0.3)
			sb.shadow_size = 7
		"pressed":
			sb.bg_color = Color("2a1b0f")
			sb.border_color = GOLD
			sb.border_width_top = 3
			sb.border_width_bottom = 1
			sb.content_margin_top = 9
			sb.content_margin_bottom = 7
		"disabled":
			sb.bg_color = Color("2a221a")
			sb.border_color = Color("5d5145")
	return sb


static func box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# --- Фабрики -------------------------------------------------------------------

## Панель: тёмное дерево с золотой орнаментальной рамкой.
static func panel(color: Color = PANEL, radius: int = 8, frame_kind: String = "ornate") -> PanelContainer:
	var p := FramedPanel.new()
	var sb := box(color, radius)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	p.frame = frame(frame_kind)
	return p


class FramedPanel:
	extends PanelContainer
	var frame: StyleBox

	func _draw() -> void:
		if frame:
			draw_style_box(frame, Rect2(Vector2(3, 3), size - Vector2(6, 6)))


## Надпись. Золотые надписи от 20 пт автоматически набираются заголовочным шрифтом.
static func label(text: String, size: int = 16, color: Color = CREAM, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if color == GOLD and size >= 20:
		l.add_theme_font_override("font", font("title"))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_color_override("font_outline_color", Color("3a2410"))
		l.add_theme_constant_override("outline_size", maxi(2, size / 8))
	return l


## Заголовок окна: вязь + разделитель.
static func title(text: String, size: int = 30) -> VBoxContainer:
	var v := vbox(0)
	v.add_child(label(text, size, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(divider(maxf(220.0, text.length() * size * 0.55)))
	return v


static func button(text: String, size: int = 18, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -4))
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.play("hover", -16, 0.05, 0.06))
	return b


## Кнопка «Звук: вкл/выкл».
static func sound_button(size: int = 14) -> Button:
	var b := button("", size)
	var sync := func(): b.text = "Звук: выкл" if Sfx.muted else "Звук: вкл"
	sync.call()
	b.pressed.connect(func():
		Sfx.set_muted(not Sfx.muted)
		sync.call())
	return b


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
