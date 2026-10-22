class_name TTStyle
extends RefCounted
## Стиль «Тип Топ» — как у коробки и карт: фон с лучами (бирюзовый / чёрный у версии «Для взрослых»),
## белые «пузыри» с толстой обводкой, жирный округлый шрифт, шкала «какашка → единорог».

const ART := "res://games/tip_top/art/"
const INK := Color("1b1b1f")
const WHITE := Color("ffffff")
const YELLOW := Color("ffd23f")

## Дизайн-система (docs/styleboard_tip_top.png): бирюза (18+: графит) и жёлтый — акцент/CTA;
## белые карточки, чёрный текст и контур; зелёный/красный — только концы шкалы темы, розовый — только 18+.
## Текст — 3 размера:
const H1 := 28
const BODY := 17
const CAP := 14

static var adult := false
static var _fonts := {}
static var _theme: Theme
static var _theme_adult: Theme


static func bg() -> Color:
	return Color("111114") if adult else Color("2f7f86")


static func bg2() -> Color:
	return Color("2a2a30") if adult else Color("4fa3a8")


## Цвет «от …» (первая крайность) и «до …» (вторая).
static func lo_color() -> Color:
	return Color("27b5d8") if adult else Color("2fae4f")


static func hi_color() -> Color:
	return Color("ec3f9c") if adult else Color("e8452c")


static func accent() -> Color:
	return Color("ec3f9c") if adult else Color("ffd23f")


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var f: FontFile = load(ART + ("fonts/RubikMonoOne-Regular.ttf" if kind == "title" else "fonts/Nunito-Variable.ttf"))
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = f
		if kind != "title":
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			fv.variation_opentype = {wght: {"regular": 600, "bold": 850}[kind]}
		_fonts[kind] = fv
	return _fonts[kind]


