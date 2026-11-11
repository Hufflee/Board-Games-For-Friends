
extends Control
## Плавающая панель поверх экрана: общая основа чата и мини-игр.
## Полоса управления сверху (вкладки с крестиками и мигающей точкой, кнопки панели, «свернуть», «закрыть»),
## перенос зажатием за полосу, размер — за уголок справа снизу, сворачивание в компактную кнопку.
## Место, размер и состояние запоминаются по ключу `key` в user://float_panels.cfg и общие для всех экранов.
## Наследник строит содержимое в `_build_body()` (узел `body`) и свои кнопки полосы в `_fill_header()`.

enum Mode { OPEN, MINI, CLOSED }

signal tab_selected(id: String)
signal tab_closed(id: String)
signal mode_changed
signal rescaled

const SAVE_PATH := "user://float_panels.cfg"
const K_MIN := 0.7
const K_MAX := 1.8
const BLINK := 0.45

static var _layouts := {}
static var _loaded := false

## Палитра окна: тёмная основа, подкрашенная под акцент текущей игры (set_palette).
var c_bg := Color(0.086, 0.098, 0.125, 0.96)
var c_head := Color(0.13, 0.145, 0.18)
var c_soft := Color(0.17, 0.19, 0.235)
var c_line := Color(0.27, 0.3, 0.37)
var c_ink := Color(0.95, 0.94, 0.98)
var c_muted := Color(0.62, 0.65, 0.72)
var c_accent := Color(0.38, 0.72, 0.95)
var c_head_ink := Color(0.95, 0.94, 0.98)  # надписи на полосе вкладок
var c_head_muted := Color(0.62, 0.65, 0.72)
## Обводка окна и простой свёрнутой плашки — как у кнопки, с которой взят цвет (ширина 0 — тонкая линия c_line).
var outline_color := Color(0, 0, 0, 0)
var outline_width := 0
var outline_radius := -1  # −1 — обычное скругление окна


func _edge() -> int:
	return outline_width if outline_width > 0 else 1


func _edge_color() -> Color:
	return outline_color if outline_width > 0 else c_line


func _corner() -> int:
	return outline_radius if outline_radius >= 0 else px(10)
## Своя свёрнутая кнопка: () -> Button (например, кнопка верхней полосы текущей игры). Пусто — простая плашка.
var mini_factory := Callable()
var _mini_button: Button

var key := "panel"
var mode_key := ""  # под каким ключом помнить «открыта / свёрнута / закрыта» (пусто — как key)
var title := "Панель"
var base_size := Vector2(340, 320)
var k := 1.0  # размер, выбранный игроком (множитель к base_size)
var mode: int = Mode.OPEN
var scale_content := true  # вместе с панелью растут шрифты и полоса (чат); иначе меняется только поле (мини-игры)
var close_minimizes := false  # крестик сворачивает (на экранах, где открыть панель больше нечем)
var hover_zoom := Vector2.ZERO  # размер при наведении на содержимое (0 — не увеличивать)
var hover_zoom_on := true
var top_limit := 0.0
var default_place := Callable()  # (size: Vector2, parent_size: Vector2) -> Vector2
var current_tab := ""
var mini_dot := false  # мигающая точка на свёрнутой кнопке

var body: Control
var header_extra: HBoxContainer

