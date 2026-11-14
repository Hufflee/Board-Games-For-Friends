extends Control
## «Сапёр» в окне «Общение»: поле 16×16, левая кнопка — открыть, правая — флажок.
## Бесконечный режим: у каждого слоя свой цвет, в клетке рисуется самый глубокий видимый слой
## (правила видимости — hub/minigames/logic/mg_mines.gd).

const Mines := preload("res://hub/minigames/logic/mg_mines.gd")
## Цвет закрытой клетки по слою (по кругу), открытая — тот же тон, темнее.
const LAYER_COLORS := [Color("5d7fb8"), Color("8a62b5"), Color("3f9a86"), Color("b7744a"), Color("b0566f"), Color("7f9a3e")]

var mg: Node
var id := ""
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw())


static func layer_color(depth: int) -> Color:
	return LAYER_COLORS[depth % LAYER_COLORS.size()]


## Цифры одного цвета на весь слой — светлый тон цвета слоя (синий слой — голубые, розовый — розовые).
static func number_color(depth: int) -> Color:
	var tone := layer_color(depth)
	return Color.from_hsv(tone.h, minf(1.0, tone.s * 0.75 + 0.1), 1.0)


func _state() -> Dictionary:
	if mg == null or not mg.sessions.has(id):
		return {}
	return mg.sessions[id].state


func _rect() -> Rect2:
	var side := floorf(minf(size.x, size.y) / Mines.N) * Mines.N
	return Rect2(((size - Vector2(side, side)) * 0.5).floor(), Vector2(side, side))


func _cell_at(point: Vector2) -> int:
	var area := _rect()
	if not area.has_point(point):
		return -1
	var cell := area.size.x / Mines.N
	return int((point.y - area.position.y) / cell) * Mines.N + int((point.x - area.position.x) / cell)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := _cell_at((event as InputEventMouseMotion).position)
		if at != _hover:
			_hover = at
			queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	var sq := _cell_at(button.position)
	if sq < 0 or bool(_state().get("over", true)):
		return
	mg.move(id, {"flag" if button.button_index == MOUSE_BUTTON_RIGHT else "open": sq})


func _draw() -> void:
	var state := _state()
	if state.is_empty():
		return
	var area := _rect()
	var cell := area.size.x / Mines.N
	var font := get_theme_default_font()
	var font_size := int(cell * 0.62)
	var over := bool(state.over)
	var boom: Array = state.get("boom", [])
	draw_rect(area.grow(2), Color(0.04, 0.05, 0.08))
	for sq in Mines.CELLS:
		var d := Mines.depth_at(state, sq)
		var lay := Mines.layer(state, d)
		var tone := layer_color(d)
		var rect := Rect2(area.position + Vector2(sq % Mines.N, sq / Mines.N) * cell, Vector2(cell, cell)).grow(-0.5)
		var opened := int(lay.open[sq]) == 1
		var mine := int(lay.mine[sq]) == 1
		if not opened:
			draw_rect(rect, tone.darkened(0.05))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, maxf(1.0, cell * 0.12))), tone.lightened(0.18))  # свет сверху
			if sq == _hover and not over:
				draw_rect(rect, Color(1, 1, 1, 0.14))
			if int(lay.flag[sq]) == 1:
				_draw_flag(rect)
			elif over and mine:
				_draw_mine(rect, Color(0.1, 0.1, 0.12))
			continue
		draw_rect(rect, tone.darkened(0.48))
		draw_rect(rect.grow(-0.5), tone.darkened(0.2), false, 1.0)  # рамка в цвет слоя — слои различимы и у открытых клеток
		if mine:
			var exploded := boom.size() == 2 and int(boom[0]) == d and int(boom[1]) == sq
			if exploded:
				draw_rect(rect, Color("d94a3d"))
			_draw_mine(rect, Color(0.08, 0.08, 0.1))
			continue
		var num := int(lay.num[sq])
		if num > 0:
			var text := str(num)
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var at := rect.get_center() + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 1.0)
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, number_color(d))


func _draw_flag(rect: Rect2) -> void:
	var c := rect.get_center()
	var s := rect.size.x
	draw_line(c + Vector2(-s * 0.12, -s * 0.3), c + Vector2(-s * 0.12, s * 0.3), Color(0.12, 0.12, 0.14), maxf(1.0, s * 0.08))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.3), c + Vector2(s * 0.28, -s * 0.15), c + Vector2(-s * 0.12, 0.0)]), Color("e8473a"))


func _draw_mine(rect: Rect2, ink: Color) -> void:
	var c := rect.get_center()
	var r := rect.size.x * 0.24
	for i in 4:
		var dir := Vector2.from_angle(i * PI / 4.0) * r * 1.45
		draw_line(c - dir, c + dir, ink, maxf(1.0, rect.size.x * 0.07))
	draw_circle(c, r, ink)
