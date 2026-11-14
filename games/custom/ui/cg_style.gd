class_name CGStyle
extends RefCounted
## Общий 2D-стиль стола и оболочки редактора: шрифты хаба, фиолетовый и бирюзовый.

const HEAD := preload("res://hub/art/fonts/RussoOne-Regular.ttf")
const BODY := preload("res://games/custom/ui/cg_body.tres")
const CardLayers := preload("res://games/custom/ui/cg_card_layers.gd")

## Оформление игры из редактора (meta.look: основной цвет и акцент). Пока задано — стол рисуется в цветах
## автора, а не в теме приложения (у пользовательской игры один вид). Пусто — цвета сборника по теме.
static var _look := {}
## Шрифт заголовков из оформления игры (встроенный набор редактора, ключ builtin:…); null — шрифт сборника.
static var _head: Font = null
## Вид кнопок игры (meta.look.buttons): только внешний вид — заливка, текст, окантовка, скругление, шрифт, тень.
static var _buttons := {}
static var _button_font: Font = null

static func set_game_look(look: Variant) -> void:
	_look = {}
	_head = null
	_buttons = {}
	_button_font = null
	if look is Dictionary and look.get("buttons") is Dictionary:
		_buttons = look.buttons.duplicate()
		if str(_buttons.get("font", "")).begins_with("builtin:"):
			_button_font = load("res://editor/ed_fonts.gd").font(str(_buttons.font))
	if look is Dictionary and str(look.get("font", "")).begins_with("builtin:"):
		_head = load("res://editor/ed_fonts.gd").font(str(look.font))
	if not look is Dictionary or not Color.html_is_valid(str(look.get("main", ""))) or not Color.html_is_valid(str(look.get("accent", ""))):
		_look = {}
		return
	var main := Color(str(look.main))
	var deep := main.get_luminance() < 0.5
	_look = {
		"dark": deep,
		"bg": main,
		"panel": main.lightened(0.09) if deep else main.darkened(0.08),
		"ink": Color("f4eff8").lerp(main, 0.1) if deep else Color("1f1a26").lerp(main, 0.2),
		"accent": Color(str(look.accent)),
	}

static func game_look_active() -> bool:
	return not _look.is_empty()

static func dark() -> bool:
	return bool(_look.dark) if not _look.is_empty() else Prefs.dark_theme()

static func bg() -> Color:
	if not _look.is_empty():
		return _look.bg
	return Color("171322") if dark() else Color("e9e5ef")

static func panel() -> Color:
	if not _look.is_empty():
		return _look.panel
	return Color("292235") if dark() else Color("d9d2e4")

static func ink() -> Color:
	if not _look.is_empty():
		return _look.ink
	return Color("e4ddec") if dark() else Color("30263f")

