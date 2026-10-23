class_name PlayPauseIcon
extends Control
## Иконка паузы/продолжения с морфом: две полоски «‖» перетекают в две половинки треугольника «▶»
## (зазор между ними закрывается) и обратно. Цвет — цвет текста кнопки. Рисуется кодом, без картинок.
## PlayPauseIcon.attach(btn, play) — иконка слева в кнопке; morph(to_play, then) — анимация, потом действие.

const SIZE := 16.0
const TIME := 0.24  # длительность морфа, с

## Две фигуры по 4 точки (доли квадрата иконки): «пауза» и «плей» (треугольник, разрезанный по x = 0.56).
const PAUSE_L := [Vector2(0.18, 0.12), Vector2(0.42, 0.12), Vector2(0.42, 0.88), Vector2(0.18, 0.88)]
const PAUSE_R := [Vector2(0.58, 0.12), Vector2(0.82, 0.12), Vector2(0.82, 0.88), Vector2(0.58, 0.88)]
const PLAY_L := [Vector2(0.2, 0.08), Vector2(0.56, 0.3), Vector2(0.56, 0.7), Vector2(0.2, 0.92)]
const PLAY_R := [Vector2(0.56, 0.3), Vector2(0.92, 0.5), Vector2(0.92, 0.5), Vector2(0.56, 0.7)]

var t := 0.0:  # 0 — «‖», 1 — «▶»
	set(v):
		t = v
		queue_redraw()
var _busy := false


## Иконка в кнопке слева от текста (место под неё — пустой icon у кнопки). play — сразу показать «▶».
static func attach(btn: Button, play: bool) -> PlayPauseIcon:
	var img := Image.create(int(SIZE), int(SIZE), false, Image.FORMAT_RGBA8)
	btn.icon = ImageTexture.create_from_image(img)  # прозрачная — только резервирует место
	var ic := PlayPauseIcon.new()
	ic.t = 1.0 if play else 0.0
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size = Vector2(SIZE, SIZE)
	btn.add_child(ic)
	btn.resized.connect(ic._place)
	ic._place.call_deferred()
	return ic


func _place() -> void:
	var b := get_parent() as Button
	if b == null:
		return
	var sb := b.get_theme_stylebox("normal")
	var left := sb.get_margin(SIDE_LEFT) if sb else 8.0
	position = Vector2(left, (b.size.y - SIZE) * 0.5).round()


## Состояние приходит от игры, в том числе после пересборки стола или внешнего снятия паузы.
func sync_state(play: bool) -> void:
	if not _busy and not is_equal_approx(t, 1.0 if play else 0.0):
		morph(play)


## Морф в «▶» (to_play) или «‖», после него — then (действие кнопки).
func morph(to_play: bool, then: Callable = Callable()) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(self, "t", 1.0 if to_play else 0.0, TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_busy = false
		if then.is_valid():
			then.call())


func _draw() -> void:
	var b := get_parent() as Button
	var col := b.get_theme_color("font_hover_color" if b.is_hovered() else "font_color") if b else Color.WHITE
	for pair in [[PAUSE_L, PLAY_L], [PAUSE_R, PLAY_R]]:
		var pts := PackedVector2Array()
		for i in 4:
			pts.append((pair[0][i] as Vector2).lerp(pair[1][i], t) * SIZE)
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.0, true)  # сглаженный край