static func box(color: Color, radius: int = 14, border: Color = INK, border_w: int = 4, shadow: float = 0.3) -> StyleBoxFlat:
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
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if adult and _theme_adult:
		return _theme_adult
	if not adult and _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 16
	t.set_font("normal_font", "RichTextLabel", font("regular"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", WHITE)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("bold"))
		t.set_stylebox("normal", cls, box(WHITE, 12, INK, 3, 0.35))
		t.set_stylebox("hover", cls, box(accent().lightened(0.55), 12, INK, 3, 0.35))
		var p := box(accent(), 12, INK, 3, 0.0)
		t.set_stylebox("pressed", cls, p)
		t.set_stylebox("disabled", cls, box(Color(1, 1, 1, 0.45), 12, Color(INK, 0.4), 3, 0.0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			t.set_color(c, cls, INK)
		t.set_color("font_disabled_color", cls, Color(INK, 0.45))
	t.set_stylebox("normal", "LineEdit", box(WHITE, 12, INK, 3, 0.0))
	t.set_stylebox("focus", "LineEdit", box(WHITE, 12, accent(), 4, 0.0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	t.set_color("caret_color", "LineEdit", INK)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", WHITE)
	t.set_color("font_hover_color", "CheckBox", YELLOW)
	t.set_color("font_pressed_color", "CheckBox", WHITE)
	t.set_color("font_hover_pressed_color", "CheckBox", YELLOW)
	t.set_stylebox("panel", "TooltipPanel", box(WHITE, 8, INK, 2, 0.0))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("panel", "PopupMenu", box(WHITE, 8, INK, 2, 0.0))
	t.set_color("font_color", "PopupMenu", INK)
	var scroll := box(Color(0, 0, 0, 0.15), 4, INK, 0, 0.0)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(WHITE, 4, INK, 0, 0.0))
	t.set_stylebox("slider", "HSlider", box(WHITE, 4, INK, 2, 0.0))
	t.set_stylebox("grabber_area", "HSlider", box(accent(), 4, INK, 0, 0.0))
	if adult:
		_theme_adult = t
	else:
		_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(accent(), 12, INK, 3, 0.35)
	sel.content_margin_left = maxf(sel.content_margin_left, 12)
	sel.content_margin_right = maxf(sel.content_margin_right, 12)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", INK)
	# опасное/второстепенное действие (выход из партии): приглушено, при наведении — красным
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(1, 1, 1, 0.55), 12, Color(INK, 0.4), 3, 0.0)
	var qh := box(WHITE, 12, Color("e0393e"), 3, 0.2)
	for sb in [qn, qh]:
		sb.content_margin_left = maxf(sb.content_margin_left, 12)
		sb.content_margin_right = maxf(sb.content_margin_right, 12)
		sb.content_margin_top = maxf(sb.content_margin_top, 6)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 6)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", Color(INK, 0.6))
	t.set_color("font_hover_color", "QuietButton", Color("e0393e"))
	t.set_color("font_pressed_color", "QuietButton", Color("e0393e"))
	# окно подтверждения (LeaveGuard)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(WHITE, 16, INK, 4, 0.35)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
	t.set_color("font_color", "ConfirmPanel", INK)
	return t


static func label(text: String, size: int = BODY, color: Color = WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, weight: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != "regular":
		l.add_theme_font_override("font", font(weight))
	l.horizontal_alignment = align
	return l


## Заголовок как на коробке: белые буквы с толстой чёрной обводкой.
static func title(text: String, size: int = H1) -> Label:
	var l := label(text, size, WHITE, HORIZONTAL_ALIGNMENT_CENTER, "title")
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
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


## Главная кнопка — жёлтая (розовая у «Для взрослых»).
static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.add_theme_stylebox_override("normal", box(accent(), 12, INK, 3, 0.35))
	b.add_theme_stylebox_override("hover", box(accent().lightened(0.2), 12, INK, 3, 0.35))
	b.add_theme_font_override("font", font("title"))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, INK if not adult else WHITE)
	return b


## «Пузырь»: белая плашка с толстой обводкой (как на картах).
static func bubble(pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(WHITE, 16, INK, 4, 0.35)
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


static var _tex := {}


## Текстура с кэшем: держим ссылку, иначе при рисовании в _draw она освобождается до вывода на экран.
static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(ART + name + ".png")
	return _tex[name]


## Тема с цветными крайностями: «вопрос от НИЗ до ВЕРХ» (BBCode).
static func theme_bbcode(t: Array) -> String:
	return "%s [color=#%s]от %s[/color] до [color=#%s]%s[/color]." % [str(t[0]).to_upper(), lo_color().to_html(false), str(t[1]).to_upper(), hi_color().to_html(false), str(t[2]).to_upper()]


## Фон с лучами, как на коробке.
class Rays:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TTStyle.bg())
		var c := size * Vector2(0.5, 0.42)
		var r := size.length()
		var n := 36
		var rot := Time.get_ticks_msec() / 1000.0 * 0.02
		for i in n:
			if i % 2 == 1:
				continue
			var a0 := rot + TAU * i / n
			var a1 := rot + TAU * (i + 1) / n
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), Color(TTStyle.bg2(), 0.35))
		# виньетка
		for k in 6:
			var w := 60.0 + k * 30.0
			draw_rect(Rect2(Vector2.ZERO, size).grow(-k * 8.0), Color(0, 0, 0, 0.05), false, w * 0.1)


## Шкала «какашка → единорог» (градиент, как на коробке).
class Gauge:
	extends Control

	func _draw() -> void:
		var r := Rect2(Vector2(28, size.y * 0.3), Vector2(size.x - 56, size.y * 0.4))
		var cols := [Color("b5652f"), Color("e8452c"), Color("f7a531"), Color("ffd23f"), Color("8fd14f"), Color("4fc3e8"), Color("ec3f9c")]
		var n := 40
		for i in n:
			var t := float(i) / n
			var k := t * (cols.size() - 1)
			var col: Color = (cols[int(k)] as Color).lerp(cols[mini(int(k) + 1, cols.size() - 1)], k - int(k))
			draw_rect(Rect2(r.position + Vector2(r.size.x * t, 0), Vector2(r.size.x / n + 1, r.size.y)), col)
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = TTStyle.INK
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, r.grow(2))
		var p := TTStyle.tex("token_poop")
		var u := TTStyle.tex("token_unicorn")
		draw_texture_rect(p, Rect2(Vector2(0, size.y / 2.0 - 22), Vector2(44, 44)), false)
		draw_texture_rect(u, Rect2(Vector2(size.x - 44, size.y / 2.0 - 22), Vector2(44, 44)), false)
