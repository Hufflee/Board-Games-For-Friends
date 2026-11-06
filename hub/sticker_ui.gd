extends Control
## Стикеры в хабе (поверх 3D-комнаты): значок-смайлик над вылетевшей коробкой → панель стикеров →
## клик по обложке наклеивает выбранный стикер в это место.
## Клик по уже наклеенному стикеру (на обложке, на доске или в списке панели) — выделить его: тянуть мышью,
## крутить и менять размер (ползунки, ⟲/⟳, колесо — размер, Shift+колесо — поворот); «Снять» — отдельной кнопкой.
## Выступающая за обложку/пробку часть стикера обрезается (hub/sticker_clip.gdshader).
## Доска друзей: в комнате друга (режим наблюдения) — наклеить ему стикер, свои — двигать/крутить/снимать;
## своя доска — только посмотреть (себе клеить нельзя). Данные и сеть — Net.stickers (hub/sticker_net.gd).
## Создаёт hub.gd: StickerUI.new(room, watch_peer: Callable, watch_name: Callable).

signal box_panel_toggled(open: bool)  # хаб прячет карточку игры: панель стикеров встаёт на её место

const Stickers := preload("res://hub/stickers.gd")
const Board := preload("res://hub/sticker_board.gd")
const TILE := 56  # кнопка стикера в панели
const COLS := 6  # стикеров в ряду панели
const HANDLE_R := 7.0  # точка поворота у рамки выделения
const HANDLE_GAP := 18.0
const TURN_STEP := PI / 12.0  # 15° на кнопку
const WHEEL_TURN := 0.12
const WHEEL_SCALE := 1.08

var _room: NeonRoom
var _watch_peer: Callable
var _watch_name: Callable
var _smiley: Button
var _panel: PanelContainer  # панель стикеров коробки или доски
var _panel_kind := ""  # "box" | "board"
var _catcher: Control  # во время наклеивания ловит клик по обложке
var _placing := ""  # id стикера «в руке»
var _placing_board := 0  # клеим на доску этого друга (0 — на свою коробку)
var _ghost: TextureRect
var _toast: Label
var _toast_tween: Tween
var _board_uv := Vector2(0.5, 0.5)
var _clock := 0.0
var _shown_peer := -1
# Выделенный стикер: на коробке — игра и номер, на доске друга — его uid. _sel = [u, v, поворот, размер].
var _sel_kind := ""
var _sel_key := ""
var _sel_index := -1
var _sel: Array = []
var _sel_owner := 0  # хозяин доски (peer) для стикера доски
var _dragging := false
var _rotating := false  # тянут точку поворота
var _sel_face := 0  # сторона коробки выделенного стикера
var _hit_face := 0  # сторона коробки под курсором при последнем попадании
var _spinning := false  # коробку крутят правой кнопкой мыши
var _spin_mouse := Vector2.ZERO
var _spin_start := Vector2.ZERO
var _spin_tween: Tween
var _rot_sign := 1.0  # как поворот стикера отражается на экране (обложка смотрит на камеру под углом)
var _drag_offset := Vector2.ZERO
var _board_dirty := false
var _board_clock := 0.0
var _size_slider: HSlider
var _turn_slider: HSlider


func _init(room: NeonRoom, watch_peer: Callable, watch_name: Callable) -> void:
	_room = room
	_watch_peer = watch_peer
	_watch_name = watch_name


func _ready() -> void:
	name = "StickerUI"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_smiley = HubStyle.button("", 14)
	_smiley.name = "StickerSmiley"
	_smiley.custom_minimum_size = Vector2(44, 44)
	_smiley.tooltip_text = "Стикеры на коробку"
	_smiley.draw.connect(_draw_smiley)
	_smiley.pressed.connect(_toggle_box_panel)
	_smiley.visible = false
	add_child(_smiley)
	_catcher = Control.new()
	_catcher.name = "StickerPlacing"
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_catcher.visible = false
	_catcher.gui_input.connect(_placing_input)
	add_child(_catcher)
	_ghost = TextureRect.new()
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.size = Vector2(72, 72)
	_ghost.modulate.a = 0.85
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	add_child(_ghost)
	_toast = HubStyle.label("", 15, HubStyle.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, "medium")
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = -72
	_toast.offset_bottom = -48
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)
	_room.board_requested.connect(open_board)
	_room.board_moved.connect(func(center: Vector2):
		if _own_room():
			Net.stickers.set_board_pos(center))
	_room.box_released.connect(func():
		if _panel_kind == "box":
			_close_panel())
	var net_stickers: Node = Net.stickers
	net_stickers.changed.connect(func(_peer): _apply(true))
	net_stickers.notice.connect(toast)
	_apply(true)


