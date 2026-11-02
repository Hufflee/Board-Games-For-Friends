extends Control
## Холст лица карты: общая отрисовка со столом, перенос, четыре угла, поворот, панорама и зум.
const Style := preload("res://games/custom/ui/cg_style.gd")
const Faces := preload("res://games/custom/logic/cg_faces.gd")
signal selected(index: int)
signal transformed(index: int, rect: Array, rotation: float)
signal view_changed(zoom: float, pan: Vector2)
var selection := -1
var zoom := 1.0
var pan := Vector2.ZERO
var layers: Array = []
var _design := Vector2(504, 704)
var _face: Control
var _handles: Control
var _mode := ""
var _start := Vector2.ZERO
var _original := Rect2()
var _draft := Rect2()
var _corner := Vector2.ONE
var _angle := 0.0
var _original_angle := 0.0

class Handles extends Control:
	var canvas
	func _draw() -> void:
		canvas.draw_handles(self)

func _init() -> void:
	name = "CardFaceCanvas"
	custom_minimum_size = Vector2(320, 320)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	clip_contents = true
	resized.connect(_place)

func configure(deck: Dictionary, row: Dictionary, reader: RefCounted, index: int) -> void:
	selection = index
	layers = deck.get("face", {}).get("layers", []).duplicate(true)
	var dimensions := Faces.dimensions(deck)
	_design = Vector2(dimensions[0], dimensions[1])
	if is_instance_valid(_face):
		remove_child(_face)
		_face.queue_free()
	_face = Style.CardFace.new(Faces.fields(row, deck))
	_face.layer_reader = reader
	_face.custom_font = reader.font(str(deck.get("face", {}).get("font", "")))
	add_child(_face)
	if not is_instance_valid(_handles):
		_handles = Handles.new()
		_handles.canvas = self
		_handles.mouse_filter = MOUSE_FILTER_IGNORE
		_handles.z_index = 2
		_handles.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_handles)
	_place()

func _factor() -> float:
	return maxf(0.01, minf((size.x - 48) / _design.x, (size.y - 48) / _design.y)) * zoom

func _origin() -> Vector2:
	return (size - _design * _factor()) * 0.5 + pan

func design_point(point: Vector2) -> Vector2:
	return (point - _origin()) / _factor()

func _place() -> void:
	if is_instance_valid(_face):
		_face.position = _origin()
		_face.size = _design * _factor()
	if is_instance_valid(_handles):
		_handles.queue_redraw()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Style.panel().darkened(0.08))

func _rect(index: int) -> Rect2:
	var rect: Array = layers[index].rect
	return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))

func _point(rect: Rect2, corner: Vector2, degrees: float) -> Vector2:
	return rect.get_center() + (rect.size * 0.5 * corner).rotated(deg_to_rad(degrees))

func draw_handles(canvas: CanvasItem) -> void:
	if selection < 0 or selection >= layers.size() or not layers[selection].get("visible", true):
		return
	var rect := _draft if _mode in ["move", "resize", "rotate"] else _rect(selection)
	var degrees: float = _angle if _mode in ["move", "resize", "rotate"] else float(layers[selection].get("rotation", 0))
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		var point := _origin() + _point(rect, corner, degrees) * _factor()
		points.append(point)
		if not layers[selection].get("locked", false):
			canvas.draw_rect(Rect2(point - Vector2(5, 5), Vector2(10, 10)), Style.accent())
	canvas.draw_polyline(points, Style.accent(), 2, true)
	if not layers[selection].get("locked", false):
		var top := _point(rect, Vector2(0, -1), degrees)
		var handle := top + Vector2(0, -32).rotated(deg_to_rad(degrees))
		canvas.draw_line(_origin() + top * _factor(), _origin() + handle * _factor(), Style.accent(), 2)
		canvas.draw_circle(_origin() + handle * _factor(), 6, Style.accent())

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := design_point(event.position)
		zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.5, 4)
		pan += event.position - (_origin() + before * _factor())
		_place()
		view_changed.emit(zoom, pan)
		accept_event()
		return
	if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		_mode = "pan"
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := design_point(event.position)
	_mode = ""
	if selection >= 0 and selection < layers.size() and layers[selection].get("visible", true) and not layers[selection].get("locked", false):
		var rect := _rect(selection)
		var degrees := float(layers[selection].get("rotation", 0))
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			if point.distance_to(_point(rect, corner, degrees)) * _factor() <= 12:
				_mode = "resize"
				_corner = corner
		var handle := _point(rect, Vector2(0, -1), degrees) + Vector2(0, -32).rotated(deg_to_rad(degrees))
		if point.distance_to(handle) * _factor() <= 12:
			_mode = "rotate"
	if _mode.is_empty():
		selection = -1
		for index in range(layers.size() - 1, -1, -1):
			if not layers[index].get("visible", true):
				continue
			var rect := _rect(index)
			var local := (point - rect.get_center()).rotated(-deg_to_rad(float(layers[index].get("rotation", 0))))
			if Rect2(-rect.size * 0.5, rect.size).has_point(local):
				selection = index
				_mode = "" if layers[index].get("locked", false) else "move"
				break
		selected.emit(selection)
	if selection >= 0:
		_start = point
		_original = _rect(selection)
		_draft = _original
		_original_angle = float(layers[selection].get("rotation", 0))
		_angle = _original_angle
	_handles.queue_redraw()
	accept_event()

func _input(event: InputEvent) -> void:
	if _mode.is_empty():
		return
	if event is InputEventMouseMotion:
		if _mode == "pan":
			pan += event.relative
			_place()
			view_changed.emit(zoom, pan)
			return
		var point := design_point(get_global_transform_with_canvas().affine_inverse() * event.position)
		if _mode == "move":
			_draft.position = (_original.position + point - _start).snapped(Vector2(4, 4))
		elif _mode == "resize":
			var anchor := _point(_original, -_corner, _original_angle)
			_draft.size = ((point - anchor).rotated(-deg_to_rad(_original_angle)) * _corner).max(Vector2(8, 8)).min(Vector2(4096, 4096))
			var center := anchor + (_draft.size * 0.5 * _corner).rotated(deg_to_rad(_original_angle))
			_draft.position = center - _draft.size * 0.5
		elif _mode == "rotate":
			var center := _original.get_center()
			_angle = clampf(snappedf(_original_angle + rad_to_deg((point - center).angle() - (_start - center).angle()), 1), -3600, 3600)
		_draft.position = _draft.position.clamp(Vector2(-4096, -4096), Vector2(4096, 4096))
		var layer: Control = _face.find_child("CardLayer%d" % selection, true, false)
		if is_instance_valid(layer):
			layer.position = _draft.position
			layer.size = _draft.size
			layer.pivot_offset = _draft.size * 0.5
			layer.rotation_degrees = _angle
		_handles.queue_redraw()
	elif event is InputEventMouseButton and not event.pressed:
		var changed: bool = _mode in ["move", "resize", "rotate"] and (_draft != _original or not is_equal_approx(_angle, _original_angle))
		_mode = ""
		if changed:
			transformed.emit(selection, [_draft.position.x, _draft.position.y, _draft.size.x, _draft.size.y], _angle)
		get_viewport().set_input_as_handled()
