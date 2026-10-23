class_name DWStyle
extends RefCounted

const ACCENT_FX := preload("res://hub/ui_accent_fx.gd")
## Жутковатый «хеллоуинский» стиль «Опасных слов» — своя тема, не общая «таверна».
## Ночь, туман, луна, летучие мыши, паутина.
## Дизайн-система (docs/styleboard_dangerous_words.png): 2 основных цвета — тыква (акцент, «Тыквы») и фиолет
## («Летучие мыши», рамки); нейтральные — ночь, панель, текст, подпись; сигналы — зелёный только «успех»,
## красный только «провал». Текст — 3 размера: H1 (слово, заголовок), BODY (основной), CAP (подписи).

const NIGHT := Color("120a1c")
const PANEL := Color(0.11, 0.06, 0.17, 0.92)
const PANEL_2 := Color(0.17, 0.09, 0.25, 0.95)
const PUMPKIN := Color("ff8a1f")
const SLIME := Color("8cff5a")
const VIOLET := Color("b07cff")
const VIOLET_DIM := Color("6b3fa0")  # рамки, полосы прокрутки
const BLOOD := Color("e0303a")
const TEXT := Color("efe6ff")
const MUTED := Color("a497bf")
const TEAM_COLORS := [PUMPKIN, VIOLET]

const H1 := 44
const BODY := 18
const CAP := 14

const FONT_DIR := "res://games/dangerous_words/art/fonts/"
const MUSIC := [
	"res://games/dangerous_words/audio/halloween_hullabaloo.mp3",
	"res://games/dangerous_words/audio/wonderful_nightmare.ogg",
	"res://games/dangerous_words/audio/creepy_loop.ogg",
]

static var _fonts := {}
static var _theme: Theme


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var file: String = {"title": "RubikWetPaint-Regular.ttf", "word": "Nunito-Variable.ttf"}.get(kind, "Rubik-Variable.ttf")
		var f: FontFile = load(FONT_DIR + file)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = f
		if kind == "word":
			# загаданные слова — округлый жирный Nunito
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
		elif kind == "bold":
			fv.variation_opentype = {"wght": 700}
		elif kind == "regular":
			fv.variation_opentype = {"wght": 420}
		_fonts[kind] = fv
	return _fonts[kind]


static func box(color: Color, radius: int = 12, border: Color = Color.TRANSPARENT, border_w: int = 0, glow: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if glow.a > 0.0:
		sb.shadow_color = glow
		sb.shadow_size = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 17
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("bold"))
		t.set_stylebox("normal", cls, box(Color("2a1540"), 14, VIOLET_DIM, 2, Color(0, 0, 0, 0.5)))
		t.set_stylebox("hover", cls, box(Color("3d1d5c"), 14, PUMPKIN, 2, Color(PUMPKIN, 0.45)))
		t.set_stylebox("pressed", cls, box(Color("1a0c29"), 14, PUMPKIN, 2, Color(PUMPKIN, 0.35)))
		t.set_stylebox("disabled", cls, box(Color("1b1226"), 14, Color("3a2d4a"), 1))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, PUMPKIN)
		t.set_color("font_pressed_color", cls, PUMPKIN)
		t.set_color("font_disabled_color", cls, Color("5d5070"))
	t.set_stylebox("normal", "LineEdit", box(Color("0d0714"), 10, VIOLET_DIM, 2))
	t.set_stylebox("focus", "LineEdit", box(Color("0d0714"), 10, PUMPKIN, 2, Color(PUMPKIN, 0.3)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.35))
	t.set_color("caret_color", "LineEdit", PUMPKIN)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", PUMPKIN)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PopupMenu", box(Color("1a0c29"), 8, VIOLET_DIM, 1))
	t.set_stylebox("hover", "PopupMenu", box(Color("3d1d5c"), 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", PUMPKIN)
	t.set_stylebox("panel", "TooltipPanel", box(Color("1a0c29"), 8, PUMPKIN, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var scroll := box(Color(0, 0, 0, 0.3), 4)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(VIOLET_DIM, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(PUMPKIN, 4))
	t.set_stylebox("slider", "HSlider", box(Color("0d0714"), 4, VIOLET_DIM, 1))
	t.set_stylebox("grabber_area", "HSlider", box(PUMPKIN, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(PUMPKIN, 4))
	_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(PUMPKIN, 14, PUMPKIN.lightened(0.25), 2)
	sel.content_margin_left = maxf(sel.content_margin_left, 12)
	sel.content_margin_right = maxf(sel.content_margin_right, 12)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", Color("1a0c29"))
	# опасное/второстепенное действие (выход из партии): приглушено, при наведении — красным
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(0, 0, 0, 0.25), 14, Color("3a2d4a"), 1)
	var qh := box(Color("2a1022"), 14, BLOOD, 2)
	for sb in [qn, qh]:
		sb.content_margin_left = maxf(sb.content_margin_left, 12)
		sb.content_margin_right = maxf(sb.content_margin_right, 12)
		sb.content_margin_top = maxf(sb.content_margin_top, 6)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 6)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", MUTED)
	t.set_color("font_hover_color", "QuietButton", BLOOD.lightened(0.3))
	t.set_color("font_pressed_color", "QuietButton", BLOOD.lightened(0.3))
	# окно подтверждения (LeaveGuard)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(Color("1b1226"), 18, PUMPKIN, 2)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", Color("f3eaff"))
	return t


static func label(text: String, size: int = BODY, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font("bold"))
	l.horizontal_alignment = align
	return l


## Заголовок «капающей краской»: оранжевый с тёмной обводкой и зелёным свечением.
static func title(text: String, size: int = H1, color: Color = PUMPKIN) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", font("title"))
	l.add_theme_color_override("font_outline_color", Color("1a0505"))
	l.add_theme_constant_override("outline_size", maxi(4, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(SLIME, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 8)
	return l


static func button(text: String, size: int = BODY, min_w: int = 0) -> Button:
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

## Главное действие: прежний стиль кнопки и периодический блик.
static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	ACCENT_FX.sheen(b)
	return b


static func panel(border: Color = VIOLET_DIM) -> PanelContainer:
	var p := WebPanel.new()
	p.add_theme_stylebox_override("panel", box(PANEL, 16, border, 2, Color(0, 0, 0, 0.6)))
	return p


## Панель с паутиной в углах.
class WebPanel:
	extends PanelContainer

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.18)
		_web(Vector2(0, 0), Vector2(1, 1), c)
		_web(Vector2(size.x, 0), Vector2(-1, 1), c)

	func _web(o: Vector2, d: Vector2, c: Color) -> void:
		var r := 34.0
		for k in 5:
			var a := k * PI / 8.0
			draw_line(o, o + Vector2(cos(a) * d.x, sin(a) * d.y) * r, c, 1.0, true)
		for ring in [0.35, 0.65, 0.95]:
			var pts := PackedVector2Array()
			for k in 5:
				var a := k * PI / 8.0
				pts.append(o + Vector2(cos(a) * d.x, sin(a) * d.y) * r * ring)
			draw_polyline(pts, c, 1.0, true)


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


static func art(name: String) -> Texture2D:
	return load("res://games/dangerous_words/art/%s.png" % name)
