class_name FCStyle
extends RefCounted
## Стиль «Первого контакта»: древний папирус и иероглифы у землян, бирюзовый свет корабля
## у инопланетян. Светлая тема — папирус днём, тёмная — ночь в пустыне под звёздами.
## Дизайн-система: папирус/песчаник (поле, панели) + охра (рамки, «мой ход»); бирюза — только
## язык инопланетян (знаки, их подсветка и панель набора). Заголовки — Yeseva One, текст — Exo 2.
## Три размера: H1, BODY, CAP.

const ART := "res://games/first_contact/art/"
## Названия предметов (art/items_cut/item_N.png — картинка без печатных подписей, название рисует игра).
const ITEM_NAMES := ["Ступка", "Плуг", "Кольцо", "Веретено", "Пояс", "Лопата", "Змея", "Кнут", "Миска", "Антилопа",
	"Молоко", "Яблоко", "Коза", "Крестьянин", "Пчела", "Воин", "Овца", "Рыболовный крючок", "Катапульта", "Бусы",
	"Наковальня", "Лодка", "Лист дерева", "Головной убор", "Кокос", "Верёвка", "Кирка", "Кожаный мяч", "Молот", "Женщина",
	"Рубаха", "Топор", "Рыба", "Лев", "Слон", "Череп", "Дыня", "Кошка", "Собака", "Лук",
	"Бык", "Свинья", "Мышь", "Костёр", "Табличка с письменами", "Бобы", "Щит", "Кувшин", "Пальма", "Камень",
	"Огурец", "Мясо", "Хлеб", "Арбуз", "Горох", "Стул", "Виноград", "Копьё", "Жезл", "Труба"]
const H1 := 26
const BODY := 17
const CAP := 14

const LIGHT := {
	"bg": Color("e9d9b0"),
	"fiber": Color("dccb9c"),
	"panel": Color("f4e9cb"),
	"panel_edge": Color("b8975a"),
	"tile": Color("efe1bb"),
	"item_tint": Color("f4e7c4"),
	"ink": Color("3b2a17"),
	"muted": Color("7d6644"),
	"ochre": Color("b5741f"),
	"ochre_ink": Color("fff6e2"),
	"alien": Color("15a99c"),
	"alien_soft": Color(0.08, 0.66, 0.61, 0.18),
	"alien_ink": Color("eafffb"),
	"ship": Color("123c45"),
	"shadow": Color(0.25, 0.16, 0.05, 0.22),
}

const DARK := {
	"bg": Color("15172a"),
	"fiber": Color("1b1e34"),
	"panel": Color("232338"),
	"panel_edge": Color("4a4058"),
	"tile": Color("2d2b40"),
	"item_tint": Color("cfc2a2"),
	"ink": Color("f0e4c8"),
	"muted": Color("a59a86"),
	"ochre": Color("e0a23e"),
	"ochre_ink": Color("2a1b08"),
	"alien": Color("3fe0cf"),
	"alien_soft": Color(0.25, 0.88, 0.81, 0.16),
	"alien_ink": Color("06231f"),
	"ship": Color("0d2a31"),
	"shadow": Color(0, 0, 0, 0.4),
}

static var _fonts := {}
static var _items := {}


## Вырезанная картинка предмета без подписей (кэш: текстуры живут, пока открыта игра).
static func item_texture(id: int) -> Texture2D:
	if not _items.has(id):
		_items[id] = load(ART + "items_cut/item_%d.png" % id)
	return _items[id]


static func dark() -> bool:
	return Prefs.dark_theme()


static func c(key: String) -> Color:
	return (DARK if dark() else LIGHT)[key]


## "title" — Yeseva One; "regular"/"bold" — Exo 2.
static func font(kind: String = "regular") -> Font:
	if not _fonts.has(kind):
		var path := ART + ("fonts/YesevaOne-Regular.ttf" if kind == "title" else "fonts/Exo2-Variable.ttf")
		var file: FontFile = load(path)
		var symbols := SystemFont.new()
		symbols.font_names = PackedStringArray(["Segoe UI Symbol", "Cambria Math", "Segoe UI", "Arial"])
		file.fallbacks = [symbols]
		var variation := FontVariation.new()
		variation.base_font = file
		if kind != "title":
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			variation.variation_opentype = {wght: 450 if kind == "regular" else 700}
		_fonts[kind] = variation
	return _fonts[kind]


