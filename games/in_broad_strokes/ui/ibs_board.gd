extends Control
## Прозрачные планшеты (листы кальки). Данные штрихов хранятся в долях планшета.
## Вид — IBSStyle: калька на скотче, графитовые линии днём, белые на синьке ночью.
## В рисовании прошлые слои слева на 80 %, новый лист по центру; при совмещении новый лист
## переезжает на старые слои.

signal draft_changed

const Rules := preload("res://games/in_broad_strokes/logic/ibs_rules.gd")

var data: Dictionary = {}
var draft: Array[PackedVector2Array] = []
var current := PackedVector2Array()
var curve := false
var anim := 0.0
var drawing := false
var blocked := false  # кривая упёрлась в запрет «изгиб в другую сторону» — подсказка на листе


func present(view: Dictionary) -> void:
	if view.get("serial") != data.get("serial"):
		clear_draft()
		anim = float(view.get("elapsed", 0))
	data = view
	queue_redraw()


func set_curve(value: bool) -> void:
	if curve != value:
		clear_draft()
	curve = value


func clear_draft() -> void:
	drawing = false
	draft.clear()
	current.clear()
	draft_changed.emit()
	queue_redraw()


## Сколько линий ещё можно провести на этом слое.
func strokes_left() -> int:
	return (1 if curve else 2) - draft.size()


func _process(delta: float) -> void:
	if data.get("phase", "") == "merge" and not Net.paused:
		anim += delta
		queue_redraw()


func _artist_now() -> bool:
	return data.get("phase") == "draw" and data.get("seat", -1) >= 0 and data.seat == data.artist


func _active() -> Rect2:
	var side := minf(size.y - 56, minf(size.x * 0.52, 470))
	var shifted: bool = (data.get("phase") == "draw" and not data.get("layers", []).is_empty()) or (data.get("phase") == "merge" and data.layers.size() > 1)
	return Rect2(Vector2(size.x * (0.64 if shifted else 0.5) - side * 0.5, (size.y - side) * 0.5 - 10), Vector2.ONE * side)


func _gui_input(event: InputEvent) -> void:
	if not _artist_now():
		return
	var area := _active()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and area.has_point(event.position) and draft.size() < (1 if curve else 2):
			drawing = true
			current = PackedVector2Array([_normalized(area, event.position), _normalized(area, event.position)])
			accept_event()
		elif not event.pressed and drawing:
			_sample(area, event.position)
			if current[0].distance_to(current[-1]) > 0.002 or (curve and current.size() > 3):
				draft.append(current)
				draft_changed.emit()
			current = PackedVector2Array()
			drawing = false
			blocked = false
			accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and drawing:
		_sample(area, event.position)
		queue_redraw()


func _normalized(area: Rect2, point: Vector2) -> Vector2:
	return ((point - area.position) / area.size).clamp(Vector2.ZERO, Vector2.ONE)


func _sample(area: Rect2, point: Vector2) -> void:
	var pos := _normalized(area, point)
	if curve:
		# точки — не чаще шага проверки; точка, которая загнула бы кривую в другую сторону, не ставится
		# (та же проверка, что у хоста: IBSRules.curve_ok)
		if current.size() < 180 and current[-1].distance_to(pos) >= Rules.CURVE_STEP:
			var candidate := current.duplicate()
			candidate.append(pos)
			if Rules.curve_ok(candidate):
				current = candidate
				blocked = false
			else:
				blocked = true
	else:
		current[1] = pos


func _sheet(rect: Rect2, layers: Array) -> void:
	IBSStyle.draw_sheet(self, rect)
	for layer: Array in layers:
		_draw_layer(rect, layer)


func _caption(pos: Vector2, text: String) -> void:
	draw_string(IBSStyle.font("title"), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, IBSStyle.c("muted"))


func _draw() -> void:
	mouse_default_cursor_shape = Control.CURSOR_CROSS if _artist_now() else Control.CURSOR_ARROW
	if data.is_empty():
		return
	var active := _active()
	var layers: Array = data.layers
	var old := Rect2(Vector2(20, active.position.y + active.size.y * 0.1), active.size * 0.8)
	var joined := Rect2(Vector2(size.x * 0.5 - active.size.x * 0.5, active.position.y), active.size)
	if data.phase == "draw":
		if not layers.is_empty():
			# стопка прошлых слоёв: смещённые листы под верхним
			for k in range(mini(layers.size() - 1, 3), 0, -1):
				IBSStyle.draw_sheet(self, Rect2(old.position + Vector2(k * 6, k * 6), old.size))
			_sheet(old, layers)
			_caption(old.position + Vector2(0, old.size.y + 34), "прошлые слои · %d" % layers.size())
		var working: Array = draft.duplicate()
		if drawing:
			working.append(current)
		_sheet(active, [working])
		if _artist_now():
			if working.is_empty():
				var hint := "проведите линию мышью"
				var f := IBSStyle.font("title")
				var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
				draw_string(f, active.get_center() + Vector2(-w / 2, 8), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(IBSStyle.c("muted"), 0.8))
			_caption(active.position + Vector2(0, active.size.y + 34), "новый слой · осталось линий: %d" % maxi(0, strokes_left()))
			if curve and drawing and blocked:
				draw_string(IBSStyle.font("title"), active.position + Vector2(12, 30), "кривая гнётся только в одну сторону", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, IBSStyle.c("red"))
		else:
			_caption(active.position + Vector2(0, active.size.y + 34), "новый слой · рисует %s" % str(data.names[data.artist]))
	elif data.phase == "merge" and layers.size() > 1:
		var t := smoothstep(0, 1, clampf(anim / 0.7, 0, 1))
		var backing := Rect2(old.position.lerp(joined.position, t), old.size.lerp(joined.size, t))
		var front := Rect2(active.position.lerp(joined.position, t), active.size)
		_sheet(backing, layers.slice(0, -1))
		IBSStyle.draw_sheet(self, front)
		for layer: Array in layers.slice(0, -1):
			_draw_layer(backing, layer)
		_draw_layer(front, layers.back())
	else:
		var rect := joined if layers.size() > 1 or data.phase != "draw" else active
		for k in range(mini(layers.size() - 1, 3), 0, -1):
			IBSStyle.draw_sheet(self, Rect2(rect.position + Vector2(k * 6, k * 6), rect.size))
		_sheet(rect, layers)
		if not layers.is_empty():
			_caption(rect.position + Vector2(0, rect.size.y + 34), "совмещено слоёв: %d" % layers.size())


func _draw_layer(rect: Rect2, paths: Array) -> void:
	var stroke := IBSStyle.c("stroke")
	for path: PackedVector2Array in paths:
		var points := PackedVector2Array()
		for pt in path:
			points.append(rect.position + pt * rect.size)
		draw_polyline(points, stroke, 4.5, true)