static func accent() -> Color:
	if not _look.is_empty():
		return _look.accent
	return Color("65cfcc") if dark() else Color("187d82")

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 16
	for state: String in ["font_color", "font_focus_color"]:
		result.set_color(state, "LinkButton", ink())
	for state: String in ["font_hover_color", "font_pressed_color"]:
		result.set_color(state, "LinkButton", accent())
	for type: String in ["Button", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			result.set_stylebox(state, type, button_box(button_fill(false).lightened(0.06) if state == "hover" else button_fill(false)))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			result.set_color(state, type, ink())
		result.set_color("font_disabled_color", type, ink().lerp(panel(), 0.55))
	for state: String in ["normal", "focus", "read_only"]:
		result.set_stylebox(state, "LineEdit", box(panel().darkened(0.08), 8))
	for state: String in ["font_color", "font_placeholder_color", "caret_color"]:
		result.set_color(state, "LineEdit", ink())
	result.set_color("selection_color", "LineEdit", Color(accent(), 0.35))
	for state: String in ["normal", "focus", "read_only"]:
		result.set_stylebox(state, "TextEdit", box(panel().darkened(0.08), 8))
	for state: String in ["font_color", "font_readonly_color", "caret_color"]:
		result.set_color(state, "TextEdit", ink())
	result.set_color("selection_color", "TextEdit", Color(accent(), 0.35))
	result.set_stylebox("panel", "PopupMenu", box(panel()))
	result.set_stylebox("hover", "PopupMenu", box(panel().lightened(0.1)))
	result.set_color("font_color", "PopupMenu", ink())
	result.set_color("font_hover_color", "PopupMenu", ink())
	result.set_color("font_color", "Label", ink())
	return result

static func box(color: Color, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.border_color = color.darkened(0.16)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.06, 0.04, 0.09, 0.14)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style

static func label(text: String, size: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", BODY)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", ink())
	return item

## Шрифт заголовков: из оформления игры или шрифт сборника.
static func head_font() -> Font:
	return _head if _head != null else HEAD

static func heading(text: String, size: int = 24) -> Label:
	var item := label(text, size)
	item.add_theme_font_override("font", head_font())
	return item

static func button(text: String, size: int = 16) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 40
	item.add_theme_font_size_override("font_size", size)
	style_button(item, false)
	return item

static func primary(text: String, size: int = 16) -> Button:
	var item := button(text, size)
	style_button(item, true)
	return item

## Заливка кнопки: своя из оформления игры или панель/акцент сборника.
static func button_fill(main: bool) -> Color:
	if main:
		return accent()
	return Color(str(_buttons.fill)) if Color.html_is_valid(str(_buttons.get("fill", ""))) else panel()

## Коробка кнопки с окантовкой, скруглением и тенью из оформления игры.
static func button_box(fill: Color, padding: int = 12) -> StyleBoxFlat:
	var style := box(fill, padding)
	if _buttons.is_empty():
		return style
	style.set_corner_radius_all(int(clampf(float(_buttons.get("radius", 8)), 0, 28)))
	var width := int(clampf(float(_buttons.get("border_width", 1)), 0, 6))
	style.set_border_width_all(width)
	style.border_color = Color(str(_buttons.border)) if Color.html_is_valid(str(_buttons.get("border", ""))) else fill.darkened(0.16)
	if not bool(_buttons.get("shadow", true)):
		style.shadow_size = 0
	return style

## Весь внешний вид кнопки (функция не меняется). Вызывается и для готовых кнопок — например, верхней полосы.
static func style_button(item: Button, main: bool = false) -> void:
	var fill := button_fill(main)
	item.add_theme_font_override("font", _button_font if _button_font != null else BODY)
	var padding := 16 if main else 12
	for mode in ["normal", "hover", "pressed", "hover_pressed"]:
		var tone := fill.lightened(0.08) if mode == "hover" else (fill.darkened(0.08) if mode in ["pressed", "hover_pressed"] else fill)
		item.add_theme_stylebox_override(mode, button_box(tone, padding))
	# Недоступная кнопка (и главная) — спокойной заливкой, чтобы не звала нажать.
	item.add_theme_stylebox_override("disabled", button_box(button_fill(false), padding))
	var focus := button_box(Color.TRANSPARENT)
	focus.border_color = accent() if not main else ink()
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	item.add_theme_stylebox_override("focus", focus)
	var text := bg() if main else (Color(str(_buttons.text)) if Color.html_is_valid(str(_buttons.get("text", ""))) else ink())
	for mode in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(mode, text)
	var calm := button_fill(false)
	var calm_text := Color(str(_buttons.text)) if Color.html_is_valid(str(_buttons.get("text", ""))) else ink()
	item.add_theme_color_override("font_disabled_color", calm_text.lerp(calm, 0.55))

static func column(gap: int = 16) -> VBoxContainer:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", gap)
	return item

## Обычный Window не наследует заливку экрана; без неё светлый текстовый интерфейс попадает на серый фон движка.
static func window_surface(window: Window) -> void:
	var background := ColorRect.new()
	background.name = "EditorWindowSurface"
	background.color = bg()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(background)

static func row(gap: int = 8) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", gap)
	return item

static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func value_text(value: Variant) -> String:
	if value is float and is_equal_approx(value, round(value)):
		return str(int(value))
	return str(value)

static func card_back(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_style_box(box(Color("40334e"), 0), rect)
	var inset := rect.grow(-12)
	canvas.draw_rect(inset, Color("8e7ba7"), false, 2)
	canvas.draw_line(inset.position, inset.end, Color("8e7ba7"), 2)
	canvas.draw_line(Vector2(inset.end.x, inset.position.y), Vector2(inset.position.x, inset.end.y), Color("8e7ba7"), 2)

## Жетон: форма (круг/квадрат/шестиугольник/своя картинка), цвет (свой или tint — игрока/команды),
## картинка лица или оборота (data.flipped), номинал — по центру или, если есть картинка, в значке снизу.
class TokenFace extends Control:
	var data: Dictionary
	## Источник картинок (cg_assets: image(hash)); без него рисуется только форма.
	var reader: Object
	## Цвет игрока/команды; прозрачный — цвет из данных.
	var tint := Color.TRANSPARENT
	func _init(fields: Dictionary, assets: Object = null, owner_tint: Color = Color.TRANSPARENT) -> void:
		data = fields
		reader = assets
		tint = owner_tint
		mouse_filter = MOUSE_FILTER_IGNORE
	func _picture() -> Texture2D:
		var key := str(data.get("back" if bool(data.get("flipped", false)) else "image", ""))
		return reader.image(key) if reader != null and not key.is_empty() else null
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.44
		var flipped := bool(data.get("flipped", false))
		var color := tint if tint.a > 0.0 else Color.from_string(str(data.get("color", "#65cfcc")), CGStyle.accent())
		if flipped and str(data.get("back", "")).is_empty():
			color = color.darkened(0.3)
		var picture := _picture()
		var shape := str(data.get("shape", "circle"))
		if shape == "image" and picture != null:
			var scale := minf(radius * 2 / picture.get_width(), radius * 2 / picture.get_height())
			var shown := Vector2(picture.get_size()) * scale
			if tint.a > 0.0:
				draw_circle(center, radius + 4, tint)
			draw_texture_rect(picture, Rect2(center - shown * 0.5, shown), false)
		else:
			draw_circle(center + Vector2(0, 3), radius, Color(0.05, 0.04, 0.08, 0.2))
			match shape:
				"square": draw_style_box(CGStyle.box(color, 0), Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2))
				"hex":
					var points := PackedVector2Array()
					for i in 6:
						points.append(center + Vector2.from_angle(TAU * i / 6.0) * radius)
					draw_colored_polygon(points, color)
				_: draw_circle(center, radius, color)
			if picture != null:
				var inner := radius * 1.3
				var fit := minf(inner / picture.get_width(), inner / picture.get_height())
				var shown := Vector2(picture.get_size()) * fit
				draw_texture_rect(picture, Rect2(center - shown * 0.5, shown), false)
		# Номинал: у оборота — только если задан номинал оборота (он уже стал «value» при перевороте).
		if not bool(data.get("show_value", true)) or flipped and not data.has("back_value"):
			return
		var label := CGStyle.value_text(data.get("value", 1))
		if picture != null:
			var badge := maxf(16.0, radius * 0.42)
			var spot := center + Vector2(0, radius - badge * 0.6)
			draw_circle(spot, badge, Color("30263f"))
			var small := int(clampf(badge, 10, 24))
			draw_string(CGStyle.HEAD, Vector2(spot.x - badge * 2, spot.y + small * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, badge * 4, small, Color("f3ecdc"))
			return
		var ink := Color("f3ecdc") if color.get_luminance() < 0.45 else Color("30263f")
		var font_size := 32 if CGStyle.HEAD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x < size.x * 0.8 else 16
		draw_string(CGStyle.HEAD, Vector2(0, center.y + font_size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink)

## Фон стола игры из редактора в прямоугольнике rect: цвет (пусто — цвет темы), картинка и затемнение.
static func draw_table_background(canvas: CanvasItem, rect: Rect2, background: Dictionary, texture: Texture2D) -> void:
	var color := str(background.get("color", ""))
	canvas.draw_rect(rect, Color.from_string(color, bg()) if not color.is_empty() else bg())
	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		var image_size := Vector2(texture.get_size())
		match str(background.get("fit", "cover")):
			"stretch":
				canvas.draw_texture_rect(texture, rect, false)
			"center":
				var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
				var shown := image_size * scale
				canvas.draw_texture_rect(texture, Rect2(rect.position + (rect.size - shown) * 0.5, shown), false)
			"tile":
				var step := image_size * maxf(0.25, minf(1.0, 256.0 / maxf(image_size.x, image_size.y)))
				var y := rect.position.y
				while y < rect.end.y:
					var x := rect.position.x
					while x < rect.end.x:
						var cell := Rect2(Vector2(x, y), step).intersection(rect)
						canvas.draw_texture_rect_region(texture, cell, Rect2(Vector2.ZERO, image_size * (cell.size / step)))
						x += step.x
					y += step.y
			_:
				# «Заполнить»: по меньшей стороне, лишнее обрезается по центру.
				var scale := maxf(rect.size.x / image_size.x, rect.size.y / image_size.y)
				var region := Rect2((image_size - rect.size / scale) * 0.5, rect.size / scale)
				canvas.draw_texture_rect_region(texture, rect, region)
	var dim := clampf(float(background.get("dim", 0)), 0.0, 0.9)
	if dim > 0.0:
		canvas.draw_rect(rect, Color(0, 0, 0, dim))

## Внешний вид кости PerudoDie по набору из «Элементы → Кубики». reader — cg_assets (картинки граней), может быть null.
## tint — цвет игрока/команды для набора с color = "player"/"team" (прозрачный — обычная кость).
static func style_die(die: Control, look: Dictionary, reader: RefCounted, tint: Color = Color.TRANSPARENT) -> void:
	var by_owner: bool = look.get("color") in ["player", "team"]
	die.color = tint if by_owner and tint.a > 0.0 else Color.from_string(str(look.get("color", "#f3ead2")) if not by_owner else "#f3ead2", Color("f3ead2"))
	die.pip_color = Color.from_string(str(look.get("pips", "")), Color.TRANSPARENT) if look.has("pips") else Color.TRANSPARENT
	die.number_faces = look.get("faces", "dots") == "numbers"
	die.sides = int(look.get("sides", 6))
	var textures: Array = []
	if look.get("faces", "dots") == "images" and reader != null:
		for hash_value: Variant in look.get("images", []):
			textures.append(reader.image(str(hash_value)) if not str(hash_value).is_empty() else null)
	die.face_textures = textures

class CardFace extends Control:
	var data: Dictionary
	var art_texture: Texture2D
	var custom_font: Font
	var layer_reader: RefCounted
	var _art: TextureRect
	func _init(fields: Dictionary) -> void:
		data = fields
		mouse_filter = MOUSE_FILTER_IGNORE
	func _ready() -> void:
		if data.has("layers"):
			var layers := CGStyle.CardLayers.new()
			layers.name = "CardFaceLayers"
			layers.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
			add_child(layers)
			layers.setup(data, layer_reader, custom_font if custom_font != null else CGStyle.BODY)
			return
		if art_texture != null:
			_art = TextureRect.new()
			_art.texture = art_texture
			_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_art.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(_art)
			resized.connect(_place_art)
			_place_art()
	func _place_art() -> void:
		if is_instance_valid(_art):
			_art.position = Vector2(8, 32)
			_art.size = Vector2(maxf(1, size.x - 16), maxf(1, size.y - 48))
	func _draw() -> void:
		var paper := Color.from_string(str(data.get("paper", "#ded7c8")), Color("ded7c8"))
		draw_style_box(CGStyle.box(paper, 0), Rect2(Vector2.ZERO, size))
		if data.has("layers"):
			return
		# На тёмной бумаге — светлые надписи, иначе текст пропадает.
		var ink := Color("f3ecdc") if paper.get_luminance() < 0.45 else Color("30263f")
		var title := CGStyle.value_text(data.get("title", data.get("name", data.get("rank", "Карта"))))
		var number := CGStyle.value_text(data.get("rank", data.get("value", "")))
		draw_string(custom_font if custom_font != null else CGStyle.BODY, Vector2(10, 24), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 16, ink)
		draw_string(custom_font if custom_font != null else CGStyle.HEAD, Vector2(0, size.y * 0.58), number, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, ink)
		var text := str(data.get("text", ""))
		if not text.is_empty():
			draw_multiline_string(CGStyle.BODY, Vector2(10, size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 16, 3, ink)
