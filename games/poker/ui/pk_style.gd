extends RefCounted
## «Покер»: мини-дизайн-система — неоновый Лас-Вегас. Тёмная фиолетовая комната, сукно с неоновой каймой
## (розовый + голубой), золото — только для главного действия. Шрифты: Russo One — заголовки, Exo 2 — текст.
## Размеры текста: 28 / 16 / 12. Светлая тема — «дневной зал»: сиреневые стены, стол тот же.

const HEAD := preload("res://hub/art/fonts/RussoOne-Regular.ttf")
const FONT := preload("res://hub/art/fonts/Exo2-Variable.ttf")
const PINK := Color("ff3fa4")  # неон: ход, выделение, мой стол
const CYAN := Color("35e0ff")  # неон: вторая трубка, банк, подсветка карт
const GOLD := Color("ffc94d")  # главное действие (рейз/колл), победа
const GOOD := Color("5fe3a1")
const BAD := Color("ff5d6c")
const FELT := Color("3a1866")
const FELT_CENTER := Color("552a8c")
const RAIL := Color("1f0f35")
const CARD_SIZE := Vector2(420, 582)


static func dark() -> bool:
	return Prefs.dark_theme()


## Фон комнаты.
static func page() -> Color:
	return Color("120822") if dark() else Color("e9def7")


## Золотые числа (очки, стек) на панелях: на светлом фоне — темнее, иначе не читаются.
static func gold_ink() -> Color:
	return GOLD if dark() else Color("a8740a")


static func ink() -> Color:
	return Color("f1e9ff") if dark() else Color("2a1840")


static func muted() -> Color:
	return Color("a996c8") if dark() else Color("6d5a8a")


## Панели интерфейса (боковые, ставка, итоги).
static func panel() -> Color:
	return Color("221238") if dark() else Color("f7f1ff")


## Текст на сукне — всегда светлый: стол одинаковый в обеих темах.
static func felt_ink() -> Color:
	return Color("f1e9ff")


