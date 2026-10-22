class_name AAStyle
extends RefCounted
## Стиль «Алольского атлета»: тропический комикс — фон-«солнце» из лучей (красный, фиолетовый,
## жёлтый, розовый) как на рубашке карт, белые панели с толстой чёрной обводкой. Шрифт — Rubik (OFL).
## Дизайн-система: 2 цвета — фиолетовый (фон) и чёрные чернила; белый — панели; жёлтый — главная кнопка.
## Текст — 3 размера: H1, BODY, CAP.

const PINK := Color("ff5fb4")
const PINK_DARK := Color("8a3fd1")
const PINK_LIGHT := Color("ff6fb7")
const INK := Color("1b1b1b")
const PAPER := Color("ffffff")
const MUTED := Color("6d6d6d")
const ACCENT := Color("ffd23f")
const OK := Color("2fae4f")
const BAD := Color("e0393e")
const H1 := 30
const BODY := 17
const CAP := 14

const ART := "res://games/alola_athlete/art/"
const MUSIC := [
	"res://games/alola_athlete/audio/tropical_fantasy.ogg",
	"res://games/alola_athlete/audio/feel_good_island.ogg",
]
const CARD := Vector2(92, 118)

static var _fonts := {}
static var _theme: Theme
static var _icons := {}


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var base: FontFile = load(ART + "fonts/Rubik-Variable.ttf")
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		base.fallbacks = [sym]
		var f := FontVariation.new()
		f.base_font = base
		f.variation_opentype = {"wght": 800 if kind != "regular" else 500}
		_fonts[kind] = f
	return _fonts[kind]


## Картинка: "cards/rowlet", "tokens/rowlet", "tracks/mele", "chips/gold3".
static func tex(path: String) -> Texture2D:
	if not _icons.has(path):
		_icons[path] = load(ART + path + ".webp")
	return _icons[path]


static func box(color: Color, radius: int = 14, border: Color = INK, border_w: int = 3, shadow: float = 0.25) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0.0:
		sb.shadow_color = Color(0, 0, 0, shadow)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(4, 5)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = BODY
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", INK)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("bold"))
		t.set_stylebox("normal", cls, box(PAPER, 12, INK, 3, 0.25))
		t.set_stylebox("hover", cls, box(Color("fff3a8"), 12, INK, 3, 0.3))
		var p := box(ACCENT, 12, INK, 3, 0.0)
		p.content_margin_top = 10
		p.content_margin_bottom = 6
		t.set_stylebox("pressed", cls, p)
		t.set_stylebox("disabled", cls, box(Color(1, 1, 1, 0.55), 12, Color(INK, 0.35), 3, 0.0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, cls, INK)
		t.set_color("font_disabled_color", cls, Color(INK, 0.45))
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", PINK_DARK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", PINK_DARK)
	t.set_stylebox("normal", "LineEdit", box(PAPER, 10, INK, 3, 0.0))
	t.set_stylebox("focus", "LineEdit", box(PAPER, 10, PINK, 3, 0.0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", PINK)
	t.set_stylebox("panel", "TooltipPanel", box(INK, 8, INK, 0, 0.0))
	t.set_color("font_color", "TooltipLabel", PAPER)
	t.set_stylebox("panel", "PopupMenu", box(PAPER, 8, INK, 2, 0.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.08), 4, INK, 0, 0.0))
	t.set_stylebox("grabber", "VScrollBar", box(INK, 4, INK, 0, 0.0))
	# выбранный вариант (UISel.pick) — жёлтая заливка
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(ACCENT, 12, INK, 3, 0.25)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", INK)
	# опасное действие (выход) и окно подтверждения (LeaveGuard)
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(1, 1, 1, 0.5), 12, Color(INK, 0.4), 2, 0.0)
	var qh := box(PAPER, 12, BAD, 3, 0.2)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", Color(INK, 0.65))
	t.set_color("font_hover_color", "QuietButton", BAD)
	t.set_color("font_pressed_color", "QuietButton", BAD)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(PAPER, 16, INK, 4, 0.3)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", INK)
	_theme = t
	return t


static func label(text: String, size: int = BODY, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font("bold"))
	l.horizontal_alignment = align
	return l


## Заголовок «маркером»: белые буквы с толстой чёрной обводкой.
static func title(text: String, size: int = H1) -> Label:
	var l := label(text, size, PAPER, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	return l


static func button(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -6))
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.play("hover", -14, 0.1, 0.05))
	return b


static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.theme_type_variation = "SelectedButton"
	return b


static func panel(pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(PAPER, 18, INK, 4, 0.25)
	sb.set_content_margin_all(pad)
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


## Чат — белые карточки с чёрным контуром.
static func restyle_chat(chat: Control) -> void:
	chat.ready.connect(func():
		chat.add_theme_stylebox_override("panel", box(PAPER, 12, INK, 3, 0.2))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", INK))


## Фон: «солнце» из цветных лучей (как рубашка карт), приглушённое тёмной виньеткой.
class Backdrop:
	extends Control

	const RAYS := [Color("e8403c"), Color("8a3fd1"), Color("f5c932"), Color("ff7fc8")]

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("2a1240"))
		var c := size * 0.5
		var r := size.length()
		var n := 24
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var col: Color = RAYS[i % RAYS.size()]
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), Color(col, 0.55))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.02, 0.14, 0.45))