## Панель-свиток: папирус с охристой кромкой и мягкой тенью.
static func panel(pad: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c("panel")
	box.border_color = Color(c("panel_edge"), 0.8)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.shadow_color = c("shadow")
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	box.set_content_margin_all(pad)
	return box


## Панель корабля (язык инопланетян): тёмная бирюза со свечением.
static func ship_panel(pad: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = c("ship")
	box.border_color = c("alien")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(c("alien"), 0.35)
	box.shadow_size = 10
	box.set_content_margin_all(pad)
	return box


## Кнопки: "primary" — охра (одна на экран), "secondary" — папирус с кромкой, "alien" — бирюзовый
## знак, "quiet" — без подложки.
static func button_box(kind: String, state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4 if kind != "alien" else 8)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	match kind:
		"primary":
			box.bg_color = c("ochre")
			box.border_color = c("ochre").darkened(0.3)
			box.border_width_bottom = 3
			box.shadow_color = c("shadow")
			box.shadow_size = 4
			box.shadow_offset = Vector2(0, 2)
		"alien":
			box.bg_color = Color(c("alien"), 0.12)
			box.border_color = Color(c("alien"), 0.7)
			box.set_border_width_all(2)
		"secondary":
			box.bg_color = c("panel")
			box.border_color = Color(c("panel_edge"), 0.9)
			box.set_border_width_all(2)
		_:
			box.bg_color = Color(0, 0, 0, 0)
	match state:
		"hover":
			box.bg_color = box.bg_color.lightened(0.08) if kind != "quiet" else Color(c("ink"), 0.08)
			if kind == "alien":
				box.bg_color = Color(c("alien"), 0.28)
		"pressed":
			box.bg_color = c("alien") if kind == "alien" else box.bg_color.darkened(0.12)
			box.border_width_bottom = mini(box.border_width_bottom, 2)
			box.shadow_size = 0
		"disabled":
			box.bg_color = Color(box.bg_color, box.bg_color.a * 0.45)
			box.border_color = Color(box.border_color, 0.25)
			box.shadow_size = 0
	return box


static func style_button(button: Button, kind: String = "secondary", size: int = BODY) -> Button:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_box(kind, state))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := c("ochre_ink") if kind == "primary" else (c("alien") if kind == "alien" else (c("muted") if kind == "quiet" else c("ink")))
	for key in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_pressed_color", c("alien_ink") if kind == "alien" else ink)
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
	for cls in ["Label", "Button", "CheckButton", "OptionButton"]:
		theme.set_color("font_color", cls, c("ink"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", button_box("secondary", state))
	theme.set_stylebox("panel", "PanelContainer", panel())
	return theme


## Фон: волокна папируса (сетка тонких линий) днём; звёзды и пирамиды ночью.
static func draw_backdrop(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, c("bg"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if dark():
		for i in 120:
			var p := Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y * 0.8)
			ci.draw_circle(p, rng.randf_range(0.5, 1.5), Color(1, 0.95, 0.85, rng.randf_range(0.2, 0.7)))
		var base := rect.size.y
		for pyr: Array in [[0.70, 150.0], [0.82, 100.0], [0.93, 70.0]]:
			var x: float = rect.size.x * pyr[0]
			var h: float = pyr[1]
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - h, base), Vector2(x, base - h), Vector2(x + h, base)]), Color("1d1f35"))
		return
	var y := 0.0
	while y < rect.size.y:
		ci.draw_line(Vector2(0, y), Vector2(rect.size.x, y + rng.randf_range(-2, 2)), c("fiber"), rng.randf_range(1, 3))
		y += rng.randf_range(5, 11)
	var x := 0.0
	while x < rect.size.x:
		ci.draw_line(Vector2(x, 0), Vector2(x + rng.randf_range(-2, 2), rect.size.y), Color(c("fiber"), 0.5), rng.randf_range(1, 2))
		x += rng.randf_range(14, 30)
