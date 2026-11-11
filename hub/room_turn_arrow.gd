extends Button
## Стрелка смены ракурса хаба появляется у края экрана под курсором.

var room: Node
var party: Control
var _amount := 0.0
var _return_y := 0.0
var _right := false


func _ready() -> void:
	flat = true
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func(): room.look_left_wall(not _right))


func _process(delta: float) -> void:
	_update_arrow(get_global_mouse_position(), delta)


func _update_arrow(mouse: Vector2, delta: float) -> void:
	var bounds := get_viewport_rect().size
	var right: bool = room.left_wall_view()
	if right != _right:
		_amount = 0.0
		_right = right
	var top := bounds.y * 0.5
	if is_instance_valid(party) and party.is_visible_in_tree():
		top = maxf(top, party.get_global_rect().end.y + 12.0)
	var height := bounds.y / 3.0 if right else maxf(0.0, bounds.y - 20.0 - top)
	if right and (_amount < 0.01 or mouse.x >= bounds.x - 22.0 and not is_hovered()):
		_return_y = clampf(mouse.y - height * 0.5, 16.0, bounds.y - height - 16.0)
	var active: bool = room.can_turn_room() and height >= 32.0
	var near_edge := mouse.x >= bounds.x - 32.0 if right else mouse.x <= 32.0 and mouse.y >= top
	var show_arrow := active and (near_edge or _amount > 0.02 and is_hovered())
	_amount = move_toward(_amount, 1.0 if show_arrow else 0.0, delta * 5.0)
	visible = active and _amount > 0.01
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	size = Vector2(52.0, height)
	var slide := ease(_amount, 0.45)
	position = Vector2(lerpf(bounds.x, bounds.x - size.x - 12.0, slide) if right else lerpf(-size.x, 12.0, slide), _return_y if right else top)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var direction := 1.0 if _right else -1.0
	draw_polyline(PackedVector2Array([center + Vector2(-7.0 * direction, -12.0),
		center + Vector2(5.0 * direction, 0.0), center + Vector2(-7.0 * direction, 12.0)]),
		Color("ffffff") if is_hovered() else Color(0.81, 0.89, 1.0, 0.85), 3.0, true)
