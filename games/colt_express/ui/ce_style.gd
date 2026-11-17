class_name CEStyle
extends RefCounted
## Стиль «Кольт Экспресс»: вестерн-плакат «Разыскивается».
## Светлая тема — выгоревшая бумага афиши и дневная пустыня; тёмная — ночной поезд под луной.
## Дизайн-система: бумага афиши (панели, карты) + дерево (поезд, рамки); красный — только главное
## действие и «ваш ход», латунь — выделение (текущий шаг раунда, выбранное). Заголовки — узкий
## плакатный Oswald прописными, текст — Bitter. Три размера: H1, BODY, CAP.

const ART := "res://games/colt_express/art/"
const H1 := 26
const BODY := 17
const CAP := 14

const LIGHT := {
	"bg": Color("eadab3"),
	"plank": Color("e1cda2"),
	"panel": Color("f6ecd3"),
	"panel_edge": Color("b99363"),
	"inset": Color("eadcbc"),
	"ink": Color("3a2416"),
	"muted": Color("6b5236"),
	"accent": Color("b2382b"),
	"accent_ink": Color("fbf1dc"),
	"brass": Color("c48a2c"),
	"sky_top": Color("f6e2b6"),
	"sky_bottom": Color("ecbf82"),
	"far": Color("e2ad73"),
	"near": Color("cd8d58"),
	"ground": Color("b97a4b"),
	"wood": Color("8a5a36"),
	"wood_light": Color("a8734a"),
	"wood_dark": Color("4f3220"),
	"window": Color("f3dca6"),
	"rail": Color("4d3424"),
	"shadow": Color(0.23, 0.13, 0.06, 0.22),
}

const DARK := {
	"bg": Color("1c1a22"),
	"plank": Color("211e28"),
	"panel": Color("2b2631"),
	"panel_edge": Color("54443a"),
	"inset": Color("231f29"),
	"ink": Color("f0e2c3"),
	"muted": Color("a8987f"),
	"accent": Color("cf4a39"),
	"accent_ink": Color("fff3dc"),
	"brass": Color("e2ac4a"),
	"sky_top": Color("10152a"),
	"sky_bottom": Color("2e2947"),
	"far": Color("2b2640"),
	"near": Color("231d33"),
	"ground": Color("1e1826"),
	"wood": Color("5e3d29"),
	"wood_light": Color("78502f"),
	"wood_dark": Color("2e1d14"),
	"window": Color("ffcd6a"),
	"rail": Color("17121b"),
	"shadow": Color(0, 0, 0, 0.35),
}

static var _fonts := {}
static var _tex := {}


static func dark() -> bool:
	return Prefs.dark_theme()


## Цвет из палитры текущей темы.
static func c(key: String) -> Color:
	return (DARK if dark() else LIGHT)[key]


## Шрифты: "title" — плакатный Oswald, "regular"/"bold" — Bitter.
static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var path := ART + ("fonts/Oswald-Variable.ttf" if kind == "title" else "fonts/Bitter-Variable.ttf")
		var file: FontFile = load(path)
		var symbols := SystemFont.new()
		symbols.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		file.fallbacks = [symbols]
		var variation := FontVariation.new()
		variation.base_font = file
		var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
		var weight: int = {"title": 650, "regular": 450, "bold": 700}[kind]
		variation.variation_opentype = {wght: weight}
		_fonts[kind] = variation
	return _fonts[kind]


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(ART + name) if ResourceLoader.exists(ART + name) else null
	return _tex[name]


