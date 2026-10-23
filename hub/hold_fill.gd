class_name HoldFill
extends Control
## Заливка кнопки «зажми и держи» (LeaveGuard.hold): пока кнопку держат, слева направо растёт заливка
## в форме самой кнопки (маска — её же стиль, скругления совпадают), с мягким бликом на переднем краю.
## Заполнилась — короткая вспышка и действие. Отпустили раньше — заливка быстро стекает, а под кнопкой
## на секунду всплывает подсказка «Удерживайте кнопку» (кнопка не меняет размер). Цвет — «опасный» цвет наведения из темы игры.

const DRAIN := 3.5  # во сколько раз стекает быстрее, чем набирается

var on_done: Callable
var progress := 0.0  # 0…1, линейно по времени удержания
var _holding := false
var _done := false
var _flash := 0.0  # вспышка после срабатывания 1 → 0
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _btn() -> Button:
	return get_parent() as Button


func start() -> void:
	if _done:
		return
	_holding = true
	set_process(true)
	Sfx.play("hover", -10, 0.05, 0.05)


func stop() -> void:
	if not _holding:
		return
	_holding = false
	# короткое нажатие — подсказать, что кнопку надо держать
	if progress < 0.35 and not _done:
		_show_hint()


func _show_hint() -> void:
	var b := _btn()
	if is_instance_valid(_hint):
		_hint.queue_free()
	_hint = Label.new()
	_hint.text = "Удерживайте кнопку"
	_hint.top_level = true
	_hint.z_index = 100
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", b.get_theme_color("font_hover_color"))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)
	_hint.reset_size()
	# под кнопкой, по её центру; у нижнего края экрана — над ней
	var gp := b.global_position
	var y := gp.y + b.size.y + 4.0
	if y + _hint.size.y > get_viewport_rect().size.y - 4.0:
		y = gp.y - _hint.size.y - 4.0
	var x := clampf(gp.x + (b.size.x - _hint.size.x) * 0.5, 4.0, get_viewport_rect().size.x - _hint.size.x - 4.0)
	_hint.global_position = Vector2(x, y - 4.0)
	_hint.modulate.a = 0.0
	var h := _hint
	var tw := h.create_tween()
	tw.tween_property(h, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(h, "global_position:y", y, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(h, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(h.queue_free)


func _process(delta: float) -> void:
	var t := LeaveGuard.HOLD_TIME
	if _holding and not _done:
		progress = minf(1.0, progress + delta / t)
		if progress >= 1.0:
			_done = true
			_holding = false
			_flash = 1.0
			Sfx.play("click", -4)
			# действие — после кадра со вспышкой, чтобы заливку было видно целиком
			(func():
				if on_done.is_valid():
					on_done.call()).call_deferred()
	elif not _done:
		progress = maxf(0.0, progress - delta * DRAIN / t)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		if _flash == 0.0:
			_done = false
			progress = 0.0
	queue_redraw()
	if not _holding and progress <= 0.0 and _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	var b := _btn()
	if b == null or (progress <= 0.0 and _flash <= 0.0):
		return
	var col := b.get_theme_color("font_hover_color")
	# плавный ход: в начале чуть медленнее, к концу — увереннее (сглаженная кривая, без отскока)
	var k := progress * progress * (3.0 - 2.0 * progress)
	var w := size.x * (1.0 if _flash > 0.0 else k)
	var sb := b.get_theme_stylebox("normal")
	var rad := 6.0
	if sb is StyleBoxFlat:
		rad = float((sb as StyleBoxFlat).corner_radius_top_left)
	var shape := StyleBoxFlat.new()
	shape.set_corner_radius_all(int(rad))
	shape.bg_color = Color(col, 0.32 + 0.25 * _flash)
	shape.anti_aliasing = true
	# заливка: прямоугольник формы кнопки, обрезанный по ширине (draw_style_box в узкую рамку сохраняет скругления)
	var r := Rect2(Vector2.ZERO, Vector2(maxf(w, rad * 2.0), size.y))
	if w < rad * 2.0:
		shape.bg_color.a *= w / (rad * 2.0)
	draw_style_box(shape, r)
	# блик на переднем краю заливки
	if _flash <= 0.0 and progress > 0.02 and progress < 1.0:
		var x := r.end.x
		for i in 6:
			var a := 0.16 * (1.0 - i / 6.0)
			draw_rect(Rect2(x - 2.0 - i * 2.0, 2.0, 2.0, size.y - 4.0), Color(1, 1, 1, a))
