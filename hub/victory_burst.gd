extends Control
## Рисованная победная вспышка: геометрия наклейки, объём, лампочки и искры.
## Одиночный, командный и многострочный финал. PNG не используется; акцент игры сохраняется.

const Aura := preload("res://hub/victory_burst.gdshader")
const GOLD := Color("efb52f")
const SINGLE_FIT := 0.78  # Запас до подписи участников даже на пике отскока 1.08.
var preview_time := -1.0  # Стенд может закрепить конкретный момент появления.
var _elapsed := 0.0
var _accent := GOLD
var _dark := false
var _center := Vector2.ZERO
var _outline := PackedVector2Array()
var _extent := Vector2.ZERO
var _highlight: Array[PackedVector2Array] = []
var _shade: Array[PackedVector2Array] = []
var _aura: ColorRect
var _material: ShaderMaterial
var _motion_was := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aura = ColorRect.new()
	_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = Aura
	_aura.material = _material
	# Свечение рисуется под собственным контуром и не затрагивает соседние слои UI.
	_aura.show_behind_parent = true
	add_child(_aura)


func configure(points: PackedVector2Array, center: Vector2, accent: Color, dark: bool) -> void:
	_center = center
	_accent = accent
	_dark = dark
	_outline.clear()
	_extent = Vector2.ZERO
	# Неровность задаётся геометрией, не шумом/текстурой; одинаковая при каждом открытии.
	for i: int in points.size():
		var relative := points[i] - center
		var wobble := 1.0 + 0.004 * sin(i * 2.3) + 0.003 * cos(i * 4.1)
		_outline.append(relative * wobble)
		_extent = _extent.max((relative * wobble).abs())
	var below := PackedVector2Array()
	var above := PackedVector2Array()
	for point: Vector2 in _outline:
		below.append(point + Vector2(0, 10))
		above.append(point - Vector2(0, 8))
	_highlight = Geometry2D.clip_polygons(_outline, below)
	_shade = Geometry2D.clip_polygons(_outline, above)
	queue_redraw()


func restart() -> void:
	_elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if Prefs.parallax:
		_elapsed += delta
	if Prefs.parallax or _motion_was != Prefs.parallax:
		queue_redraw()
	_motion_was = Prefs.parallax


func _appearance(time: float) -> float:
	if not Prefs.parallax:
		return 1.0
	if time < 0.3:
		return lerpf(0.6, 1.08, 1.0 - pow(1.0 - clampf(time / 0.3, 0, 1), 3))
	return lerpf(1.08, 1.0, 1.0 - pow(1.0 - clampf((time - 0.3) / 0.2, 0, 1), 2))


func _shape(scale_value: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in _outline:
		points.append(_center + point * scale_value + shift)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result


func _draw() -> void:
	if _outline.is_empty() or not is_instance_valid(_aura):
		return
	var time := preview_time if preview_time >= 0.0 else _elapsed
	var movement := Prefs.parallax
	var pop := _appearance(time)
	var reveal := smoothstep(0.14, 0.65, time) if movement else 1.0
	_material.set_shader_parameter("accent", _accent)
	_material.set_shader_parameter("gold", GOLD)
	_material.set_shader_parameter("elapsed", time if movement else 0.0)
	_material.set_shader_parameter("reveal", reveal)
	_material.set_shader_parameter("warmth", 0.26 if _dark else 0.10)
	var area := get_parent_control().size
	var aura_half := Vector2(368, 228)
	if _extent.x > 240:
		aura_half.x = minf(area.x * 0.5 - 8, _extent.x * 1.2 + 16)
	_aura.position = _center - aura_half
	_aura.size = aura_half * 2
	var face := GOLD.lerp(_accent, 0.38)
	face.s = clampf(face.s * 1.15, 0.5, 0.86)
	face.v = 0.92 if _dark else 0.82
	var edge := _accent.lerp(GOLD, 0.35).darkened(0.46 if not _dark else 0.35)
	var back := _accent.lerp(GOLD, 0.24).darkened(0.26)
	# Две вырезанные звезды со сдвигом: насыщенный нижний слой и светлая лицевая часть.
	draw_colored_polygon(_shape(pop * 1.025, Vector2(1, 10) * pop), Color(edge, 0.3))
	draw_colored_polygon(_shape(pop, Vector2(0, 7) * pop), back)
	draw_polyline(_closed(_shape(pop, Vector2(0, 7) * pop)), edge, 2.5, true)
	draw_colored_polygon(_shape(pop * 0.975, Vector2(0, -3) * pop), face)
	draw_set_transform(_center + Vector2(0, -3) * pop, 0, Vector2.ONE * pop * 0.975)
	for band: PackedVector2Array in _highlight:
		draw_colored_polygon(band, face.lightened(0.22))
	for band: PackedVector2Array in _shade:
		draw_colored_polygon(band, face.darkened(0.12))
	draw_set_transform(Vector2.ZERO)
	# Светлый серп по верхней кромке, тень по нижней — плоские рисованные слои.
	for i: int in _outline.size():
		var a: Vector2 = _outline[i]
		var b: Vector2 = _outline[(i + 1) % _outline.size()]
		var start := _center + a * pop * 0.972 + Vector2(0, -3) * pop
		var end := _center + b * pop * 0.972 + Vector2(0, -3) * pop
		if a.y < -18 and b.y < -18:
			draw_line(start, end, face.lightened(0.40), 5.5 * pop, true)
		if a.y > 18 and b.y > 18:
			draw_line(start, end, back.darkened(0.05), 6.5 * pop, true)
	draw_polyline(_closed(_shape(pop * 0.975, Vector2(0, -3) * pop)), Color(edge, 0.8), 1.6, true)
	# Одно кольцо лампочек по краю: спокойный центр остаётся портрету и нику.
	for i: int in 36:
		var angle := TAU * i / 36.0
		var point := _center + Vector2(cos(angle) * _extent.x * 0.835, sin(angle) * _extent.y * 0.736) * pop
		var lamp := face.lightened(0.62) if i % 3 != 0 else GOLD.lightened(0.18)
		draw_circle(point + Vector2(0, 1.5), 2.6 * pop, Color(edge, 0.5))
		draw_circle(point, 2.1 * pop, lamp)
	# Восемь четырёхлучевых искр за пределами портрета, мерцающих по очереди.
	var places := [Vector2(-310, -36), Vector2(-245, -145), Vector2(-110, -193), Vector2(142, -186),
		Vector2(300, -83), Vector2(305, 89), Vector2(210, 169), Vector2(-270, 130)]
	for i: int in places.size():
		var pulse := 0.6 + 0.4 * sin(time * 2.6 - i * 0.9) if movement else 0.85
		var radius := (6.0 + (i % 3) * 2.0) * pulse
		var spread := Vector2.ONE if _extent.x < 240 else _extent / Vector2(280 * SINGLE_FIT, 174 * SINGLE_FIT)
		var center: Vector2 = _center + places[i] * spread
		center.x = clampf(center.x, 16, area.x - 16)
		center.y = clampf(center.y, 64, area.y - 72)
		var spark := PackedVector2Array()
		for j: int in 8:
			var angle := j * TAU / 8.0 - PI / 2
			var r := radius if j % 2 == 0 else radius * 0.23
			spark.append(center + Vector2(cos(angle), sin(angle)) * r)
		draw_colored_polygon(spark, Color(GOLD.lightened(0.35), reveal * pulse))
