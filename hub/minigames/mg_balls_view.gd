extends Control
## «Сумо» в окне «Общение»: арена, свои и чужие шарики, таблица очков и лента выталкиваний.
## Шарик катится к курсору, пока курсор над ареной; щелчок — рывок. Положение приходит от хоста
## (hub/minigames/mg_net.gd) 15 раз в секунду, между снимками шарики плавно догоняют.

const Balls := preload("res://hub/minigames/logic/mg_balls.gd")
const ARENA := Color("1d2333")
const RIM := Color("5a6788")
const SEND_EVERY := 1.0 / 15.0
const RESEND := 0.5  # без изменений ввод всё равно повторяется: пакеты без гарантии доставки

var mg: Node
var id := ""
var status: Label  # строка состояния окна: очки и время до сброса
var _shown: Dictionary = {}  # peer → видимое положение
var _snap_at := 0.0
var _last_snap: Dictionary = {}
var _send_clock := 0.0
var _aim_sent := Vector2(INF, INF)
var _on_sent := false
var _since_sent := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _state() -> Dictionary:
	if mg == null or not mg.sessions.has(id):
		return {}
	return mg.sessions[id].state


func _arena() -> Rect2:
	var side := floorf(minf(size.x, size.y)) - 8.0
	return Rect2(((size - Vector2(side, side)) * 0.5).floor(), Vector2(side, side))


func _to_screen(point: Vector2) -> Vector2:
	var area := _arena()
	return area.get_center() + point * area.size.x * 0.5


func _to_arena(point: Vector2) -> Vector2:
	var area := _arena()
	return (point - area.get_center()) / (area.size.x * 0.5)


func _process(delta: float) -> void:
	var state := _state()
	if state.is_empty():
		return
	if not is_same(state, _last_snap):
		_last_snap = state
		_snap_at = 0.0
	_snap_at = minf(_snap_at + delta, 0.15)
	var seen := {}
	for row: Array in state.get("list", []):
		var peer := int(row[0])
		seen[peer] = true
		var target: Vector2 = (row[3] as Vector2) + (row[4] as Vector2) * _snap_at
		var shown: Vector2 = _shown.get(peer, target)
		if not bool(row[5]) or shown.distance_to(target) > 0.5:
			shown = target  # вылет и появление — без плавного перелёта через арену
		_shown[peer] = shown.lerp(target, 1.0 - exp(-18.0 * delta))
	for peer: int in _shown.keys():
		if not seen.has(peer):
			_shown.erase(peer)
	_send_aim(delta)
	_update_status(state)
	queue_redraw()


func _update_status(state: Dictionary) -> void:
	if status == null or not is_instance_valid(status):
		return
	var mine := 0
	var alpha := 1.0
	for row: Array in state.get("list", []):
		if int(row[0]) == mg.my_peer():
			mine = int(row[6])
			alpha = float(row[8]) if row.size() > 8 else 1.0
	var text := "Серия: %d · щелчок — рывок" % mine
	if alpha < 1.0:
		text = "Очки: %d · %s" % [mine, "вы призрак — курсор на поле" if not _on_sent else "проявляетесь…"]
	if status.text != text:
		status.text = text


func _send_aim(delta: float) -> void:
	_send_clock += delta
	if _send_clock < SEND_EVERY:
		return
	_send_clock = 0.0
	_since_sent += SEND_EVERY
	var mouse := get_local_mouse_position()
	# курсор вне поля (или окно свёрнуто / другая вкладка) — через секунду шарик станет призраком
	var on := is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(mouse)
	var aim := _to_arena(mouse)
	if on == _on_sent and (not on or aim.distance_to(_aim_sent) < 0.01) and _since_sent < RESEND:
		return
	_since_sent = 0.0
	_on_sent = on
	_aim_sent = aim
	mg.room_act("balls", {"aim": aim, "on": on})


func _exit_tree() -> void:
	if mg != null and _on_sent:
		mg.room_act("balls", {"aim": _aim_sent, "on": false})  # поле закрыли — курсор больше не на нём


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		mg.room_act("balls", {"aim": _to_arena(button.position), "on": true})
		mg.room_act("balls", {"dash": true})


func _draw() -> void:
	var state := _state()
	var area := _arena()
	var center := area.get_center()
	var radius := area.size.x * 0.5
	draw_circle(center + Vector2(0, 4), radius, Color(0, 0, 0, 0.3))
	draw_circle(center, radius, ARENA)
	draw_arc(center, radius * 0.5, 0.0, TAU, 48, Color(RIM, 0.25), 1.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, RIM, 3.0, true)
	if state.is_empty():
		return
	var me: int = mg.my_peer()
	var font := get_theme_default_font()
	var ball_r := Balls.RADIUS * radius
	for row: Array in state.get("list", []):
		if not bool(row[5]):
			continue
		var peer := int(row[0])
		var at := _to_screen(_shown.get(peer, row[3]))
		var fill: Color = Net.color_of(int(row[2]))
		var alpha := float(row[8]) if row.size() > 8 else 1.0  # призрак и проявление — полупрозрачные
		if alpha >= 1.0:
			draw_circle(at + Vector2(0, ball_r * 0.18), ball_r, Color(0, 0, 0, 0.35))
			draw_circle(at, ball_r, fill.darkened(0.2))
			draw_circle(at - Vector2(ball_r, ball_r) * 0.08, ball_r * 0.86, fill)
		else:
			draw_circle(at, ball_r, Color(fill, alpha))  # без теней и слоёв — прозрачность ровная
			draw_arc(at, ball_r, 0.0, TAU, 24, Color(fill.lightened(0.3), alpha), 1.5, true)
		draw_circle(at - Vector2(ball_r, ball_r) * 0.35, ball_r * 0.25, Color(1, 1, 1, 0.35 * alpha))
		if bool(row[7]):
			draw_arc(at, ball_r * 1.35, 0.0, TAU, 24, Color(1, 1, 1, 0.5 * alpha), 2.0, true)  # рывок
		if peer == me:
			draw_arc(at, ball_r * 1.2, 0.0, TAU, 24, Color(Color("ffe08a"), alpha * lerpf(0.28, 1.0, float(row[9]) if row.size() > 9 else 1.0)), 2.0, true)
		var nick := str(row[1]).left(10)
		var width := font.get_string_size(nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, at + Vector2(-width * 0.5, -ball_r - 4), nick, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8 * maxf(alpha, 0.5)))
