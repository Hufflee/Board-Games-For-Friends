class_name BRStyle
extends RefCounted

const ACCENT_FX := preload("res://hub/ui_accent_fx.gd")
## Стиль «Большой бродилки»: деревянная настолка — рамки из досок, пергаментные окна и карты,
## мультяшные фишки (как на поле в art/src). Дизайн-система: 2 цвета — дерево (панели, рамки)
## и пергамент (окна, карты, текст на дереве); зелёный — главная кнопка и «мой ход», красный — опасность.
## Текст — 3 размера: H1, BODY, CAP.

const WOOD := Color("6b4426")
const WOOD_2 := Color("8a5a32")
const WOOD_DARK := Color("3f2715")
const PARCH := Color("f3e6c4")
const PARCH_DIM := Color("dccb9f")
const INK := Color("3b2614")
const MUTED := Color("7a6248")
const GREEN := Color("7cc24a")
const GREEN_DARK := Color("4f8a2a")
const RED := Color("e0653a")
const GOLD := Color("f2c03a")
const H1 := 30
const BODY := 17
const CAP := 14

const ART := "res://games/brodilka/art/"
const MUSIC := [
	"res://games/brodilka/audio/happy_adventure.mp3",
	"res://games/brodilka/audio/flowerbed_fields.ogg",
]
## Цвета фишек — по одежде персонажей с листа Тадам.
const PAWNS := [Color("3d8fd0"), Color("d23a2a"), Color("f0a028"), Color("6cc04a"), Color("e8c020"), Color("27407a"), Color("2fb8b0"), Color("c8285e")]
## Фишки-персонажи: art/cards/pawn_0..7.png (бородач, рыжая, пёс, близняшки, копейщик — из мода; енот, путешественница, лисица — ComfyUI).
const PAWN_COUNT := 8

static var _fonts := {}
static var _theme: Theme
static var _theme_dark := false  # тема собрана для тёмного режима — сменили режим, собираем заново


## Тёмная тема: дерево темнее, пергамент приглушён (без белых плашек).
static func dark() -> bool:
	return Prefs.dark_theme()


## Тёмная тема — пергамент заметно темнее (как в сумерках), текст остаётся тёмным и читаемым.
static func parch() -> Color:
	return Color("b39e72") if dark() else PARCH


static func parch_dim() -> Color:
	return Color("9c875e") if dark() else PARCH_DIM


static func parch_hover() -> Color:
	return Color("c2ad80") if dark() else Color("f8eed4")


## Текст — Oswald (узкий, как на картах), заголовки — Rubik ExtraBold (как надпись на коробке). Оба OFL.
static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var file := "Rubik-Variable.ttf" if kind == "title" else "Oswald-Variable.ttf"
		var weight: int = {"regular": 420, "bold": 600, "title": 800}.get(kind, 420)
		var base: FontFile = load(ART + "fonts/" + file)
		var sym := SystemFont.new()
		sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		base.fallbacks = [sym]
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {"wght": weight}
		_fonts[kind] = fv
	return _fonts[kind]


