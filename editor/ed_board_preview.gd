extends Control
## Просмотр планшета игрока в «Элементах»: картинка, рамка цвета игрока и ячейки (зоны, счётчики).
## Ячейку можно перетащить мышью, правый нижний угол — изменить размер; координаты — доли картинки.
## Используется из editor/ed_app.gd (_board_properties).

signal cell_changed(index: int, rect: Array)
signal cell_selected(index: int)

const Style := preload("res://games/custom/ui/cg_style.gd")
var board: Dictionary = {}
var texture: Texture2D
var tint := Color.TRANSPARENT
var selection := -1
var _drag := ""
var _from := Vector2.ZERO
var _original: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(560, 360)
	mouse_filter = MOUSE_FILTER_STOP

## Прямоугольник картинки внутри просмотра (с сохранением пропорций картинки).
func board_rect() -> Rect2:
	var area := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	if texture == null or texture.get_width() <= 0:
		var fallback := Vector2(area.size.x, area.size.x * 0.5)
		if fallback.y > area.size.y:
			fallback = Vector2(area.size.y * 2, area.size.y)
		return Rect2(area.position + (area.size - fallback) * 0.5, fallback)
	var scale := minf(area.size.x / texture.get_width(), area.size.y / texture.get_height())
	var shown := Vector2(texture.get_size()) * scale
	return Rect2(area.position + (area.size - shown) * 0.5, shown)

func cell_rect(index: int) -> Rect2:
	var cells: Array = board.get("cells", [])
	if index < 0 or index >= cells.size():
		return Rect2()
	var values: Array = cells[index].get("rect", [0.1, 0.1, 0.3, 0.3])
	var whole := board_rect()
	return Rect2(whole.position + Vector2(float(values[0]), float(values[1])) * whole.size, Vector2(float(values[2]), float(values[3])) * whole.size)

func _draw() -> void:
	var whole := board_rect()
	if texture != null:
		draw_texture_rect(texture, whole, false)
	else:
		draw_style_box(Style.box(Style.panel().lerp(Style.ink(), 0.08), 8), whole)
		draw_string(Style.BODY, whole.get_center() + Vector2(-whole.size.x * 0.5, 0), "Картинка планшета", HORIZONTAL_ALIGNMENT_CENTER, whole.size.x, 20, Color(Style.ink(), 0.5))
	if tint.a > 0.0:
		draw_rect(whole.grow(2), tint, false, 4)
	var cells: Array = board.get("cells", [])
	for index in cells.size():
		var rect := cell_rect(index)
		var counter: bool = cells[index].get("kind") == "counter"
		draw_rect(rect, Color(0.08, 0.06, 0.12, 0.45))
		draw_rect(rect, Style.accent() if index == selection else Color(1, 1, 1, 0.7), false, 3 if index == selection else 2)
		var title := str(cells[index].get("title", "Счётчик" if counter else "Зона"))
		draw_string(Style.BODY, rect.position + Vector2(8, 22), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(8, rect.size.x - 16), 16, Color("f3ecdc"))
		draw_rect(Rect2(rect.end - Vector2(10, 10), Vector2(10, 10)), Style.accent() if index == selection else Color(1, 1, 1, 0.7))

func _gui_input(event: InputEvent) -> void:
	var cells: Array = board.get("cells", [])
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = ""
			for index in range(cells.size() - 1, -1, -1):
				var rect := cell_rect(index)
				if Rect2(rect.end - Vector2(14, 14), Vector2(18, 18)).has_point(event.position):
					_drag = "resize"
				elif rect.has_point(event.position):
					_drag = "move"
				if not _drag.is_empty():
					selection = index
					_from = event.position
					_original = cells[index].get("rect", [0.1, 0.1, 0.3, 0.3]).duplicate()
					cell_selected.emit(index)
					break
			queue_redraw()
		elif not _drag.is_empty():
			_drag = ""
			if selection >= 0 and selection < cells.size():
				cell_changed.emit(selection, cells[selection].rect.duplicate())
		accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty() and selection >= 0 and selection < cells.size():
		var whole := board_rect()
		var delta: Vector2 = (event.position - _from) / whole.size.max(Vector2.ONE)
		var next: Array = _original.duplicate()
		if _drag == "move":
			next[0] = clampf(float(_original[0]) + delta.x, 0.0, 1.0 - float(_original[2]))
			next[1] = clampf(float(_original[1]) + delta.y, 0.0, 1.0 - float(_original[3]))
		else:
			next[2] = clampf(float(_original[2]) + delta.x, 0.05, 1.0 - float(_original[0]))
			next[3] = clampf(float(_original[3]) + delta.y, 0.05, 1.0 - float(_original[1]))
		for i in 4:
			next[i] = snappedf(float(next[i]), 0.005)
		cells[selection]["rect"] = next
		queue_redraw()
		accept_event()
