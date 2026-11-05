extends Control
## Стол Unspoken: общая стопка, приватная рука и единогласная «Паника».

const Style := preload("res://games/the_mind/ui/tm_style.gd")
const Hand := preload("res://games/the_mind/ui/tm_hand.gd")
var app: Node
var _top: TopBar
var _body: VBoxContainer
var _view: Dictionary = {}
var _seat := -2
var _revealed := false
var _preview: Control
var _order: Array = []
var _hand_key := ""
var _play_zone: Control
var _drag_active := false
var _side_zone: Control
var _seat_positions: Dictionary = {}
var _fx_queue: Array = []
var _fx_running := false
var _seen_event := 0
var _shown_event := 0
var _shown_pile: Array = []
var _fx_epoch := ""
var _fx_generation := 0
var _fx_layer: Control
var _hand_control: Control
var _hand_signature := ""

func _ready() -> void:
	add_child(Style.Background.new())
	_top = TopBar.make(self, "Unspoken", Style.button, null, Style.ink(), Style.HEAD)
	_top.coin_at = func() -> Vector2: return get_global_rect().position + Vector2(48, size.y - 48)
	for item: Array in [["Правила", app.show_rules], ["Настройки", app.show_settings], ["Тема", _theme], ["Журнал", _journal]]:
		var b := Style.button(item[0], 14)
		b.pressed.connect(item[1])
		_top.actions.add_child(b)
	var leave := Style.button("Выйти", 14)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	_top.actions.add_child(leave)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", int(TopBar.HEIGHT) + 16)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	_body = Style.column(8)
	margin.add_child(_body)
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_fx_layer.z_index = 70
	_fx_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_fx_layer)
	Net.state_changed.connect(_state)
	if not Net.view.is_empty():
		_state(Net.view)

func _send(kind: String, data: Dictionary = {}) -> void:
	data["revision"] = _view.get("revision", -1)
	Net.send_action(kind, data)

func _state(view: Dictionary) -> void:
	var key := str([view.get("game_id"), view.get("level"), view.get("blind")])
	var entries: Array = view.get("events", [])
	if key != _fx_epoch:
		_fx_epoch = key
		_fx_generation += 1
		_fx_queue.clear()
		Style.clear(_fx_layer)
		_fx_running = false
		_seen_event = int(entries.back().id) if not entries.is_empty() else 0
		_shown_event = _seen_event
		_shown_pile = (view.get("pile", []) as Array).duplicate()
		if bool(view.get("blind", false)) and _shown_pile.is_empty():
			_shown_pile.resize(int(view.get("pile_count", 0)))
			_shown_pile.fill(0)
	else:
		for entry: Dictionary in entries:
			if int(entry.id) > _seen_event:
				_fx_queue.append(entry.duplicate())
				_seen_event = int(entry.id)
	if _seat != int(view.get("seat", -1)) or key != _hand_key:
		_revealed = not bool(view.get("hotseat", false))
		_order.clear()
	_seat = int(view.get("seat", -1))
	_hand_key = key
	_view = view
	_rebuild()
	if not _fx_running and not _fx_queue.is_empty():
		_run_fx.call_deferred()