func _peer() -> int:
	return int(_watch_peer.call())


func _own_room() -> bool:
	return _peer() == 0 and not _room.remote_view


# --- Показ стикеров на коробках и доске ----------------------------------------------------

func _process(delta: float) -> void:
	_place_smiley()
	if _placing != "":
		_ghost.position = get_local_mouse_position() - _ghost.size * 0.5
	_clock += delta
	if _clock >= 0.3 or _shown_peer != _peer():
		_clock = 0.0
		_apply(false)
	# Стикер на доске друга: во время перетаскивания отправляем не чаще ~6 раз в секунду.
	_board_clock += delta
	if _board_dirty and _board_clock >= 0.16:
		_send_board_update()
	queue_redraw()


## Стикеры той комнаты, что сейчас на экране: своей или наблюдаемого друга.
func _apply(_force: bool) -> void:
	if not is_instance_valid(_room):
		return
	var peer := _peer()
	if _shown_peer != peer and _panel_kind != "":
		_close_panel()
	_shown_peer = peer
	var data: Dictionary = Net.stickers.room_of(peer)
	for item: Variant in _room.boxes:
		if not is_instance_valid(item):
			continue  # коробку только что убрали (смена комнаты)
		var box := item as GameBox
		if box != null and not box.is_figurine():
			box.set_stickers(data.boxes.get(_room._shelf_id(box), []))
	if is_instance_valid(_room.sticker_board):
		_room.set_board_position(Net.stickers.board_pos(peer))
		var board: Array = data.board
		if _sel_kind == "board" and peer == _sel_owner:
			# Свой стикер на доске друга двигается сразу, не дожидаясь ответа хозяина доски.
			board = board.duplicate(true)
			var found := false
			for entry: Array in board:
				if str(entry[0]) == _sel_key:
					entry[2] = _sel[0]
					entry[3] = _sel[1]
					entry[4] = _sel[2]
					if entry.size() > 7:
						entry[7] = _sel[3]
					else:
						entry.append(_sel[3])
					found = true
			if not found and not _board_dirty:
				_deselect()
		_room.sticker_board.show_stickers(board)


func _place_smiley() -> void:
	var box := _room.focused
	var show := box != null and _own_room() and not box.is_cups() and not box.is_figurine() and not _room._editor_on
	_smiley.visible = show
	if not show:
		if _panel_kind == "box":
			_close_panel()
		return
	# Над верхним краем обложки вылетевшей коробки.
	var top := box.global_transform * Vector3(box.size.x / 2.0, box.size.y / 2.0 + 0.012, 0)
	if _room.camera.is_position_behind(top):
		_smiley.visible = false
		return
	var at := _room.camera.unproject_position(top)
	_smiley.position = at - Vector2(_smiley.size.x * 0.5, _smiley.size.y + 6)


## Плоский одноцветный смайлик (как остальные значки хаба — линиями).
func _draw_smiley() -> void:
	var c := _smiley.size * 0.5
	var color := HubStyle.YELLOW if _panel_kind != "box" else HubStyle.PINK
	_smiley.draw_arc(c, 14, 0, TAU, 40, color, 2.0, true)
	_smiley.draw_circle(c + Vector2(-5, -4), 2.2, color)
	_smiley.draw_circle(c + Vector2(5, -4), 2.2, color)
	_smiley.draw_arc(c + Vector2(0, 1), 8, 0.35, PI - 0.35, 16, color, 2.0, true)


## Рамка выделенного стикера: неоновый круг по его размеру и риска поворота.
func _draw() -> void:
	if _sel_kind == "" or _sel.is_empty():
		return
	var frame := _sel_frame()
	if frame.is_empty():
		return
	var center: Vector2 = frame.center
	var radius: float = frame.radius
	draw_arc(center, radius + 3, 0, TAU, 48, Color(0, 0, 0, 0.45), 4.0, true)
	draw_arc(center, radius, 0, TAU, 48, HubStyle.YELLOW, 2.0, true)
	# Точка поворота на ножке снаружи круга: зажать и вести — стикер крутится за курсором.
	var tick: Vector2 = frame.up
	var handle := center + tick * (radius + HANDLE_GAP + HANDLE_R)
	var color := HubStyle.PINK if _rotating else HubStyle.YELLOW
	draw_line(center + tick * radius, center + tick * (radius + HANDLE_GAP), Color(0, 0, 0, 0.45), 4.0, true)
	draw_line(center + tick * radius, center + tick * (radius + HANDLE_GAP), color, 2.0, true)
	draw_circle(handle, HANDLE_R + 2.0, Color(0, 0, 0, 0.55))
	draw_circle(handle, HANDLE_R, color)
	draw_circle(handle, HANDLE_R * 0.4, Color(0.1, 0.06, 0.18))


