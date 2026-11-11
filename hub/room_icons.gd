extends RefCounted
## Плоские значки линиями для кнопок комнаты хаба (одним цветом, как смайлик стикеров и галерея плаката):
## крестик «снять», плакат, мяч, доска друзей. Подключать через preload("res://hub/room_icons.gd");
## рисовать в обработчике draw кнопки: button.draw.connect(func(): RoomIcons.cross(button, цвет)).

const WIDTH := 2.0


## Крестик «снять совсем».
static func cross(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	var r := minf(button.size.x, button.size.y) * 0.2
	button.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, WIDTH + 0.5, true)
	button.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), color, WIDTH + 0.5, true)


## Плакат: прямоугольник, гора и солнце внутри, плюс в углу — «повесить новый».
static func poster(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	var box := Rect2(c + Vector2(-11, -9), Vector2(20, 17))
	button.draw_rect(box, color, false, WIDTH, true)
	var base := box.end.y - 2.0
	button.draw_polyline(PackedVector2Array([Vector2(box.position.x + 2, base), Vector2(box.position.x + 8, box.position.y + 7), Vector2(box.position.x + 13, base)]), color, WIDTH, true)
	button.draw_arc(Vector2(box.end.x - 5, box.position.y + 5), 2.2, 0, TAU, 12, color, WIDTH, true)
	_plus(button, c + Vector2(12, 10), color)


## Мяч: круг с наклонной полосой.
static func ball(button: Control, color: Color, on: bool) -> void:
	var c := button.size * 0.5
	var r := 10.0
	button.draw_arc(c, r, 0, TAU, 32, color, WIDTH, true)
	var tilt := Vector2(cos(-0.45), sin(-0.45))
	var across := Vector2(-tilt.y, tilt.x)
	for side: float in [-1.0, 1.0]:
		var mid := c + across * side * 3.5
		var half := sqrt(maxf(0.0, r * r - 3.5 * 3.5)) - 0.6
		button.draw_line(mid - tilt * half, mid + tilt * half, color, WIDTH * 0.8, true)
	if not on:  # выключен — перечёркнут
		button.draw_line(c + Vector2(-13, 13), c + Vector2(13, -13), color, WIDTH + 0.5, true)


## Доска друзей: рамка, полочка снизу, линия «маркером», плюс в углу.
static func board(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	var box := Rect2(c + Vector2(-12, -9), Vector2(22, 15))
	button.draw_rect(box, color, false, WIDTH, true)
	button.draw_line(Vector2(box.position.x + 5, box.end.y + 3), Vector2(box.end.x - 5, box.end.y + 3), color, WIDTH, true)
	button.draw_polyline(PackedVector2Array([Vector2(box.position.x + 4, box.position.y + 9), Vector2(box.position.x + 8, box.position.y + 5), Vector2(box.position.x + 12, box.position.y + 9), Vector2(box.position.x + 16, box.position.y + 5)]), color, WIDTH * 0.8, true)
	_plus(button, c + Vector2(12, 10), color)


static func basket(button: Control, color: Color) -> void:
	var center := button.size * 0.5
	button.draw_rect(Rect2(center + Vector2(-10, -10), Vector2(20, 13)), color, false, WIDTH, true)
	button.draw_line(center + Vector2(-7, 2), center + Vector2(7, 2), color, WIDTH, true)
	button.draw_polyline(PackedVector2Array([center + Vector2(-6, 3), center + Vector2(-3, 11),
		center + Vector2(3, 11), center + Vector2(6, 3)]), color, WIDTH, true)


static func _plus(button: Control, at: Vector2, color: Color) -> void:
	button.draw_circle(at, 6.5, Color(0.08, 0.05, 0.16, 0.9))
	button.draw_line(at + Vector2(-3.5, 0), at + Vector2(3.5, 0), color, WIDTH, true)
	button.draw_line(at + Vector2(0, -3.5), at + Vector2(0, 3.5), color, WIDTH, true)
