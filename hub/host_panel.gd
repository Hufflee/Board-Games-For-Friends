class_name HostPanel
extends CanvasLayer
## Панель хоста (UI): тёмное перетаскиваемое окно поверх любой игры. Открывает кнопка «Панель хоста»
## в верхней полосе (только у хоста во время партии). Логика — Net.host_tools (games/king_of_12/net/host_tools.gd).
## Категории: «Игра» (отмена/повтор, таймер, смена темы) и по одной на игрока (параметры, карты,
## «Сделать зрителем», «Кикнуть» — в самом низу, по удержанию).

const BG := Color(0.08, 0.085, 0.1, 0.99)  # сквозь панель не просвечивает текст стола
const INK := Color("e9e6df")
const MUTED := Color(0.91, 0.9, 0.87, 0.55)
const ACCENT := Color("5fb3ff")
const W := 340.0

var _panel: PanelContainer
var _body: VBoxContainer
var _drag_from := Vector2.INF
var _placed := false
var _open_sections := {"game": true}  # какие категории раскрыты (ключ — "game" / место)
static var _last_pos := Vector2(-1, -1)


static func toggle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for n: Node in tree.root.get_children():
		if n is HostPanel:
			n.queue_free()
			return
	var p := HostPanel.new()
	tree.root.add_child(p)


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_allowed")
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(W, 0)
	add_child(_panel)
	var col := _vbox(12)
	_panel.add_child(col)
	# заголовок — за него окно и перетаскивают
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.gui_input.connect(_on_head_input)
	var title := _label("Панель хоста", 18, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close := _button("✕", false)
	close.tooltip_text = "Закрыть панель"
	close.pressed.connect(queue_free)
	head.add_child(close)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(W, 0)
	col.add_child(scroll)
	_body = _vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	scroll.set_meta("fit", true)
	Net.state_changed.connect(func(_v): _rebuild())
	Net.session_closed.connect(func(_r): queue_free())
	Net.game_ended.connect(queue_free)
	Net.party_game_changed.connect(func(_g): queue_free())
	get_tree().scene_changed.connect(queue_free)
	get_viewport().size_changed.connect(_fit)
	_rebuild()
	_place.call_deferred()


func _place() -> void:
	var vs := get_viewport().get_visible_rect().size
	if _last_pos.x < 0:
		_last_pos = Vector2(vs.x - W - 56, TopBar.HEIGHT + 16)
	_panel.position = _last_pos
	_placed = true
	_fit()


## Окно не выходит за экран; список прокручивается, если игроков много.
func _fit() -> void:
	if not is_instance_valid(_panel) or not _placed:
		return
	var vs := get_viewport().get_visible_rect().size
	var scroll := _body.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, maxf(120.0, vs.y - 160.0))
	_panel.reset_size()
	_panel.position = _panel.position.clamp(Vector2(8, 8), (vs - _panel.size - Vector2(8, 8)).max(Vector2(8, 8)))
	_last_pos = _panel.position


func _on_head_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag_from = _panel.get_global_mouse_position() - _panel.position if e.pressed else Vector2.INF
	elif e is InputEventMouseMotion and _drag_from != Vector2.INF:
		_panel.position = _panel.get_global_mouse_position() - _drag_from
		_fit()


## Пересобираем по каждому состоянию, но не пока хост печатает число в поле.
## Панель живёт только в партии хоста: вышли в лобби, к выбору игры или в меню — закрываем сами.
func _process(_d: float) -> void:
	if not Net.in_game or not Net.is_host():
		queue_free()


func _rebuild() -> void:
	if not Net.is_host() or not Net.in_game:
		queue_free()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and _panel.is_ancestor_of(focus) and focus is LineEdit:
		return
	for c: Node in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var info: Dictionary = Net.host_tools.info()
	_section("game", "Игра", _game_rows(info))
	for p: Dictionary in info.players:
		_section(p.seat, str(p.name) + ("  · бот" if p.bot else ""), _player_rows(p, info))
	_fit.call_deferred()


func _section(key: Variant, title: String, rows: Array) -> void:
	var open := bool(_open_sections.get(key, false))
	var head := _button(("▾  " if open else "▸  ") + title, false)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", 15)
	head.pressed.connect(func():
		_open_sections[key] = not open
		_rebuild())
	_body.add_child(head)
	if not open:
		return
	var box := _vbox(8)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_child(box)
	for r: Control in rows:
		box.add_child(r)
	_body.add_child(margin)


