class_name PauseLayer
extends CanvasLayer
## Пауза поверх любой игры. У хоста во время партии — кнопка «⏸ Пауза»; на паузе у всех затемнение
## и окно. Хост здесь же сажает за стол друзей, которые вошли в пати посреди партии: вместо бота /
## вылетевшего игрока или новым местом (если игра это позволяет).
## Оформление — из темы текущей игры («ConfirmPanel», «SelectedButton»). Создаёт Net.

var _root: Control
var _button: Button
var _dim: ColorRect
var _panel: PanelContainer
var _key := ""
var _poll := 0.0
var _status := ""


func _ready() -> void:
	layer = 95
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "ConfirmPanel"
	_panel.visible = false
	_root.add_child(_panel)
	_button = Button.new()
	_button.text = "⏸ Пауза"
	_button.tooltip_text = "Поставить игру на паузу (только хост). Здесь же можно посадить за стол новых друзей из пати."
	_button.add_theme_font_size_override("font_size", 13)
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func():
		Sfx.play("click", -6)
		Net.set_paused(true))
	_button.visible = false
	_root.add_child(_button)
	Net.state_changed.connect(func(_v): _refresh())
	Net.pause_changed.connect(_refresh)
	Net.lobby_changed.connect(_refresh)
	Net.game_ended.connect(_refresh)
	Net.session_closed.connect(func(_r): _refresh())
	get_viewport().size_changed.connect(_place)


func _process(delta: float) -> void:
	# у хоста список ждущих меняется без рассылки состояния — проверяем пару раз в секунду
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		_refresh()


func _is_paused() -> bool:
	if not Net.in_session() or Net.view.is_empty():
		return false
	return Net.paused if Net.is_host() else bool(Net.view.get("game_paused", false))


func _refresh() -> void:
	var playing := Net.in_session() and not Net.view.is_empty() and (Net.in_game or not Net.is_host())
	var on := playing and _is_paused()
	# тема — от текущей игры (каждая ставит свою на корень окна): CanvasLayer её сам не наследует
	if _root.theme != get_tree().root.theme:
		_root.theme = get_tree().root.theme
		_key = ""
	var waiting := Net.waiting_members()
	_button.visible = playing and Net.is_host() and not on
	_button.text = "⏸ Пауза" + (" · ждут: %d" % waiting.size() if not waiting.is_empty() else "")
	_dim.visible = on
	_panel.visible = on
	var key := "%s|%s|%s|%s|%s" % [on, Net.is_host(), waiting, Net.free_seats(), _status]
	if key != _key:
		_key = key
		if on:
			_build(waiting)
	_place()


func _place() -> void:
	var vs := _root.get_viewport_rect().size
	_button.reset_size()
	# над панелью чата в правом нижнем углу — там она ничего на столе не закрывает
	var y := vs.y - _button.size.y - 60
	var scene := get_tree().current_scene
	if scene:
		for c in scene.find_children("*", "K12ChatPanel", true, false):
			if (c as Control).is_visible_in_tree():
				y = (c as Control).get_global_rect().position.y - _button.size.y - 6
				break
	_button.position = Vector2(vs.x - _button.size.x - 14, y)
	if _panel.visible:
		_panel.reset_size()
		_panel.position = (vs - _panel.size) * 0.5


func _label(t: String, size: int, alpha: float = 1.0) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", _panel.get_theme_color("font_color", "ConfirmPanel"))
	l.modulate.a = alpha
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 460
	return l


func _btn(t: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 17 if primary else 15)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.theme_type_variation = "SelectedButton"
	return b


func _build(waiting: Array) -> void:
	for c in _panel.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	var title := _label("ПАУЗА", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if not Net.is_host():
		var l := _label("Хост поставил игру на паузу. Часы хода стоят — можно спокойно отойти.", 16, 0.85)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		return
	var go := _btn("Продолжить игру", true)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func():
		_status = ""
		Net.set_paused(false))
	col.add_child(go)
	col.add_child(HSeparator.new())
	col.add_child(_label("Новые игроки", 18))
	if waiting.is_empty():
		col.add_child(_label("Друзья могут войти в пати по коду или приглашению Steam прямо сейчас — здесь появится кнопка, чтобы посадить их за стол.", 15, 0.8))
	var seats := Net.free_seats()
	var can_add := Net.can_add_seat()
	for w in waiting:
		col.add_child(_label("%s ждёт места:" % w["name"], 15))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		row.custom_minimum_size.x = 440
		for st in seats:
			var b := _btn("Вместо «%s»" % st["name"])
			b.tooltip_text = "Займёт это место со всеми картами и очками"
			var pe: int = w["peer"]
			var se: int = st["seat"]
			b.pressed.connect(func(): _seat(pe, se))
			row.add_child(b)
		if can_add:
			var nb := _btn("Новым игроком", true)
			var pe2: int = w["peer"]
			nb.pressed.connect(func(): _seat(pe2, -1))
			row.add_child(nb)
		if seats.is_empty() and not can_add:
			row.add_child(_label("В эту партию нельзя добавить игрока посреди игры — он сыграет в следующей.", 13, 0.7))
		col.add_child(row)
	if _status != "":
		col.add_child(_label(_status, 13, 0.8))


func _seat(peer: int, seat: int) -> void:
	Sfx.play("click", -6)
	var err := Net.seat_member(peer, seat)
	_status = err if err != "" else "Готово! Снимите паузу, когда все будут готовы."
	_refresh()
