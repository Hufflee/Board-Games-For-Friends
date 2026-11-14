extends Control
## Панель личного редактора шкафа; геометрия меняется через проверяемые запросы NeonRoom.
var room: Node
var _values: Dictionary = {}
var _message: Label
var _zoom: HSlider
var _zoom_label: Label
var _undo: Button
var _ball: Button  # мяч в комнате: вкл / выкл
var _room_button: Button  # выбор комнаты главного меню (HubRooms)
var _panel: PanelContainer  # параметры шкафа (справа): в виде на полки прячется
var _items_button: Button  # раскрывает предметы комнаты
var _color_button: Button  # цвет шкафа (значок шкафа)
var _color_list: PanelContainer
var _items: HBoxContainer  # плакат, мяч, доска, корзина
var _room_list: PanelContainer  # раскрытый список комнат справа от кнопки

const RoomIcons := preload("res://hub/room_icons.gd")
const Rooms := preload("res://hub/rooms/hub_rooms.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := HubStyle.panel(HubStyle.CYAN)
	_panel = panel
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
	# одна кнопка «предметы комнаты» — по нажатию справа от неё раскрываются плакат, мяч, доска, корзина
	_items_button = _icon_button("Предметы комнаты: плакат, мяч, доска друзей, корзина", func(b: Button): RoomIcons.items(b, HubStyle.CYAN if is_instance_valid(_items) and _items.visible else HubStyle.TEXT))
	_items_button.name = "EditorItems"
	props.add_child(_items_button)
	_items = HubStyle.hbox(8)
	_items.name = "EditorItemsRow"
	_items.visible = false
	add_child(_items)
	_items_button.pressed.connect(func():
		_items.visible = not _items.visible
		if _items.visible:
			close_room_list()
			close_color_list()
			_items.position = _items_button.global_position + Vector2(_items_button.size.x + 8, 0)
		_items_button.queue_redraw())
	var add_poster := _icon_button("Повесить плакат с картинкой по умолчанию", func(b: Button): RoomIcons.poster(b, HubStyle.TEXT))
	add_poster.name = "EditorAddPoster"
	add_poster.pressed.connect(func(): room.emit_signal("poster_add_requested"))
	_items.add_child(add_poster)
	_ball = _icon_button("", func(b: Button): RoomIcons.ball(b, HubStyle.TEXT if bool(room.call("ball_view_on")) else HubStyle.MUTED, bool(room.call("ball_view_on"))))
	_ball.name = "EditorBall"
	_ball.pressed.connect(func():
		room.call("set_ball_enabled", not bool(room.call("ball_view_on")))
		_sync_ball())
	_items.add_child(_ball)
	var add_board := _icon_button("Повесить ещё одну доску друзей", func(b: Button): RoomIcons.board(b, HubStyle.TEXT))
	add_board.name = "EditorAddBoard"
	add_board.pressed.connect(func(): room.call("add_friend_board"))
	_items.add_child(add_board)
	var basket := _icon_button("Мини-корзина для мяча: повесить или снять (в виде на полки — на стену с полками)", func(b: Button): RoomIcons.basket(b, HubStyle.TEXT))
	basket.name = "EditorAddBasket"
	basket.pressed.connect(func(): room.call("add_room_basket"))
	_items.add_child(basket)
	_sync_ball()
	# Выбор комнаты — отдельно, ниже предметов: меняет окружение, не расстановку.
	_color_button = _icon_button("Цвет шкафа и тумбы под телевизором", func(b: Button): RoomIcons.room(b, HubStyle.CYAN if is_instance_valid(_color_list) else HubStyle.TEXT))
	_color_button.name = "EditorShelfColor"
	_color_button.pressed.connect(func():
		if is_instance_valid(_color_list):
			close_color_list()
		else:
			open_color_list())
	props.add_child(_color_button)
	_room_button = _icon_button("Комната главного меню — выбрать другую", func(b: Button): RoomIcons.door(b, HubStyle.CYAN if is_instance_valid(_room_list) else HubStyle.TEXT))
	_room_button.name = "EditorRoom"
	_room_button.pressed.connect(func():
		if is_instance_valid(_room_list):
			close_room_list()
		else:
			open_room_list())
	props.add_child(_room_button)
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
	# поворот к полкам на левой стене — как в главном меню (стрелка у края экрана)
	var turn: Button = load("res://hub/room_turn_arrow.gd").new()
	turn.name = "EditorTurnArrow"
	turn.room = room
	turn.z_index = 3
	add_child(turn)
	room.connect("view_turned", _on_view_turned)
	_on_view_turned(bool(room.call("left_wall_view")))


## Вид на полки: параметры шкафа прячутся; плакат, доска, мяч, корзина — для левой стены; цвет — полок.
func _on_view_turned(left: bool) -> void:
	if is_instance_valid(_panel):
		_panel.visible = not left
	close_color_list()
	_sync_ball()
	if is_instance_valid(_color_button):
		_color_button.tooltip_text = "Цвет полок на стене" if left else "Цвет шкафа и тумбы под телевизором"


func _process(_delta: float) -> void:
	if is_instance_valid(_undo) and is_instance_valid(room):
		_undo.disabled = not bool(room.call("can_undo_shelf"))


## Список комнат справа от кнопки: значок, название, подсказка; выбор применяется сразу и сохраняется.
func open_room_list() -> void:
	close_room_list()
	close_color_list()
	if is_instance_valid(_items) and _items.visible:
		_items.visible = false
		_items_button.queue_redraw()
	_room_list = HubStyle.panel(HubStyle.CYAN)
	_room_list.name = "EditorRoomList"
	_room_list.theme = HubStyle.theme()
	add_child(_room_list)
	var col := HubStyle.vbox(8)
	_room_list.add_child(col)
	col.add_child(HubStyle.label("Комната", 14, HubStyle.MUTED))
	var current := str(room.get("room_id"))
	for entry: Dictionary in Rooms.listed():  # сезонные — только в свой сезон
		var id := str(entry.id)
		var item := HubStyle.button("", 14)
		item.custom_minimum_size = Vector2(216, 48)
		item.tooltip_text = str(entry.get("hint", ""))
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var row := HubStyle.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		item.add_child(row)
		var picture := _room_picture(entry, id == current)
		row.add_child(picture)
		var title := HubStyle.label(str(entry.title), 14, HubStyle.TEXT)
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title)
		UISel.pick(item, id == current)
		item.pressed.connect(func():
			room.call("apply_room", id)
			open_room_list())  # перерисовать выбранное
		col.add_child(item)
	# справа от кнопки, верх списка — на уровне кнопки
	_room_list.position = _room_button.global_position + Vector2(_room_button.size.x + 8, -8)
	_room_button.queue_redraw()


