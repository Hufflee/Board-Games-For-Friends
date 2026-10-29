extends K12TableCard
## Карточка WS: захват из каталога начинает тот же жест, что и захват со стола.
## Escape и смена разрешения редактирования возвращают карточку без отправки действия.

signal cancelled


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if dragging and (get_tree().paused or not draggable):
		dragging = false
		z_index = 0
		cancelled.emit()


func _gui_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	super._gui_input(event)


func begin_from_catalog(at: Vector2) -> void:
	place(_to_parent(at))
	_press_pos = at
	_grab = Vector2.ZERO
	_moved = false
	dragging = true
	z_index = 100
	drag_started.emit(self)


func _input(event: InputEvent) -> void:
	if dragging and (not draggable or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		dragging = false
		z_index = 0
		cancelled.emit()
		get_viewport().set_input_as_handled()
		return
	super._input(event)
