class_name PauseLayer
extends Node
## Пауза поверх любой игры. У хоста во время партии — кнопка «⏸ Пауза»; на паузе у всех затемнение
## и окно. Хост здесь же сажает за стол друзей, которые вошли в пати посреди партии: вместо бота /
## вылетевшего игрока или новым местом (если игра это позволяет).
## Здесь же управляется антистресс-монетка (Fidget): во всех играх во время партии, в сцене игры над столом.
## Оформление — из темы текущей игры («ConfirmPanel», «SelectedButton»). Создаёт Net.

var _root: Control
var _overlay_scene: WeakRef
var _button: Button
var _button_icon: Control
const FidgetScript := preload("res://hub/fidget.gd")
const PlayPauseScript := preload("res://hub/play_pause_icon.gd")  # иконка «‖ ↔ ▶» с морфом  # по пути: слой грузится до регистрации классов
var _fidget: Control  # антистресс — во всех играх
var _spec_button: Button  # «Стать зрителем» — у любого игрока за столом
var _spec_banner: Label  # у зрителя: «Вы зритель…»
var _offer: PanelContainer  # у зрителя: «Сесть вместо бота» / «Войти в команду» — согласиться или отказаться
var _offer_key := ""
var _offer_declined := ""  # от этого набора мест зритель отказался — пока он не изменится, не предлагаем
## У зрителя работают только эти кнопки (по тексту); остальное в игре — действия, их зритель не жмёт.
const SPECTATOR_OK := ["Правила", "Настройки", "Журнал", "Выйти", "Покинуть", "Завершить", "Закрыть", "Понятно",
	"К выбору", "В меню", "Всё поле", "К фишке", "+", "−", "Чат", "Быстрый", "Отмена", "Назад", "Остаться"]
var _dim: ColorRect
var _panel: PanelContainer
var _key := ""
var _poll := 0.0
var _status := ""


func _ready() -> void:
	_root = Control.new()
	_root.name = "PauseOverlay"
	_root.z_index = 70
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	_root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "ConfirmPanel"
	_panel.visible = false
	_root.add_child(_panel)
	_button = Button.new()
	_button.text = "Пауза"
	_button.tooltip_text = "Поставить игру на паузу (только хост). Здесь же можно посадить за стол новых друзей из пати."
	_button.add_theme_font_size_override("font_size", 13)
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.focus_mode = Control.FOCUS_NONE
	var bic = PlayPauseScript.attach(_button, Net.paused)
	_button_icon = bic
	_button.pressed.connect(func():
		Sfx.play("click", -6)
		bic.morph(true, func(): Net.set_paused(true)))
	_button.visible = false
	_root.add_child(_button)
	_spec_button = Button.new()
	_spec_button.text = "👁 Стать зрителем"
	_spec_button.tooltip_text = "Выйти из-за стола и смотреть: за ваше место будет играть бот. Вернуть за стол может хост через «Паузу»."
	_spec_button.add_theme_font_size_override("font_size", 13)
	_spec_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_spec_button.focus_mode = Control.FOCUS_NONE
	_spec_button.pressed.connect(func():
		LeaveGuard.ask(_spec_button, "Стать зрителем?", "За ваше место будет играть бот. Вы увидите стол как обычный игрок; вернуть за стол может хост через «Паузу».", "Смотреть", Net.become_spectator, "Остаться в игре"))
	_spec_button.visible = false
	_root.add_child(_spec_button)
	_spec_banner = Label.new()
	_spec_banner.text = "👁 Вы зритель — хост может посадить вас за стол через «Паузу»"
	_spec_banner.add_theme_font_size_override("font_size", 15)
	_spec_banner.add_theme_color_override("font_color", Color("f4efe4"))
	_spec_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_spec_banner.add_theme_constant_override("outline_size", 6)
	_spec_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spec_banner.visible = false
	_root.add_child(_spec_banner)
	_offer = PanelContainer.new()
	_offer.theme_type_variation = "ConfirmPanel"
	_offer.visible = false
	_root.add_child(_offer)
	# После смены темы сцена уже готова: восстанавливаем монетку до следующего кадра, без ожидания опроса.
	get_tree().scene_changed.connect(_refresh)
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


