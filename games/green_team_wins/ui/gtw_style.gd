class_name GTWStyle
extends RefCounted
## Стиль Green Team Wins: яркая пати-викторина в духе карт — бирюзовый фон с «мемфис»-узором
## (треугольники, зигзаги, кружки), белые плашки с толстой тёмной обводкой, как у карт.
## Цвет закреплён за смыслом: зелёный — зелёная команда и главное действие, оранжевый — оранжевая
## команда. Тёмная тема — ночная бирюза. Заголовки — Seymour One, текст — Balsamiq Sans.
## Три размера: H1, BODY, CAP.

const ART := "res://games/green_team_wins/art/"
const H1 := 24
const BODY := 18
const CAP := 14

const LIGHT := {
	"bg": Color("5ccfdf"),
	"pattern": Color("49bccd"),
	"panel": Color("fffdf6"),
	"outline": Color("23313a"),
	"inset": Color("eaf6f3"),
	"ink": Color("23313a"),
	"muted": Color("5d6f74"),
	"green": Color("7cc242"),
	"green_ink": Color("16300a"),
	"orange": Color("f2902c"),
	"orange_ink": Color("3a1d02"),
	"neutral": Color("c9d3d3"),
	"shadow": Color("23313a"),
}

const DARK := {
	"bg": Color("0f2a31"),
	"pattern": Color("143640"),
	"panel": Color("1c3b44"),
	"outline": Color("0a1a1f"),
	"inset": Color("173239"),
	"ink": Color("eef8f3"),
	"muted": Color("9fb9b7"),
	"green": Color("8fd654"),
	"green_ink": Color("102506"),
	"orange": Color("f7a043"),
	"orange_ink": Color("2e1601"),
	"neutral": Color("3d585e"),
	"shadow": Color("06141a"),
}

static var _fonts := {}


static func dark() -> bool:
	return Prefs.dark_theme()


static func c(key: String) -> Color:
	return (DARK if dark() else LIGHT)[key]


## "title" — Seymour One; "regular"/"bold" — Balsamiq Sans.
static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var path: String = ART + {"title": "fonts/SeymourOne-Regular.ttf", "regular": "fonts/BalsamiqSans-Regular.ttf", "bold": "fonts/BalsamiqSans-Bold.ttf"}[kind]
		var file: FontFile = load(path)
		var symbols := SystemFont.new()
		symbols.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial"])
		file.fallbacks = [symbols]
		_fonts[kind] = file
	return _fonts[kind]


## Плашка «как карта»: светлая, толстая тёмная обводка, жёсткая тень-смещение (мультяшно).
static func panel(pad: int = 16, fill_key: String = "panel") -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c(fill_key)
	box.border_color = c("outline")
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.shadow_color = Color(c("shadow"), 0.9 if not dark() else 0.6)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, 5)
	box.set_content_margin_all(pad)
	return box


## Кнопки: "primary" — зелёная (одна на экран), "secondary" — белая плашка, "option" — вариант
## ответа (выбранный — зелёная заливка), "quiet" — без подложки.
static func button_box(kind: String, state: String) -> StyleBoxFlat:
	var box := panel(10)
	box.set_corner_radius_all(12)
	box.content_margin_left = 16
	box.content_margin_right = 16
	match kind:
		"primary":
			box.bg_color = c("green")
		"quiet":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = Color(0, 0, 0, 0)
			box.shadow_offset = Vector2.ZERO
	match state:
		"hover":
			box.bg_color = box.bg_color.lightened(0.1) if kind != "quiet" else Color(c("ink"), 0.08)
			box.shadow_offset = Vector2(0, 6) if kind != "quiet" else Vector2.ZERO
		"pressed":
			box.bg_color = c("green") if kind == "option" else box.bg_color.darkened(0.1)
			box.shadow_offset = Vector2(0, 1) if kind != "option" else Vector2(0, 5)
		"disabled":
			box.bg_color = Color(box.bg_color, 0.5)
			box.border_color = Color(box.border_color, 0.35)
			box.shadow_offset = Vector2.ZERO
	return box


static func style_button(button: Button, kind: String = "secondary", size: int = BODY) -> Button:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_box(kind, state))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := c("green_ink") if kind == "primary" else (c("muted") if kind == "quiet" else c("ink"))
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_pressed_color", c("green_ink") if kind in ["option", "primary"] else ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.45))
	# главная кнопка — тоже Balsamiq: широкий Seymour One на кнопке читается «сплюснутым» (владелец, 14.11)
	button.add_theme_font_override("font", font("bold"))
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
	theme.set_stylebox("panel", "PanelContainer", panel())
	return theme


## Фон-«мемфис» как на рубашках карт: треугольники, зигзаги и кружки тоном темнее фона.
static func draw_backdrop(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, c("bg"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var col := c("pattern")
	var step := 72.0
	var y := 0.0
	while y < rect.size.y + step:
		var x := fmod(y * 0.37, step) - step
		while x < rect.size.x + step:
			var p := Vector2(x + rng.randf_range(-14, 14), y + rng.randf_range(-14, 14))
			match rng.randi() % 3:
				0:
					var a := rng.randf() * TAU
					var r := rng.randf_range(10, 18)
					ci.draw_colored_polygon(PackedVector2Array([p + Vector2(cos(a), sin(a)) * r, p + Vector2(cos(a + 2.1), sin(a + 2.1)) * r, p + Vector2(cos(a + 4.2), sin(a + 4.2)) * r]), col)
				1:
					var pts := PackedVector2Array()
					for k in 5:
						pts.append(p + Vector2(k * 7.0, -6.0 if k % 2 == 0 else 6.0))
					ci.draw_polyline(pts, col, 4, true)
				_:
					ci.draw_circle(p, rng.randf_range(5, 9), col)
			x += step
		y += step