var _frame: Panel
var _head: Panel
var _tab_row: HBoxContainer
var _tab_scroll: ScrollContainer
var _mini: PanelContainer
var _mini_label: Label
var _grip: Control
var _tabs: Array = []
var _dots: Array[Label] = []
var _pos := Vector2.ZERO  # место свёрнутой кнопки: окно раскрывается от неё и в неё же сворачивается
var _mini_size := Vector2(96, 32)
var _open_right := false  # окно раскрыто влево от кнопки (справа — край экрана)
var _open_bottom := false  # окно раскрыто вверх от кнопки (снизу — край экрана)
var _placed := false
var _press := false
var _press_tab := ""
var _press_at := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _dragging := false
var _resizing := false
var _live_k := 1.0
var _zoom := 0.0
var _zoom_wait := 0.0
var _blink_clock := 0.0
var _blink_on := true
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_layout()
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_frame)
	_head = Panel.new()
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_head.gui_input.connect(_drag_input.bind(""))
	add_child(_head)
	body = Control.new()
	body.clip_contents = true
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	_grip = Control.new()
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.tooltip_text = "Потяните, чтобы изменить размер"
	_grip.gui_input.connect(_grip_input)
	_grip.draw.connect(_draw_grip)
	add_child(_grip)
	_mini = PanelContainer.new()
	_mini.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mini.gui_input.connect(_drag_input.bind("__mini"))
	add_child(_mini)
	_built = true
	_build_body()
	_restyle()
	rebuild_mini()
	var parent := get_parent() as Control
	if parent != null:
		parent.resized.connect(_apply)
	_pick_side.call_deferred()
	_apply.call_deferred()


## Содержимое панели (в `body`). Вызывается один раз.
func _build_body() -> void:
	pass


## Свои кнопки в полосе управления (в `header_extra`). Вызывается при каждой смене размера.
func _fill_header() -> void:
	pass


## Размер изменился: наследник пересчитывает свои шрифты и отступы.
func _rescale_body() -> void:
	pass


## Перекрасить окно под акцент: оттенок акцента уходит в фон, полосу и рамки.
func set_palette(accent: Color) -> void:
	var hue := accent.h
	var vivid := Color.from_hsv(hue, clampf(accent.s, 0.45, 0.8), maxf(accent.v, 0.9))
	c_accent = vivid
	c_bg = Color.from_hsv(hue, 0.5, 0.2, 0.97)
	c_head = Color.from_hsv(hue, 0.55, 0.32)
	c_soft = Color.from_hsv(hue, 0.4, 0.38)
	c_line = Color.from_hsv(hue, 0.4, 0.46)
	c_muted = Color.from_hsv(hue, 0.16, 0.78)
	c_head_ink = c_ink
	c_head_muted = c_muted
	if _built:
		_restyle()
		_rescale_body()
		_apply()


## Цвета окна от готовой кнопки (кнопка «Общение» верхней полосы игры): её заливка — цвет полосы вкладок,
## тот же цвет, затемнённый и слегка прозрачный, — фон сообщений и игр. Так окно сочетается с экраном.
func set_palette_from_button(fill: Color, text: Color) -> void:
	var head := Color(fill.r, fill.g, fill.b, 1.0)
	var light := head.get_luminance()
	c_head = head
	c_bg = Color(head.darkened(0.58), 0.88)
	c_soft = Color(head.darkened(0.42), 1.0)
	c_line = head.darkened(0.25) if light > 0.45 else head.lightened(0.22)
	c_muted = Color.from_hsv(head.h, minf(head.s, 0.2), 0.8)
	c_accent = Color.from_hsv(head.h, clampf(head.s, 0.35, 0.8), maxf(head.v, 0.88)) if head.s > 0.12 else Color(0.85, 0.87, 0.92)
	# надписи на полосе: цвет текста самой кнопки, если он читается на её заливке
	if absf(text.get_luminance() - light) > 0.3:
		c_head_ink = Color(text.r, text.g, text.b, 1.0)
	else:
		c_head_ink = Color(0.08, 0.07, 0.1) if light > 0.55 else Color(0.97, 0.96, 0.99)
	c_head_muted = c_head_ink.lerp(head, 0.32)
	if _built:
		_restyle()
		_rescale_body()
		_apply()