## Закрываем открытый просмотр при входе в паузу; игровые окна остаются под затемнением.
func _hide_card_previews(scene: Node) -> void:
	if scene == null:
		return
	for node: Node in scene.find_children("*", "Control", true, false):
		if node.has_method("_hide_preview"):
			node.call("_hide_preview")
		else:
			for property: Dictionary in node.get_property_list():
				if property.name == "_preview":
					var preview: Variant = node.get("_preview")
					if is_instance_valid(preview) and preview is Control:
						preview.hide()


func _is_paused() -> bool:
	if not Net.in_session() or Net.view.is_empty():
		return false
	return Net.paused if Net.is_host() else bool(Net.view.get("game_paused", false))


func _refresh() -> void:
	var scene := get_tree().current_scene
	_attach_overlay(scene)
	var in_hub := scene != null and scene.scene_file_path == HubGames.HUB_SCENE
	# в хабе (меню) пауза и плашки не показываются — даже если от партии осталось состояние
	var playing := Net.in_session() and not Net.view.is_empty() and (Net.in_game or not Net.is_host()) and not in_hub
	var on := playing and _is_paused()
	if on and not _dim.visible:
		_hide_card_previews(scene)
	# тема — от текущей игры (каждая ставит свою на корень окна): CanvasLayer её сам не наследует
	if _root.theme != get_tree().root.theme:
		_root.theme = get_tree().root.theme
		_key = ""
	var waiting := Net.waiting_members()
	# у стола с верхней полосой (TopBar) пауза и «зритель» — в ней
	var has_bar := get_tree().get_first_node_in_group("top_bar") != null
	for bar: TopBar in get_tree().get_nodes_in_group("top_bar"):
		_lift_service(bar, on)
		_lift_service(bar.chat, on)
	_button.visible = playing and Net.is_host() and not on and not has_bar
	_place_fidget(playing)
	_order_overlay_input(scene)
	var spectator := playing and bool(Net.view.get("spectator", false))
	_spec_banner.visible = spectator and not on
	_update_offer(spectator and not on)
	_spec_button.visible = playing and not on and not spectator and Net.can_spectate() and not has_bar
	_button_icon.sync_state(on)
	_button.text = ("Продолжить" if on else "Пауза") + (" · ждут: %d" % waiting.size() if not waiting.is_empty() else "")
	_dim.visible = on
	_panel.visible = on
	var key := "%s|%s|%s|%s|%s" % [on, Net.is_host(), waiting, Net.free_seats(), _status]
	if key != _key:
		_key = key
		if on:
			_build(waiting)
	_place()


## Общий canvas: стол ниже паузы, верхняя полоса/чат/монетка выше,
## окна правил и настроек выше обоих. При смене сцены сохраняем общий оверлей.
func _attach_overlay(scene: Node) -> void:
	if scene == null or _root.get_parent() == scene:
		return
	var previous: Node = _overlay_scene.get_ref() if _overlay_scene != null else null
	if is_instance_valid(previous) and previous.tree_exiting.is_connected(_detach_overlay):
		previous.tree_exiting.disconnect(_detach_overlay)
	_root.reparent(scene, false)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_scene = weakref(scene)
	if not scene.tree_exiting.is_connected(_detach_overlay):
		scene.tree_exiting.connect(_detach_overlay, CONNECT_ONE_SHOT)


func _detach_overlay() -> void:
	if is_instance_valid(_root) and not is_queued_for_deletion():
		_root.reparent(self, false)


## z_index задаёт отрисовку, но GUI ищет цель мыши в обратном порядке детей.
## Стол и монетка создаются/пересобираются после оверлея: окно паузы должно идти
## после них, а служебные окна (правила, настройки) — после окна паузы.
func _order_overlay_input(scene: Node) -> void:
	if scene == null or _root.get_parent() != scene:
		return
	var windows: Array[Node] = []
	var last_table := -1
	for child: Node in scene.get_children():
		if child == _root:
			continue
		if child is Control and (child as Control).z_index >= 100:
			windows.append(child)
		else:
			last_table = child.get_index()
	var misplaced := _root.get_index() < last_table
	for window: Node in windows:
		misplaced = misplaced or window.get_index() < _root.get_index()
	if misplaced:
		scene.move_child(_root, -1)
		for window: Node in windows:
			scene.move_child(window, -1)


