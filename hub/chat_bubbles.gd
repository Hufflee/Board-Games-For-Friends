class_name ChatBubbles
extends Control
## Всплывающее окошко с репликой / сообщением чата для столов без табличек игроков.
## Одно окошко за раз: новое сообщение быстро гасит прежнее и появляется на его месте —
## окошки не наслаиваются друг на друга.
## make_bubble(text: String) -> Control — оформление в стиле игры.

var make_bubble: Callable
var anchor := Vector2(-270, 120)  # от правого верхнего угла родителя
var _current: Control
var _queue: Array = []
var _busy := false


static func attach(parent: Control, maker: Callable, at: Vector2 = Vector2(-270, 120)) -> ChatBubbles:
	var c := ChatBubbles.new()
	c.make_bubble = maker
	c.anchor = at
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 60
	parent.add_child(c)
	return c


func _ready() -> void:
	Net.chat_received.connect(_on_chat)


func _on_chat(entry: Dictionary) -> void:
	if entry.get("kind", "") == "system" or not is_visible_in_tree() or not Net.chat_entry_visible(entry):
		return
	_queue.append("%s: %s" % [entry.get("name", ""), str(entry.get("text", "")).left(60)])
	if _queue.size() > 3:
		_queue.pop_front()  # пишут очень быстро — показываем последние
	_next()


func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	if is_instance_valid(_current):
		# прежнее окошко быстро гаснет, потом появляется новое
		var old := _current
		_current = null
		var f := old.create_tween()
		f.tween_property(old, "modulate:a", 0.0, 0.12)
		f.tween_callback(old.queue_free)
		# ждём таймером, а не концом анимации: окошко могло само догаснуть и удалиться —
		# тогда его анимация не закончится никогда и окошки перестанут появляться
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree():
			_busy = false
			return
	var b: Control = make_bubble.call(_queue.pop_front())
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	b.reset_size()
	b.position = Vector2(size.x + anchor.x, anchor.y)
	b.pivot_offset = b.size * 0.5
	b.scale = Vector2.ONE * 0.5
	_current = b
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_busy = false
	if not _queue.is_empty():
		await get_tree().create_timer(0.7).timeout  # каждое окошко видно хотя бы мгновение
		if is_inside_tree():
			_next()
		return
	t.tween_interval(3.2)
	t.tween_property(b, "modulate:a", 0.0, 0.4)
	t.tween_callback(func():
		if _current == b:
			_current = null
		b.queue_free())