static func box(fill: Color = Color.TRANSPARENT, pad: int = 16, radius: int = 14, glow: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = panel() if fill == Color.TRANSPARENT else fill
	b.border_color = b.bg_color.darkened(0.35) if glow == Color.TRANSPARENT else glow
	b.set_border_width_all(1 if glow == Color.TRANSPARENT else 2)
	b.border_width_bottom = 3 if glow == Color.TRANSPARENT else 2
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	b.anti_aliasing_size = 0.75
	if glow != Color.TRANSPARENT:
		b.shadow_color = Color(glow, 0.45)
		b.shadow_size = 10
	else:
		b.shadow_color = Color(0, 0, 0, 0.3 if dark() else 0.14)
		b.shadow_size = 8
		b.shadow_offset = Vector2(0, 3)
	return b


static func weighted(base: Font, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {"wght": weight}
	return f


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = weighted(FONT, 600)
	t.default_font_size = 16
	t.set_color("font_color", "Label", ink())
	t.set_stylebox("panel", "PanelContainer", box())
	var base := Color("2c1748") if dark() else Color("ffffff").lerp(Color("e9def7"), 0.4)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := base.lightened(0.08) if state == "hover" else base.darkened(0.12) if state == "pressed" else base
		t.set_stylebox(state, "Button", box(fill, 10, 10))
		t.set_color("font_" + state + "_color", "Button", muted() if state == "disabled" else ink())
	t.set_color("font_color", "Button", ink())
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# главное действие — золото с неоновым ореолом
	t.set_type_variation("SelectedButton", "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := GOLD.lightened(0.1) if state == "hover" else GOLD.darkened(0.15) if state == "pressed" else GOLD
		if state == "disabled":
			fill = GOLD.darkened(0.45)
		t.set_stylebox(state, "SelectedButton", box(fill, 10, 10, Color(GOLD, 0.0) if state == "disabled" else GOLD.lightened(0.2)))
		t.set_color("font_" + state + "_color", "SelectedButton", Color("2a1406"))
	t.set_color("font_color", "SelectedButton", Color("2a1406"))
	t.set_stylebox("focus", "SelectedButton", StyleBoxEmpty.new())
	# выбранный вариант (лобби) — розовая трубка
	t.set_type_variation("PickedButton", "Button")
	var picked := box(base.lerp(PINK, 0.25), 10, 10, PINK)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "PickedButton", picked)
		t.set_color("font_" + state + "_color", "PickedButton", ink())
	var field := box(Color("140a24") if dark() else Color("fbf8ff"), 8, 8)
	field.border_color = Color(CYAN, 0.5)
	field.set_border_width_all(1)
	field.shadow_size = 0
	t.set_stylebox("normal", "LineEdit", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = CYAN
	focus.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", ink())
	t.set_color("caret_color", "LineEdit", CYAN)
	# ползунок ставки: трубка + розовая ручка
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(CYAN, 0.25)
	groove.set_corner_radius_all(4)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill_area := groove.duplicate() as StyleBoxFlat
	fill_area.bg_color = CYAN
	t.set_stylebox("grabber_area", "HSlider", fill_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_area)
	t.set_icon("grabber", "HSlider", _grabber(PINK))
	t.set_icon("grabber_highlight", "HSlider", _grabber(PINK.lightened(0.2)))
	t.set_color("default_color", "RichTextLabel", ink())
	return t


static func _grabber(color: Color) -> Texture2D:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	for y: int in 22:
		for x: int in 22:
			var d := Vector2(x - 10.5, y - 10.5).length()
			var a := clampf(10.5 - d, 0.0, 1.0)
			var c := color if d < 7.5 else Color.WHITE
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 16, color: Color = Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink() if color == Color.TRANSPARENT else color)
	return l


static func heading(text: String, size: int = 28, color: Color = Color.TRANSPARENT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", HEAD)
	return l


static func section(text: String) -> Label:
	var l := label(text.to_upper(), 12, muted())
	l.add_theme_font_override("font", weighted(FONT, 800))
	return l


static func button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = 40
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func pick(b: Button, on: bool) -> void:
	UISel.pick(b, on)
	if on:
		b.theme_type_variation = "PickedButton"


static func column(gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


static func row(gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func card_texture(id: int) -> Texture2D:
	if id < 0:
		return BACK
	return load("res://games/the_gang/art/cards/%d.webp" % id) as Texture2D


## Своя неоновая рубашка (tools/chips_poker.py).
const BACK := preload("res://games/poker/art/card_back.png")


## Спрайт кучи фишек по размеру в больших блайндах: 1 фишка → столбик → два → россыпь → гора.
static func pile_texture(amount: int, big_blind: int = 2) -> Texture2D:
	var bbs := float(amount) / float(maxi(1, big_blind))
	var index := 0 if bbs <= 1.5 else 1 if bbs <= 5.0 else 2 if bbs <= 15.0 else 3 if bbs <= 45.0 else 4
	return PILES[index]


## Кучи фишек — заранее (загрузка прямо в отрисовке давала белый прямоугольник).
const PILES: Array[Texture2D] = [
	preload("res://games/poker/art/chips/pile_1.png"),
	preload("res://games/poker/art/chips/pile_2.png"),
	preload("res://games/poker/art/chips/pile_3.png"),
	preload("res://games/poker/art/chips/pile_4.png"),
	preload("res://games/poker/art/chips/pile_5.png"),
]


## Неоновая трубка: несколько обводок с убывающей яркостью вокруг эллипса.
static func neon_ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color, width: float = 3.0) -> void:
	var pts := PackedVector2Array()
	for i: int in 97:
		var a := TAU * i / 96.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	for layer: int in [14, 9, 5]:
		canvas.draw_polyline(pts, Color(color, 0.07 + 0.04 * (14 - layer) / 5.0), width + layer, true)
	canvas.draw_polyline(pts, color, width, true)
	canvas.draw_polyline(pts, Color(1, 1, 1, 0.55), maxf(1.0, width * 0.35), true)


## Комната: фон, лучи прожекторов и гирлянда лампочек сверху.
static func paint_backdrop(canvas: CanvasItem, dimensions: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, dimensions), page())
	var glow_a := 0.16 if dark() else 0.10
	for spot: Array in [[Vector2(0.12, 0.2), PINK], [Vector2(0.88, 0.25), CYAN], [Vector2(0.5, 1.05), Color("9b5cff")]]:
		var c: Vector2 = spot[0] * dimensions
		for k: int in 8:
			canvas.draw_circle(c, dimensions.y * (0.55 - k * 0.06), Color(spot[1], glow_a / 8.0))
	# гирлянда: ряд лампочек у верхнего края
	var bulbs := int(dimensions.x / 28.0)
	for i: int in bulbs:
		var p := Vector2(14 + i * 28, 8)
		var on := i % 3 != 0
		canvas.draw_circle(p, 6, Color(GOLD, 0.12 if on else 0.04))
		canvas.draw_circle(p, 2.5, Color(GOLD, 0.8 if on else 0.25))
