class_name HCStyle
extends RefCounted
## Современный спокойный стиль «Оттенков и подсказок»: светлый тёплый фон, мягкие тени, крупные скругления,
## приглушённые графит / шалфей / пыльно-синий. Всё яркое — только на самом поле.

## Дизайн-система (docs/styleboard_calm.png, тёмная — docs/styleboard_calm_dark.png): шалфей — акцент/CTA,
## сумерки — второй цвет, глина — только провал/ошибки/часы; 3 размера текста — H1, BODY, CAP.
## Палитра переключается (Prefs: тема светлая / тёмная / как в системе) — set_dark().
const H1 := 30
const BODY := 16
const CAP := 13
const INK_ART := Color("2e3035")  # тёмный текст на самих игровых предметах (карточки, клетки) — не меняется с темой

const LIGHT := {
	"BG": Color("f4f1eb"), "SURFACE": Color(1, 1, 1, 0.94), "SURFACE_2": Color("ece7df"), "LINE": Color("e0dacf"),
	"CARD": Color.WHITE, "CARD_HI": Color("faf8f4"), "INK": Color("2e3035"), "MUTED": Color("6e7179"),
	"SAGE": Color("5e8d7d"), "DUSK": Color("6b82b3"), "CLAY": Color("c8664f"), "ON_ACCENT": Color.WHITE,
	"SHADOW": Color(0.18, 0.15, 0.1, 0.10),
}
const DARK := {
	"BG": Color("1c1e22"), "SURFACE": Color(0.153, 0.165, 0.188, 0.96), "SURFACE_2": Color("31353d"), "LINE": Color("3a3e46"),
	"CARD": Color("2b2e35"), "CARD_HI": Color("30343b"), "INK": Color("ece8e1"), "MUTED": Color("a3a7b0"),
	"SAGE": Color("7fb3a1"), "DUSK": Color("93a8d8"), "CLAY": Color("e38b73"), "ON_ACCENT": Color("1c1e22"),
	"SHADOW": Color(0, 0, 0, 0.35),
}

static var dark := false
static var BG: Color = LIGHT["BG"]
static var SURFACE: Color = LIGHT["SURFACE"]
static var SURFACE_2: Color = LIGHT["SURFACE_2"]
static var LINE: Color = LIGHT["LINE"]
static var CARD: Color = LIGHT["CARD"]
static var CARD_HI: Color = LIGHT["CARD_HI"]
static var INK: Color = LIGHT["INK"]
static var MUTED: Color = LIGHT["MUTED"]
static var SAGE: Color = LIGHT["SAGE"]
static var DUSK: Color = LIGHT["DUSK"]
static var CLAY: Color = LIGHT["CLAY"]
static var ON_ACCENT: Color = LIGHT["ON_ACCENT"]
static var SHADOW: Color = LIGHT["SHADOW"]


## Включить тёмную/светлую палитру (тема пересобирается при следующем theme()).
static func set_dark(on: bool) -> void:
	dark = on
	var pal: Dictionary = DARK if on else LIGHT
	BG = pal["BG"]
	SURFACE = pal["SURFACE"]
	SURFACE_2 = pal["SURFACE_2"]
	LINE = pal["LINE"]
	CARD = pal["CARD"]
	CARD_HI = pal["CARD_HI"]
	INK = pal["INK"]
	MUTED = pal["MUTED"]
	SAGE = pal["SAGE"]
	DUSK = pal["DUSK"]
	CLAY = pal["CLAY"]
	ON_ACCENT = pal["ON_ACCENT"]
	SHADOW = pal["SHADOW"]
	_theme = null


## Синхронизировать с настройкой игрока; true — палитра поменялась.
static func sync_prefs() -> bool:
	var want: bool = Prefs.dark_theme()
	if want == dark and _theme != null:
		return false
	set_dark(want)
	return true

const FONT := "res://games/hues_and_cues/art/fonts/Manrope-Variable.ttf"
const MUSIC := [
	"res://games/hues_and_cues/audio/calm_piano_vaporware.mp3",
	"res://games/hues_and_cues/audio/another_august.mp3",
	"res://games/hues_and_cues/audio/jrpg_piano.mp3",
]

static var _fonts := {}
static var _theme: Theme


