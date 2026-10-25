extends Control
## Панель личного редактора шкафа; геометрия меняется через проверяемые запросы NeonRoom.
var room: Node
var _values: Dictionary = {}
var _message: Label


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
	var help := (
		HubStyle
		. label(
			"Потяните за боковое ребро шкафа, чтобы изменить ширину всех столбцов. За горизонтальное ребро — высоту всех полок.",
			14,
			HubStyle.MUTED
		)
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(help)
	_message = HubStyle.label("", 14, HubStyle.YELLOW)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_message)
	var done := HubStyle.button("Готово", 16)
	done.pressed.connect(func(): room.finish_shelf_editor(true))
	col.add_child(done)
	var cancel := HubStyle.button("Отмена", 14)
	cancel.pressed.connect(func(): room.finish_shelf_editor(false))
	col.add_child(cancel)
	sync()


func sync(message: String = "") -> void:
	var geometry: Dictionary = room.get("_cabinet")
	for key in _values:
		(_values[key] as SpinBox).set_value_no_signal(
			float(geometry[key]) * (100.0 if key in ["width", "height"] else 1.0)
		)
	_message.text = message


func _change() -> void:
	var geometry: Dictionary = (room.get("_cabinet") as Dictionary).duplicate(true)
	for key in _values:
		geometry[key] = (
			float((_values[key] as SpinBox).value) / (100.0 if key in ["width", "height"] else 1.0)
		)
	geometry.rows = int(geometry.rows)
	geometry.cols = int(geometry.cols)
	var message: String = room.request_shelf_geometry(geometry)
	sync(message)
