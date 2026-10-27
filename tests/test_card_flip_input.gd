extends SceneTree
## Отдельное наблюдение настоящих GUI MouseEvent и координат жеста, без NH/сети.
var flip: Node
var card: Control
var shown := true
var down := false

func _initialize() -> void:
	_run.call_deferred()

func send(at: Vector2, button: int = -1) -> void:
	if button < 0:
		var event := InputEventMouseMotion.new()
		event.position = at
		event.global_position = at
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)
	else:
		down = button == 1
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	card = ColorRect.new()
	card.position = Vector2(40, 80)
	card.size = Vector2(120, 150)
	root.add_child(card)
	flip = load("res://hub/card_flip.gd").attach(card, func(up: bool): shown = up, true, true)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouse:
			print("EDGE EVENT ", event.get_class(), " event.global=", event.global_position,
				" polled=", card.get_global_mouse_position(), " progress=", flip.progress, " dragging=", flip.dragging))
	await process_frame
	await send(Vector2(158, 120))
	await send(Vector2(158, 120), 1)
	var grabbed: bool = flip.dragging
	await send(Vector2(70, 120))
	var passed_middle: bool = flip.progress >= 0.5
	await send(Vector2(70, 120), 0)
	await create_timer(0.4).timeout
	var completed: bool = not shown and not flip.busy
	print("EDGE INPUT: захват=", grabbed, " середина=", passed_middle, " завершён=", completed)
	await root.get_node("Sfx").request_quit(0 if grabbed and passed_middle and completed else 1)