static func box(color: Color, radius: int = 8, border: Color = WOOD, border_w: int = 3, shadow: float = 0.3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0.0:
		sb.shadow_color = Color(0.15, 0.08, 0.02, shadow)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme and _theme_dark == dark():
		return _theme
	_theme_dark = dark()
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = BODY
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	for cls in ["Button", "OptionButton"]:
		t.set_font("font", cls, font("bold"))
		t.set_stylebox("normal", cls, box(parch(), 8, WOOD, 3, 0.3))
		t.set_stylebox("hover", cls, box(parch_hover(), 8, WOOD_2, 3, 0.35))
		var p := box(parch_dim(), 8, WOOD, 3, 0.0)
		p.content_margin_top = 10
		p.content_margin_bottom = 6
		t.set_stylebox("pressed", cls, p)
		t.set_stylebox("disabled", cls, box(Color(parch(), 0.5), 8, Color(WOOD, 0.4), 3, 0.0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, cls, INK)
		t.set_color("font_disabled_color", cls, Color(INK, 0.45))
	var field := Color("c9b588") if dark() else Color("fbf3dc")
	t.set_stylebox("normal", "LineEdit", box(field, 6, WOOD, 2, 0.0))
	t.set_stylebox("focus", "LineEdit", box(field, 6, GREEN_DARK, 2, 0.0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", GREEN_DARK)
	t.set_stylebox("panel", "TooltipPanel", box(WOOD_DARK, 6, WOOD_2, 2, 0.0))
	t.set_color("font_color", "TooltipLabel", PARCH)
	t.set_stylebox("panel", "PopupMenu", box(parch(), 6, WOOD, 2, 0.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.1), 4, WOOD, 0, 0.0))
	t.set_stylebox("grabber", "VScrollBar", box(WOOD_2, 4, WOOD, 0, 0.0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(WOOD, 4, WOOD, 0, 0.0))
	# главная кнопка и выбранный вариант (UISel.pick) — зелёная, как зелёная клетка
	t.set_type_variation("SelectedButton", "Button")
	var sel := box(GREEN, 8, GREEN_DARK, 3, 0.35)
	t.set_stylebox("normal", "SelectedButton", sel)
	t.set_stylebox("hover", "SelectedButton", box(Color("8fd25c"), 8, GREEN_DARK, 3, 0.4))
	t.set_stylebox("pressed", "SelectedButton", sel)
	t.set_stylebox("disabled", "SelectedButton", sel)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		t.set_color(c, "SelectedButton", INK)
	# тихая кнопка (выход) и окно подтверждения (LeaveGuard)
	t.set_type_variation("QuietButton", "Button")
	var qh := box(parch(), 8, RED, 2, 0.2)
	t.set_stylebox("normal", "QuietButton", box(Color(parch(), 0.55), 8, Color(WOOD, 0.4), 2, 0.0))
	t.set_stylebox("hover", "QuietButton", qh)
	t.set_stylebox("pressed", "QuietButton", qh)
	t.set_color("font_color", "QuietButton", Color(INK, 0.7))
	t.set_color("font_hover_color", "QuietButton", RED)
	t.set_color("font_pressed_color", "QuietButton", RED)
	t.set_type_variation("ConfirmPanel", "PanelContainer")
	var cp := box(parch(), 10, WOOD, 6, 0.45)
	cp.set_content_margin_all(26)
	t.set_stylebox("panel", "ConfirmPanel", cp)
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


## Заголовок: пергамент на дереве с тёмной обводкой.
static func title(text: String, size: int = H1, color: Color = PARCH) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER, "title")
	l.add_theme_color_override("font_outline_color", WOOD_DARK)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
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
			Sfx.play("hover", -14, 0.1, 0.05))
	return b


static func primary(text: String, size: int = BODY, min_w: int = 0) -> Button:
	var b := button(text, size, min_w)
	b.theme_type_variation = "SelectedButton"
	ACCENT_FX.sheen(b)
	return b


## Пергаментное окно в деревянной рамке.
static func panel(pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(parch(), 10, WOOD, 6, 0.4)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Деревянная плашка (панель игроков, журнал) — текст на ней пергаментный.
static func wood_panel(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(WOOD_DARK if dark() else WOOD, 8, WOOD_DARK, 2, 0.35)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Карта Лавки без жёлтой каймы-«солнышка» с листа мода: только сама карта в коричневой рамке.
static func shop_card_tex(path: String) -> Texture2D:
	var src: Texture2D = load(path)
	if src == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = src
	var sz := src.get_size()
	at.region = Rect2(sz.x * 0.054, sz.y * 0.041, sz.x * (1.0 - 0.108), sz.y * (1.0 - 0.079))
	return at


static func pawn_tex(i: int) -> Texture2D:
	return load(ART + "cards/pawn_%d.png" % (i % PAWN_COUNT))


## Карта по id картинки (gb_0_1, tadam_3, shop_hook, *_back).
static func card_tex(id: String) -> Texture2D:
	return load(ART + "cards/" + id + ".webp")


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
		chat.add_theme_stylebox_override("panel", box(parch(), 8, WOOD, 3, 0.35))
		for n in chat.find_children("*", "RichTextLabel", true, false):
			(n as RichTextLabel).add_theme_color_override("default_color", INK))


## Монета: золотой кружок с числом (иконка ресурса во всей игре).
static func coin_label(n: int, size: int = BODY) -> HBoxContainer:
	var h := hbox(4)
	var c := Coin.new()
	c.custom_minimum_size = Vector2(size, size)
	h.add_child(c)
	h.add_child(label(str(n), size, INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	return h


class Coin:
	extends Control

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c + Vector2(0, 1.5), r, Color(0.3, 0.18, 0.05, 0.35))
		draw_circle(c, r, BRStyle.GOLD)
		draw_arc(c, r * 0.68, 0, TAU, 20, Color("c8901c"), 1.5, true)


## Фон: доски стола — горизонтальные планки с прожилками, светлее сверху (свет сверху).
class Backdrop:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var dark := BRStyle.dark()
		var base := BRStyle.WOOD_DARK if dark else BRStyle.WOOD
		draw_rect(Rect2(Vector2.ZERO, size), base)
		var h := 72.0
		var y := 0.0
		var i := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		while y < size.y:
			var tone := base.lightened(0.04 * (i % 3)) if not dark else base.darkened(0.06 * (i % 3))
			draw_rect(Rect2(0, y, size.x, h - 3), tone)
			draw_rect(Rect2(0, y + h - 3, size.x, 3), Color(0, 0, 0, 0.28))
			draw_rect(Rect2(0, y, size.x, 2), Color(1, 1, 1, 0.05))
			for k in 5:
				var gy := y + rng.randf_range(10, h - 12)
				var x0 := rng.randf_range(-100, size.x)
				draw_line(Vector2(x0, gy), Vector2(x0 + rng.randf_range(120, 420), gy + rng.randf_range(-3, 3)), Color(0, 0, 0, 0.08), 2.0)
			# стыки досок
			var jx := rng.randf_range(0, size.x)
			draw_rect(Rect2(jx, y, 3, h - 3), Color(0, 0, 0, 0.22))
			y += h
			i += 1
		for k in 10:
			var t := k / 10.0
			draw_rect(Rect2(0, size.y * t, size.x, size.y / 10.0 + 1), Color(0, 0, 0, 0.025 * k))