func _handle_pos() -> Vector2:
	var frame := _sel_frame()
	if frame.is_empty():
		return Vector2(-1e6, -1e6)
	return frame.center + frame.up * (float(frame.radius) + HANDLE_GAP + HANDLE_R)


## Центр, радиус и направление «вверх» выделенного стикера на экране.
func _sel_frame(turn: float = NAN) -> Dictionary:
	var camera := _room.camera
	var r := float(_sel[2]) if is_nan(turn) else turn
	var center3: Vector3
	var up3: Vector3
	var half: float
	if _sel_kind == "box":
		var box := _room.focused
		if box == null:
			return {}
		# Центр и «вверх» стикера на его стороне коробки (повёрнутой или нет).
		var at := box.sticker_transform(_sel_face, Vector2(float(_sel[0]), float(_sel[1])), r, 0.0)
		center3 = box.global_transform * at.origin
		up3 = (box.global_transform.basis * at.basis * Vector3.UP).normalized()
		half = box.sticker_side() * float(_sel[3]) * 0.55
	else:
		var board: Node3D = _room.sticker_board
		if not is_instance_valid(board):
			return {}
		center3 = board.global_transform * Vector3((float(_sel[0]) - 0.5) * Board.SIZE.x, (0.5 - float(_sel[1])) * Board.SIZE.y, 0.007)
		up3 = (board.global_transform.basis * Basis(Vector3.BACK, r) * Vector3.UP).normalized()
		half = Board.SIDE * float(_sel[3]) * 0.55
	if camera.is_position_behind(center3):
		return {}
	var center := camera.unproject_position(center3)
	var tip := camera.unproject_position(center3 + up3 * half)
	var up := (tip - center)
	return {"center": center, "radius": maxf(10.0, up.length()), "up": up.normalized() if up.length() > 0.01 else Vector2.UP}


# --- Панели -------------------------------------------------------------------------------

func _close_panel(keep_selection: bool = false) -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_size_slider = null
	_turn_slider = null
	if _panel_kind == "box" and not keep_selection:
		box_panel_toggled.emit(false)
		_spinning = false
		if _room.focused != null and _room.focused.spin_ready() and _room.focused.view_spin != Vector2.ZERO:
			_spin_by(Vector2.INF)  # закрыли стикеры — коробка снова обложкой к игроку
	_panel_kind = ""
	_stop_placing()
	if not keep_selection:
		_deselect(false)
	if is_instance_valid(_smiley):
		_smiley.queue_redraw()


func _new_panel(kind: String, border: Color) -> VBoxContainer:
	_close_panel(true)
	_panel_kind = kind
	_panel = HubStyle.panel(border)
	_panel.name = "StickerPanel"
	add_child(_panel)
	var col := HubStyle.vbox(10)
	_panel.add_child(col)
	return col


