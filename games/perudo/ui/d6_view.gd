class_name PerudoDie
extends Control
## Кость d6: по умолчанию цвета слоновой кости, а в партии — цвета стакана своего игрока (белые точки).
## Единица (джокер) — звезда вместо точки.

var value := 1:
	set(v):
		value = v
		queue_redraw()
var highlight := Color.TRANSPARENT:  # подсветка совпавших при вскрытии
	set(v):
		highlight = v
		queue_redraw()
var color := Color("f3ead2"):  # слоновая кость — нейтральная кость
	set(v):
		color = v
		queue_redraw()
var star_one := true  # единица — звезда (джокер Перудо); в других играх — обычная точка
var sides := 6:
	set(v):
		sides = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()

const PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
}


func _init(v: int = 1, side: float = 40.0, body: Color = Color("f3ead2")) -> void:
	value = v
	color = body
	custom_minimum_size = Vector2(side, side)
	size = Vector2(side, side)
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	if sides == 8:
		_draw_d8(s)
		return
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	if highlight.a > 0.0:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(highlight, 0.0)
		glow.set_corner_radius_all(int(s * 0.25))
		glow.shadow_color = highlight
		glow.shadow_size = int(s * 0.22)
		draw_style_box(glow, r)
	var sb := StyleBoxFlat.new()
	var ivory := color == Color("f3ead2")
	sb.bg_color = color if not dim else color.darkened(0.45)
	sb.set_corner_radius_all(int(s * 0.2))
	sb.border_color = color.darkened(0.25)
	sb.set_border_width_all(maxi(1, int(s * 0.04)))
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = int(s * 0.08)
	sb.shadow_offset = Vector2(0, s * 0.05)
	draw_style_box(sb, r)
	# лёгкий блик сверху
	draw_rect(Rect2(s * 0.15, s * 0.08, s * 0.7, s * 0.12), Color(1, 1, 1, 0.25))
	# точки: на слоновой кости — бордовые, на цветных — белые (на светлых — тёмные)
	var pip := Color("7a1414") if ivory else (Color("1b1b1b") if color.get_luminance() > 0.62 else Color.WHITE)
	if dim:
		pip = pip.darkened(0.5)
	if value == 1 and star_one:
		_star(Vector2(s, s) * 0.5, s * 0.3, (Color("d4a017") if ivory else pip) if not dim else Color("6d5a25"))
		return
	for p in PIPS.get(value, []):
		draw_circle(p * s, s * 0.085, pip)

## Числовой D8 использует ту же2D-механику TossDie, без отдельной физики.
func _draw_d8(side: float) -> void:
	var points := PackedVector2Array([Vector2(side * 0.5, 2), Vector2(side - 2, side * 0.5), Vector2(side * 0.5, side - 2), Vector2(2, side * 0.5)])
	var body := color.darkened(0.45) if dim else color
	var shadow := points.duplicate()
	for index in shadow.size():
		shadow[index].y += side * 0.05
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	draw_colored_polygon(points, body)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, body.darkened(0.3), 2, true)
	draw_line(points[0], Vector2(side * 0.5, side * 0.76), body.darkened(0.2), 1, true)
	draw_line(points[1], Vector2(side * 0.5, side * 0.76), body.darkened(0.2), 1, true)
	draw_line(points[3], Vector2(side * 0.5, side * 0.76), body.darkened(0.2), 1, true)
	var font := ThemeDB.fallback_font
	var font_size := int(side * 0.34)
	var text := str(value)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((side - width) * 0.5, side * 0.64), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("7a1414"))


func _star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color("7a5a10"), 1.2, true)
