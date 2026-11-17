class_name IBSStyle
extends RefCounted
## Стиль «В общих чертах»: калька на чертёжном столе. Светлая тема — миллиметровка и полупрозрачные
## листы кальки на малярном скотче, графитовые штрихи; тёмная — синька (белые линии на синем).
## Дизайн-система: бумага/сетка (фон, листы) + чертёжный синий (главное действие, выбранный
## инструмент); красный карандаш — только сдача и ошибки. Заголовки — Neucha (пометки от руки),
## текст — Nunito. Три размера: H1, BODY, CAP.

const ART := "res://games/in_broad_strokes/art/"
const H1 := 28
const BODY := 17
const CAP := 14

const LIGHT := {
	"bg": Color("edf0ea"),
	"grid": Color("d7e0dc"),
	"grid_major": Color("c3d1cc"),
	"panel": Color("fbfcf8"),
	"panel_edge": Color("b9c6c1"),
	"sheet": Color(1, 1, 1, 0.72),
	"sheet_edge": Color("9fb2ad"),
	"tape": Color(0.95, 0.85, 0.5, 0.85),
	"stroke": Color("23272a"),
	"ink": Color("23302e"),
	"muted": Color("5c6e6a"),
	"accent": Color("2d6cb3"),
	"accent_ink": Color("f4f8ff"),
	"red": Color("b83b30"),
	"shadow": Color(0.1, 0.2, 0.2, 0.18),
}

const DARK := {
	"bg": Color("16396a"),
	"grid": Color("1d4579"),
	"grid_major": Color("28568f"),
	"panel": Color("1b3f72"),
	"panel_edge": Color("4f7ab4"),
	"sheet": Color(0.78, 0.88, 1.0, 0.10),
	"sheet_edge": Color(0.85, 0.92, 1.0, 0.7),
	"tape": Color(0.85, 0.92, 1.0, 0.35),
	"stroke": Color("f3f8ff"),
	"ink": Color("eef5ff"),
	"muted": Color("a6bfe0"),
	"accent": Color("ffd166"),
	"accent_ink": Color("1a2c45"),
	"red": Color("ff8a7a"),
	"shadow": Color(0, 0.05, 0.15, 0.4),
}

static var _fonts := {}


static func dark() -> bool:
	return Prefs.dark_theme()


static func c(key: String) -> Color:
	return (DARK if dark() else LIGHT)[key]


## "title" — Neucha; "regular"/"bold" — Nunito.
static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var path := ART + ("fonts/Neucha-Regular.ttf" if kind == "title" else "fonts/Nunito-Variable.ttf")
		var file: FontFile = load(path)
		var variation := FontVariation.new()
		variation.base_font = file
		if kind != "title":
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			variation.variation_opentype = {wght: 500 if kind == "regular" else 800}
		_fonts[kind] = variation
	return _fonts[kind]


## Панель-планшет: бумага с тонкой кромкой, мягкая тень.
static func panel(pad: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c("panel")
	box.border_color = Color(c("panel_edge"), 0.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.shadow_color = c("shadow")
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 3)
	box.set_content_margin_all(pad)
	return box


## Кнопки: "primary" — чертёжный синий (днём) / жёлтый (синька); "secondary" — бумага;
## "tool" — инструмент (выбранный — заливка акцентом); "danger" — тихая красная (сдача, удержанием);
## "quiet" — без подложки.
static func button_box(kind: String, state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(6)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	match kind:
		"primary":
			box.bg_color = c("accent")
			box.shadow_color = c("shadow")
			box.shadow_size = 4
			box.shadow_offset = Vector2(0, 2)
		"secondary", "tool":
			box.bg_color = c("panel")
			box.border_color = c("panel_edge")
			box.set_border_width_all(1)
		"danger":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color(c("red"), 0.6)
			box.set_border_width_all(1)
			box.set_border_width_all(1)
		_:
			box.bg_color = Color(0, 0, 0, 0)
	match state:
		"hover":
			box.bg_color = box.bg_color.lightened(0.08) if kind in ["primary", "secondary", "tool"] else Color(c("ink"), 0.07)
		"pressed":
			box.bg_color = c("accent") if kind == "tool" else box.bg_color.darkened(0.1)
			box.shadow_size = 0
		"disabled":
			box.bg_color = Color(box.bg_color, box.bg_color.a * 0.45)
			box.border_color = Color(box.border_color, 0.3)
			box.shadow_size = 0
	return box


static func style_button(button: Button, kind: String = "secondary", size: int = BODY) -> Button:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_box(kind, state))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := c("accent_ink") if kind == "primary" else (c("red") if kind == "danger" else (c("muted") if kind == "quiet" else c("ink")))
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_pressed_color", c("accent_ink") if kind in ["tool", "primary"] else ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.45))
	button.add_theme_font_override("font", font("bold"))
	button.add_theme_font_size_override("font_size", size)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


static func label(text: String, size: int = BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", font(kind))
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", c(color_key))
	return lb


static func heading(text: String, size: int = H1, color_key: String = "ink") -> Label:
	return label(text, size, "title", color_key)


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("regular")
	theme.default_font_size = BODY
	for cls in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit"]:
		theme.set_color("font_color", cls, c("ink"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", button_box("secondary", state))
	var field := StyleBoxFlat.new()
	field.bg_color = c("panel")
	field.border_color = c("panel_edge")
	field.set_border_width_all(1)
	field.border_width_bottom = 2
	field.set_corner_radius_all(6)
	field.set_content_margin_all(10)
	theme.set_stylebox("normal", "LineEdit", field)
	var focus := field.duplicate()
	focus.border_color = c("accent")
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("panel", "PanelContainer", panel())
	return theme


## Миллиметровка: мелкая сетка 16 px и крупная 80 px.
static func draw_backdrop(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, c("bg"))
	var x := 0.0
	while x < rect.size.x:
		ci.draw_line(Vector2(x, 0), Vector2(x, rect.size.y), c("grid_major") if int(x) % 80 == 0 else c("grid"), 1)
		x += 16.0
	var y := 0.0
	while y < rect.size.y:
		ci.draw_line(Vector2(0, y), Vector2(rect.size.x, y), c("grid_major") if int(y) % 80 == 0 else c("grid"), 1)
		y += 16.0


## Лист кальки: полупрозрачный, тонкая кромка, полоски скотча по верхним углам.
static func draw_sheet(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(Rect2(rect.position + Vector2(0, 4), rect.size), c("shadow"))
	ci.draw_rect(rect, c("sheet"))
	ci.draw_rect(rect, c("sheet_edge"), false, 1.5)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y)]:
		ci.draw_set_transform(corner, deg_to_rad(-35.0 if corner == rect.position else 35.0))
		ci.draw_rect(Rect2(-22, -8, 44, 16), c("tape"))
		ci.draw_set_transform(Vector2.ZERO)


## Пары цветов для проверки интерфейса.
static func contrast_pairs() -> Array:
	return [
		[c("ink"), c("panel"), "текст панели", false],
		[c("muted"), c("bg"), "подпись на фоне", false],
		[c("accent_ink"), c("accent"), "главная кнопка", false],
		[c("red"), c("panel"), "сдача", false],
	]
