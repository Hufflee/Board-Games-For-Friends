class_name STInkBox
extends StyleBox
## Рисованная плашка «Стиллиона» (кнопки, панели, поля): заливка с бумажным зерном, чуть неровный
## чернильный контур «от руки», жёсткая тень со сдвигом и (по желанию) блик сверху, как у мультяшной кнопки.
## Создаётся через STStyle.box(); свойства названы как у StyleBoxFlat, чтобы код таблиц не менялся.

const GRAIN := "res://games/stillion/art/ui_grain.png"
const STEP := 10.0  # шаг точек контура, px

var bg_color := Color.WHITE
var border_color := Color.BLACK
var border_width := 3
var corner_radius := 12
var shadow_color := Color(0, 0, 0, 0.85)
var shadow_offset := Vector2(4, 4)
var gloss := false  # блик у верхнего края (главные и выбранные кнопки)
var wobble := 1.1  # насколько «гуляет» линия, px

static var _grain: Texture2D


func set_border_width_all(w: int) -> void:
	border_width = w


func set_corner_radius_all(r: int) -> void:
	corner_radius = r


func _draw(ci: RID, rect: Rect2) -> void:
	var outline := _shape(rect, wobble)
	if shadow_offset != Vector2.ZERO and shadow_color.a > 0.0:
		var sh := PackedVector2Array()
		for p in outline:
			sh.append(p + shadow_offset)
		RenderingServer.canvas_item_add_polygon(ci, sh, PackedColorArray([shadow_color]))
	if bg_color.a > 0.0:
		if _grain == null and ResourceLoader.exists(GRAIN):
			_grain = load(GRAIN)
		if _grain:
			# зерно бумаги: текстура почти белая, заливка её подкрашивает
			RenderingServer.canvas_item_set_default_texture_repeat(ci, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
			var uvs := PackedVector2Array()
			for p in outline:
				uvs.append(p / 256.0)
			RenderingServer.canvas_item_add_polygon(ci, outline, PackedColorArray([bg_color]), uvs, _grain.get_rid())
		else:
			RenderingServer.canvas_item_add_polygon(ci, outline, PackedColorArray([bg_color]))
	if gloss:
		_draw_gloss(ci, rect)
	if border_width > 0 and border_color.a > 0.0:
		var closed := outline.duplicate()
		closed.append(outline[0])
		RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([border_color]), float(border_width), true)


## Блик: светлая дуга вдоль верхнего края и точка у левого угла.
func _draw_gloss(ci: RID, rect: Rect2) -> void:
	var r := minf(float(corner_radius), rect.size.y * 0.5)
	var inset := float(border_width) + 3.0
	var y := rect.position.y + inset + 1.0
	var x0 := rect.position.x + r + inset
	var x1 := rect.end.x - r - inset - rect.size.x * 0.18
	if x1 - x0 < 12.0:
		return
	var col := Color(1, 1, 1, 0.38)
	var pts := PackedVector2Array([Vector2(x0, y + 2.0), Vector2(x0 + 6.0, y), Vector2(x1, y)])
	RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([col]), 3.0, true)
	RenderingServer.canvas_item_add_circle(ci, Vector2(x1 + 9.0, y), 2.0, col)


## Контур скруглённого прямоугольника, точки сдвинуты по нормали детерминированным «шумом»
## (зависит от размера, не от позиции — при прокрутке линия не дрожит).
func _shape(rect: Rect2, amp: float) -> PackedVector2Array:
	var r := clampf(float(corner_radius), 0.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
	amp = minf(amp, minf(rect.size.x, rect.size.y) * 0.04)  # мелкие плашки — ровнее, иначе контур самопересекается
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	var sd := rect.size.x * 0.137 + rect.size.y * 0.311
	var k := 0
	for ci in 4:
		var c: Vector2 = corners[ci][0]
		var a0: float = corners[ci][1]
		var prev_c: Vector2 = corners[(ci + 3) % 4][0]
		var prev_end := prev_c + Vector2.from_angle(a0) * r
		var start := c + Vector2.from_angle(a0) * r
		# прямой участок до угла
		var seg := start - prev_end
		var n := int(seg.length() / STEP) if seg.length() >= 1.0 else 0
		if seg.length() >= 1.0:
			n = maxi(1, n)
		var normal := Vector2.from_angle(a0)
		for i in n:
			var p := prev_end + seg * (float(i) / n)
			pts.append(p + normal * _noise(sd, k) * amp)
			k += 1
		# дуга угла
		var arc_n := maxi(2, int(r / 3.0))
		for i in arc_n:  # последняя точка дуги — начало следующего участка
			var a := a0 + PI * 0.5 * float(i) / arc_n
			var p := c + Vector2.from_angle(a) * r
			pts.append(p + Vector2.from_angle(a) * _noise(sd, k) * amp)
			k += 1
	return pts


static func _noise(sd: float, i: int) -> float:
	return sin(sd + i * 1.71) * 0.6 + sin(sd * 1.3 + i * 0.53) * 0.4