## Кнопка на полосе вкладок: надписи в цвет полосы, а не тёмного фона.
func _on_head(b: Button) -> Button:
	b.add_theme_color_override("font_color", c_head_muted)
	b.add_theme_color_override("font_hover_color", c_head_ink)
	b.add_theme_color_override("font_pressed_color", c_head_ink)
	var veil := Color(c_head_ink, 0.16)
	b.add_theme_stylebox_override("hover", flat(veil, 5, 4))
	b.add_theme_stylebox_override("pressed", flat(Color(c_head_ink, 0.24), 5, 4))
	return b


## Пересобрать свёрнутую кнопку (сменился экран — у новой игры другая кнопка полосы).
func rebuild_mini() -> void:
	if not _built:
		return
	for child: Node in _mini.get_children():
		_mini.remove_child(child)
		child.queue_free()
	_mini_button = null
	_mini_label = null
	var made: Variant = mini_factory.call() if mini_factory.is_valid() else null
	if made is Button:
		_mini_button = made
		_mini_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mini_button.focus_mode = Control.FOCUS_NONE
		_mini.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_mini.add_child(_mini_button)
	else:
		var plate := flat(c_head, mini(_corner(), 14), 8, _edge_color())
		plate.set_border_width_all(_edge())
		plate.shadow_color = Color(0, 0, 0, 0.3)
		plate.shadow_size = 5
		plate.shadow_offset = Vector2(0, 2)
		_mini.add_theme_stylebox_override("panel", plate)
		_mini_label = Label.new()
		_mini_label.add_theme_font_size_override("font_size", 14)
		_mini_label.add_theme_color_override("font_color", c_head_ink)
		_mini.add_child(_mini_label)
	_mini_text()
	var measured := _mini.get_combined_minimum_size()
	if measured.x > 8.0 and measured.y > 8.0:
		_mini_size = measured
	_apply()


func _mini_text() -> void:
	var text := title + (" ●" if mini_dot and _blink_on else ("   " if mini_dot else ""))
	if _mini_button != null and is_instance_valid(_mini_button):
		_mini_button.text = text
	elif _mini_label != null and is_instance_valid(_mini_label):
		_mini_label.text = text


## Куда на самом деле ведёт «закрыть» (наследник может свернуть вместо закрытия).
func _closing_mode() -> int:
	return Mode.MINI if close_minimizes else Mode.CLOSED


func px(n: float) -> int:
	return roundi(n * (k if scale_content else 1.0))


func head_height() -> float:
	return float(px(30))


func is_open() -> bool:
	return mode == Mode.OPEN


func set_mode(next: int) -> void:
	if next == Mode.CLOSED:
		next = _closing_mode()
	if mode == next:
		return
	mode = next
	if next == Mode.OPEN:
		_pick_side()
	_zoom = 0.0
	_store()
	_apply()
	mode_changed.emit()


## Вкладки: [{id, text, closable, dot, tip}], current — выбранная.
func set_tabs(list: Array, current: String) -> void:
	_tabs = list
	current_tab = current
	if _built:
		_rebuild_tabs()