func _lift_service(control: Control, on: bool) -> void:
	if on:
		if not control.has_meta("pause_z"):
			control.set_meta("pause_z", control.z_index)
		control.z_index = 90
	elif control.has_meta("pause_z"):
		control.z_index = int(control.get_meta("pause_z"))
		control.remove_meta("pause_z")


## Монетка живёт в сцене игры, сразу над столом (app.screen): окна поверх стола (настройки, правила,
## подтверждения) её закрывают, а при выходе из игры она исчезает вместе со сценой.
func _place_fidget(show: bool) -> void:
	var sc := get_tree().current_scene
	if sc != null and sc.scene_file_path == HubGames.HUB_SCENE:
		FidgetScript.forget()
	if not show or not (sc is Control):
		if is_instance_valid(_fidget):
			_fidget.visible = false
		return
	if not is_instance_valid(_fidget) or _fidget.get_parent() != sc:
		if is_instance_valid(_fidget):
			_fidget.queue_free()
		_fidget = FidgetScript.new()
		sc.add_child(_fidget)
	_fidget.visible = true
	var screen = sc.get("screen")
	var want := (screen as Node).get_index() + 1 if screen is Node and (screen as Node).get_parent() == sc else sc.get_child_count() - 1
	if _fidget.get_index() != mini(want, sc.get_child_count() - 1):
		sc.move_child(_fidget, mini(want, sc.get_child_count() - 1))


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
	_spec_button.reset_size()
	var bx := _button.position.x - _spec_button.size.x - 8 if _button.visible else vs.x - _spec_button.size.x - 14
	_spec_button.position = Vector2(bx, y)
	_spec_banner.reset_size()
	var top := 56.0 if get_tree().get_first_node_in_group("top_bar") != null else 44.0  # под верхней полосой стола
	_spec_banner.position = Vector2((vs.x - _spec_banner.size.x) * 0.5, top)
	_offer.reset_size()
	_offer.position = Vector2((vs.x - _offer.size.x) * 0.5, top + 32)
	if _panel.visible:
		_panel.reset_size()
		_panel.position = (vs - _panel.size) * 0.5


func _label(t: String, size: int, alpha: float = 1.0) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	var has_panel_color := _root.theme != null and _root.theme.has_color("font_color", "ConfirmPanel")
	var color_type := "ConfirmPanel" if has_panel_color else "Label"
	l.add_theme_color_override("font_color", _panel.get_theme_color("font_color", color_type))
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
		_invite_block(col)
		return
	var go := _btn("Продолжить игру", true)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var gic = PlayPauseScript.attach(go, true)
	go.pressed.connect(func():
		_status = ""
		gic.morph(false, func(): Net.set_paused(false)))  # «▶» перетекает в «‖» — игра пошла
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
	_invite_block(col)
	if _status != "":
		col.add_child(_label(_status, 13, 0.8))


## «Пригласить в пати»: окно друзей Steam и код комнаты — у всех, кто в пати.
func _invite_block(col: VBoxContainer) -> void:
	var party := Net.is_party()
	col.add_child(HSeparator.new())
	col.add_child(_label("Пригласить друзей", 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var steam_ok: bool = party and Net.mode == "steam" and Net.steam_ok
	var inv := _btn("Пригласить через Steam", steam_ok)
	inv.disabled = not steam_ok
	inv.tooltip_text = "Список друзей Steam — приглашение придёт им в Steam" if steam_ok else "Пати не через Steam — дайте друзьям код комнаты"
	inv.pressed.connect(func():
		Sfx.play("click", -6)
		SteamInvite.open_panel(99))
	row.add_child(inv)
	var code := Net.lobby_code() if party else ""
	var cp := _btn("Скопировать код комнаты")
	cp.disabled = not party
	cp.tooltip_text = code
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		Sfx.play("click", -6)
		cp.text = "Код скопирован ✓")
	row.add_child(cp)
	col.add_child(row)
	if not party:
		var nl := _label("Сейчас игра на одном компьютере — друзей можно позвать в пати: в главном меню «Создать пати (Steam)» или по коду комнаты.", 13, 0.7)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nl)
		return
	var cl := _label("Код: " + code, 13, 0.7)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cl)


