class_name RSBStyle
extends RefCounted
## Стиль «Ready Set Bet»: американский ипподром 80-х — бумага старой афиши, зелёное сукно,
## красные заголовки плитой-антиквой, кремовые таблички, золото. Арт — из правил (только для личной игры).

const FELT := Color("1f5c36")
const FELT_DARK := Color("143f24")
const GOLD := Color("e9c45a")
const DIRT := Color("8a5a35")
# игровые предметы (поле, дорожка, VIP-карты) — свои цвета, не меняются с темой
const INK_ART := Color("2b1d14")
const CREAM_ART := Color("fbf3dd")

## Светлая (бумага афиши) и тёмная (docs/styleboard_ready_set_bet_dark.png) палитры интерфейса; set_dark().
const LIGHT := {
	"PAPER": Color("efe2c4"), "PAPER_DARK": Color("d9c69e"), "CREAM": Color("fbf3dd"), "HOVER": Color("fff8e6"),
	"INK": Color("2b1d14"), "MUTED": Color("7a6650"), "RED": Color("c8312b"), "MONEY": Color("2e7d32"),
	"RAY": Color(1, 0.93, 0.75, 0.35),
}
const DARK := {
	"PAPER": Color("17120d"), "PAPER_DARK": Color("241b13"), "CREAM": Color("2a2018"), "HOVER": Color("35291f"),
	"INK": Color("f3e7cc"), "MUTED": Color("b3a083"), "RED": Color("e04a3f"), "MONEY": Color("e9c45a"),
	"RAY": Color(1, 0.85, 0.6, 0.04),
}
static var dark := false
static var PAPER: Color = LIGHT["PAPER"]
static var PAPER_DARK: Color = LIGHT["PAPER_DARK"]
static var CREAM: Color = LIGHT["CREAM"]
static var HOVER: Color = LIGHT["HOVER"]
static var INK: Color = LIGHT["INK"]
static var MUTED: Color = LIGHT["MUTED"]
static var RED: Color = LIGHT["RED"]
static var MONEY: Color = LIGHT["MONEY"]  # суммы и выигрыши (светлая — зелёный на бумаге, тёмная — золото)
static var RAY: Color = LIGHT["RAY"]


static func set_dark(on: bool) -> void:
	dark = on
	var pal: Dictionary = DARK if on else LIGHT
	PAPER = pal["PAPER"]
	PAPER_DARK = pal["PAPER_DARK"]
	CREAM = pal["CREAM"]
	HOVER = pal["HOVER"]
	INK = pal["INK"]
	MUTED = pal["MUTED"]
	RED = pal["RED"]
	MONEY = pal["MONEY"]
	RAY = pal["RAY"]
	_theme = null


static func sync_prefs() -> bool:
	var want: bool = Prefs.dark_theme()
	if want == dark and _theme != null:
		return false
	set_dark(want)
	return true

## Дизайн-система (docs/styleboard_ready_set_bet.png): 2 основных цвета — красный (акцент, CTA) и сукно;
## нейтральные — бумага, кремовая панель, чернила, подписи; деньги — MONEY на светлом, GOLD на тёмном.
## Текст — 3 размера:
const H1 := 36
const BODY := 16
const CAP := 13
const HORSE_COLORS := {"blue": Color("33a9e0"), "orange": Color("f2a81d"), "red": Color("ec5a7a"), "black": Color("1b1b1b")}
const PLAYER_COLORS := ["blue", "pink", "brown", "navy", "gray", "purple", "green", "yellow"]
const PLAYER_TINT := [Color("6fa8dc"), Color("f08fb0"), Color("a8774f"), Color("4b4f80"), Color("9a9a9a"), Color("a45bb0"), Color("8cc152"), Color("f4c430")]
const PLAYER_NAMES := ["голубой", "розовый", "коричневый", "синий", "серый", "фиолетовый", "зелёный", "жёлтый"]

const ART := "res://games/ready_set_bet/art/"
const MUSIC := [
	"res://games/ready_set_bet/audio/gone_fishin.mp3",
	"res://games/ready_set_bet/audio/happy_vibes.mp3",
]
const WIN_JINGLE := "res://games/ready_set_bet/audio/reel_winner.mp3"

static var _fonts := {}
static var _theme: Theme
static var _tex := {}


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var path := ART + ("fonts/KellySlab-Regular.ttf" if kind == "title" else "fonts/Bitter-Variable.ttf")
		var f: FontFile = load(path)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = f
		if kind != "title":
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			fv.variation_opentype = {wght: {"regular": 450, "bold": 750}[kind]}
		_fonts[kind] = fv
	return _fonts[kind]


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(ART + name + ".png")
	return _tex[name]


static func token_tex(seat: int, v: int, bonus: String) -> Texture2D:
	if bonus != "":
		return tex("bonus_%s_%d" % [bonus, v])
	return tex("token_%s_%d" % [PLAYER_COLORS[seat % 8], v])