## Цвет шкафа: несколько вариантов, выбор применяется сразу и сохраняется (NeonRoom.set_shelf_color).
func open_color_list() -> void:
	close_color_list()
	close_room_list()
	_color_list = HubStyle.panel(HubStyle.CYAN)
	_color_list.name = "EditorShelfColorList"
	_color_list.theme = HubStyle.theme()
	add_child(_color_list)
	var col := HubStyle.vbox(8)
	_color_list.add_child(col)
	var shelves := bool(room.call("left_wall_view"))  # в виде на полки — цвет полок, а не шкафа
	col.add_child(HubStyle.label("Цвет полок" if shelves else "Цвет шкафа", 14, HubStyle.MUTED))
	var current: Color = room.get("wall_shelf_wood" if shelves else "shelf_wood")
	for entry: Array in room.get("SHELF_COLORS"):
		var color := Color.html(str(entry[1]))
		var item := HubStyle.button("", 14)
		item.custom_minimum_size = Vector2(216, 44)
		var row := HubStyle.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		item.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var title := HubStyle.label(str(entry[0]), 14, HubStyle.TEXT)
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title)
		UISel.pick(item, color.is_equal_approx(current))
		item.pressed.connect(func():
			room.call("set_wall_shelf_color" if shelves else "set_shelf_color", color)
			open_color_list())
		col.add_child(item)
	_color_list.position = _color_button.global_position + Vector2(_color_button.size.x + 8, -8)
	_color_button.queue_redraw()


func close_color_list() -> void:
	if is_instance_valid(_color_list):
		_color_list.queue_free()
	_color_list = null
	if is_instance_valid(_color_button):
		_color_button.queue_redraw()


func close_room_list() -> void:
	if is_instance_valid(_room_list):
		_room_list.queue_free()
	_room_list = null
	if is_instance_valid(_room_button):
		_room_button.queue_redraw()


## Превью комнаты: картинка (комнаты из мастерской) или значок линиями.
func _room_picture(entry: Dictionary, selected: bool) -> Control:
	var path := str(entry.get("preview", ""))
	if path != "" and ResourceLoader.exists(path):
		var image := TextureRect.new()
		image.texture = load(path)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(32, 32)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return image
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kind := str(entry.get("icon", ""))
	icon.draw.connect(func(): RoomIcons.room_icon(icon, kind, HubStyle.CYAN if selected else HubStyle.TEXT))
	return icon


func _input(event: InputEvent) -> void:
	if is_instance_valid(_color_list) and event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position
		if not _color_list.get_global_rect().has_point(point) and not _color_button.get_global_rect().has_point(point):
			close_color_list()
	# нажатие мимо списка и кнопки закрывает список
	if not is_instance_valid(_room_list) or not event is InputEventMouseButton or not event.pressed:
		return
	var at: Vector2 = event.position
	if not _room_list.get_global_rect().has_point(at) and not _room_button.get_global_rect().has_point(at):
		close_room_list()


func _icon_button(tooltip: String, paint: Callable) -> Button:
	var button := HubStyle.button("", 14)
	button.theme = HubStyle.theme()
	button.custom_minimum_size = Vector2(52, 44)
	button.tooltip_text = tooltip
	button.draw.connect(func(): paint.call(button))
	return button


func _sync_ball() -> void:
	var on := bool(room.call("ball_view_on"))
	var where := " (у полок)" if bool(room.call("left_wall_view")) else ""
	_ball.tooltip_text = ("Мяч-попрыгун%s: включён — нажмите, чтобы убрать" if on else "Мяч-попрыгун%s убран — нажмите, чтобы вернуть") % where
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
