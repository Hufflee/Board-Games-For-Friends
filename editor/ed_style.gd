extends "res://games/custom/ui/cg_style.gd"
## Стиль оболочки редактора «Неоновый портал» (решение владельца 12.11, стайлборд
## docs/styleboard_editor_dimension_portal_v3.png): глубокий фиолетовый фон с дождём символов, стеклянные
## панели с неоновой кромкой, Exo 2 SemiBold/Bold, заголовки Rubik Mono One.
## Наследует стиль игр (cg_style.gd) и подменяет только оболочку: внутри CGStyle всё остаётся как в игре,
## поэтому предпросмотры стола и карт (ed_canvas, ed_card_canvas…) рисуются стилем игры.

const EXO := preload("res://editor/fonts/Exo2-Variable.ttf")
const MONO := preload("res://editor/fonts/base/rubikmono/font.ttf")
const GLYPHS := "01ΔΣЖЯλΩ#%&@∑∆≈◇□▲ФШЮ7342ΞΨ"

static var _semibold: FontVariation
static var _bold: FontVariation

static func _weight(value: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = EXO
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): value}
	return font

static func body_font() -> Font:
	if _semibold == null:
		_semibold = _weight(600)
	return _semibold

static func bold_font() -> Font:
	if _bold == null:
		_bold = _weight(700)
	return _bold

static func head_font() -> Font:
	return MONO

## ---------- Палитра. Тёмная — «Неоновый портал»; светлая — то же измерение днём (лаванда, те же неоны).
static func dark() -> bool:
	return Prefs.dark_theme()

static func bg() -> Color:
	return Color("0b0720") if dark() else Color("ece6fb")

static func bg_far() -> Color:
	return Color("1d0b3a") if dark() else Color("d9cff5")

static func panel() -> Color:
	return Color("1a1036") if dark() else Color("f7f3ff")

static func ink() -> Color:
	return Color("efe6ff") if dark() else Color("221637")

static func accent() -> Color:
	return Color("3ff0ff") if dark() else Color("0f8fa6")

## Второй неон — кромки, второстепенные подсветки.
static func accent2() -> Color:
	return Color("ff3fd0") if dark() else Color("c2189a")

## Текст на акцентной заливке.
static func on_accent() -> Color:
	return Color("140c24") if dark() else Color("ffffff")

static func rain_colors() -> Array:
	return [Color("ff3fd0"), Color("3ff0ff"), Color("8a5bff")] if dark() else [Color("c2189a"), Color("0f8fa6"), Color("6a3fd6")]

## ---------- Коробки: стекло с неоновой кромкой и мягким свечением.
static func box(color: Color, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, minf(color.a, 0.84))
	style.set_corner_radius_all(12)
	style.border_color = Color(accent2(), 0.32)
	style.set_border_width_all(1)
	style.shadow_color = Color(accent2(), 0.10 if dark() else 0.08)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style

## Активное (выбранная вкладка, выбранный элемент): кромка акцентом и свечение.
static func glow_box(color: Color, padding: int = 12) -> StyleBoxFlat:
	var style := box(color, padding)
	style.border_color = accent()
	style.set_border_width_all(2)
	style.shadow_color = Color(accent(), 0.35)
	style.shadow_size = 12
	return style

static func field_box() -> StyleBoxFlat:
	var style := box(Color(bg(), 0.72), 8)
	style.set_corner_radius_all(8)
	style.border_color = Color(accent(), 0.35)
	style.shadow_size = 0
	return style

## ---------- Виджеты.
static func label(text: String, size: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", body_font())
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", ink())
	return item

## Заголовки разделов — Rubik Mono акцентом (как «БЛОКИ», «СВОЙСТВА»), крупные — светлым текстом.
static func heading(text: String, size: int = 24) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", head_font())
	item.add_theme_font_size_override("font_size", 15 if size <= 24 else 20)
	item.add_theme_color_override("font_color", accent() if size <= 24 else ink())
	return item

static func button(text: String, size: int = 16) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 40
	item.add_theme_font_override("font", bold_font())
	item.add_theme_font_size_override("font_size", size)
	_style_plain(item)
	return item

static func _style_plain(item: Button) -> void:
	var normal := box(Color(panel(), 0.62), 12)
	normal.set_corner_radius_all(10)
	normal.border_color = Color(accent2(), 0.5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = accent()
	hover.shadow_color = Color(accent(), 0.25)
	hover.shadow_size = 8
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(panel(), 0.9).lerp(accent(), 0.18)
	pressed.border_color = accent()
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(panel(), 0.35)
	disabled.border_color = Color(accent2(), 0.18)
	disabled.shadow_size = 0
	var focus := normal.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = accent()
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	for pair: Array in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["disabled", disabled], ["focus", focus]]:
		item.add_theme_stylebox_override(pair[0], pair[1])
	for mode in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(mode, ink())
	item.add_theme_color_override("font_disabled_color", Color(ink(), 0.4))

static func primary(text: String, size: int = 16) -> Button:
	var item := button(text, size)
	var normal := box(accent(), 16)
	normal.set_corner_radius_all(10)
	normal.border_color = accent().lightened(0.3)
	normal.shadow_color = Color(accent(), 0.45)
	normal.shadow_size = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent().lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent().darkened(0.12)
	for pair: Array in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed]]:
		item.add_theme_stylebox_override(pair[0], pair[1])
	for mode in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(mode, on_accent())
	return item

