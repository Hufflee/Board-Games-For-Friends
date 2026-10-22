class_name PerudoPirateDecor
extends Control
## Пиратские рисунки поверх стола «Перудо»: роза ветров, пунктир маршрута с крестиком «клад здесь»,
## надпись на карте, фонари по углам (мерцают) и пиратский флаг.

const INK := Color(0.28, 0.16, 0.07, 0.55)
const FONT := "res://games/perudo/art/fonts/Underdog-Regular.ttf"

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(FONT)
	return _font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, K12Tavern.TABLE_Y)
	var r := K12Tavern.TABLE_RADII - Vector2.ONE * (K12Tavern.RIM + K12Tavern.LEATHER)
	var t := Time.get_ticks_msec() / 1000.0
	# роза ветров — справа на карте
	_compass(c + Vector2(r.x * 0.62, -r.y * 0.38), 46.0)
	# пунктир маршрута и крестик — слева
	var pts := PackedVector2Array()
	for i in 40:
		var k := i / 39.0
		pts.append(c + Vector2(-r.x * 0.78 + k * r.x * 0.42, r.y * 0.25 - sin(k * PI * 1.6) * 60.0 - k * 40.0))
	for i in range(0, pts.size() - 1, 2):
		draw_line(pts[i], pts[i + 1], INK, 2.5, true)
	var x := pts[pts.size() - 1]
	draw_line(x - Vector2(10, 10), x + Vector2(10, 10), Color(0.6, 0.12, 0.08, 0.75), 4.0, true)
	draw_line(x - Vector2(10, -10), x + Vector2(10, -10), Color(0.6, 0.12, 0.08, 0.75), 4.0, true)
	draw_string(font(), c + Vector2(-r.x * 0.82, r.y * 0.5), "Здесь водятся лжецы", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	# фонари по нижним углам: тёплое мерцающее пятно
	for side in [-1.0, 1.0]:
		var p := Vector2(size.x / 2.0 + side * (size.x / 2.0 - 70.0), size.y - 70.0)
		var f := 0.8 + 0.12 * sin(t * 7.0 + side) + 0.08 * sin(t * 13.0)
		for k in 6:
			draw_circle(p, 90.0 - k * 14.0, Color(1.0, 0.65, 0.25, 0.035 * f))
		draw_rect(Rect2(p - Vector2(12, 18), Vector2(24, 34)), Color(0.12, 0.08, 0.05))
		draw_rect(Rect2(p - Vector2(8, 12), Vector2(16, 22)), Color(1.0, 0.75, 0.35, 0.85 * f))
		draw_line(p + Vector2(0, -18), p + Vector2(0, -30), Color(0.12, 0.08, 0.05), 3.0)
	# пиратский флаг в левом нижнем углу над фонарём
	var fp := Vector2(36, size.y - 220)
	draw_line(fp, fp + Vector2(0, 110), Color(0.25, 0.17, 0.1), 4.0)
	var wave := sin(t * 2.0) * 4.0
	var flag := PackedVector2Array([fp, fp + Vector2(70, wave), fp + Vector2(70, 46 + wave), fp + Vector2(0, 46)])
	draw_colored_polygon(flag, Color(0.06, 0.06, 0.07))
	var sc := fp + Vector2(35, 20 + wave * 0.5)
	draw_circle(sc, 9, Color(0.92, 0.9, 0.85))
	draw_circle(sc + Vector2(-3, -1), 2.2, Color(0.06, 0.06, 0.07))
	draw_circle(sc + Vector2(3, -1), 2.2, Color(0.06, 0.06, 0.07))
	draw_line(sc + Vector2(-14, 10), sc + Vector2(14, 20), Color(0.92, 0.9, 0.85), 3.0)
	draw_line(sc + Vector2(-14, 20), sc + Vector2(14, 10), Color(0.92, 0.9, 0.85), 3.0)


func _compass(p: Vector2, r: float) -> void:
	draw_arc(p, r, 0, TAU, 48, INK, 2.0, true)
	draw_arc(p, r * 0.82, 0, TAU, 48, INK, 1.0, true)
	for i in 8:
		var a := -PI / 2.0 + i * TAU / 8.0
		var len := r * (1.15 if i % 2 == 0 else 0.7)
		var tip := p + Vector2(cos(a), sin(a)) * len
		var side := Vector2(cos(a + PI / 2.0), sin(a + PI / 2.0)) * r * 0.12
		draw_colored_polygon(PackedVector2Array([p + side, tip, p - side]), Color(INK, 0.7 if i % 2 == 0 else 0.4))
	draw_string(font(), p + Vector2(-7, -r * 1.2 - 4), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
