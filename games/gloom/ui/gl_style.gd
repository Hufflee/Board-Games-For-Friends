class_name GLStyle
extends RefCounted

const ACCENT_FX := preload("res://hub/ui_accent_fx.gd")
## Стиль Gloom: викторианская готика в духе Эдварда Гори — тёмные обои с узором, панели цвета
## старой кости с чёрно-серебряной каймой, кроваво-красный акцент. Шрифты — Old Standard (текст)
## и Cormorant SC (заголовки), оба OFL.
## Дизайн-система: 2 цвета — уголь (фон) и кость (панели, текст на тёмном); красный — только
## главная кнопка и смерть. Текст — 3 размера: H1, BODY, CAP.

const COAL := Color("17141a")
const COAL_2 := Color("231e25")
const BONE := Color("e9e2d4")
const BONE_DIM := Color("b9b0a0")
const INK := Color("1d1a1c")
const SILVER := Color("9d968c")
const MUTED := Color("756d64")
const BLOOD := Color("a3202a")
const BLOOD_LIGHT := Color("d2424a")
const OK := Color("6f9a5a")
const H1 := 30
const BODY := 17
const CAP := 14

const ART := "res://games/gloom/art/"
const MUSIC := [
	"res://games/gloom/audio/death_waltz.ogg",
	"res://games/gloom/audio/apparitions_ball.ogg",
]
const CARD := Vector2(507, 729)  # картинка карты

static var _fonts := {}
static var _theme: Theme
static var _tex := {}


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var file: String = {"regular": "OldStandard-Regular.ttf", "bold": "OldStandard-Bold.ttf", "italic": "OldStandard-Italic.ttf", "title": "CormorantSC-Bold.ttf"}.get(kind, "OldStandard-Regular.ttf")
		var f: FontFile = load(ART + "fonts/" + file)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		_fonts[kind] = f
	return _fonts[kind]


## Картинка карты: "ch3" — персонаж, "d12" — карта колоды, "back" — рубашка.
static func tex(id: String) -> Texture2D:
	if not _tex.has(id):
		_tex[id] = load(ART + "cards/" + id + ".webp")
	return _tex[id]


static func card_tex(card: int) -> Texture2D:
	return tex("d%d" % card)


static func char_tex(char_id: int) -> Texture2D:
	return tex("ch%d" % char_id)


