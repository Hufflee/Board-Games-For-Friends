extends Control
## Поле «Гонки»: пять трасс, лёд, анимированный воздух и стартовый отсчёт.
## Курсор и щелчок-рывок — как в «Сумо»; симуляция и рекорды приходят от хоста.

const Race := preload("res://hub/minigames/logic/mg_race.gd")
const CAMERA_ZOOM := 1.8  # поле зрения примерно 56% ширины и высоты прежнего общего вида
var mg: Node
var id := ""
var status: Label
var foot: Label
var _send_clock := 0.0
var _clock := 0.0
var _sent_on := false
var _last_track := -1
var _path := PackedVector2Array()
var _fans: Array = []
var _shown := {}
var _extent := Vector2(1.4, 1.0)
var _last_snap: Dictionary = {}
var _snap_age := 0.0
var _falling := {}
var _camera := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _scale() -> float:
	return maxf(1.0, minf((size.x - 12.0) / (_extent.x * 2.0), (size.y - 12.0) / (_extent.y * 2.0))) * CAMERA_ZOOM


func _screen(pos: Vector2) -> Vector2:
	return size * 0.5 + (pos - _camera) * _scale()


func _world(pos: Vector2) -> Vector2:
	return _camera + (pos - size * 0.5) / _scale()


func _state() -> Dictionary:
	return mg.sessions.get(id, {}).get("state", {}) if mg != null else {}


static func _time(seconds: float) -> String:
	return "%02d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]


func _process(delta: float) -> void:
	_clock += delta
	var state := _state()
	if state.is_empty():
		return
	if not is_same(state, _last_snap):
		_last_snap = state
		_snap_age = 0.0
	_snap_age += delta
	if _last_track != int(state.track):
		_last_track = int(state.track)
		_path = Race.track(_last_track)
		_fans = Race.fans(_last_track)
		_extent = Vector2(1.25, 0.9)
		for point: Vector2 in _path:
			_extent = _extent.max(point.abs() + Vector2.ONE * (Race.WIDTH + 0.06))
		for fan: Dictionary in _fans:
			_extent = _extent.max((fan.pos as Vector2).abs() + Vector2.ONE * 0.14)
		_shown.clear()
	_send_clock += delta
	if _send_clock >= 1.0 / 15.0:
		_send_clock = 0.0
		var mouse := get_local_mouse_position()
		_sent_on = is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(mouse) and not mg.blocked_now()
		mg.room_act("race", {"aim": _world(mouse), "on": _sent_on})
	var parts := PackedStringArray()
	for row: Dictionary in state.list:
		var peer := int(row.peer)
		var target: Vector2 = row.pos
		var shown: Vector2 = _shown.get(peer, target)
		var falling := float(row.get("fall", -1.0)) >= 0.0
		var changed_fall := falling != bool(_falling.get(peer, false))
		_falling[peer] = falling
		_shown[peer] = target if changed_fall or shown.distance_to(target) > 0.35 else shown.lerp(target, 1.0 - exp(-22.0 * delta))
		parts.append("%s %s" % [str(row.name).left(10), "✓" if bool(row.done) else "%d/3" % mini(3, int(row.lap) + 1)])
		if peer == mg.my_peer():
			_camera = _shown[peer]
			if state.phase == "solo":
				var best: float = mg.best_time("race_%d" % int(state.track))
				status.text = "%s · %s" % [Race.NAMES[int(state.track)], _time(float(row.elapsed))]
				foot.text = "Личный рекорд: %s · щелчок — рывок" % (_time(best) if best > 0.0 else "—")
			else:
				status.text = "%s · круг %d/3 · место %d/%d" % [Race.NAMES[int(state.track)], mini(3, int(row.lap) + 1), int(row.place), state.list.size()]
	if state.phase != "solo":
		foot.text = "Лидер: %s\n%s" % [str(state.get("leader", "—")), " · ".join(parts)]
	status.tooltip_text = status.text
	foot.tooltip_text = foot.text
	queue_redraw()


func _exit_tree() -> void:
	if mg != null and _sent_on:
		mg.room_act("race", {"aim": Vector2.ZERO, "on": false})


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not mg.blocked_now():
			mg.room_act("race", {"aim": _world(button.position), "on": true})
			mg.room_act("race", {"dash": true})