static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var f: FontFile = load(FONT)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		f.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = f
		var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
		fv.variation_opentype = {wght: {"regular": 480, "medium": 600, "bold": 750, "title": 800}[kind]}
		if kind == "title":
			fv.spacing_glyph = -1
		_fonts[kind] = fv
	return _fonts[kind]


static func box(color: Color, radius: int = 14, border: Color = Color.TRANSPARENT, border_w: int = 0, shadow: Color = Color.TRANSPARENT, shadow_size: int = 14) -> StyleBoxFlat:
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
		sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
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
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Label", INK)
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("medium"))
		var n := box(CARD, 12, LINE, 1, SHADOW, 6)
		n.content_margin_top = 8
		n.content_margin_bottom = 8
		t.set_stylebox("normal", cls, n)
		var h := box(CARD_HI, 12, SAGE, 1, Color(SAGE, 0.18), 8)
		h.content_margin_top = 8
		h.content_margin_bottom = 8
		t.set_stylebox("hover", cls, h)
		var p := box(SURFACE_2, 12, SAGE, 1)
		p.content_margin_top = 8
		p.content_margin_bottom = 8
		t.set_stylebox("pressed", cls, p)
		var d := box(Color(CARD, 0.45), 12, Color(LINE, 0.6), 1)
		d.content_margin_top = 8
		d.content_margin_bottom = 8
		t.set_stylebox("disabled", cls, d)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, INK)
		t.set_color("font_hover_color", cls, SAGE.darkened(0.2))
		t.set_color("font_pressed_color", cls, SAGE.darkened(0.3))
		t.set_color("font_disabled_color", cls, Color(MUTED, 0.7))
	t.set_stylebox("normal", "LineEdit", box(CARD, 12, LINE, 1))
	t.set_stylebox("focus", "LineEdit", box(CARD, 12, SAGE, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", SAGE)
	t.set_color("selection_color", "LineEdit", Color(SAGE, 0.25))
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", SAGE)
	t.set_color("font_pressed_color", "CheckBox", INK)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	t.set_stylebox("panel", "PopupMenu", box(CARD, 10, LINE, 1, SHADOW))
	t.set_stylebox("hover", "PopupMenu", box(SURFACE_2, 8))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", SAGE)
	t.set_stylebox("panel", "TooltipPanel", box(INK, 8))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	var scroll := box(Color(INK, 0.06), 4)
	scroll.set_content_margin_all(2)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(Color(INK, 0.25), 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(SAGE, 4))
	t.set_stylebox("slider", "HSlider", box(SURFACE_2, 4))
	t.set_stylebox("grabber_area", "HSlider", box(SAGE, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(SAGE.darkened(0.1), 4))
	_theme = t
	# выбранный вариант в ряду переключателей (UISel.pick): заливка акцентом
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(SAGE, 12)
	sel.content_margin_left = maxf(sel.content_margin_left, 12)
	sel.content_margin_right = maxf(sel.content_margin_right, 12)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", ON_ACCENT)
	# опасное/второстепенное действие (выход из партии): приглушено, при наведении — красным
	t.set_type_variation("QuietButton", "Button")
	var qn := box(Color(CARD, 0.5), 12, LINE, 1)
	var qh := box(SURFACE, 12, CLAY, 1)
	for sb in [qn, qh]:
		sb.content_margin_left = maxf(sb.content_margin_left, 12)
		sb.content_margin_right = maxf(sb.content_margin_right, 12)
		sb.content_margin_top = maxf(sb.content_margin_top, 6)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, 6)
	t.set_stylebox("normal", "QuietButton", qn)
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", MUTED)
	t.set_color("font_hover_color", "QuietButton", CLAY)
	t.set_color("font_pressed_color", "QuietButton", CLAY)
	# окно подтверждения (LeaveGuard)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(SURFACE, 20, LINE, 1, SHADOW, 18)
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


static func title(text: String, size: int = H1, color: Color = INK) -> Label:
	return label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER, "title")


## Мелкая подпись капсом с разрядкой — «надзаголовок» секции.
static func caption(text: String, color: Color = MUTED) -> Label:
	var l := label(text.to_upper(), CAP, color, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	var fv := FontVariation.new()
	fv.base_font = font("bold")
	fv.spacing_glyph = 2
	l.add_theme_font_override("font", fv)
	return l


static func button(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Sfx.play("click", -8))
	return b


## Главная кнопка: заливка шалфеем, белый текст.
static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	for st in [["normal", SAGE], ["hover", SAGE.lightened(0.08)], ["pressed", SAGE.darkened(0.12)], ["disabled", Color(SAGE, 0.35)]]:
		var sb := box(st[1], 12, Color.TRANSPARENT, 0, Color(SAGE, 0.25) if st[0] != "disabled" else Color.TRANSPARENT, 8)
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		b.add_theme_stylebox_override(st[0], sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, ON_ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(ON_ACCENT, 0.8))
	b.add_theme_font_override("font", font("bold"))
	return b


static func panel(padding: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(SURFACE, 20, Color(LINE, 0.7), 1, SHADOW, 18)
	sb.set_content_margin_all(padding)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Цветной кружок-фишка (для списков игроков).
static func dot(color: Color, d: int = 16) -> Control:
	var c := Dot.new()
	c.color = color
	c.custom_minimum_size = Vector2(d, d)
	return c


## Квадратик цвета с поля.
static func swatch(color: Color, s: int = 40, radius: int = 8) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(s, s)
	p.add_theme_stylebox_override("panel", box(color, radius, Color(1, 1, 1, 0.9), 2, SHADOW, 6))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Логотип — полоска из нескольких цветов поля.
static func logo_strip(cells: Array, s: int = 22) -> HBoxContainer:
	var row := hbox(5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in cells:
		row.add_child(swatch(HCData.color(c), s, 6))
	return row


## Цвет фишки = цвет игрока (кружок у ника, его можно сменить); без партии — запасная палитра.
static func piece_color(seat: int) -> Color:
	var pl: Array = Net.view.get("players", []) if Net.view.get("game", "") in ["", "hues_and_cues"] else []
	if seat >= 0 and seat < pl.size() and pl[seat].has("color"):
		return Net.color_of(int(pl[seat]["color"]))
	return Color(HCData.PIECE_COLORS[seat % HCData.PIECE_COLORS.size()])


## Чат из общего кода — перекрашиваем под светлую тему.
static func restyle_chat(chat: Control) -> void:
	chat.ready.connect(func():
		chat.add_theme_stylebox_override("panel", box(SURFACE, 14, LINE, 1, SHADOW, 12))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", INK))


class Dot:
	extends Control
	var color := Color.WHITE

	func _draw() -> void:
		var r := size.x * 0.5
		draw_circle(Vector2(r, r + 1), r, Color(0, 0, 0, 0.12))
		draw_circle(Vector2(r, r), r, Color("cfc8bc"))
		draw_circle(Vector2(r, r), r - 1, Color.WHITE)
		draw_circle(Vector2(r, r), r - 2, color)


## Тонкая разделительная линия.
static func separator() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = LINE
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	return sep


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


## Мазок кисти (для заголовков Hues and Cues): неровная полоса с переливом цветов и сухим краем.
class BrushStroke:
	extends Control
	var colors: Array = [Color("e4572e"), Color("f3c64a"), Color("4aa96c"), Color("3d7dd8"), Color("a05cc8")]
	var seed := 7

	func _init(w: float = 360.0, h: float = 16.0) -> void:
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var n := 48
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var cols := PackedColorArray()
		for i in n + 1:
			var t := float(i) / n
			var x := t * size.x
			var taper := sin(t * PI) * 0.75 + 0.25  # кисть тоньше к концам
			var half := size.y * 0.5 * taper * (0.85 + rng.randf() * 0.3)
			var y := size.y * 0.5 + sin(t * 5.0) * size.y * 0.12
			top.append(Vector2(x, y - half))
			bottom.append(Vector2(x, y + half))
		for i in n:
			var t := float(i) / n
			var k := t * (colors.size() - 1)
			var c: Color = (colors[int(k)] as Color).lerp(colors[mini(int(k) + 1, colors.size() - 1)], k - int(k))
			c.a = 0.85
			draw_colored_polygon(PackedVector2Array([top[i], top[i + 1], bottom[i + 1], bottom[i]]), c)
		# сухие штрихи щетины
		for j in 6:
			var yy := size.y * (0.25 + 0.1 * j)
			var x0 := rng.randf_range(0.0, size.x * 0.3)
			var x1 := rng.randf_range(size.x * 0.7, size.x)
			draw_line(Vector2(x0, yy), Vector2(x1, yy + rng.randf_range(-1.5, 1.5)), Color(1, 1, 1, 0.18), 1.0, true)