func _seat(peer: int, seat: int) -> void:
	Sfx.play("click", -6)
	var err := Net.seat_member(peer, seat)
	_status = err if err != "" else "Готово! Снимите паузу, когда все будут готовы."
	_refresh()


## Зритель не нажимает игровые кнопки (хост всё равно не примет его действия) — пропускаем только
## «служебные»: правила, настройки, выход, чат, окна подтверждения и управление видом.
func _input(event: InputEvent) -> void:
	if _is_paused() and (event is InputEventMouse or event is InputEventKey):
		var target := _root.get_viewport().gui_get_focus_owner() if event is InputEventKey else _root.get_viewport().gui_get_hovered_control()
		var dragging_coin := event is InputEventMouse and is_instance_valid(_fidget) and bool(_fidget.get("_holding"))
		if not dragging_coin and not _pause_allowed(target):
			_root.get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton and event.pressed) or not bool(Net.view.get("spectator", false)):
		return
	var c := _root.get_viewport().gui_get_hovered_control()
	if c == null or not (c is BaseButton) or _spectator_allowed(c):
		return
	_root.get_viewport().set_input_as_handled()
	Sfx.play("card_shove", -12)


func _pause_allowed(control: Control) -> bool:
	var node: Node = control
	var scene := get_tree().current_scene
	while node != null and node != scene:
		if node == _root or node == _fidget or node is TopBar or node is K12ChatPanel:
			return true
		if node is Control and node.get_parent() == scene and (node as Control).z_index >= 100:
			return true
		node = node.get_parent()
	return false


func _spectator_allowed(c: Control) -> bool:
	var n: Node = c
	while n != null:
		if n == _root or n is K12ChatPanel or n is ThemeToggle:
			return true
		if n is Control and (n as Control).theme_type_variation == "ConfirmPanel":
			return true
		var sc: Script = n.get_script()
		if sc and "settings_screen" in sc.resource_path:
			return true
		n = n.get_parent()
	var t := str(c.get("text")) if c.get("text") != null else ""
	for ok in SPECTATOR_OK:
		if t.contains(ok):
			return true
	return false


## Предложение зрителю: свободное место бота (с его картами, костями, очками) или вход в команду.
func _update_offer(on: bool) -> void:
	var seats: Array = Net.view.get("free_seats", []) if on else []
	var teams: Array = Net.view.get("join_teams", []) if on else []
	var key := "%s|%s" % [seats, teams]
	var show := on and (not seats.is_empty() or not teams.is_empty()) and key != _offer_declined
	_offer.visible = show
	if not show or key == _offer_key:
		return
	_offer_key = key
	for c in _offer.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_offer.add_child(col)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	if not teams.is_empty():
		col.add_child(_label("Можно войти в игру — очки у команды общие:", 15))
		for t in teams:
			var tb := _btn("В команду" if teams.size() == 1 else "В команду %d" % (int(t) + 1), true)
			var tt := int(t)
			tb.pressed.connect(func():
				Sfx.play("click", -6)
				Net.spectator_join(-1, tt))
			row.add_child(tb)
	if not seats.is_empty():
		col.add_child(_label("Свободно место бота — можно сесть и продолжить с его прогрессом:", 15))
		for st in seats:
			var sb := _btn("Сесть вместо «%s»" % st["name"], teams.is_empty())
			var se := int(st["seat"])
			sb.pressed.connect(func():
				Sfx.play("click", -6)
				Net.spectator_join(se, -1))
			row.add_child(sb)
	var no := _btn("Не сейчас")
	no.pressed.connect(func():
		_offer_declined = key
		_offer.visible = false)
	row.add_child(no)
	col.add_child(row)
