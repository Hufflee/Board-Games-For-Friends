extends Control
## Редактор клеток поля-ходилки («Элементы → Поле»): картинка поля, клетки — кружки с номерами по порядку
## и дорожкой между ними. Щелчок по пустому месту — новая клетка в конец, по клетке — выбрать, перетащить —
## подвинуть, правый щелчок — убрать. Места клеток — доли картинки (как у планшета).

signal added(pos: Array)
signal picked(index: int)
signal moved(index: int, pos: Array)
signal removed(index: int)

const Style := preload("res://editor/ed_style.gd")
var track: Dictionary = {}
var texture: Texture2D
var selection := -1
var _drag := -1
var _press := Vector2.ZERO

func _init() -> void:
	custom_minimum_size = Vector2(560, 400)
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP

func area() -> Rect2:
	var box := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	if texture == null or texture.get_width() <= 0:
		return box
	var fit := minf(box.size.x / texture.get_width(), box.size.y / texture.get_height())
	var shown := Vector2(texture.get_size()) * fit
	return Rect2(box.position + (box.size - shown) * 0.5, shown)

func point(index: int) -> Vector2:
	var cell: Dictionary = track.cells[index]
	var whole := area()
	return whole.position + Vector2(float(cell.pos[0]), float(cell.pos[1])) * whole.size

func _hit(at: Vector2) -> int:
	var cells: Array = track.get("cells", [])
	for index in range(cells.size() - 1, -1, -1):
		if point(index).distance_to(at) <= 14:
			return index
	return -1

func _fraction(at: Vector2) -> Array:
	var whole := area()
	var local := ((at - whole.position) / whole.size.max(Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE)
	return [snappedf(local.x, 0.001), snappedf(local.y, 0.001)]

func _draw() -> void:
	var whole := area()
	if texture != null:
		draw_texture_rect(texture, whole, false)
	else:
		draw_style_box(Style.box(Color(Style.panel(), 0.6), 8), whole)
		draw_string(Style.body_font(), whole.get_center() - Vector2(whole.size.x * 0.5, 0), "Загрузите картинку поля справа, затем щёлкайте по клеткам по порядку", HORIZONTAL_ALIGNMENT_CENTER, whole.size.x, 15, Color(Style.ink(), 0.6))
	var cells: Array = track.get("cells", [])
	for index in cells.size():
		var next := index + 1
		if next >= cells.size():
			if not bool(track.get("loop", false)) or cells.size() < 3:
				break
			next = 0
		draw_line(point(index), point(next), Color(Style.accent(), 0.55), 3, true)
	for index in cells.size():
		var at := point(index)
		var start: bool = index == int(track.get("start", 0))
		var fill := Color("ff9f1c") if start else Color(Style.panel(), 0.9)
		draw_circle(at, 13, fill)
		draw_arc(at, 13, 0, TAU, 24, Style.accent() if index == selection else Color(Style.accent2(), 0.9), 3.0 if index == selection else 1.5, true)
		draw_string(Style.bold_font(), at + Vector2(-13, 5), str(index), HORIZONTAL_ALIGNMENT_CENTER, 26, 12, Color("140c24") if start else Style.ink())
		var tag := str(cells[index].get("tag", ""))
		if not tag.is_empty():
			draw_string(Style.bold_font(), at + Vector2(-60, -18), tag, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Style.accent())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var hit := _hit(event.position)
		if hit >= 0:
			removed.emit(hit)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.position
			_drag = _hit(event.position)
			if _drag >= 0:
				selection = _drag
				picked.emit(_drag)
		else:
			if _drag >= 0 and event.position.distance_to(_press) > 4:
				moved.emit(_drag, _fraction(event.position))
			elif _drag < 0 and area().has_point(event.position):
				added.emit(_fraction(event.position))
			_drag = -1
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _drag >= 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		track.cells[_drag]["pos"] = _fraction(event.position)
		queue_redraw()
		accept_event()