static func box(color: Color, radius: int = 6, border: Color = SILVER, border_w: int = 2, shadow: float = 0.35) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0.0:
		sb.shadow_color = Color(0, 0, 0, shadow)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = BODY
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", INK)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("title"))
		t.set_stylebox("normal", cls, box(BONE, 6, INK, 2, 0.3))
		t.set_stylebox("hover", cls, box(Color("f6f0e4"), 6, BLOOD, 2, 0.35))
		var p := box(BONE_DIM, 6, INK, 2, 0.0)
		p.content_margin_top = 9
		p.content_margin_bottom = 5
		t.set_stylebox("pressed", cls, p)
		t.set_stylebox("disabled", cls, box(Color(BONE, 0.45), 6, Color(INK, 0.3), 2, 0.0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, cls, INK)
		t.set_color("font_disabled_color", cls, Color(INK, 0.45))
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", BLOOD)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", BLOOD)
	t.set_stylebox("normal", "LineEdit", box(Color("fbf7ef"), 4, INK, 2, 0.0))
	t.set_stylebox("focus", "LineEdit", box(Color("fbf7ef"), 4, BLOOD, 2, 0.0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", BLOOD)
	t.set_stylebox("panel", "TooltipPanel", box(COAL, 4, SILVER, 1, 0.0))
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_stylebox("panel", "PopupMenu", box(BONE, 4, INK, 2, 0.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.1), 3, INK, 0, 0.0))
	t.set_stylebox("grabber", "VScrollBar", box(MUTED, 3, INK, 0, 0.0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(INK, 3, INK, 0, 0.0))
	# главная кнопка и выбранный вариант (UISel.pick) — кроваво-красная заливка
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(BLOOD, 6, INK, 2, 0.35)
	var sel_h := box(BLOOD_LIGHT, 6, INK, 2, 0.4)
	t.set_stylebox("normal", "SelectedButton", sel)
	t.set_stylebox("hover", "SelectedButton", sel_h)
	t.set_stylebox("pressed", "SelectedButton", sel)
	t.set_stylebox("disabled", "SelectedButton", sel)  # UISel.pick: выбранный вариант — «нажат», а не серый
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", BONE)
	# опасное действие (выход) и окно подтверждения (LeaveGuard)
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(BONE, 0.5), 6, Color(INK, 0.35), 1, 0.0)
	var qh := box(BONE, 6, BLOOD, 2, 0.2)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", Color(INK, 0.7))
	t.set_color("font_hover_color", "QuietButton", BLOOD)
	t.set_color("font_pressed_color", "QuietButton", BLOOD)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(BONE, 8, INK, 3, 0.45)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", INK)
	_theme = t
	return t


static func label(text: String, size: int = BODY, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, kind: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if kind != "regular":
		l.add_theme_font_override("font", font(kind))
	l.horizontal_alignment = align
	return l


## Заголовок: капитель Cormorant, кость на тёмном с тенью.
static func title(text: String, size: int = H1, color: Color = BONE) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER, "title")
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
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
	ACCENT_FX.sheen(b)
	return b


## Панель цвета старой кости с тёмной каймой и серебряной внутренней линией.
static func panel(pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(BONE, 6, INK, 3, 0.45)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Тёмная полупрозрачная плашка (на столе).
static func dark_panel(pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(COAL, 0.82), 6, Color(SILVER, 0.5), 1, 0.3)
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


static func restyle_chat(chat: Control) -> void:
	chat.ready.connect(func():
		chat.add_theme_stylebox_override("panel", box(BONE, 6, INK, 2, 0.35))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", INK))


## Фон: тёмные обои с дамасским узором, по краям — виньетка.
class Backdrop:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), GLStyle.COAL)
		var line := Color(GLStyle.SILVER, 0.06)
		var step := Vector2(120, 150)
		var row := 0
		var y := -40.0
		while y < size.y + 150:
			var x := -40.0 + (row % 2) * step.x * 0.5
			while x < size.x + 120:
				_damask(Vector2(x, y), line)
				x += step.x
			y += step.y * 0.5
			row += 1
		# полосы обоев
		var sx := 0.0
		while sx < size.x:
			draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(0, 0, 0, 0.18), 2.0)
			sx += step.x * 2.0
		# виньетка
		for i in 14:
			var k := i / 14.0
			var w := 70.0 * (1.0 - k)
			var c := Color(0, 0, 0, 0.05)
			draw_rect(Rect2(0, 0, w, size.y), c)
			draw_rect(Rect2(size.x - w, 0, w, size.y), c)
			draw_rect(Rect2(0, 0, size.x, w), c)
			draw_rect(Rect2(0, size.y - w, size.x, w), c)

	## Мотив дамаска: ромб из завитков и лилия в центре.
	func _damask(p: Vector2, c: Color) -> void:
		for sgn in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for i in 18:
				var t := i / 17.0
				pts.append(p + Vector2(sgn * sin(t * PI) * 26.0, -40.0 + t * 80.0))
			draw_polyline(pts, c, 2.0, true)
			draw_arc(p + Vector2(sgn * 16, -22), 7, 0, TAU, 14, c, 2.0, true)
			draw_arc(p + Vector2(sgn * 16, 22), 7, 0, TAU, 14, c, 2.0, true)
		draw_line(p + Vector2(0, -16), p + Vector2(0, 16), c, 2.0, true)
		draw_arc(p, 5, 0, TAU, 12, c, 2.0, true)
