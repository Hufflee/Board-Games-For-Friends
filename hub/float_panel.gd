
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
const BG := Color(0.086, 0.098, 0.125, 0.96)
const BG_HEAD := Color(0.13, 0.145, 0.18)
const BG_SOFT := Color(0.17, 0.19, 0.235)
const LINE := Color(0.27, 0.3, 0.37)
const INK := Color(0.9, 0.91, 0.94)
const MUTED := Color(0.62, 0.65, 0.72)
const ACCENT := Color(0.38, 0.72, 0.95)
const BLINK := 0.45

static var _layouts := {}
static var _loaded := false

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
var _pos := Vector2.ZERO
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
	_mini_label = Label.new()
	_mini.add_child(_mini_label)
	add_child(_mini)
	_built = true
	_build_body()
	_restyle()
	var parent := get_parent() as Control
	if parent != null:
		parent.resized.connect(_apply)
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


func px(n: float) -> int:
	return roundi(n * (k if scale_content else 1.0))


func head_height() -> float:
	return float(px(30))


func is_open() -> bool:
	return mode == Mode.OPEN


func set_mode(next: int) -> void:
	if next == Mode.CLOSED and close_minimizes:
		next = Mode.MINI
	if mode == next:
		return
	mode = next
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
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 5, 4))
	b.add_theme_stylebox_override("hover", flat(BG_SOFT, 5, 4))
	b.add_theme_stylebox_override("pressed", flat(BG_SOFT.darkened(0.2), 5, 4))
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
	var frame := flat(BG, px(10), 0, LINE)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 8
	frame.shadow_offset = Vector2(0, 3)
	_frame.add_theme_stylebox_override("panel", frame)
	var head := flat(BG_HEAD, px(10), 0)
	head.corner_radius_bottom_left = 0
	head.corner_radius_bottom_right = 0
	head.border_color = LINE
	head.border_width_bottom = 1
	_head.add_theme_stylebox_override("panel", head)
	var mini := flat(BG_HEAD, 9, 8, LINE)
	mini.shadow_color = Color(0, 0, 0, 0.3)
	mini.shadow_size = 5
	mini.shadow_offset = Vector2(0, 2)
	_mini.add_theme_stylebox_override("panel", mini)
	_mini_label.add_theme_font_size_override("font_size", 14)
	_mini_label.add_theme_color_override("font_color", INK)
	for child: Node in _head.get_children():
		child.queue_free()
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = px(6)
	row.offset_right = -px(4)
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
	var fold := small_button("—", "Свернуть в кнопку «%s»" % title)
	fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fold.pressed.connect(set_mode.bind(Mode.MINI))
	row.add_child(fold)
	var close := small_button("✕", "Свернуть" if close_minimizes else "Закрыть")
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
		var sb := flat(BG if on else Color(0, 0, 0, 0), px(6), px(5))
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		if on:
			sb.border_color = ACCENT
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
			dot.add_theme_color_override("font_color", ACCENT)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(dot)
			_dots.append(dot)
		var label := Label.new()
		label.text = str(tab.get("text", ""))
		label.add_theme_font_size_override("font_size", px(13))
		label.add_theme_color_override("font_color", INK if on else MUTED)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(label)
		if bool(tab.get("closable", false)):
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			var x := small_button("×", "Закрыть вкладку")
			x.custom_minimum_size = Vector2(px(16), px(16))
			x.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 4, 1))
			x.add_theme_stylebox_override("hover", flat(BG_SOFT, 4, 1))
			x.add_theme_stylebox_override("pressed", flat(BG_SOFT, 4, 1))
			x.pressed.connect(func(): tab_closed.emit(id))
			line.add_child(x)
		_tab_row.add_child(item)


func _draw_grip() -> void:
	var s := _grip.size
	for i in 3:
		var d := 4.0 + i * 4.0
		_grip.draw_line(Vector2(s.x - 2, s.y - d), Vector2(s.x - d, s.y - 2), Color(MUTED, 0.7), 1.5, true)


func _parent_size() -> Vector2:
	var parent := get_parent() as Control
	return parent.size if parent != null else get_viewport_rect().size


func _normal_size() -> Vector2:
	return (base_size * k).round()


func _clamped(pos: Vector2, rect_size: Vector2) -> Vector2:
	var limit := _parent_size() - rect_size
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, limit.x)), clampf(pos.y, minf(top_limit, maxf(0.0, limit.y)), maxf(0.0, limit.y)))


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
		_mini_label.text = title + (" ●" if mini_dot and _blink_on else ("  " if mini_dot else ""))
		_mini.reset_size()
		var mini_size := _mini.get_combined_minimum_size()
		if not _placed and default_place.is_valid():
			_pos = default_place.call(mini_size, _parent_size())
		size = mini_size
		position = _clamped(_pos, mini_size)
		_mini.position = Vector2.ZERO
		return
	var normal := _normal_size()
	if not _placed and default_place.is_valid():
		_pos = default_place.call(normal, _parent_size())
	var rect_size := normal
	if _zoom > 0.0:
		rect_size = normal.lerp(normal.max(hover_zoom).min(_parent_size()), ease(_zoom, -1.8)).round()
	var pos := _clamped(_pos, normal)
	if _zoom > 0.0:
		pos = _clamped(pos, rect_size)
	position = pos
	size = rect_size
	var hh := head_height()
	_frame.position = Vector2.ZERO
	_frame.size = rect_size
	_head.position = Vector2.ZERO
	_head.size = Vector2(rect_size.x, hh)
	body.position = Vector2(1, hh)
	body.size = Vector2(rect_size.x - 2, rect_size.y - hh - 1)
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
			_mini_label.text = title + (" ●" if _blink_on else "  ")
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
			_pos = _clamped(_press_pos + shift, size)
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
				_pos = position
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
