class_name WinGraph
extends Control
## Ломаная последних 100 партий: каждая победа +1, каждое поражение −1.
var history: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): tooltip_text = "")


func _draw() -> void:
	var font := HubStyle.font()
	if history.is_empty():
		draw_string(
			font,
			Vector2(20, 80),
			"Завершённые партии появятся здесь.",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			HubStyle.MUTED
		)
		return
	var values := PlayerStatsStore.graph_values(history)
	var lo: int = mini(-1, int(values.min()))
	var hi: int = maxi(1, int(values.max()))
	var area := Rect2(48, 18, maxf(1, size.x - 70), maxf(1, size.y - 52))
	var tick: int = maxi(1, int(ceil(float(hi - lo) / 8.0)))
	for value in range(lo, hi + 1):
		if value % tick != 0 and value != 0:
			continue
		var y: float = area.end.y - float(value - lo) / float(hi - lo) * area.size.y
		draw_line(
			Vector2(area.position.x, y),
			Vector2(area.end.x, y),
			Color(HubStyle.CYAN, 0.3 if value == 0 else 0.1),
			1
		)
		draw_string(font, Vector2(4, y + 5), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HubStyle.MUTED)
	var previous := Vector2(area.position.x, area.end.y - float(-lo) / float(hi - lo) * area.size.y)
	for i in range(1, values.size()):
		var point := Vector2(
			area.position.x + float(i) / history.size() * area.size.x,
			area.end.y - float(int(values[i]) - lo) / float(hi - lo) * area.size.y
		)
		var color: Color = HubStyle.CYAN if history[i - 1].won else HubStyle.PINK
		draw_line(previous, point, Color(color, 0.12), 7, true)
		draw_line(previous, point, color, 2.5, true)
		if history.size() <= 40:
			draw_circle(point, 2.5, color)
		previous = point
	draw_string(
		font, Vector2(area.position.x, size.y - 9), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HubStyle.MUTED
	)
	draw_string(
		font,
		Vector2(area.end.x - 24, size.y - 9),
		str(history.size()),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		HubStyle.MUTED
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not history.is_empty():
		var index: int = clampi(
			int(round((event.position.x - 48) / maxf(1, size.x - 70) * history.size())) - 1,
			0,
			history.size() - 1
		)
		var values := PlayerStatsStore.graph_values(history)
		tooltip_text = (
			"Партия %d · %s · баланс %+d"
			% [index + 1, "победа" if history[index].won else "поражение", int(values[index + 1])]
		)
