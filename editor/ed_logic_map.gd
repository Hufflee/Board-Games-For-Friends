extends Control
## Обзор цепочек логики: реальные размеры блоков, видимая область и прокрутка кликом/перетаскиванием.
## Модель документа не меняется; координаты берутся с уже построенного холста.

const Style := preload("res://games/custom/ui/cg_style.gd")
var scroll: ScrollContainer
var content: Control
var entries: Array[Control] = []
var _dragging := false
var _previous: Array = []

func setup(view: ScrollContainer, canvas: Control) -> void:
	scroll = view
	content = canvas
	name = "LogicMinimap"
	custom_minimum_size = Vector2(64, 96)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Обзор цепочек: нажмите или перетащите, чтобы перейти к нужной части."

func register(control: Control, selected: bool = false) -> void:
	control.set_meta("map_selected", selected)
	entries.append(control)

func _process(_delta: float) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	var snapshot: Array = [size, content.size, scroll.size, scroll.scroll_vertical]
	if snapshot != _previous:
		_previous = snapshot
		queue_redraw()
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false

func map_rect() -> Rect2:
	return Rect2(Vector2(6, 6), Vector2(maxf(1, size.x - 12), maxf(1, size.y - 12)))

func viewport_rect() -> Rect2:
	var area := map_rect()
	var bar := scroll.get_v_scroll_bar()
	var height := maxf(1, maxf(content.size.y, bar.page))
	return Rect2(area.position + Vector2(0, float(scroll.scroll_vertical) / height * area.size.y),
		Vector2(area.size.x, minf(area.size.y, maxf(4, bar.page / height * area.size.y)))).intersection(area)

func _draw() -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	draw_style_box(Style.box(Style.panel().darkened(0.06), 0), Rect2(Vector2.ZERO, size))
	var area := map_rect()
	var canvas_size := Vector2(maxf(1, content.size.x), maxf(1, content.size.y))
	for entry: Control in entries:
		if not is_instance_valid(entry):
			continue
		var offset := entry.global_position - content.global_position
		var position := area.position + offset / canvas_size * area.size
		var dimensions := entry.get_global_rect().size / canvas_size * area.size
		dimensions.y = maxf(2, dimensions.y)
		var color := Style.accent() if bool(entry.get_meta("map_selected", false)) else Style.ink().lerp(Style.panel(), 0.45)
		draw_rect(Rect2(position, dimensions).intersection(area), color)
	var visible := viewport_rect()
	draw_rect(visible, Color(Style.accent(), 0.12))
	draw_rect(visible, Style.accent(), false, 2)

func _seek(point: Vector2) -> void:
	var area := map_rect()
	var bar := scroll.get_v_scroll_bar()
	var fraction := clampf((point.y - area.position.y) / area.size.y, 0, 1)
	var height := maxf(content.size.y, bar.page)
	scroll.scroll_vertical = roundi(clampf(fraction * height - bar.page * 0.5, 0, maxf(0, bar.max_value - bar.page)))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_seek(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_seek(event.position)
		accept_event()