func _center_text(text: String, y: float, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	var state := _state()
	if state.is_empty() or _path.is_empty():
		return
	var scale := _scale()
	var road := PackedVector2Array()
	for pos: Vector2 in _path:
		road.append(_screen(pos))
	road.append(road[0])
	draw_polyline(road, Color("727a81"), Race.ROAD_EDGE * 2.0 * scale, true)
	draw_polyline(road, Color("313c49"), Race.WIDTH * 2.0 * scale, true)
	# Лёд рисуется цельными полосами с соединёнными углами, как сама дорога.
	# Отдельные толстые draw_line оставляли на изгибах треугольные просветы.
	var first_dry := 0
	for i in _path.size():
		if not Race.surface(int(state.track), i):
			first_dry = i
			break
	var ice_strip := PackedVector2Array()
	for offset in _path.size():
		var i := (first_dry + offset) % _path.size()
		if Race.surface(int(state.track), i):
			if ice_strip.is_empty():
				ice_strip.append(_screen(_path[i]))
			ice_strip.append(_screen(_path[(i + 1) % _path.size()]))
		elif not ice_strip.is_empty():
			draw_polyline(ice_strip, Color("82bfd4"), Race.WIDTH * 2.0 * scale, true)
			ice_strip = PackedVector2Array()
	if not ice_strip.is_empty():
		draw_polyline(ice_strip, Color("82bfd4"), Race.WIDTH * 2.0 * scale, true)
	for i in _path.size():
		var a := _screen(_path[i])
		var b := _screen(_path[(i + 1) % _path.size()])
		if Race.surface(int(state.track), i):
			if i % 4 == 0:
				var side := (b - a).normalized().orthogonal() * Race.WIDTH * scale * 0.7
				draw_line(a - side, a + side * 0.6, Color("c4e5ed"), 1.0, true)
		elif i % 5 < 2:
			draw_line(a, b, Color("828991"), 1.0, true)
	# Стартовая клетчатая полоса и стрелка направления.
	var start := _screen(_path[0])
	var tangent := (_path[1] - _path[0]).normalized()
	var side := tangent.orthogonal()
	for k in 6:
		var at := start + side * Race.WIDTH * scale * (-1.0 + (k + 0.5) / 3.0)
		draw_line(at - tangent * 3.0, at + tangent * 3.0, Color("e1ddc8") if k % 2 == 0 else Color("171e26"), Race.WIDTH * scale / 3.0, true)
	var arrow := _screen(_path[6])
	var ahead := (_path[7] - _path[6]).normalized()
	draw_line(arrow - ahead * 5.0, arrow + ahead * 5.0, Color("e9d193"), 2.0, true)
	draw_line(arrow + ahead * 5.0, arrow + ahead.orthogonal() * 4.0, Color("e9d193"), 2.0, true)
	draw_line(arrow + ahead * 5.0, arrow - ahead.orthogonal() * 4.0, Color("e9d193"), 2.0, true)
	for fan: Dictionary in _fans:
		var dir: Vector2 = fan.dir
		var origin := _screen(fan.pos)
		var normal := dir.orthogonal()
		draw_line(origin - normal * 0.10 * scale, origin + normal * 0.10 * scale, Color("9da4aa"), 3.0, true)
		for k in 5:
			var t := fmod(_clock * 0.8 + k * 0.2, 1.0)
			var at := origin + dir * t * 0.70 * scale + normal * ((k % 3) - 1) * 0.055 * scale
			draw_line(at, at + dir * 0.06 * scale, Color(0.8, 0.87, 0.9, (1.0 - t) * 0.7), 1.0, true)
	var font := get_theme_default_font()
	for row: Dictionary in state.list:
		if bool(row.done):
			continue
		var at := _screen(_shown.get(int(row.peer), row.pos))
		var color := Color(Net.color_of(int(row.color)), float(row.alpha))
		var fall := float(row.get("fall", -1.0))
		var radius := Race.RADIUS * scale
		if fall >= 0.0:
			var t := clampf(fall + _snap_age / Race.FALL_TIME, 0.0, 1.0)
			at += ((row.get("fall_velocity", Vector2.ZERO) as Vector2) * t * Race.FALL_TIME + Vector2(0, 0.14 * t * t)) * scale
			radius *= lerpf(1.0, 0.08, t)
			color.a *= 1.0 - t
		else:
			draw_circle(at + Vector2(0, 2), radius, Color(0, 0, 0, 0.25 * color.a))
		draw_circle(at, radius, color)
		if int(row.peer) == mg.my_peer() and bool(row.get("dash_ready", false)):
			draw_arc(at, radius + 2.0 * (radius / (Race.RADIUS * scale)), 0.0, TAU, 24, Color(Color("e9d193"), color.a), 1.0, true)
		if fall < 0.0 and (int(row.peer) == mg.my_peer() or at.distance_to(get_local_mouse_position()) < Race.RADIUS * scale * 1.8):
			var nick := str(row.name).left(8)
			var width := font.get_string_size(nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, at + Vector2(-width * 0.5, -Race.RADIUS * scale - 4), nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e4e6e9"))
	if state.phase == "countdown":
		var left := int(ceilf(float(state.left)))
		_center_text(str(left), size.y * 0.5 + 16, 46, Color("efd49c"))
		_center_text("До старта", size.y * 0.5 + 36, 12, Color("c4cbd5"))
	elif state.phase == "race" and float(state.get("go_left", 0.0)) > 0.0:
		_center_text("0", size.y * 0.5 + 16, 46, Color("efd49c"))
		_center_text("Старт!", size.y * 0.5 + 36, 12, Color("c4cbd5"))
	elif state.phase == "results":
		_center_text("Финиш", size.y * 0.5 - 15, 24, Color("efd49c"))
		var place := 0
		for peer: int in state.finish:
			for row: Dictionary in state.list:
				if int(row.peer) == peer:
					place += 1
					_center_text("%d. %s" % [place, str(row.name).left(16)], size.y * 0.5 + place * 17, 12, Color("dbe0e6"))
