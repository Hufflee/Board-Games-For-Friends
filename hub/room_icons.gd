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


## Куб (неоновый куб на шкафу): изометрический контур; скрыт — перечёркнут.
static func cube(button: Control, color: Color, shown: bool) -> void:
	var c := button.size * 0.5 + Vector2(0, 1)
	var r := 10.0
	var top := c + Vector2(0, -r)
	var left := c + Vector2(-r * 0.87, -r * 0.5)
	var right := c + Vector2(r * 0.87, -r * 0.5)
	var low_left := c + Vector2(-r * 0.87, r * 0.5)
	var low_right := c + Vector2(r * 0.87, r * 0.5)
	var bottom := c + Vector2(0, r)
	button.draw_polyline(PackedVector2Array([top, right, low_right, bottom, low_left, left, top]), color, WIDTH, true)
	button.draw_polyline(PackedVector2Array([left, c, right]), color, WIDTH * 0.8, true)
	button.draw_line(c, bottom, color, WIDTH * 0.8, true)
	if not shown:
		button.draw_line(c + Vector2(-13, 13), c + Vector2(13, -13), color, WIDTH + 0.5, true)


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


## Комната: стены в перспективе (дальняя стена — прямоугольник, от углов — рёбра к краям).
static func room(button: Control, color: Color) -> void:
	# шкаф с ячейками: корпус, полки, перегородки, ножки
	var c := button.size * 0.5
	var body := Rect2(c + Vector2(-10, -12), Vector2(20, 22))
	button.draw_rect(body, color, false, WIDTH, true)
	for k in [1, 2]:
		var y: float = body.position.y + body.size.y * k / 3.0
		button.draw_line(Vector2(body.position.x, y), Vector2(body.end.x, y), color, WIDTH * 0.8, true)
	button.draw_line(Vector2(c.x, body.position.y), Vector2(c.x, body.position.y + body.size.y / 3.0), color, WIDTH * 0.8, true)
	button.draw_line(Vector2(c.x + 2, body.position.y + body.size.y * 2 / 3.0), Vector2(c.x + 2, body.end.y), color, WIDTH * 0.8, true)
	for x: float in [body.position.x + 2, body.end.x - 2]:
		button.draw_line(Vector2(x, body.end.y), Vector2(x, body.end.y + 3), color, WIDTH, true)


## Дверь (выбор комнаты): рама, полотно, ручка (референс владельца).
static func door(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	var frame := Rect2(c + Vector2(-8, -13), Vector2(16, 26))
	button.draw_rect(frame, color, false, WIDTH, true)
	var leaf := frame.grow(-3.0)
	button.draw_line(leaf.position, Vector2(leaf.end.x, leaf.position.y), color, WIDTH * 0.8, true)
	button.draw_line(Vector2(leaf.end.x, leaf.position.y), leaf.end, color, WIDTH * 0.8, true)
	button.draw_line(leaf.end, Vector2(leaf.position.x, leaf.end.y), color, WIDTH * 0.8, true)
	button.draw_line(leaf.position, Vector2(leaf.position.x, c.y - 4), color, WIDTH * 0.8, true)
	button.draw_line(Vector2(leaf.position.x, c.y + 4), Vector2(leaf.position.x, leaf.end.y), color, WIDTH * 0.8, true)
	button.draw_rect(Rect2(Vector2(leaf.position.x - 1.5, c.y - 3), Vector2(3, 6)), color, false, WIDTH * 0.8, true)
	button.draw_line(Vector2(leaf.position.x + 1.5, c.y - 1), Vector2(leaf.position.x + 5, c.y - 1), color, WIDTH * 0.8, true)


## Предметы комнаты (кнопка, раскрывающая плакат, мяч, доску, корзину): квадрат, круг, плюс.
static func items(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	button.draw_rect(Rect2(c + Vector2(-11, -10), Vector2(10, 10)), color, false, WIDTH, true)
	button.draw_arc(c + Vector2(6, -5), 5.0, 0, TAU, 20, color, WIDTH, true)
	button.draw_rect(Rect2(c + Vector2(-11, 2), Vector2(10, 9)), color, false, WIDTH, true)
	button.draw_line(c + Vector2(6, 2), c + Vector2(6, 11), color, WIDTH, true)
	button.draw_line(c + Vector2(1.5, 6.5), c + Vector2(10.5, 6.5), color, WIDTH, true)


static func _room_at(canvas: CanvasItem, c: Vector2, color: Color, k: float) -> void:
	var outer := Rect2(c + Vector2(-12, -10) * k, Vector2(24, 20) * k)
	var inner := Rect2(c + Vector2(-5, -4) * k, Vector2(10, 8) * k)
	canvas.draw_rect(outer, color, false, WIDTH, true)
	canvas.draw_rect(inner, color, false, WIDTH * 0.8, true)
	for pair: Array in [[outer.position, inner.position], [Vector2(outer.end.x, outer.position.y), Vector2(inner.end.x, inner.position.y)],
			[Vector2(outer.position.x, outer.end.y), Vector2(inner.position.x, inner.end.y)], [outer.end, inner.end]]:
		canvas.draw_line(pair[0], pair[1], color, WIDTH * 0.8, true)


## Значок комнаты в списке (HubRooms: поле icon): winter — снежинка, neon — месяц и звезда, иначе — комната.
static func room_icon(canvas: Control, kind: String, color: Color) -> void:
	var c := canvas.size * 0.5
	match kind:
		"winter":
			for i in 6:
				var dir := Vector2.from_angle(i * TAU / 6.0 - PI * 0.5)
				var side := Vector2(-dir.y, dir.x)
				canvas.draw_line(c, c + dir * 12.0, color, WIDTH, true)
				var at := c + dir * 7.5
				canvas.draw_line(at, at + (dir - side) * 3.2, color, WIDTH * 0.8, true)
				canvas.draw_line(at, at + (dir + side) * 3.2, color, WIDTH * 0.8, true)
		"neon":
			# месяц: дуги двух окружностей сходятся в рожках (точки пересечения посчитаны заранее)
			var mc := c + Vector2(-4, 1)
			canvas.draw_arc(mc, 10.0, 0.99, TAU - 0.99, 28, color, WIDTH, true)
			canvas.draw_arc(mc + Vector2(4, 0), 8.5, 1.397, TAU - 1.397, 24, color, WIDTH, true)
			var star := PackedVector2Array()
			var sc := c + Vector2(8, -5)
			for i in 11:
				var r := 5.0 if i % 2 == 0 else 2.2
				star.append(sc + Vector2.from_angle(i * TAU / 10.0 - PI * 0.5) * r)
			canvas.draw_polyline(star, color, WIDTH * 0.8, true)
		_:
			_room_at(canvas, c, color, 0.9)


static func _plus(button: Control, at: Vector2, color: Color) -> void:
	button.draw_circle(at, 6.5, Color(0.08, 0.05, 0.16, 0.9))
	button.draw_line(at + Vector2(-3.5, 0), at + Vector2(3.5, 0), color, WIDTH, true)
	button.draw_line(at + Vector2(0, -3.5), at + Vector2(0, 3.5), color, WIDTH, true)


## Полка с диагональным левым концом и коробкой сверху.
static func upper_shelves(button: Control, color: Color) -> void:
	var c := button.size * 0.5
	var points := PackedVector2Array([c + Vector2(-15, -5), c + Vector2(-6, 4), c + Vector2(15, 4)])
	button.draw_polyline(points, color, WIDTH, true)
	button.draw_rect(Rect2(c + Vector2(0, -7), Vector2(11, 10)), color, false, WIDTH)