func small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", px(13))
	b.add_theme_color_override("font_color", c_muted)
	b.add_theme_color_override("font_hover_color", c_ink)
	b.add_theme_color_override("font_pressed_color", c_accent)
	b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 5, 4))
	b.add_theme_stylebox_override("hover", flat(c_soft, 5, 4))
	b.add_theme_stylebox_override("pressed", flat(c_soft.darkened(0.2), 5, 4))
	b.add_theme_stylebox_override("disabled", flat(Color(0, 0, 0, 0), 5, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(px(22), px(22))
	return b


static func flat(color: Color, radius: int = 6, margin: int = 6, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


# --- Оформление и раскладка ------------------------------------------------------------

func _restyle() -> void:
	var frame := flat(c_bg, _corner(), 0, _edge_color())
	frame.set_border_width_all(_edge())
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 8
	frame.shadow_offset = Vector2(0, 3)
	_frame.add_theme_stylebox_override("panel", frame)
	var head := flat(c_head, _corner(), 0)
	head.corner_radius_bottom_left = 0
	head.corner_radius_bottom_right = 0
	head.border_color = _edge_color()
	head.border_width_left = _edge()
	head.border_width_top = _edge()
	head.border_width_right = _edge()
	head.border_width_bottom = 1
	_head.add_theme_stylebox_override("panel", head)
	for child: Node in _head.get_children():
		child.queue_free()
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = px(6) + _edge()
	row.offset_right = -px(4) - _edge()
	row.offset_top = _edge() - 1
	row.add_theme_constant_override("separation", px(2))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_head.add_child(row)
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_tab_scroll)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", px(2))
	_tab_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_tab_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_scroll.add_child(_tab_row)
	header_extra = HBoxContainer.new()
	header_extra.add_theme_constant_override("separation", px(2))
	header_extra.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(header_extra)
	_fill_header()
	for extra: Node in header_extra.get_children():
		if extra is Button:
			_on_head(extra as Button)
	var fold := _on_head(small_button("—", "Свернуть в кнопку «%s»" % title))
	fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fold.pressed.connect(set_mode.bind(Mode.MINI))
	row.add_child(fold)
	var close := _on_head(small_button("✕", "Свернуть" if close_minimizes else "Закрыть"))
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(set_mode.bind(Mode.CLOSED))
	row.add_child(close)
	_rebuild_tabs()


func _rebuild_tabs() -> void:
	if _tab_row == null:
		return
	for child: Node in _tab_row.get_children():
		_tab_row.remove_child(child)
		child.queue_free()
	_dots.clear()
	for tab: Dictionary in _tabs:
		var id := str(tab.get("id", ""))
		var on := id == current_tab
		var item := PanelContainer.new()
		var sb := flat(c_bg if on else Color(0, 0, 0, 0), px(6), px(5))
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		if on:
			sb.border_color = c_accent
			sb.border_width_top = 2
		item.add_theme_stylebox_override("panel", sb)
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.tooltip_text = str(tab.get("tip", ""))
		item.size_flags_vertical = Control.SIZE_SHRINK_END
		item.gui_input.connect(_drag_input.bind(id))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", px(4))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(line)
		if bool(tab.get("dot", false)):
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_font_size_override("font_size", px(10))
			dot.add_theme_color_override("font_color", c_accent if on else c_head_ink)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(dot)
			_dots.append(dot)
		var label := Label.new()
		label.text = str(tab.get("text", ""))
		label.add_theme_font_size_override("font_size", px(13))
		label.add_theme_color_override("font_color", c_ink if on else c_head_muted)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(label)
		if bool(tab.get("closable", false)):
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			var x := small_button("×", "Закрыть вкладку")
			x.custom_minimum_size = Vector2(px(16), px(16))
			x.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 4, 1))
			x.add_theme_stylebox_override("hover", flat(c_soft, 4, 1))
			x.add_theme_stylebox_override("pressed", flat(c_soft, 4, 1))
			if not on:
				_on_head(x)
				x.add_theme_stylebox_override("hover", flat(Color(c_head_ink, 0.16), 4, 1))
				x.add_theme_stylebox_override("pressed", flat(Color(c_head_ink, 0.24), 4, 1))
			x.pressed.connect(func(): tab_closed.emit(id))
			line.add_child(x)
		_tab_row.add_child(item)


func _draw_grip() -> void:
	var s := _grip.size
	for i in 3:
		var d := 4.0 + i * 4.0
		_grip.draw_line(Vector2(s.x - 2, s.y - d), Vector2(s.x - d, s.y - 2), Color(c_muted, 0.7), 1.5, true)


func _parent_size() -> Vector2:
	var parent := get_parent() as Control
	return parent.size if parent != null else get_viewport_rect().size


func _normal_size() -> Vector2:
	return (base_size * k).round()


func _clamped(pos: Vector2, rect_size: Vector2) -> Vector2:
	var limit := _parent_size() - rect_size
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, limit.x)), clampf(pos.y, minf(top_limit, maxf(0.0, limit.y)), maxf(0.0, limit.y)))


