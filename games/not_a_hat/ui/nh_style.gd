class_name NHStyle
extends RefCounted
## Стиль «Это не шляпа!»: ярко-розовый фон с белыми каракулями, белые карточки с чёрными
## рисунками от руки, рубашки — розовые со стрелкой. Шрифт — Balsamiq Sans (OFL).
## Дизайн-система: 2 цвета — розовый (фон, рубашки) и чёрные чернила; белый — карточки и панели;
## жёлтый — только акцент/главная кнопка. Текст — 3 размера: H1, BODY, CAP.

const PINK := Color("e5007e")
const PINK_DARK := Color("b8005f")
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

const ART := "res://games/not_a_hat/art/"
const MUSIC := [
	"res://games/not_a_hat/audio/quirky_jazz.mp3",
	"res://games/not_a_hat/audio/catch_me.mp3",
]
const CARD := Vector2(92, 118)

static var _fonts := {}
static var _theme: Theme
static var _icons := {}


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var f: FontFile = load(ART + "fonts/" + ("BalsamiqSans-Bold.ttf" if kind != "regular" else "BalsamiqSans-Regular.ttf"))
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		_fonts[kind] = f
	return _fonts[kind]


static func icon(g: int) -> Texture2D:
	var id := NHData.gift_icon(g)
	if id == "":
		return null
	if not _icons.has(id):
		_icons[id] = load(ART + "gifts/" + id + ".svg")
	return _icons[id]


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


## Фон: розовый с белыми каракулями (подарки, стрелки, спирали), как на коробке.
class Backdrop:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), NHStyle.PINK)
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		var c := Color(1, 1, 1, 0.13)
		var step := 150.0
		var y := 40.0
		var row := 0
		while y < size.y + 60:
			var x := 30.0 + (row % 2) * step * 0.5
			while x < size.x + 60:
				var p := Vector2(x + rng.randf_range(-20, 20), y + rng.randf_range(-20, 20))
				match rng.randi() % 5:
					0:  # стрелка
						var a := rng.randf_range(-0.6, 0.6)
						var d := Vector2(cos(a), sin(a)) * 40
						draw_line(p - d, p + d, c, 3.0, true)
						draw_line(p + d, p + d - d.rotated(0.5) * 0.35, c, 3.0, true)
						draw_line(p + d, p + d - d.rotated(-0.5) * 0.35, c, 3.0, true)
					1:  # подарок
						draw_rect(Rect2(p - Vector2(18, 14), Vector2(36, 28)), c, false, 3.0)
						draw_line(p + Vector2(0, -14), p + Vector2(0, 14), c, 3.0)
						draw_arc(p + Vector2(-7, -18), 7, 0, TAU, 12, c, 3.0, true)
						draw_arc(p + Vector2(7, -18), 7, 0, TAU, 12, c, 3.0, true)
					2:  # спираль
						var pts := PackedVector2Array()
						for i in 30:
							var t := i * 0.35
							pts.append(p + Vector2(cos(t), sin(t)) * (3 + t * 3.0))
						draw_polyline(pts, c, 3.0, true)
					3:  # звёздочка
						for k in 4:
							var a2 := k * PI / 4.0
							draw_line(p - Vector2(cos(a2), sin(a2)) * 12, p + Vector2(cos(a2), sin(a2)) * 12, c, 3.0, true)
					_:  # волна
						var pts2 := PackedVector2Array()
						for i in 12:
							pts2.append(p + Vector2(i * 6 - 33, sin(i * 0.9) * 7))
						draw_polyline(pts2, c, 3.0, true)
				x += step
			y += step * 0.75
			row += 1