## Панель-афиша: бумага, полупрозрачная кромка в тон, мягкая тень снизу.
static func poster(pad: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c("panel")
	box.border_color = c("panel_edge")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.shadow_color = c("shadow")
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	box.set_content_margin_all(pad)
	return box


## Вдавленная подложка (очередь карт, поле ввода).
static func inset(pad: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c("inset")
	box.set_corner_radius_all(6)
	box.border_color = c("shadow")
	box.border_width_top = 2
	box.set_content_margin_all(pad)
	return box


## Кнопки: "primary" — красная плакатная (одна на экран), "secondary" — бумага с латунной
## кромкой, "quiet" — без подложки (выход и второстепенное).
static func button_box(kind: String, state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(6)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	match kind:
		"primary":
			box.bg_color = c("accent")
			box.border_color = c("accent").darkened(0.3)
			box.border_width_bottom = 3
			box.shadow_color = c("shadow")
			box.shadow_size = 4
			box.shadow_offset = Vector2(0, 2)
		"secondary":
			box.bg_color = c("panel")
			box.border_color = Color(c("brass"), 0.7)
			box.set_border_width_all(2)
			box.border_width_bottom = 3
		_:
			box.bg_color = Color(c("ink"), 0.0)
	match state:
		"hover":
			box.bg_color = box.bg_color.lightened(0.08) if kind != "quiet" else Color(c("ink"), 0.08)
		"pressed":
			box.bg_color = box.bg_color.darkened(0.12) if kind != "quiet" else Color(c("ink"), 0.14)
			box.border_width_bottom = mini(box.border_width_bottom, 1)
			box.shadow_size = 0
		"disabled":
			box.bg_color = Color(box.bg_color, box.bg_color.a * 0.45)
			box.border_color = Color(box.border_color, 0.25)
			box.shadow_size = 0
	return box


static func style_button(button: Button, kind: String = "secondary", size: int = BODY) -> Button:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := button_box(kind, "normal" if state == "focus" else state)
		if state == "focus":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color(c("brass"), 0.8)
			box.set_border_width_all(2)
			box.shadow_size = 0
		button.add_theme_stylebox_override(state, box)
	var ink := c("accent_ink") if kind == "primary" else (c("muted") if kind == "quiet" else c("ink"))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.45))
	button.add_theme_font_override("font", font("title" if kind == "primary" else "bold"))
	button.add_theme_font_size_override("font_size", size + (2 if kind == "primary" else 0))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


static func label(text: String, size: int = BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", font(kind))
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", c(color_key))
	return lb


## Заголовок-афиша: прописные, разрядка, плакатный шрифт.
static func heading(text: String, size: int = H1, color_key: String = "ink") -> Label:
	var lb := label(text.to_upper(), size, "title", color_key)
	return lb


## Тема экрана: шрифты и цвета по умолчанию для всего, что собрано без явных стилей.
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("regular")
	theme.default_font_size = BODY
	for cls in ["Label", "Button", "CheckButton", "OptionButton", "RichTextLabel"]:
		theme.set_color("font_color", cls, c("ink"))
	theme.set_color("default_color", "RichTextLabel", c("ink"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", button_box("secondary", state))
		theme.set_stylebox(state, "OptionButton", button_box("secondary", state))
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", poster())
	return theme


# --- Рисование сцены поезда --------------------------------------------------

## Скорость пейзажа во время показа действий, px/с (ближний план; дальние слои медленнее).
## Подобрана так, чтобы при показе действий подряд казалось, что поезд мчится (владелец, 14.11).
const SCROLL_SPEED := 720.0

## Фон поезда: небо, солнце/луна со звёздами, две гряды столовых гор, кактусы и столбы, земля и шпалы.
## scroll — пройденный путь в px: слои сдвигаются с параллаксом и бесшовно повторяются.
static func draw_scenery(ci: CanvasItem, rect: Rect2, horizon: float, rail: float, scroll: float = 0.0) -> void:
	var top := c("sky_top")
	var bottom := c("sky_bottom")
	var bands := 24
	for i in bands:
		var y0 := rect.position.y + rect.size.y * i / bands
		var col := top.lerp(bottom, float(i) / (bands - 1))
		ci.draw_rect(Rect2(rect.position.x, y0, rect.size.x, rect.size.y / bands + 1), col)
	var x0 := rect.position.x
	var w := rect.size.x
	if dark():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 60:
			var p := Vector2(x0 + fposmod(rng.randf() * w + scroll * 0.02, w), rect.position.y + rng.randf() * (horizon - rect.position.y))
			ci.draw_circle(p, rng.randf_range(0.6, 1.6), Color(1, 0.96, 0.85, rng.randf_range(0.3, 0.9)))
		var moon := Vector2(x0 + w * 0.82, rect.position.y + 52)
		ci.draw_circle(moon, 40, Color(1, 0.93, 0.7, 0.08))
		ci.draw_circle(moon, 26, Color("f2e6c2"))
		ci.draw_circle(moon + Vector2(9, -5), 22, Color("f2e6c2").lerp(top, 0.9))
	else:
		var sun := Vector2(x0 + w * 0.8, rect.position.y + 58)
		ci.draw_circle(sun, 48, Color(1, 0.95, 0.75, 0.25))
		ci.draw_circle(sun, 30, Color("fbe7b2"))
	# дальняя гряда — медленно, ближняя — быстрее (параллакс); концы профиля на одной высоте — шов не виден
	var far := [Vector2(0.0, -20), Vector2(0.06, -30), Vector2(0.10, -74), Vector2(0.22, -74), Vector2(0.26, -36),
		Vector2(0.48, -30), Vector2(0.52, -58), Vector2(0.60, -58), Vector2(0.64, -26), Vector2(1.0, -20)]
	var near := [Vector2(0.0, 6), Vector2(0.30, -6), Vector2(0.34, -40), Vector2(0.42, -40), Vector2(0.45, 0),
		Vector2(0.76, -4), Vector2(0.79, -28), Vector2(0.85, -28), Vector2(0.88, 4), Vector2(1.0, 6)]
	_ridge(ci, far, x0, w, horizon, rail, -fposmod(scroll * 0.12, w), c("far"))
	_ridge(ci, near, x0, w, horizon, rail, -fposmod(scroll * 0.35, w), c("near"))
	ci.draw_rect(Rect2(x0, rail, w, rect.end.y - rail), c("ground"))
	# кактусы на ближнем плане (на уровне горизонта, за поездом) — едут быстрее гор
	var cactus := Color(c("near").darkened(0.25), 0.9)
	var period := 340.0
	var shift := fposmod(scroll * 0.6, period)
	var x := x0 - shift - period
	while x < rect.end.x + period:
		_cactus(ci, Vector2(x + 90, horizon + 14), cactus)
		x += period
	# телеграфные столбы и шпалы — скорость поезда
	var pole := Color(c("rail"), 0.7)
	var pole_period := 420.0
	x = x0 - fposmod(scroll, pole_period) - pole_period
	while x < rect.end.x + pole_period:
		ci.draw_line(Vector2(x + 200, rail), Vector2(x + 200, horizon - 40), pole, 3)
		ci.draw_line(Vector2(x + 190, horizon - 34), Vector2(x + 210, horizon - 34), pole, 2)
		x += pole_period
	var tie := Color(c("rail"), 0.55)
	x = x0 - fposmod(scroll, 26.0)
	while x < rect.end.x:
		ci.draw_rect(Rect2(x, rail + 2, 14, 6), tie)
		x += 26.0
	ci.draw_line(Vector2(x0, rail + 2), Vector2(rect.end.x, rail + 2), c("rail"), 4)


static func _ridge(ci: CanvasItem, profile: Array, x0: float, w: float, horizon: float, rail: float, offset: float, col: Color) -> void:
	for copy in 2:
		var pts := PackedVector2Array()
		for p: Vector2 in profile:
			pts.append(Vector2(x0 + offset + copy * w + p.x * w, horizon + p.y))
		pts.append(Vector2(x0 + offset + copy * w + w, rail))
		pts.append(Vector2(x0 + offset + copy * w, rail))
		ci.draw_colored_polygon(pts, col)


static func _cactus(ci: CanvasItem, base: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(base.x - 4, base.y - 34, 8, 34), col)
	ci.draw_rect(Rect2(base.x - 14, base.y - 22, 6, 12), col)
	ci.draw_rect(Rect2(base.x - 14, base.y - 14, 12, 5), col)
	ci.draw_rect(Rect2(base.x + 8, base.y - 28, 6, 14), col)
	ci.draw_rect(Rect2(base.x + 2, base.y - 18, 12, 5), col)


## Вагон из досок: крыша с бортиком, окна (ночью светятся), лесенка, колёса.
## engine — паровоз. cx — центр, w — ширина, roof/rail — верх крыши и уровень рельса.
static func draw_wagon(ci: CanvasItem, cx: float, roof: float, rail: float, w: float, engine: bool) -> void:
	var left := cx - w / 2.0
	var body_top := roof + 6.0
	var body_bottom := rail - 16.0
	var wood := c("wood")
	var light := c("wood_light")
	var edge := c("wood_dark")
	ci.draw_rect(Rect2(left + 4, body_bottom + 2, w - 8, 4), Color(0, 0, 0, 0.25))
	if engine:
		# паровоз смотрит по ходу поезда (вправо): будка — к вагонам (слева), котёл, труба и
		# скотосбрасыватель — впереди (справа)
		var cab := Rect2(left + w * 0.04, body_top, w * 0.38, body_bottom - body_top)
		ci.draw_rect(cab, wood)
		ci.draw_rect(Rect2(cab.position.x + 6, cab.position.y + 8, cab.size.x - 12, 18), c("window"))
		ci.draw_rect(Rect2(cab.position.x - 4, body_top - 4, cab.size.x + 8, 6), edge)
		var boiler := Rect2(left + w * 0.4, body_top + (body_bottom - body_top) * 0.38, w * 0.56, (body_bottom - body_top) * 0.62)
		ci.draw_rect(boiler, Color("3b3330") if not dark() else Color("2a2424"))
		for i in 3:
			ci.draw_line(Vector2(boiler.position.x + boiler.size.x * (0.25 + i * 0.25), boiler.position.y),
				Vector2(boiler.position.x + boiler.size.x * (0.25 + i * 0.25), boiler.end.y), Color("c48a2c", 0.6), 2)
		var stack := Rect2(left + w * 0.78, body_top - 2, w * 0.1, boiler.position.y - body_top + 2)
		ci.draw_rect(stack, Color("2a2424"))
		ci.draw_rect(Rect2(stack.position.x - 4, stack.position.y - 6, stack.size.x + 8, 7), Color("2a2424"))
		var nose := left + w
		ci.draw_colored_polygon(PackedVector2Array([Vector2(nose, body_bottom), Vector2(nose + 12, body_bottom + 8),
			Vector2(nose - 6, body_bottom + 8)]), Color("2a2424"))
	else:
		ci.draw_rect(Rect2(left, body_top, w, body_bottom - body_top), wood)
		var plank := (body_bottom - body_top) / 5.0
		for i in range(1, 5):
			ci.draw_line(Vector2(left, body_top + plank * i), Vector2(left + w, body_top + plank * i), Color(edge, 0.35), 1)
		var win_w := (w - 30) / 3.0
		for i in 3:
			var win := Rect2(left + 8 + i * (win_w + 7), body_top + 10, win_w, (body_bottom - body_top) * 0.36)
			ci.draw_rect(win, c("window") if dark() else Color(c("window"), 0.9))
			ci.draw_rect(win, edge, false, 2)
		ci.draw_rect(Rect2(left - 3, roof, w + 6, 7), edge)
		ci.draw_rect(Rect2(left, body_top, 4, body_bottom - body_top), light)
		ci.draw_rect(Rect2(left + w - 4, body_top, 4, body_bottom - body_top), light)
		for rung in 5:
			var y := body_top + 4 + (body_bottom - body_top - 8) * rung / 4.0
			ci.draw_line(Vector2(left + w + 1, y), Vector2(left + w + 7, y), light, 2)
	ci.draw_rect(Rect2(left, body_bottom, w, 6), edge)
	for off in [0.2, 0.8]:
		var hub := Vector2(left + w * off, rail - 6)
		ci.draw_circle(hub, 9, Color("2a201b"))
		ci.draw_circle(hub, 6, c("wood_light").darkened(0.2))
		ci.draw_circle(hub, 2.5, Color("2a201b"))


## Жетон добычи: мешочек с $, самоцвет или саквояж.
static func draw_loot(ci: CanvasItem, pos: Vector2, kind: String, scale: float = 1.0) -> void:
	var outline := Color(0.15, 0.09, 0.05, 0.9)
	match kind:
		"gem":
			var pts := PackedVector2Array([pos + Vector2(-6, -3) * scale, pos + Vector2(-3, -7) * scale, pos + Vector2(3, -7) * scale,
				pos + Vector2(6, -3) * scale, pos + Vector2(0, 5) * scale])
			ci.draw_colored_polygon(pts, Color("e0566a"))
			pts.append(pts[0])
			ci.draw_polyline(pts, outline, 1.2)
		"case":
			var r := Rect2(pos - Vector2(8, 6) * scale, Vector2(16, 11) * scale)
			ci.draw_rect(r, Color("e2a24c"))
			ci.draw_rect(r, outline, false, 1.2)
			ci.draw_rect(Rect2(pos - Vector2(3, 8) * scale, Vector2(6, 2.5) * scale), outline)
		"whiskey":
			ci.draw_rect(Rect2(pos - Vector2(3.5, 6) * scale, Vector2(7, 11) * scale), Color("b8743a"))
			ci.draw_rect(Rect2(pos - Vector2(1.5, 9) * scale, Vector2(3, 3) * scale), Color("6b4426"))
		_:
			ci.draw_circle(pos, 7 * scale, Color("d9b26a"))
			ci.draw_arc(pos, 7 * scale, 0, TAU, 20, outline, 1.2, true)
			ci.draw_string(font("bold"), pos + Vector2(-3.5, 4.5) * scale, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * scale), Color("5a3a12"))


## Рубашка карты действия (закрытая карта в тоннеле): красная афиша со звездой шерифа.
static func draw_card_back(ci: CanvasItem, rect: Rect2) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color("8f2a22")
	back.border_color = Color("d9a64a")
	back.set_border_width_all(maxi(2, int(rect.size.x / 22)))
	back.set_corner_radius_all(maxi(3, int(rect.size.x / 12)))
	ci.draw_style_box(back, rect)
	var center := rect.get_center()
	var r := rect.size.x * 0.26
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		pts.append(center + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, Color("e2b65a"))


## Пары цветов для проверки интерфейса.
static func contrast_pairs() -> Array:
	return [
		[c("ink"), c("panel"), "текст панели", false],
		[c("muted"), c("bg"), "подпись", false],
	]
