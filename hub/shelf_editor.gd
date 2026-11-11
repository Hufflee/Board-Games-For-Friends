extends Control
## Панель личного редактора шкафа; геометрия меняется через проверяемые запросы NeonRoom.
var room: Node
var _values: Dictionary = {}
var _message: Label
var _zoom: HSlider
var _zoom_label: Label
var _undo: Button
var _ball: Button  # мяч в комнате: вкл / выкл

const RoomIcons := preload("res://hub/room_icons.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := HubStyle.panel(HubStyle.CYAN)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -310
	panel.offset_right = -16
	panel.offset_top = 82
	add_child(panel)
	var col := HubStyle.vbox(12)
	col.custom_minimum_size.x = 264
	panel.add_child(col)
	col.add_child(HubStyle.neon_label("РЕДАКТОР ШКАФА", 20, HubStyle.CYAN))
	for spec in [
		["rows", "Ряды", 1, 8, 1],
		["cols", "Столбцы", 1, 6, 1],
		["width", "Ширина ячейки", 20, int(ShelfConfig.MAX_WIDTH * 100), 1],
		["height", "Высота ячейки", 14, 70, 1]
	]:
		var row := HubStyle.hbox(8)
		col.add_child(row)
		var label := HubStyle.label(str(spec[1]), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = float(spec[2])
		spin.max_value = float(spec[3])
		spin.step = float(spec[4])
		spin.custom_minimum_size.x = 106
		if spec[0] in ["width", "height"]:
			spin.suffix = "см"
		row.add_child(spin)
		_values[str(spec[0])] = spin
		spin.value_changed.connect(func(_value): _change())
	var zoom_row := HubStyle.hbox(8)
	col.add_child(zoom_row)
	zoom_row.add_child(HubStyle.label("Камера", 14))
	_zoom = HSlider.new()
	_zoom.min_value = Prefs.SHELF_ZOOM_MIN
	_zoom.max_value = Prefs.SHELF_ZOOM_MAX
	_zoom.step = 0.05
	_zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom.tooltip_text = "Приближение комнаты. Можно также прокрутить колесо над комнатой."
	zoom_row.add_child(_zoom)
	_zoom_label = HubStyle.label("", 14)
	_zoom_label.custom_minimum_size.x = 44
	zoom_row.add_child(_zoom_label)
	_zoom.value_changed.connect(func(value: float):
		room.set_shelf_camera_zoom(value)
		sync_zoom())
	sync_zoom()
	# Управление предметами комнаты слева, параметры шкафа справа.
	var props := HubStyle.vbox(8)
	props.name = "EditorRoomTools"
	props.position = Vector2(16, 82)
	add_child(props)
	var add_poster := _icon_button("Повесить плакат с картинкой по умолчанию", func(b: Button): RoomIcons.poster(b, HubStyle.TEXT))
	add_poster.name = "EditorAddPoster"
	add_poster.pressed.connect(func(): room.emit_signal("poster_add_requested"))
	props.add_child(add_poster)
	_ball = _icon_button("", func(b: Button): RoomIcons.ball(b, HubStyle.TEXT if bool(room.get("ball_on")) else HubStyle.MUTED, bool(room.get("ball_on"))))
	_ball.name = "EditorBall"
	_ball.pressed.connect(func():
		room.call("set_ball_enabled", not bool(room.get("ball_on")))
		_sync_ball())
	props.add_child(_ball)
	var add_board := _icon_button("Повесить ещё одну доску друзей", func(b: Button): RoomIcons.board(b, HubStyle.TEXT))
	add_board.name = "EditorAddBoard"
	add_board.pressed.connect(func(): room.call("add_friend_board"))
	props.add_child(add_board)
	var basket := _icon_button("Повесить мини-корзину для мяча", func(b: Button): RoomIcons.basket(b, HubStyle.TEXT))
	basket.name = "EditorAddBasket"
	basket.pressed.connect(func(): room.call("add_room_basket"))
	props.add_child(basket)
	_sync_ball()
	var help := (
		HubStyle
		. label(
			"Тяните рёбра: перегородка меняет ширину ящиков своего ряда, полка — высоту рядов, края шкафа — всё. Правый клик по перегородке или куску полки убирает его (два ящика → один), правый клик внутри ящика ставит перегородку, пунктир — вернуть полку.",
			14,
			HubStyle.MUTED
		)
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(help)
	_message = HubStyle.label("", 14, HubStyle.YELLOW)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_message)
	_undo = HubStyle.button("↶ Отменить изменение (Ctrl+Z)", 14)
	_undo.tooltip_text = "Вернуть шкаф на шаг назад: перестановку, поворот коробки, размер ящиков"
	_undo.pressed.connect(func(): room.undo_shelf_edit())
	col.add_child(_undo)
	var done := HubStyle.button("Готово", 16)
	done.pressed.connect(func(): room.finish_shelf_editor(true))
	col.add_child(done)
	var cancel := HubStyle.button("Отмена", 14)
	cancel.pressed.connect(func(): room.finish_shelf_editor(false))
	col.add_child(cancel)
	sync()


func _process(_delta: float) -> void:
	if is_instance_valid(_undo) and is_instance_valid(room):
		_undo.disabled = not bool(room.call("can_undo_shelf"))


func _icon_button(tooltip: String, paint: Callable) -> Button:
	var button := HubStyle.button("", 14)
	button.theme = HubStyle.theme()
	button.custom_minimum_size = Vector2(52, 44)
	button.tooltip_text = tooltip
	button.draw.connect(func(): paint.call(button))
	return button


func _sync_ball() -> void:
	var on := bool(room.get("ball_on"))
	_ball.tooltip_text = "Мяч-попрыгун в комнате: включён — нажмите, чтобы убрать" if on else "Мяч-попрыгун убран — нажмите, чтобы вернуть"
	_ball.queue_redraw()


func sync_zoom() -> void:
	_zoom.set_value_no_signal(Prefs.shelf_camera_zoom)
	_zoom_label.text = "%d%%" % roundi(Prefs.shelf_camera_zoom * 100)


func sync(message: String = "") -> void:
	var geometry: Dictionary = room.get("_cabinet")
	for key in _values:
		(_values[key] as SpinBox).set_value_no_signal(
			float(geometry[key]) * (100.0 if key in ["width", "height"] else 1.0)
		)
	_message.text = message


func _change() -> void:
	var geometry: Dictionary = (room.get("_cabinet") as Dictionary).duplicate(true)
	# Число в поле «Ширина / Высота ячейки» — для всех ячеек сразу (свои размеры ящиков сбрасываются).
	var current: Dictionary = room.get("_cabinet")
	if absf(float((_values["width"] as SpinBox).value) / 100.0 - float(current.width)) > 0.006 or int((_values["cols"] as SpinBox).value) != int(current.cols) or int((_values["rows"] as SpinBox).value) != int(current.rows):
		geometry.erase("col_widths")
		geometry.erase("cells")  # число рядов / столбцов / ширина — снова обычная сетка
	if absf(float((_values["height"] as SpinBox).value) / 100.0 - float(current.height)) > 0.006 or int((_values["rows"] as SpinBox).value) != int(current.rows):
		geometry.erase("row_heights")
	for key in _values:
		geometry[key] = (
			float((_values[key] as SpinBox).value) / (100.0 if key in ["width", "height"] else 1.0)
		)
	geometry.rows = int(geometry.rows)
	geometry.cols = int(geometry.cols)
	var message: String = room.request_shelf_geometry(geometry)
	sync(message)