## Тема оболочки: стекло, поля с неоновой кромкой, Exo 2.
static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = body_font()
	result.default_font_size = 16
	for state: String in ["font_color", "font_focus_color"]:
		result.set_color(state, "LinkButton", ink())
	for state: String in ["font_hover_color", "font_pressed_color"]:
		result.set_color(state, "LinkButton", accent())
	var probe := Button.new()
	_style_plain(probe)
	for type: String in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			result.set_stylebox(state, type, probe.get_theme_stylebox(state))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			result.set_color(state, type, ink())
		result.set_color("font_disabled_color", type, Color(ink(), 0.4))
		result.set_font("font", type, bold_font())
	probe.free()
	for state: String in ["normal", "focus", "read_only"]:
		result.set_stylebox(state, "LineEdit", field_box())
		result.set_stylebox(state, "TextEdit", field_box())
	for type: String in ["LineEdit", "TextEdit"]:
		for state: String in ["font_color", "caret_color"]:
			result.set_color(state, type, ink())
		result.set_color("font_placeholder_color", type, Color(ink(), 0.45))
		result.set_color("selection_color", type, Color(accent(), 0.35))
	result.set_color("font_readonly_color", "TextEdit", Color(ink(), 0.7))
	var popup := box(Color(panel(), 0.97), 8)
	result.set_stylebox("panel", "PopupMenu", popup)
	result.set_stylebox("hover", "PopupMenu", box(Color(accent(), 0.25), 6))
	result.set_color("font_color", "PopupMenu", ink())
	result.set_color("font_hover_color", "PopupMenu", ink())
	result.set_color("font_color", "Label", ink())
	result.set_font("font", "Label", body_font())
	result.set_color("font_color", "TooltipLabel", ink())
	result.set_stylebox("panel", "TooltipPanel", box(Color(panel(), 0.97), 8))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(accent(), 0.55)
	grabber.set_corner_radius_all(4)
	for bar: String in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(bg(), 0.4)
		track.set_corner_radius_all(4)
		track.set_content_margin_all(3)
		result.set_stylebox("scroll", bar, track)
		result.set_stylebox("grabber", bar, grabber)
		result.set_stylebox("grabber_highlight", bar, grabber)
		result.set_stylebox("grabber_pressed", bar, grabber)
	return result

## Окно редактора: тот же фон измерения, что у оболочки.
static func window_surface(window: Window) -> void:
	var background := Backdrop.new()
	background.name = "EditorWindowSurface"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(background)

## Фон «другого измерения»: градиент, тонкая сетка и дождь символов (не зелёный).
## Градиент и сетка — отдельный слой, рисуется один раз (и при смене размера/темы); дождь двигается
## каждый кадр плавно, символ привязан к своей капле (не мигает), новый набор — когда колонка начинается заново.
class Backdrop extends Control:
	var _columns: Array = []
	var _random := RandomNumberGenerator.new()
	var _style: GDScript
	var _font: Font
	var _tones: Array = []
	var _strength := 0.5
	var _base: Control
	func _ready() -> void:
		_random.seed = 7
		_style = load("res://editor/ed_style.gd")
		_base = Control.new()
		_base.name = "BackdropBase"
		_base.mouse_filter = MOUSE_FILTER_IGNORE
		_base.show_behind_parent = true
		_base.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_base.draw.connect(_draw_base)
		add_child(_base)
		resized.connect(_seed)
		_seed()
	func _seed() -> void:
		_columns.clear()
		for column in int(ceilf(maxf(size.x, 1280) / 20.0)):
			_columns.append({"head": _random.randf_range(-200, maxf(size.y, 720)), "speed": _random.randf_range(18, 46), "length": _random.randi_range(5, 16), "salt": _random.randi()})
		refresh()
	## Цвета темы и шрифт — один раз на смену темы, не в каждом кадре.
	func refresh() -> void:
		_font = _style.body_font()
		_tones = _style.rain_colors()
		_strength = 0.5 if _style.dark() else 0.35
		if is_instance_valid(_base):
			_base.queue_redraw()
		queue_redraw()
	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		for column: Dictionary in _columns:
			column.head += float(column.speed) * delta
			if float(column.head) - int(column.length) * 18 > size.y:
				column.head = _random.randf_range(-260, -20)
				column.salt = _random.randi()
		queue_redraw()
	func _draw_base() -> void:
		var top: Color = _style.bg()
		var bottom: Color = _style.bg_far()
		var y := 0.0
		while y < size.y:
			_base.draw_rect(Rect2(0, y, size.x, 8.0), top.lerp(bottom, y / maxf(size.y, 1)))
			y += 8.0
		var line := Color(_style.accent(), 0.035 if _style.dark() else 0.06)
		var x := 0.0
		while x < size.x:
			_base.draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1)
			x += 40
		y = 0.0
		while y < size.y:
			_base.draw_line(Vector2(0, y), Vector2(size.x, y), line, 1)
			y += 40
	func _draw() -> void:
		if _font == null or _tones.is_empty():
			return
		for index in _columns.size():
			var column: Dictionary = _columns[index]
			var tone: Color = _tones[index % _tones.size()]
			var length := int(column.length)
			for k in length:
				var at: float = float(column.head) - k * 18
				if at < -10 or at > size.y + 10:
					continue
				var alpha: float = (1.0 - float(k) / length) * (_strength if k == 0 else _strength * 0.4)
				var glyph := GLYPHS[posmod(int(column.salt) + k * 7, GLYPHS.length())]
				draw_string(_font, Vector2(index * 20 + 4, at), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(tone, alpha))