## В какую сторону раскрыться от свёрнутой кнопки: туда, где есть место. Если справа или снизу край
## экрана — окно растёт влево или вверх, а кнопка остаётся в своём углу и после сворачивания.
func _pick_side() -> void:
	var normal := _normal_size()
	var room := _parent_size()
	_open_right = _pos.x + normal.x > room.x and _pos.x + _mini_size.x - normal.x >= 0.0
	_open_bottom = _pos.y + normal.y > room.y and _pos.y + _mini_size.y - normal.y >= top_limit


func _open_pos(normal: Vector2) -> Vector2:
	return Vector2(
		_pos.x + _mini_size.x - normal.x if _open_right else _pos.x,
		_pos.y + _mini_size.y - normal.y if _open_bottom else _pos.y
	)


## Раскрытое окно передвинули — кнопка едет вместе с тем углом, от которого оно раскрыто.
func _anchor_from(rect_pos: Vector2, normal: Vector2) -> void:
	_pos = Vector2(
		rect_pos.x + normal.x - _mini_size.x if _open_right else rect_pos.x,
		rect_pos.y + normal.y - _mini_size.y if _open_bottom else rect_pos.y
	)


## Поставить панель по текущему состоянию: место, размер, свёрнутость.
func _apply() -> void:
	if not _built or not is_inside_tree():
		return
	visible = mode != Mode.CLOSED
	var open := mode == Mode.OPEN
	_frame.visible = open
	_head.visible = open
	body.visible = open
	_grip.visible = open
	_mini.visible = mode == Mode.MINI
	if mode == Mode.CLOSED:
		return
	if mode == Mode.MINI:
		_mini_text()
		_mini.reset_size()
		var mini_size := _mini.get_combined_minimum_size()
		_mini_size = mini_size
		if not _placed and default_place.is_valid():
			_pos = default_place.call(mini_size, _parent_size())
		size = mini_size
		position = _clamped(_pos, mini_size)
		_mini.position = Vector2.ZERO
		return
	var normal := _normal_size()
	if not _placed and default_place.is_valid():
		_pos = default_place.call(_mini_size, _parent_size())
		_pick_side()
	var rect_size := normal
	if _zoom > 0.0:
		rect_size = normal.lerp(normal.max(hover_zoom).min(_parent_size()), ease(_zoom, -1.8)).round()
	var pos := _clamped(_open_pos(normal), normal)
	if _zoom > 0.0:
		pos = _clamped(pos, rect_size)
	position = pos
	size = rect_size
	var hh := head_height()
	_frame.position = Vector2.ZERO
	_frame.size = rect_size
	_head.position = Vector2.ZERO
	_head.size = Vector2(rect_size.x, hh)
	body.position = Vector2(_edge(), hh)
	body.size = Vector2(rect_size.x - _edge() * 2, rect_size.y - hh - _edge())
	_grip.size = Vector2(16, 16)
	_grip.position = rect_size - _grip.size
	_grip.queue_redraw()


func _process(delta: float) -> void:
	if mode == Mode.CLOSED:
		return
	_blink_clock += delta
	if _blink_clock >= BLINK:
		_blink_clock = 0.0
		_blink_on = not _blink_on
		for dot: Label in _dots:
			if is_instance_valid(dot):
				dot.modulate.a = 1.0 if _blink_on else 0.15
		if mode == Mode.MINI and mini_dot:
			_mini_text()
	if mode != Mode.OPEN or hover_zoom == Vector2.ZERO:
		return
	var want := false
	if hover_zoom_on and not _dragging and not _resizing and is_visible_in_tree():
		var mouse := get_local_mouse_position()
		var inside := Rect2(Vector2.ZERO, size).has_point(mouse)
		if _zoom > 0.0:
			want = inside
		else:
			want = inside and mouse.y > head_height() and not _over_grip(mouse) and _hover_is_ours()
	if want and _zoom <= 0.0:
		_zoom_wait += delta
		if _zoom_wait < 0.12:
			return
	else:
		_zoom_wait = 0.0
	var target := 1.0 if want else 0.0
	if not is_equal_approx(_zoom, target):
		_zoom = move_toward(_zoom, target, delta / 0.16)
		_apply()