func _rebuild() -> void:
	var hand_signature := str([_hand_key, _seat, _revealed, _view.get("spectator", false), _view.get("hand", [])])
	var keep_hand: bool = is_instance_valid(_hand_control) and hand_signature == _hand_signature
	if keep_hand:
		_hand_control.get_parent().remove_child(_hand_control)
	else:
		_hand_control = null
	_hand_signature = hand_signature
	Style.clear(_body)
	_seat_positions.clear()
	_drag_active = false
	_close_preview()
	if _view.is_empty():
		return
	_top.info.text = "Уровень %d / %d%s" % [int(_view.level), int(_view.target), " · вслепую" if _view.blind else ""]
	var players: Array = _view.players
	var seats := GridContainer.new()
	seats.columns = 4 if players.size() > 4 else players.size()
	seats.add_theme_constant_override("h_separation", 16)
	seats.add_theme_constant_override("v_separation", 8)
	_body.add_child(seats)
	for i in players.size():
		var text := "%s · %d карт" % [players[i].get("name", "Игрок"), int(players[i].count)]
		if _view.phase == "focus" and bool(_view.ready[i]):
			text += " · готов"
		if _view.phase == "vote" and bool(_view.votes[i]):
			text += " · за"
		var b := Style.button(("● " if i == _seat else "") + text)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.clip_text = true
		b.disabled = not bool(_view.get("hotseat", false))
		b.pressed.connect(func(): Net.send_action("view_seat", {"seat": i}))
		seats.add_child(b)
		_seat_positions[i] = b
		TurnNameGlow.apply(b, TurnSeats.acting("the_mind", _view).has(i))
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 8))
	_body.add_child(status)
	var status_row := Style.row(16)
	status.add_child(status_row)
	var status_col := Style.column(8)
	status_col.size_flags_horizontal = SIZE_EXPAND_FILL
	status_row.add_child(status_col)
	status_col.add_child(Style.heading("ЖИЗНИ  %d     /     ПАНИКА  %d" % [int(_view.lives), int(_view.panic)], 28))
	var msg := Style.label(str(_view.message))
	if _view.phase == "play" and not bool(_view.get("can_play", true)):
		msg.text = "У вас меньшая карта — нажмите СТОП." if bool(_view.get("can_stop", false)) else "Ждём СТОП владельца меньшей карты."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_col.add_child(msg)
	status_col.add_child(Style.label("Бонус за уровень: " + str(_view.get("level_reward", "без бонуса")), 14))
	var panic_card := Style.PanicCard.new()
	panic_card.mouse_entered.connect(_show_panic)
	panic_card.mouse_exited.connect(_close_preview)
	status_row.add_child(panic_card)
	var play_row := Style.row(16)
	play_row.size_flags_vertical = SIZE_EXPAND_FILL
	_body.add_child(play_row)
	var center := CenterContainer.new()
	_play_zone = center
	center.draw.connect(_draw_drop_zone)
	center.size_flags_vertical = SIZE_EXPAND_FILL
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	play_row.add_child(center)
	var stack := Style.column(8)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stack)
	var pile: Array = _shown_pile
	if not _fx_running and _fx_queue.is_empty() and _view.phase in ["level_done", "game_over"]:
		pile = _view.pile
	if not pile.is_empty():
		var number := int(pile.back())
		var face: Control
		if number > 0:
			face = Style.face(number)
		else:
			face = Control.new()
			face.draw.connect(func(): Style.back(face, Rect2(Vector2.ZERO, face.size)))
		face.custom_minimum_size = Vector2(96, 140)
		face.size_flags_horizontal = SIZE_SHRINK_CENTER
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		if number > 0:
			face.mouse_entered.connect(func(): _show_preview({"value": number}))
		face.mouse_exited.connect(_close_preview)
		stack.add_child(face)
	else:
		var empty := Style.heading("%d КАРТ В СТОПКЕ" % int(_view.pile_count) if int(_view.pile_count) > 0 else "ПОЧУВСТВУЙТЕ МОМЕНТ", 28)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(empty)
	var last: Dictionary = _view.get("last_play", {})
	if not last.is_empty():
		var who := int(last.get("seat", -1))
		if who >= 0 and who < players.size():
			var played := Style.label("Последняя карта: %s" % players[who].get("name", "Игрок"))
			played.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stack.add_child(played)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 176
	side.size_flags_vertical = SIZE_EXPAND_FILL
	play_row.add_child(side)
	_side_zone = side
	var side_col := Style.column(8)
	side.add_child(side_col)
	side_col.add_child(Style.label("СБРОС · %d" % (_view.discarded as Array).size()))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	side_col.add_child(scroll)
	var discards := GridContainer.new()
	discards.columns = 2
	discards.add_theme_constant_override("h_separation", 8)
	discards.add_theme_constant_override("v_separation", 8)
	scroll.add_child(discards)
	for item: Dictionary in _view.get("discard_info", []):
		if int(item.id) > _shown_event:
			continue
		var col := Style.column(4)
		discards.add_child(col)
		var owner := Style.label(str(players[int(item.seat)].get("name", "Игрок")), 12)
		owner.clip_text = true
		col.add_child(owner)
		var face := Style.face(int(item.card), 28, 12)
		face.custom_minimum_size = Vector2(64, 96)
		face.mouse_filter = MOUSE_FILTER_STOP
		face.mouse_entered.connect(func(): _show_preview({"value": int(item.card)}))
		face.mouse_exited.connect(_close_preview)
		col.add_child(face)
	var actions := Style.row(16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(actions)
	var active: bool = _seat >= 0 and not bool(_view.get("spectator", false))
	var paused: bool = bool(_view.get("game_paused", false))
	match str(_view.phase):
		"focus":
			if active and not (_view.hand as Array).is_empty():
				var ready := Style.primary("Готов" if not bool(_view.ready[_seat]) else "Ждём команду…")
				ready.name = "Ready"
				ready.disabled = paused or bool(_view.ready[_seat])
				ready.pressed.connect(func(): _send("ready"))
				actions.add_child(ready)
		"play":
			if active:
				var stop := Style.primary("СТОП") if bool(_view.get("can_stop", false)) else Style.button("СТОП")
				stop.name = "Stop"
				stop.disabled = paused or not bool(_view.get("can_stop", false))
				stop.pressed.connect(func(): _send("stop"))
				actions.add_child(stop)
				for item: Array in [["Паника", "panic"], ["Собраться", "refocus"]]:
					var b := Style.button(item[0])
					b.disabled = paused or not bool(_view.get("can_play", true)) or (item[1] == "panic" and int(_view.panic) == 0)
					if item[1] == "refocus" and float(_view.get("refocus_left", 0.0)) > 0.0:
						b.disabled = true
						b.tooltip_text = "Между сборами команды должно пройти 15 секунд."
					b.pressed.connect(func(): _send(item[1]))
					actions.add_child(b)
		"vote":
			if active:
				var yes := Style.primary("Согласен" if not bool(_view.votes[_seat]) else "Вы согласились")
				yes.disabled = paused or bool(_view.votes[_seat])
				yes.pressed.connect(func(): _send("yes"))
				actions.add_child(yes)
				var no := Style.button("Без Паники")
				no.disabled = paused
				no.pressed.connect(func(): _send("no"))
				actions.add_child(no)
		"level_done":
			if active:
				var next := Style.primary("Следующий уровень")
				next.disabled = paused
				next.pressed.connect(func(): _send("next"))
				actions.add_child(next)
	var hand: Array = _view.hand
	if active and not hand.is_empty():
		if not _revealed:
			var reveal := Style.primary("Показать мою руку")
			reveal.pressed.connect(func():
				_revealed = true
				_rebuild())
			_body.add_child(reveal)
			var hidden := Control.new()
			hidden.custom_minimum_size.y = 158
			_body.add_child(hidden)
		else:
			var hint := Style.label("Ваша рука · нажмите карту или перетащите её в центр")
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_body.add_child(hint)
			if keep_hand:
				_body.add_child(_hand_control)
			else:
				var row := Hand.new()
				_hand_control = row
				row.card_size = Vector2(104, 140)
				row.order = _order.duplicate()
				for value: int in hand:
					row.entries.append({"key": str(value), "value": value, "face_up": true})
				row.chosen.connect(_chosen)
				row.drop_action = _drop_card
				row.drag_began.connect(func(_entry): _set_drag(true))
				row.drag_ended.connect(func(): _set_drag(false))
				row.order_changed.connect(func(keys): _order = keys)
				row.preview_requested.connect(_show_preview)
				row.preview_closed.connect(_close_preview)
				_body.add_child(row)
	else:
		var empty_hand := Style.label("Зритель: чужие карты скрыты." if not active else "Вы сыграли все карты. Следите за командой.")
		empty_hand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(empty_hand)

func _chosen(entry: Dictionary) -> void:
	if _view.phase != "play" or not bool(_view.get("can_play", true)) or bool(_view.get("game_paused", false)):
		return
	var hand: Array = _view.hand
	if not hand.is_empty() and int(entry.value) != int(hand.min()):
		app.popup("СНАЧАЛА МЕНЬШАЯ КАРТА", "Каждый разыгрывает свою наименьшую карту. Остальные можно переставлять в руке.")
		return
	_send("play", {"card": int(entry.value)})

func _set_drag(active: bool) -> void:
	_drag_active = active and bool(_view.get("can_play", true)) and _view.get("phase") == "play" and not bool(_view.get("game_paused", false))
	if is_instance_valid(_play_zone):
		_play_zone.queue_redraw()

func _draw_drop_zone() -> void:
	if _drag_active and is_instance_valid(_play_zone):
		var frame := Style.box(Color(Style.GOLD, 0.1), 0)
		frame.border_color = Color(Style.GOLD, 0.65)
		frame.set_border_width_all(2)
		_play_zone.draw_style_box(frame, Rect2(Vector2(8, 8), _play_zone.size - Vector2(16, 16)))

func _drop_card(entry: Dictionary, at: Vector2) -> bool:
	if not is_instance_valid(_play_zone) or not _play_zone.get_global_rect().has_point(at):
		return false
	if _view.get("phase") != "play" or not bool(_view.get("can_play", true)) or bool(_view.get("game_paused", false)):
		return false
	_chosen(entry)
	return true

func presentation_view() -> Dictionary:
	if _view.get("phase") == "game_over" and (_fx_running or not _fx_queue.is_empty()):
		var shown := _view.duplicate()
		shown.phase = "presenting"
		return shown
	return _view

func _run_fx() -> void:
	if _fx_running:
		return
	_fx_running = true
	var generation := _fx_generation
	while not _fx_queue.is_empty() and generation == _fx_generation:
		var entry: Dictionary = _fx_queue.pop_front()
		await get_tree().process_frame
		if generation != _fx_generation or not is_inside_tree():
			return
		var who := int(entry.seat)
		var origin := Vector2(size.x * 0.5, size.y - 96)
		if who != _seat and _seat_positions.has(who) and is_instance_valid(_seat_positions[who]):
			origin = (_seat_positions[who] as Control).get_global_rect().get_center()
		var destination := _play_zone.get_global_rect().get_center()
		if entry.kind == "discard":
			destination = _side_zone.get_global_rect().get_center()
		var moving := Control.new()
		moving.size = Vector2(112, 170)
		moving.mouse_filter = MOUSE_FILTER_IGNORE
		moving.pivot_offset = moving.size * 0.5
		moving.position = origin - global_position - moving.size * 0.5
		moving.rotation = -0.1
		_fx_layer.add_child(moving)
		var owner := Style.label(str((_view.players as Array)[who].get("name", "Игрок")), 14)
		owner.size.x = 112
		owner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		moving.add_child(owner)
		var up := int(entry.card) > 0
		var card := K12TableCard.new("effect", up, Style.face(int(entry.card)), Vector2(96, 140))
		card.back_drawer = Style.back
		card.position = Vector2(8, 24)
		card.mouse_filter = MOUSE_FILTER_IGNORE
		moving.add_child(card)
		var tween := create_tween().set_parallel()
		tween.tween_property(moving, "position", destination - global_position - moving.size * 0.5, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(moving, "rotation", 0.025, 0.34)
		await tween.finished
		if generation != _fx_generation:
			return
		if entry.kind == "play":
			_shown_pile.append(int(entry.card))
		_shown_event = int(entry.id)
		moving.queue_free()
		_rebuild()
	_fx_running = false
	_rebuild()

func _show_preview(entry: Dictionary) -> void:
	if preload("res://hub/card_magnifier.gd").offer(self):
		return
	_close_preview()
	_preview = Style.face(int(entry.value))
	_preview.z_index = 85
	_preview.size = Vector2(180, 264)
	_preview.position = size * 0.5 - _preview.size * 0.5
	add_child(_preview)

func _close_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null

func _show_panic() -> void:
	_close_preview()
	_preview = Style.PanicCard.new()
	_preview.z_index = 85
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	_preview.size = Vector2(180, 240)
	_preview.position = size * 0.5 - _preview.size * 0.5
	add_child(_preview)

func _journal() -> void:
	app.popup("ЖУРНАЛ", "\n".join(_view.get("log", [])))

func _theme() -> void:
	Prefs.set_value("theme_mode", "light" if Style.dark() else "dark")