func _game_rows(info: Dictionary) -> Array:
	var rows: Array = []
	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 8)
	var undo := _button("←  Отменить предыдущее действие", true)
	undo.disabled = not bool(info.undo)
	undo.tooltip_text = "Вернуть игру к состоянию до последнего действия игрока"
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo.pressed.connect(func():
		Net.host_tools.undo()
		_rebuild())
	undo_row.add_child(undo)
	if bool(info.redo):
		var redo := _button("→", true)
		redo.tooltip_text = "Повторить отменённое действие"
		redo.custom_minimum_size.x = 44
		redo.pressed.connect(func():
			Net.host_tools.redo()
			_rebuild())
		undo_row.add_child(redo)
	rows.append(undo_row)
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 8)
	var on := CheckBox.new()
	on.text = "Таймер"
	on.tooltip_text = "Выключен — время хода не ограничено"
	on.button_pressed = bool(info.timer_on)
	on.add_theme_color_override("font_color", INK)
	on.add_theme_color_override("font_pressed_color", INK)
	on.add_theme_color_override("font_hover_color", INK)
	on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_row.add_child(on)
	var secs := _spin(int(info.timer), 5, 900, 5)
	secs.suffix = "с"
	secs.editable = bool(info.timer_on)
	timer_row.add_child(secs)
	on.toggled.connect(func(v: bool): Net.host_tools.set_timer(v, int(secs.value)))
	secs.value_changed.connect(func(v: float): Net.host_tools.set_timer(true, int(v)))
	rows.append(timer_row)
	for st: Dictionary in info.get("game_stats", []):
		var stat_row := HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 8)
		var caption := _label(str(st.label), 14, INK)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_row.add_child(caption)
		var value := _spin(int(st.value), int(st.get("min", 0)), int(st.get("max", 9999)), 1)
		var stat_key := str(st.key)
		value.value_changed.connect(func(v: float): Net.host_tools.set_game_stat(stat_key, int(v)))
		stat_row.add_child(value)
		rows.append(stat_row)
	if bool(info.theme):
		var theme := _button("Изменить тему", true)
		theme.tooltip_text = "Загаданное слово/тема меняется на случайное"
		theme.pressed.connect(func():
			if not Net.host_tools.new_theme():
				theme.text = "Сейчас нельзя"
		)
		rows.append(theme)
	return rows


func _player_rows(p: Dictionary, info: Dictionary) -> Array:
	var rows: Array = []
	var seat: int = p.seat
	for st: Dictionary in p.stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := _label(str(st.label), 14, INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var spin := _spin(int(st.value), int(st.get("min", 0)), int(st.get("max", 9999)), 1)
		var key := str(st.key)
		spin.value_changed.connect(func(v: float): Net.host_tools.set_stat(seat, key, int(v)))
		row.add_child(spin)
		rows.append(row)
	if bool(p.cards):
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 8)
		var give := _button("Дать карту", true)
		give.tooltip_text = "Из колоды в руку"
		give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		give.pressed.connect(func(): Net.host_tools.give_card(seat))
		cards.add_child(give)
		var take := _button("Убрать карту", true)
		take.tooltip_text = "Забрать карту, полученную в этом ходу; если не получал — случайную"
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		take.pressed.connect(func(): Net.host_tools.take_card(seat))
		cards.add_child(take)
		rows.append(cards)
	if rows.is_empty() and not bool(p.remote):
		rows.append(_label("Для этой игры правок игрока нет.", 13, MUTED))
	if bool(p.remote):
		if bool(info.spectate):
			var spec := _button("Сделать зрителем", true)
			spec.tooltip_text = "За его место сядет бот; вернуть можно через «Паузу»"
			spec.pressed.connect(func(): Net.host_tools.make_spectator(seat))
			rows.append(spec)
		var kick := _button("Кикнуть", false)
		kick.tooltip_text = "Удерживайте, чтобы исключить игрока из пати"
		kick.add_theme_color_override("font_color", Color("ff8a8a"))
		LeaveGuard.hold(kick, func(): Net.host_tools.kick(seat), "Кикнуть?")
		rows.append(kick)
	return rows


func _vbox(gap: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## filled — обычная кнопка действия; иначе тихая (заголовки категорий, «✕», «Кикнуть»).
func _button(text: String, filled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var base := Color(1, 1, 1, 0.07) if filled else Color(1, 1, 1, 0.0)
		if state == "hover":
			base = Color(ACCENT, 0.22)
		elif state == "pressed":
			base = Color(ACCENT, 0.32)
		sb.bg_color = base
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED)
	return b


func _spin(value: int, lo: int, hi: int, step: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 96
	s.update_on_text_changed = false
	return s