func _over_grip(mouse: Vector2) -> bool:
	return Rect2(_grip.position, _grip.size).has_point(mouse)


## Под курсором — именно эта панель, а не окно поверх неё.
func _hover_is_ours() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and (hovered == self or is_ancestor_of(hovered))


# --- Перенос и размер --------------------------------------------------------------------

func _drag_input(event: InputEvent, tab: String) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press = true
			_press_tab = tab
			_press_at = button.global_position
			_press_pos = position
			_dragging = false
		elif _press:
			_press = false
			if _dragging:
				_dragging = false
				_store()
			elif tab == "__mini":
				set_mode(Mode.OPEN)
			elif tab != "":
				tab_selected.emit(tab)
		return
	if event is InputEventMouseMotion and _press:
		var shift := (event as InputEventMouseMotion).global_position - _press_at
		if not _dragging and shift.length() > 5.0:
			_dragging = true
			_zoom = 0.0
		if _dragging:
			var moved := _clamped(_press_pos + shift, size)
			if mode == Mode.OPEN:
				_anchor_from(moved, _normal_size())
			else:
				_pos = moved
			_placed = true
			_apply()


func _grip_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_resizing = true
			_zoom = 0.0
			_live_k = k
			_apply()
		elif _resizing:
			_resizing = false
			scale = Vector2.ONE
			if not is_equal_approx(_live_k, k):
				k = _live_k
				_placed = true
				_anchor_from(position, _normal_size())
				_store()
				_restyle()
				_rescale_body()
				rescaled.emit()
			_apply()
		return
	if event is InputEventMouseMotion and _resizing:
		var local := (event as InputEventMouseMotion).global_position - global_position
		var room := _parent_size() - position
		var top := minf(K_MAX, minf(room.x / base_size.x, room.y / base_size.y))
		_live_k = clampf(maxf(local.x / base_size.x, local.y / base_size.y), K_MIN, maxf(K_MIN, top))
		scale = Vector2.ONE * (_live_k / k)  # пока тянут — быстрый показ; резкий текст — после отпускания


# --- Сохранение ---------------------------------------------------------------------------

func _load_layout() -> void:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(SAVE_PATH) == OK:
			for section: String in cfg.get_sections():
				_layouts[section] = {
					"pos": cfg.get_value(section, "pos", Vector2.ZERO),
					"k": cfg.get_value(section, "k", 1.0),
					"mode": cfg.get_value(section, "mode", -1),
					"placed": cfg.get_value(section, "placed", false),
				}
	var saved: Dictionary = _layouts.get(key, {})
	_placed = bool(saved.get("placed", false))
	if saved.get("pos") is Vector2:
		_pos = saved["pos"]
	k = clampf(float(saved.get("k", 1.0)), K_MIN, K_MAX)
	var mode_saved: Dictionary = _layouts.get(mode_key if mode_key != "" else key, {})
	var saved_mode := int(mode_saved.get("mode", -1))
	if saved_mode >= 0 and saved_mode <= Mode.CLOSED:
		mode = saved_mode
		if mode == Mode.CLOSED and close_minimizes:
			mode = Mode.MINI


func _store() -> void:
	_layouts[key] = {"pos": _pos, "k": k, "mode": mode, "placed": _placed}
	if mode_key != "" and mode_key != key:
		_layouts[mode_key] = {"mode": mode}
		_layouts[key].erase("mode")
	var cfg := ConfigFile.new()
	for section: String in _layouts:
		var item: Dictionary = _layouts[section]
		for field: String in item:
			cfg.set_value(section, field, item[field])
	cfg.save(SAVE_PATH)
