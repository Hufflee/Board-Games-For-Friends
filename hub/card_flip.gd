class_name CardFlip
extends Node
## Общий 2D-переворот Control: attach, flip_to/set_face/cancel и необязательное вытягивание края.
## show_side(bool) меняет только разрешённое вызывающим кодом изображение; правил/сети здесь нет.

signal flipped(face_up: bool)

var face_up := true
var target_face_up := true
var interactive_enabled := false
var can_interact: Callable
var busy := false
var dragging := false
var progress := 0.0
var _card: Control
var _show_side: Callable
var _tween: Tween
var _side := true
var _edge := 1.0
var _start := Vector2.ZERO
var _position := Vector2.ZERO
var _scale := Vector2.ONE
var _rotation := 0.0
var _pivot := Vector2.ZERO
var _animation_position := Vector2.ZERO
var _drag_distance := 48.0


static func attach(card: Control, show_side: Callable, initial_face_up: bool = true,
		manual: bool = false) -> Node:
	# Явная загрузка работает и до регистрации нового class_name в редакторском кеше.
	var flip: Node = load("res://hub/card_flip.gd").new()
	flip._card = card
	flip._show_side = show_side
	flip.face_up = initial_face_up
	flip.target_face_up = initial_face_up
	flip._side = initial_face_up
	flip.interactive_enabled = manual
	card.add_child(flip)
	card.gui_input.connect(flip._gui_input)
	show_side.call(initial_face_up)
	return flip


func set_face(up: bool) -> void:
	cancel()
	face_up = up
	target_face_up = up
	_side = up
	_show_side.call(up)


func flip_to(up: bool, duration: float = 0.48) -> void:
	if busy and target_face_up == up:
		return
	if busy:
		cancel()
	if face_up == up:
		return
	_begin(up)
	_animate(1.0, duration)


func cancel() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	if busy and is_instance_valid(_card):
		_restore()
		_show_side.call(face_up)
	_side = face_up
	target_face_up = face_up
	busy = false
	dragging = false
	progress = 0.0


func _begin(up: bool) -> void:
	_position = _card.position
	_scale = _card.scale
	_rotation = _card.rotation
	_pivot = _card.pivot_offset
	var delta := _pivot - _card.size * 0.5
	_animation_position = _position + delta - (delta * _scale).rotated(_rotation)
	_card.pivot_offset = _card.size * 0.5
	target_face_up = up
	busy = true
	progress = 0.0
	_apply(0.0)


func _apply(value: float) -> void:
	progress = value
	var width := maxf(0.015, absf(cos(PI * value)))
	var lift := sin(PI * value)
	_card.scale = _scale * Vector2(width, 1.0 + lift * 0.04)
	_card.rotation = _rotation + _edge * lift * 0.09
	_card.position = _animation_position + Vector2(-_edge * (1.0 - width) * _card.size.x * _scale.x * 0.5, -lift * 14)
	var side := target_face_up if value >= 0.5 else face_up
	if side != _side:
		_side = side
		_show_side.call(side)


func _animate(end: float, duration: float) -> void:
	_tween = create_tween()
	_tween.tween_method(_apply, progress, end, maxf(0.02, duration)).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_finish.bind(end >= 1.0))


func _finish(commit: bool) -> void:
	_restore()
	if commit:
		face_up = target_face_up
	target_face_up = face_up
	_side = face_up
	_show_side.call(face_up)
	busy = false
	dragging = false
	progress = 0.0
	if commit:
		flipped.emit(face_up)


func _restore() -> void:
	_card.position = _position
	_card.scale = _scale
	_card.rotation = _rotation
	_card.pivot_offset = _pivot


func _gui_input(event: InputEvent) -> void:
	if not interactive_enabled or (can_interact.is_valid() and not can_interact.call()):
		if dragging:
			cancel()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not busy:
			var edge_width := clampf(_card.size.x * 0.15, 8.0, 24.0)
			if event.position.x > edge_width and event.position.x < _card.size.x - edge_width:
				return
			_edge = -1.0 if event.position.x < _card.size.x * 0.5 else 1.0
			# Координаты события согласованы с GUI-вводом; опрос курсора может отставать/быть иным.
			_start = event.global_position
			_drag_distance = maxf(48.0, _card.size.x * absf(_card.get_global_transform_with_canvas().get_scale().x))
			_begin(not face_up)
			dragging = true
			_card.accept_event()
		elif not event.pressed and dragging:
			dragging = false
			_animate(1.0 if progress >= 0.5 else 0.0, 0.24)
			_card.accept_event()
	elif event is InputEventMouseMotion and dragging:
		var distance := _start.distance_to(event.global_position)
		_apply(clampf(distance / _drag_distance, 0.0, 1.0))
		_card.accept_event()


func _exit_tree() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	if busy and is_instance_valid(_card):
		_restore()