## Заголовок панели с крестиком «Закрыть» справа (экономит высоту панели).
func _panel_header(parent: Control, title: String, color: Color) -> void:
	var head := HubStyle.hbox(8)
	var label := HubStyle.neon_label(title, 18, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var close := HubStyle.button("✕", 14)
	close.name = "ClosePanel"
	close.tooltip_text = "Закрыть (Esc)"
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(_close_panel)
	head.add_child(close)
	parent.add_child(head)


func _sticker_grid(parent: Control, on_pick: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for entry: Dictionary in Stickers.CATALOG:
		var id := str(entry.id)
		var tile := _sticker_button(id, Stickers.title(id))
		tile.name = "Sticker_" + id
		tile.pressed.connect(on_pick.bind(id))
		grid.add_child(tile)


func _sticker_button(id: String, tooltip: String, side: int = TILE) -> Button:
	var tile := HubStyle.button("", 12)
	tile.custom_minimum_size = Vector2(side, side)
	tile.icon = Stickers.texture(id)
	tile.expand_icon = true
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.tooltip_text = tooltip
	return tile


## Ряд наклеенных: нажатие выделяет стикер (а не снимает его).
func _applied_row(parent: Control, caption: String, ids: Array, keys: Array, on_pick: Callable) -> void:
	parent.add_child(HubStyle.label(caption, 13, HubStyle.MUTED))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLS * TILE + (COLS - 1) * 8, 58)
	parent.add_child(scroll)
	var row := HubStyle.hbox(6)
	scroll.add_child(row)
	for i in ids.size():
		var tile := _sticker_button(str(ids[i]), "Выделить «%s»: двигать, крутить, менять размер" % Stickers.title(str(ids[i])), 48)
		tile.name = "Applied_%s" % str(keys[i])
		UISel.pick(tile, _sel_kind != "" and str(keys[i]) == (str(_sel_index) if _sel_kind == "box" else _sel_key))
		tile.pressed.connect(on_pick.bind(keys[i]))
		row.add_child(tile)


## Управление выделенным стикером: размер, поворот, снять, готово.
func _selection_controls(parent: Control, on_remove: Callable) -> void:
	var box := HubStyle.panel(HubStyle.YELLOW)
	parent.add_child(box)
	var col := HubStyle.vbox(8)
	box.add_child(col)
	var title_id := ""
	if _sel_kind == "box":
		var list: Array = Net.stickers.box_stickers(_sel_key)
		title_id = str(list[_sel_index][0]) if _sel_index < list.size() else ""
	else:
		for entry: Array in Net.stickers.room_of(_sel_owner).board:
			if str(entry[0]) == _sel_key:
				title_id = str(entry[1])
	col.add_child(HubStyle.label("Выделен: «%s»" % Stickers.title(title_id), 15, HubStyle.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, "medium"))
	var hint := HubStyle.label("Тяните мышью · колесо — размер · Shift+колесо — поворот", 12, HubStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = COLS * TILE + (COLS - 1) * 8 - 24
	col.add_child(hint)
	var size_row := HubStyle.hbox(8)
	size_row.add_child(HubStyle.label("Размер", 13, HubStyle.TEXT))
	_size_slider = HSlider.new()
	_size_slider.name = "StickerSize"
	_size_slider.min_value = Stickers.SCALE_MIN
	_size_slider.max_value = Stickers.SCALE_MAX
	_size_slider.step = 0.05
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.set_value_no_signal(float(_sel[3]))
	_size_slider.value_changed.connect(func(value: float): _set_sel(float(_sel[0]), float(_sel[1]), float(_sel[2]), value, false))
	_size_slider.drag_ended.connect(func(_changed: bool): _commit())
	size_row.add_child(_size_slider)
	col.add_child(size_row)
	var turn_row := HubStyle.hbox(8)
	turn_row.add_child(HubStyle.label("Поворот", 13, HubStyle.TEXT))
	var left := HubStyle.button("⟲", 14)
	left.name = "TurnLeft"
	left.tooltip_text = "Повернуть на 15° против часовой"
	left.pressed.connect(func(): _turn(-TURN_STEP))
	turn_row.add_child(left)
	_turn_slider = HSlider.new()
	_turn_slider.name = "StickerTurn"
	_turn_slider.min_value = -180
	_turn_slider.max_value = 180
	_turn_slider.step = 1
	_turn_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_slider.set_value_no_signal(rad_to_deg(float(_sel[2])))
	_turn_slider.value_changed.connect(func(value: float): _set_sel(float(_sel[0]), float(_sel[1]), deg_to_rad(value), float(_sel[3]), false))
	_turn_slider.drag_ended.connect(func(_changed: bool): _commit())
	turn_row.add_child(_turn_slider)
	var right := HubStyle.button("⟳", 14)
	right.name = "TurnRight"
	right.tooltip_text = "Повернуть на 15° по часовой"
	right.pressed.connect(func(): _turn(TURN_STEP))
	turn_row.add_child(right)
	col.add_child(turn_row)
	var buttons := HubStyle.hbox(8)
	var remove := HubStyle.button("Снять", 14)
	remove.name = "StickerRemove"
	remove.pressed.connect(on_remove)
	buttons.add_child(remove)
	var done := HubStyle.primary("Готово", 14)
	done.name = "StickerDone"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func(): _deselect())
	buttons.add_child(done)
	col.add_child(buttons)


func _toggle_box_panel() -> void:
	if _panel_kind == "box":
		_close_panel()
		return
	_open_box_panel()


func _open_box_panel() -> void:
	var box := _room.focused
	if box == null:
		return
	var game := _room._shelf_id(box)
	var col := _new_panel("box", HubStyle.YELLOW)
	_smiley.queue_redraw()
	_panel_header(col, "СТИКЕРЫ", HubStyle.YELLOW)
	var hint := HubStyle.label("Стикер → нажмите на любую сторону коробки. Наклеенный — нажмите, чтобы выделить. Крутить коробку — кнопки или правая кнопка мыши.", 13, HubStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = COLS * TILE + (COLS - 1) * 8
	col.add_child(hint)
	_sticker_grid(col, _start_placing)
	_spin_row(col)
	var mine: Array = Net.stickers.box_stickers(game)
	if not mine.is_empty():
		var ids: Array = mine.map(func(entry): return str(entry[0]))
		_applied_row(col, "На коробке: %d" % mine.size(), ids, range(mine.size()), func(i: int): _select_box(game, i))
	if _sel_kind == "box" and _sel_key == game:
		_selection_controls(col, func():
			Net.stickers.remove_box_sticker(game, _sel_index)
			_deselect(false)
			_apply(true)
			_open_box_panel())
	_panel.reset_size()
	# На месте карточки игры справа — коробка слева от центра остаётся открытой.
	_panel.position = Vector2(size.x - 60 - maxf(_panel.size.x, 360), clampf((size.y - _panel.size.y) * 0.5, 72, maxf(72, size.y - _panel.size.y - 56)))
	box_panel_toggled.emit(true)


## Кнопки поворота коробки: по 90° влево/вправо/к себе/от себя и «как было».
func _spin_row(parent: Control) -> void:
	var row := HubStyle.hbox(6)
	row.name = "BoxSpin"
	row.add_child(HubStyle.label("Коробка:", 13, HubStyle.MUTED))
	for entry: Array in [["⟲", Vector2(-PI / 2.0, 0), "Повернуть влево"], ["⟳", Vector2(PI / 2.0, 0), "Повернуть вправо"],
			["⤒", Vector2(0, -PI / 2.0), "Показать верх"], ["⤓", Vector2(0, PI / 2.0), "Показать низ"], ["Обложка", Vector2.INF, "Вернуть обложкой к себе"]]:
		var button := HubStyle.button(str(entry[0]), 14)
		button.tooltip_text = str(entry[2])
		var step: Vector2 = entry[1]
		button.pressed.connect(func(): _spin_by(step))
		row.add_child(button)
	parent.add_child(row)


func _spin_by(step: Vector2) -> void:
	var box := _room.focused
	if box == null or not box.spin_ready():
		return
	var target := Vector2.ZERO if step == Vector2.INF else box.view_spin + step
	target.y = clampf(target.y, -PI / 2.0, PI / 2.0)
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = create_tween()
	_spin_tween.tween_method(func(value: Vector2): if is_instance_valid(box): box.set_view_spin(value), box.view_spin, target, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _start_placing(id: String) -> void:
	_deselect(false)
	_placing = id
	_ghost.texture = Stickers.texture(id)
	_ghost.visible = true
	_catcher.visible = true
	toast("Нажмите на любую сторону коробки, чтобы приклеить · правая кнопка — отмена")


## Клик по доске друга со стикером «в руке»: наклеить в это место.
func _place_on_board(point: Vector2) -> void:
	var peer := _placing_board
	var uv: Vector2 = _room.sticker_board.uv_at(_room.camera, point)
	if uv.x < 0.0:
		toast("Мимо доски — нажмите на саму доску")
		return
	var sticker := _placing
	_stop_placing()
	if Net.stickers.request_board_add(peer, sticker, uv.x, uv.y, randf_range(-0.45, 0.45)):
		Sfx.play("card_place", -6, 0.08)
		toast("Стикер «%s» на доске · его можно сразу тащить мышью" % Stickers.title(sticker))


func _stop_placing() -> void:
	_placing_board = 0
	_placing = ""
	if is_instance_valid(_ghost):
		_ghost.visible = false
	if is_instance_valid(_catcher):
		_catcher.visible = false


func _placing_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	accept_event()
	if event.button_index != MOUSE_BUTTON_LEFT:
		_stop_placing()
		return
	if _placing_board != 0:
		_place_on_board(event.position)
		return
	var box := _room.focused
	if box == null:
		_stop_placing()
		return
	var hit := box.face_hit(_room.camera.project_ray_origin(event.position), _room.camera.project_ray_normal(event.position))
	if int(hit.face) < 0:
		toast("Мимо коробки — нажмите на саму коробку (любую сторону)")
		return
	var uv: Vector2 = hit.uv
	var sticker := _placing
	var game := _room._shelf_id(box)
	_stop_placing()
	if Net.stickers.add_box_sticker(game, sticker, uv.x, uv.y, randf_range(-0.35, 0.35), int(hit.face)):
		Sfx.play("card_place", -6, 0.08)
		_apply(true)
		# Только что наклеенный сразу выделен — его можно подвинуть, повернуть и изменить.
		_select_box(game, Net.stickers.box_stickers(game).size() - 1)


## Точка экрана → доли обложки (+X) коробки; мимо — (-1, -1). clamp — разрешить точку за краем (для перетаскивания).
static func cover_uv(box: GameBox, camera: Camera3D, point: Vector2, clamp_edges: bool = false) -> Vector2:
	var inverse := box.global_transform.affine_inverse()
	var origin: Vector3 = inverse * camera.project_ray_origin(point)
	var direction: Vector3 = (inverse.basis * camera.project_ray_normal(point)).normalized()
	if absf(direction.x) < 0.0001:
		return Vector2(-1, -1)
	var t := (box.size.x / 2.0 - origin.x) / direction.x
	if t < 0.0:
		return Vector2(-1, -1)
	var hit := origin + direction * t
	var uv := Vector2(0.5 - hit.z / box.size.z, 0.5 - hit.y / box.size.y)
	if clamp_edges:
		return uv.clamp(Vector2.ZERO, Vector2.ONE)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


## Клик по доске: в комнате друга — наклеить ему стикер / править свои; своя — только просмотр.
func open_board(screen_point: Vector2) -> void:
	var board: Node3D = _room.sticker_board
	if not is_instance_valid(board):
		return
	var uv: Vector2 = board.uv_at(_room.camera, screen_point)
	_board_uv = uv if uv.x >= 0.0 else Vector2(randf_range(0.2, 0.8), randf_range(0.25, 0.75))
	# Нажали на свой стикер на доске друга — сразу хватаем и тащим (без отдельного выделения).
	var peer := _peer()
	if peer != 0 and uv.x >= 0.0:
		_panel_kind = "board"
		var picked := _pick_at(uv)
		if picked != "":
			_select_board(peer, picked)
			if not _sel.is_empty():
				_dragging = true
				_drag_offset = Vector2(float(_sel[0]), float(_sel[1])) - uv
			return
	_open_board_panel()


func _open_board_panel() -> void:
	var board: Node3D = _room.sticker_board
	var peer := _peer()
	var col := _new_panel("board", HubStyle.CYAN)
	col.add_child(HubStyle.neon_label("ДОСКА ДРУЗЕЙ", 18, HubStyle.CYAN))
	if peer == 0:
		var count: int = Net.stickers.local.board.size()
		var text := "Это ваша доска: сюда друзья клеят вам стикеры (сейчас — %d). Себе клеить нельзя." % count
		text += "\nЧтобы наклеить стикер другу, откройте его комнату — значок глаза рядом с ником в пати."
		var note := HubStyle.label(text, 14, HubStyle.TEXT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 340
		col.add_child(note)
		var authors := {}
		for entry: Array in Net.stickers.local.board:
			authors[str(entry[6])] = int(authors.get(str(entry[6]), 0)) + 1
		if not authors.is_empty():
			var names := PackedStringArray()
			for nick: String in authors:
				names.append("%s · %d" % [nick, authors[nick]])
			var who := HubStyle.label("От кого: " + ", ".join(names), 13, HubStyle.MUTED)
			who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			who.custom_minimum_size.x = 340
			col.add_child(who)
	else:
		var hint := HubStyle.label("Наклейте стикер для «%s» — он появится на доске в его комнате. Свой стикер на доске можно выделить нажатием." % str(_watch_name.call()), 14, HubStyle.TEXT)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = COLS * TILE + (COLS - 1) * 8
		col.add_child(hint)
		# Выбрали стикер — он «в руке», клеится туда, куда нажмёте на доске (как на коробке).
		_sticker_grid(col, func(id: String):
			_start_placing(id)
			_placing_board = peer
			toast("Нажмите на доску друга, чтобы приклеить · правая кнопка — отмена"))
		var mine: Array = Net.stickers.my_board_stickers(peer)
		if not mine.is_empty():
			var ids: Array = mine.map(func(entry): return str(entry[1]))
			var uids: Array = mine.map(func(entry): return str(entry[0]))
			_applied_row(col, "Ваши стикеры на этой доске: %d из %d" % [mine.size(), Stickers.BOARD_PER_AUTHOR], ids, uids, func(uid: String): _select_board(peer, uid))
		if _sel_kind == "board" and _sel_owner == peer:
			_selection_controls(col, func():
				Net.stickers.request_board_remove(peer, _sel_key)
				_deselect(false)
				toast("Стикер снят")
				_open_board_panel())
	var close := HubStyle.button("Закрыть", 14)
	close.pressed.connect(_close_panel)
	col.add_child(close)
	_panel.reset_size()
	var rect: Rect2 = board.screen_rect(_room.camera)
	var x := rect.position.x - _panel.size.x - 16
	if x < 330:
		x = rect.end.x + 16
	_panel.position = Vector2(clampf(x, 330, size.x - _panel.size.x - 16), clampf(rect.get_center().y - _panel.size.y * 0.5, 72, maxf(72, size.y - _panel.size.y - 56)))


# --- Выделенный стикер --------------------------------------------------------------------

func _select_box(game: String, index: int) -> void:
	var list: Array = Net.stickers.box_stickers(game)
	if index < 0 or index >= list.size():
		return
	_flush()
	var entry: Array = list[index]
	_sel_kind = "box"
	_sel_key = game
	_sel_index = index
	_sel = [float(entry[1]), float(entry[2]), float(entry[3]), float(entry[4])]
	_sel_face = int(entry[5]) if entry.size() > 5 else 0
	_open_box_panel()


func _select_board(owner: int, uid: String) -> void:
	for entry: Array in Net.stickers.my_board_stickers(owner):
		if str(entry[0]) == uid:
			_flush()
			_sel_kind = "board"
			_sel_key = uid
			_sel_owner = owner
			_sel = [float(entry[2]), float(entry[3]), float(entry[4]), float(entry[7]) if entry.size() > 7 else 1.0]
			_open_board_panel()
			return


func _deselect(rebuild: bool = true) -> void:
	if _sel_kind == "":
		return
	_flush()
	var kind := _sel_kind
	_sel_kind = ""
	_sel_key = ""
	_sel_index = -1
	_sel = []
	_dragging = false
	_rotating = false
	if rebuild and _panel_kind == kind:
		if kind == "box":
			_open_box_panel()
		else:
			_open_board_panel()


## Новое место/поворот/размер выделенного; final — сохранить (и отправить хозяину доски).
func _set_sel(u: float, v: float, r: float, k: float, final: bool) -> void:
	if _sel_kind == "":
		return
	_sel = [clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0), wrapf(r, -PI, PI), clampf(k, Stickers.SCALE_MIN, Stickers.SCALE_MAX)]
	if is_instance_valid(_size_slider):
		_size_slider.set_value_no_signal(float(_sel[3]))
	if is_instance_valid(_turn_slider):
		_turn_slider.set_value_no_signal(rad_to_deg(float(_sel[2])))
	if _sel_kind == "box":
		Net.stickers.update_box_sticker(_sel_key, _sel_index, _sel[0], _sel[1], _sel[2], _sel[3], final)
	else:
		_board_dirty = true
		if final:
			_send_board_update()
		_apply(true)


func _commit() -> void:
	if not _sel.is_empty():
		_set_sel(_sel[0], _sel[1], _sel[2], _sel[3], true)


func _flush() -> void:
	if _sel_kind == "box" and not _sel.is_empty():
		Net.stickers.update_box_sticker(_sel_key, _sel_index, _sel[0], _sel[1], _sel[2], _sel[3], true)
	elif _sel_kind == "board" and _board_dirty:
		_send_board_update()


func _send_board_update() -> void:
	_board_dirty = false
	_board_clock = 0.0
	if _sel_kind == "board" and not _sel.is_empty():
		Net.stickers.request_board_update(_sel_owner, _sel_key, _sel[0], _sel[1], _sel[2], _sel[3])


func _turn(delta: float) -> void:
	if not _sel.is_empty():
		_set_sel(_sel[0], _sel[1], float(_sel[2]) + delta, _sel[3], true)


## Точка на поверхности под курсором (обложка или доска), clamp — для перетаскивания за край.
func _surface_uv(point: Vector2, clamp_edges: bool = false) -> Vector2:
	if _panel_kind == "box" and _room.focused != null and _own_room():
		var box := _room.focused
		var origin := _room.camera.project_ray_origin(point)
		var normal := _room.camera.project_ray_normal(point)
		if clamp_edges and _dragging:
			# Тащим по плоскости своей стороны; за краем — у края (лишнее обрежется).
			var along := box.face_hit(origin, normal, _sel_face)
			return (along.uv as Vector2).clamp(Vector2.ZERO, Vector2.ONE) if int(along.face) >= 0 else Vector2(-2, -2)
		var hit := box.face_hit(origin, normal)
		if int(hit.face) < 0:
			return Vector2(-1, -1)
		_hit_face = int(hit.face)
		return hit.uv
	if _panel_kind == "board" and _peer() != 0 and is_instance_valid(_room.sticker_board):
		var uv: Vector2 = _room.sticker_board.uv_at(_room.camera, point)
		if uv.x < 0.0 and clamp_edges and _dragging:
			return Vector2(-2, -2)  # мимо доски: стикер не прыгает
		return uv
	return Vector2(-1, -1)


## Свой стикер под точкой поверхности (верхний): номер на коробке или uid на доске; нет — "".
func _pick_at(uv: Vector2) -> String:
	if _panel_kind == "box":
		var box := _room.focused
		var list: Array = Net.stickers.box_stickers(_room._shelf_id(box))
		var dims := box.face_size(_hit_face)
		for i in range(list.size() - 1, -1, -1):
			var entry: Array = list[i]
			if (int(entry[5]) if entry.size() > 5 else 0) != _hit_face:
				continue  # стикер на другой стороне
			var k := float(entry[4]) if entry.size() > 4 else 1.0
			var d := Vector2((float(entry[1]) - uv.x) * dims.x, (float(entry[2]) - uv.y) * dims.y)
			if d.length() <= box.sticker_side() * k * 0.45:
				return str(i)
		return ""
	var mine: Array = Net.stickers.my_board_stickers(_peer())
	for i in range(mine.size() - 1, -1, -1):
		var entry: Array = mine[i]
		var k := float(entry[7]) if entry.size() > 7 else 1.0
		var d := Vector2((float(entry[2]) - uv.x) * Board.SIZE.x, (float(entry[3]) - uv.y) * Board.SIZE.y)
		if d.length() <= Board.SIDE * k * 0.45:
			return str(entry[0])
	return ""


func _over_ui(point: Vector2) -> bool:
	return (is_instance_valid(_panel) and _panel.get_global_rect().has_point(point)) or (_smiley.visible and _smiley.get_global_rect().has_point(point))


## Мышь по поверхности при открытой панели: выделить свой стикер, тащить, колесо — размер/поворот.
## Работает до 3D-комнаты (_input), но клики по самой панели не трогает.
func _input(event: InputEvent) -> void:
	if _placing != "" or _panel_kind == "" or not is_visible_in_tree() or not event is InputEventMouse:
		return
	var point: Vector2 = event.position
	# Правая кнопка мыши над коробкой — крутить её (только в своей комнате, в режиме стикеров).
	if _panel_kind == "box" and _room.focused != null and _own_room():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and not _over_ui(point) and _room.focused.spin_ready():
				_spinning = true
				_spin_mouse = point
				_spin_start = _room.focused.view_spin
				get_viewport().set_input_as_handled()
				return
			if not event.pressed and _spinning:
				_spinning = false
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion and _spinning:
			var delta: Vector2 = (point - _spin_mouse) * 0.01
			_room.focused.set_view_spin(_spin_start + Vector2(delta.x, -delta.y))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if _rotating:
			var frame := _sel_frame()
			if not frame.is_empty():
				var target: float = (point - frame.center).angle()
				var current: float = (frame.up as Vector2).angle()
				_set_sel(_sel[0], _sel[1], float(_sel[2]) + angle_difference(current, target) * _rot_sign, _sel[3], false)
			get_viewport().set_input_as_handled()
			return
		if _dragging:
			var uv := _surface_uv(point, true)
			if uv.x > -1.5:
				_set_sel(uv.x + _drag_offset.x, uv.y + _drag_offset.y, _sel[2], _sel[3], false)
			get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		if _rotating:
			_rotating = false
			_commit()
			get_viewport().set_input_as_handled()
			return
		if _dragging:
			_dragging = false
			_commit()
			get_viewport().set_input_as_handled()
		return
	if not button.pressed:
		return
	# Точка поворота может выходить за обложку — проверяем её первой.
	if button.button_index == MOUSE_BUTTON_LEFT and _sel_kind != "" and point.distance_to(_handle_pos()) <= HANDLE_R + 6.0:
		var a := _sel_frame(float(_sel[2]))
		var b := _sel_frame(float(_sel[2]) + 0.1)
		if not a.is_empty() and not b.is_empty():
			_rot_sign = 1.0 if angle_difference((a.up as Vector2).angle(), (b.up as Vector2).angle()) >= 0.0 else -1.0
		_rotating = true
		get_viewport().set_input_as_handled()
		return
	if _over_ui(point):
		return
	var uv := _surface_uv(point)
	if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if _sel_kind != "" and uv.x >= 0.0:
			var up := button.button_index == MOUSE_BUTTON_WHEEL_UP
			if button.shift_pressed:
				_set_sel(_sel[0], _sel[1], float(_sel[2]) + (WHEEL_TURN if up else -WHEEL_TURN), _sel[3], true)
			else:
				_set_sel(_sel[0], _sel[1], _sel[2], float(_sel[3]) * (WHEEL_SCALE if up else 1.0 / WHEEL_SCALE), true)
			get_viewport().set_input_as_handled()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if uv.x < 0.0:
		if _sel_kind != "":
			_deselect()
		return
	var picked := _pick_at(uv)
	if picked != "":
		var same := _sel_kind != "" and picked == (str(_sel_index) if _sel_kind == "box" else _sel_key)
		if not same:
			if _panel_kind == "box":
				_select_box(_room._shelf_id(_room.focused), int(picked))
			else:
				_select_board(_peer(), picked)
		if not _sel.is_empty():
			_dragging = true
			_drag_offset = Vector2(float(_sel[0]), float(_sel[1])) - uv
		get_viewport().set_input_as_handled()
	elif _sel_kind != "":
		_deselect()
		get_viewport().set_input_as_handled()


func toast(text: String) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if _panel_kind != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _sel_kind != "":
			_deselect()
		else:
			_close_panel()
		get_viewport().set_input_as_handled()
