class_name K12DieView
extends Control
## Кристалл-кубик d12: пятиугольник с числом верхней грани.

var face := 1:
	set(v):
		face = v
		queue_redraw()
var crossed := false:  # кубик отменён в сравнении
	set(v):
		crossed = v
		queue_redraw()
var highlight := Color.TRANSPARENT:
	set(v):
		highlight = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.46
	if highlight.a > 0.0:
		draw_circle(c, r * 1.12, highlight)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 5:
		var a := -PI / 2.0 + i * TAU / 5.0
		outer.append(c + Vector2(cos(a), sin(a)) * r)
		inner.append(c + Vector2(cos(a), sin(a)) * r * 0.62)
	draw_colored_polygon(outer, K12UI.CRYSTAL_DARK)
	draw_colored_polygon(inner, K12UI.CRYSTAL)
	for i in 5:
		draw_line(outer[i], inner[i], Color(1, 1, 1, 0.35), 1.5)
	var closed := outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, Color(1, 1, 1, 0.7), 2.0)
	var font := get_theme_default_font()
	var fs := int(r * 0.8)
	var txt := str(face)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, c + Vector2(-ts.x / 2.0, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if crossed:
		draw_line(c + Vector2(-r, -r), c + Vector2(r, r), K12UI.RED, 4.0)
		draw_line(c + Vector2(r, -r), c + Vector2(-r, r), K12UI.RED, 4.0)
