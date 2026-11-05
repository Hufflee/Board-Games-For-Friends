extends PanelContainer
## Открытая карта Мачи Коро: иллюстрация из TTS-атласа, корректный текст рисуется Godot.

const Style := preload("res://games/machi_koro/ui/mk_style.gd")
const Data := preload("res://games/machi_koro/logic/mk_data.gd")
const Art := preload("res://games/machi_koro/ui/mk_art.gd")
var id := "wheat"
var large := false
var closed := false
var copies := 1
var built := false
var interactive := true
var compact := false
var narrow := false
var active := false
var fund := 0
var definition: Dictionary = {}
var semantic_color := Color.TRANSPARENT
var art_image: TextureRect
var info_label: Label
var status_label: Label
signal selected(id: String)
signal hover(card: Control, on: bool)

func _ready() -> void:
	definition = Data.catalog().get(id, {}).duplicate(true)
	if Data.LANDMARKS.has(id):
		definition = Data.LANDMARKS[id].duplicate(true)
		definition["sheet"] = 16
		definition["color"] = "landmark"
		definition["rolls"] = []
	var palette := {"blue": Color("246f9c"), "green": Color("4f7853"), "red": Color("a33d52"), "purple": Color("76548c"), "landmark": Color("a57c3b")}
	var color: Color = palette[definition.color]
	semantic_color = color
	var surface := Style.surface()
	if active:
		surface = color.darkened(0.45) if Style.dark() else surface.lerp(color, 0.16)
	add_theme_stylebox_override("panel", Style.box(surface, 8 if not large else 16))
	custom_minimum_size = Vector2(92 if narrow else 124, 132) if compact else Vector2(132, 176) if not large else Vector2(320, 452)
	var col := Style.column(4 if not large else 8)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	var title := Style.heading(str(definition.title), 14 if not large else 28)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.y = 36 if not large else 68
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(title)
	var image := TextureRect.new()
	art_image = image
	image.texture = Art.illustration(int(definition.sheet), int(definition.cell))
	image.custom_minimum_size.y = 32 if compact else 76 if not large else 176
	image.size_flags_vertical = SIZE_FILL if large else SIZE_EXPAND_FILL
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_IGNORE
	var corners := ShaderMaterial.new()
	corners.shader = preload("res://hub/card_corners.gdshader")
	image.material = corners
	if closed:
		image.modulate = Color(0.55, 0.55, 0.55)
	col.add_child(image)
	var rolls: Array = definition.rolls
	var caption := "Цена: %d" % int(definition.cost)
	if Data.LANDMARKS.has(id):
		caption = "Построено" if built else caption
	else:
		caption = "%s\nЦена: %d" % [" · ".join(rolls.map(func(n): return str(n))), int(definition.cost)]
	var info := Style.label(caption, 14 if not large else 18)
	info_label = info
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.clip_text = true
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.add_theme_color_override("font_color", color.lightened(0.25) if Style.dark() else color)
	var kind := str(definition.get("icon", ""))
	var icon_texture := Art.type_icon(kind)
	if icon_texture == null:
		col.add_child(info)
	else:
		var details := Style.row(6)
		details.alignment = BoxContainer.ALIGNMENT_CENTER
		details.mouse_filter = MOUSE_FILTER_IGNORE
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", Style.box(Color("f5efdf"), 3))
		badge.size_flags_vertical = SIZE_SHRINK_CENTER
		badge.mouse_filter = MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.name = "EnterpriseIcon"
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2.ONE * (26 if large else 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		badge.add_child(icon)
		details.add_child(badge)
		info.clip_text = false
		details.add_child(info)
		col.add_child(details)
	if large:
		var text := Style.label(str(definition.text), 18)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(text)
	else:
		var status := Style.label("Закрыто" if closed else "× %d" % copies, 14)
		status_label = status
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(status)
	update_state()
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if interactive else CURSOR_ARROW
	mouse_entered.connect(func(): hover.emit(self, true))
	mouse_exited.connect(func(): hover.emit(self, false))

## Сетевые изменения обновляют существующую карту, не сбрасывая её узел и положение.
func update_state() -> void:
	if not is_instance_valid(art_image):
		return
	var surface := Style.surface()
	if active:
		surface = semantic_color.darkened(0.45) if Style.dark() else surface.lerp(semantic_color, 0.16)
	add_theme_stylebox_override("panel", Style.box(surface, 8 if not large else 16))
	art_image.modulate = Color(0.55, 0.55, 0.55) if closed else Color.WHITE
	if Data.LANDMARKS.has(id):
		info_label.text = "Построено" if built else "Цена: %d" % int(definition.cost)
	if is_instance_valid(status_label):
		status_label.text = "Закрыто" if closed else "Фонд: %d" % fund if id == "venture" else "× %d" % copies if copies != 1 else ""
		# Место под счётчик постоянно: переход ×2 → одна карта не двигает соседние ряды.
		status_label.custom_minimum_size.y = 20
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if interactive else CURSOR_ARROW

func _gui_input(input: InputEvent) -> void:
	if interactive and input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(id)
		accept_event()

func _draw() -> void:
	if semantic_color != Color.TRANSPARENT:
		draw_line(Vector2(8, 3), Vector2(maxf(8, size.x - 8), 3), semantic_color, 3, true)
