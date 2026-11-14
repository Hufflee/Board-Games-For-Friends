extends Button
## Блок логики в виде пазла (стайлборд docs/styleboard_editor_dimension_portal_v3.png): шляпка события,
## паз сверху и выступ снизу у обычных блоков, приглушённая заливка цвета группы, неоновая кромка, светлый текст.
## Остаётся обычной кнопкой: имя, текст и сигнал pressed прежние (их используют тесты и мини-карта).
## Зажать и потянуть — сигнал dragged (перенос цепочки или блока), короткое нажатие — pressed.

signal dragged(button: Button, delta: Vector2)
signal dropped(button: Button, global_point: Vector2)

const Style := preload("res://editor/ed_style.gd")
## Приглушённые цвета групп (решение владельца: яркие выглядели детскими) и кромки к ним.
const FILL := {"event": "8a5a2e", "cards": "2c5677", "control": "7a6a2c", "vars": "7a3552", "dice": "553a7d", "end": "7a3338", "ask": "2c6b5c", "players": "3c4f7a"}
const EDGE := {"event": "ffb46b", "cards": "6cc6ff", "control": "f2d36b", "vars": "ff7fb0", "dice": "c39bff", "end": "ff8a8a", "ask": "6cf0c8", "players": "9db8ff"}
const NOTCH := 24.0

var group := "cards"
var hat := false
var selected := false
var _press := Vector2.ZERO
var _pressing := false
var _dragging := false

static func group_of(op: String) -> String:
	var Blocks: GDScript = load("res://games/custom/logic/cg_blocks.gd")
	match str(Blocks.category(op)):
		"Карты и зоны": return "cards"
		"Спросить": return "ask"
		"Кубики": return "dice"
		"Переменные": return "vars"
		"Управление": return "control"
		"Конец игры": return "end"
	return "players"

func _init() -> void:
	custom_minimum_size.y = 44
	focus_mode = FOCUS_NONE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	# Текст рисуем сами (по центру пазла, с отступом под выступ); собственный текст кнопки прозрачный.
	for mode: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(mode, Color.TRANSPARENT)
	add_theme_font_override("font", Style.bold_font())
	add_theme_font_size_override("font_size", 15)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func setup(kind: String, is_hat: bool, is_selected: bool) -> void:
	group = kind
	hat = is_hat
	selected = is_selected
	if hat:
		custom_minimum_size.y = 56
	queue_redraw()

func outline() -> PackedVector2Array:
	var width := size.x
	var height := size.y
	var points := PackedVector2Array()
	if hat:
		for i in 13:
			var t := PI + PI * i / 12.0
			points.append(Vector2(48 + cos(t) * 48, 16 + sin(t) * 14))
		points.append(Vector2(width - 10, 8))
		points.append(Vector2(width, 18))
	else:
		points.append_array([Vector2(0, 6), Vector2(6, 0), Vector2(NOTCH, 0), Vector2(NOTCH + 6, 8), Vector2(NOTCH + 30, 8), Vector2(NOTCH + 36, 0), Vector2(width - 6, 0), Vector2(width, 6)])
	points.append_array([Vector2(width, height - 6), Vector2(width - 6, height), Vector2(NOTCH + 36, height), Vector2(NOTCH + 30, height + 8),
		Vector2(NOTCH + 6, height + 8), Vector2(NOTCH, height), Vector2(6, height), Vector2(0, height - 6)])
	return points

func _draw() -> void:
	var fill := Color(FILL.get(group, "3c4f7a"))
	var edge := Color(EDGE.get(group, "9db8ff"))
	if is_hovered() and not _dragging:
		fill = fill.lightened(0.08)
	if disabled:
		fill = fill.darkened(0.35)
	var points := outline()
	if _dragging:
		# Поднятый пазл: тень снизу.
		var shadow := PackedVector2Array()
		for point: Vector2 in points:
			shadow.append(point + Vector2(8, 10))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(points, fill)
	var ring := points.duplicate()
	ring.append(points[0])
	var glow := Color(Style.accent() if selected else edge, 0.22 if selected else 0.16)
	draw_polyline(ring, glow, 7.0 if selected else 6.0, true)
	draw_polyline(ring, Style.accent() if selected else Color(edge, 0.85), 2.0 if selected else 1.5, true)
	var top := 10.0 if hat else 3.0
	draw_line(Vector2(8, top), Vector2(size.x - 10, top), Color(1, 1, 1, 0.08), 2)
	var font: Font = get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var baseline := (size.y + (12.0 if hat else 0.0)) * 0.5 + font_size * 0.35
	draw_string(font, Vector2(14, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, font_size, Color("f1eaff") if not disabled else Color("f1eaff", 0.5))

## Нажатие и перенос: короткое нажатие — обычный pressed, перенос дальше 6 px — dragged/dropped.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press = event.global_position
		elif _pressing:
			_pressing = false
			if _dragging:
				_dragging = false
				z_index = 0
				queue_redraw()
				dropped.emit(self, event.global_position)
			elif not disabled:
				pressed.emit()
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		if not _dragging and event.global_position.distance_to(_press) > 6:
			_dragging = true
			z_index = 20
			queue_redraw()
		if _dragging:
			dragged.emit(self, event.relative)
		accept_event()

func is_dragging() -> bool:
	return _dragging