static func box(color: Color, radius: int = 8, border: Color = Color.TRANSPARENT, border_w: int = 0, shadow: Color = Color.TRANSPARENT, shadow_size: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow.a > 0.0:
		sb.shadow_color = shadow
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2(2, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 16
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", INK)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("bold"))
		t.set_stylebox("normal", cls, box(CREAM, 6, INK, 2, Color(0, 0, 0, 0.25), 3))
		t.set_stylebox("hover", cls, box(HOVER, 6, RED, 2, Color(RED, 0.25), 5))
		t.set_stylebox("pressed", cls, box(PAPER_DARK, 6, RED, 2))
		t.set_stylebox("disabled", cls, box(Color(CREAM, 0.5), 6, Color(INK, 0.3), 2))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, INK)
		t.set_color("font_hover_color", cls, RED)
		t.set_color("font_pressed_color", cls, RED.darkened(0.2))
		t.set_color("font_disabled_color", cls, Color(INK, 0.4))
	t.set_stylebox("normal", "LineEdit", box(CREAM, 6, INK, 2))
	t.set_stylebox("focus", "LineEdit", box(CREAM, 6, RED, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", RED)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", RED)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", RED)
	t.set_stylebox("panel", "PopupMenu", box(CREAM, 6, INK, 2))
	t.set_stylebox("hover", "PopupMenu", box(PAPER_DARK, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("panel", "TooltipPanel", box(INK, 6, GOLD, 1))
	t.set_color("font_color", "TooltipLabel", CREAM)
	var scroll := box(Color(0, 0, 0, 0.08), 4)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(Color(INK, 0.4), 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(RED, 4))
	t.set_stylebox("slider", "HSlider", box(PAPER_DARK, 4))
	t.set_stylebox("grabber_area", "HSlider", box(RED, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(RED.lightened(0.1), 4))
	_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(RED, 6, RED.darkened(0.25), 2)
	sel.content_margin_left = maxf(sel.content_margin_left, 12)
	sel.content_margin_right = maxf(sel.content_margin_right, 12)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", Color.WHITE)
	# опасное/второстепенное действие (выход из партии): приглушено, при наведении — красным
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(CREAM, 0.6), 6, Color(INK, 0.25), 2)
	var qh := box(CREAM, 6, RED, 2)
	for sb in [qn, qh]:
		sb.content_margin_left = maxf(sb.content_margin_left, 12)
		sb.content_margin_right = maxf(sb.content_margin_right, 12)
		sb.content_margin_top = maxf(sb.content_margin_top, 6)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 6)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", Color(INK, 0.75))
	t.set_color("font_hover_color", "QuietButton", RED)
	t.set_color("font_pressed_color", "QuietButton", RED)
	# окно подтверждения (LeaveGuard)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(CREAM, 8, RED, 3)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", INK)
	return t


static func label(text: String, size: int = BODY, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, weight: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != "regular":
		l.add_theme_font_override("font", font(weight))
	l.horizontal_alignment = align
	return l


## Заголовок афиши: красная плита-антиква с кремовой обводкой и тенью.
static func title(text: String, size: int = H1, color: Color = RED) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER, "title")
	l.add_theme_color_override("font_outline_color", CREAM)
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
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
			Sfx.play("hover", -18, 0.05, 0.06))
	return b


## Большая красная кнопка «как на табло».
static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.add_theme_stylebox_override("normal", box(RED, 6, INK, 2, Color(0, 0, 0, 0.3), 3))
	b.add_theme_stylebox_override("hover", box(RED.lightened(0.1), 6, GOLD, 2, Color(GOLD, 0.3), 5))
	b.add_theme_stylebox_override("pressed", box(RED.darkened(0.15), 6, INK, 2))
	b.add_theme_stylebox_override("disabled", box(Color(RED, 0.4), 6, Color(INK, 0.3), 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_disabled_color", Color(CREAM, 0.7))
	b.add_theme_font_override("font", font("title"))
	return b


## Табличка на бумаге: кремовая с тёмной рамкой и «потёртой» тенью.
static func panel(color: Color = CREAM, border: Color = INK) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(color, 8, border, 3, Color(0, 0, 0, 0.3), 6)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func felt_panel() -> PanelContainer:
	return panel(FELT, GOLD)


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


static func pic(t: Texture2D, s: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = s
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func money(v: int) -> String:
	return "$%d" % v


## Чат из общего кода — в цветах афиши.
static func restyle_chat(chat: Control) -> void:
	chat.ready.connect(func():
		chat.add_theme_stylebox_override("panel", box(CREAM, 8, INK, 2, Color(0, 0, 0, 0.3), 5))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", INK))


## Фон: бумага афиши с выгоревшими лучами солнца 80-х и лёгким зерном.
class Backdrop:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), RSBStyle.PAPER)
		var c := Vector2(size.x * 0.5, size.y * 1.15)
		var rays := 28
		for i in rays:
			if i % 2 == 1:
				continue
			var a0 := PI + PI * i / rays
			var a1 := PI + PI * (i + 1) / rays
			var r := size.length()
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), RSBStyle.RAY)
		var rng := RandomNumberGenerator.new()
		rng.seed = 80
		for i in 900:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(RSBStyle.INK, rng.randf_range(0.02, 0.07)))
		# красно-кремовые полосы сверху и снизу — как на афише
		for k in 3:
			var col := RSBStyle.RED if k % 2 == 0 else RSBStyle.CREAM
			draw_rect(Rect2(0, k * 4, size.x, 4), col)
			draw_rect(Rect2(0, size.y - 12 + k * 4, size.x, 4), col)
