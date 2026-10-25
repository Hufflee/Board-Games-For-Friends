extends Control
## Сердечки текущего здоровья: максимум десять значков, число рядом остаётся точным.
var current := 0
var maximum := 0


func _init(hp: int = 0, max_hp: int = 0) -> void:
	current = maxi(0, hp)
	maximum = maxi(current, max_hp)
	custom_minimum_size = Vector2(100, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "Здоровье: %d / %d" % [current, maximum]
	resized.connect(queue_redraw)


func _draw() -> void:
	var slots := mini(maximum, 10)
	var step := minf(16.0, maxf(10.0, (size.x - 40.0) / maxf(1.0, slots)))
	for i in slots:
		var points := PackedVector2Array(
			[
				Vector2(0, 4),
				Vector2(3, 1),
				Vector2(6, 3),
				Vector2(9, 1),
				Vector2(12, 4),
				Vector2(12, 7),
				Vector2(6, 13),
				Vector2(0, 7)
			]
		)
		for k in points.size():
			points[k] += Vector2(i * step, 1)
		var color := Color("d75e58") if i < current else Color(FSStyle.ink(), 0.15)
		draw_colored_polygon(points, color)
		draw_polyline(points + PackedVector2Array([points[0]]), Color(FSStyle.ink(), 0.45), 1, true)
	var label := "%d/%d" % [current, maximum]
	draw_string(
		FSStyle.font(), Vector2(slots * step + 4, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FSStyle.ink()
	)
