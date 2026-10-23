extends Control
## Игровой стол: таверна, овальный стол, 3D-кубики, карты с рубашками и перетаскиванием.
## Рисует состояние из Net.view и отправляет действия через Net.send_action.
## Элементы (кубики, карты) живут между обновлениями, чтобы их можно было анимировать.

var app: Node

const TABLE_SCALE := 0.5  # карты на столе
const HAND_SCALE := 0.78  # карты в руке
const HOVER_SCALE := 1.0

var _v := {}
var _me := 0
var _n := 0

var _bg: K12Tavern
var _table_layer: Control
var _plates_layer: Control
var _hand_layer: Control
var _ui_layer: Control
var _overlay: Control
var _round_label: Label
var _banner: Label
var _center_panel: PanelContainer
var _auto_label: Label
var _auto_deadline := 0

var _dice: Array = []  # место -> K12Die3D
var _seen_throw: Array = []
var _plates: Array = []
var _slots := {}  # место -> K12TableCard
var _hand := {}  # карта -> K12TableCard
var _hover := ""
var _revealed_key := ""
var _revealing := false  # идёт поэтапное вскрытие — новые состояния ждут в _queued
var _queued := {}

const REVEAL_DUP := 2.6  # пауза после вскрытия одинаковых карт
const REVEAL_ONE := 2.0  # пауза после каждой следующей карты
var _stamped_key := ""

var _phase_key := ""  # для звуков при смене фазы
var _fx: Control  # пузыри чата, подсказки, конфетти — не очищается вместе с окнами
var _hand_order: Array = []  # свой порядок карт в руке (перетаскивание внутри веера)
var _reveal_tween: Tween
var _coins_key := ""
var _celebrated := false
var _hints_shown := {}
var _hint_panel: PanelContainer
var _chat: K12ChatPanel
var _top: TopBar
var _bubbles := {}  # место -> Label
var _autoplay := OS.get_cmdline_user_args().has("--autoplay")  # отладка: играть за себя случайно
var _autoplay_done := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = K12Tavern.new(true)
	add_child(_bg)
	for layer_name in ["_plates_layer", "_table_layer", "_ui_layer", "_hand_layer", "_overlay", "_fx"]:
		var layer := Control.new()
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		set(layer_name, layer)

	_top = TopBar.make(self, "Дюжина короля", func(t, z): return K12UI.button(t, z), null, K12UI.CREAM, K12UI.font("bold"))
	_round_label = _top.info
	var rules_btn := K12UI.button("Правила", K12UI.CAP)
	rules_btn.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules_btn)
	var hist_btn := K12UI.button("История", K12UI.CAP)
	hist_btn.pressed.connect(_show_history)
	_top.actions.add_child(hist_btn)
	var set_btn := K12UI.button("Настройки", K12UI.CAP)
	set_btn.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(set_btn)
	var leave_btn: Button
	if Net.is_party() and Net.is_host():
		leave_btn = K12UI.button("Завершить партию", K12UI.CAP)
		leave_btn.tooltip_text = "Все вернутся в лобби игры, пати сохранится"
		LeaveGuard.wire(leave_btn, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave_btn = K12UI.button("Покинуть пати", K12UI.CAP)
		LeaveGuard.wire(leave_btn, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave_btn = K12UI.button("Выйти", K12UI.CAP)
		LeaveGuard.wire(leave_btn, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	leave_btn.theme_type_variation = "QuietButton"
	_top.actions.add_child(leave_btn)

	_banner = K12UI.label("", K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_banner)

	_center_panel = PanelContainer.new()
	_center_panel.add_theme_stylebox_override("panel", K12UI.box(Color(0.06, 0.12, 0.09, 0.88), 12, Color("c9a35a"), 1))
	_center_panel.visible = false
	_ui_layer.add_child(_center_panel)

	_chat = _top.chat
	Net.chat_received.connect(_on_chat_bubble)

	resized.connect(_relayout_all)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


# =============================================================================
# Геометрия мест
# =============================================================================

func _cx() -> float:
	return size.x / 2.0 if size.x > 0 else 640.0


func _tc() -> Vector2:
	return Vector2(_cx(), K12Tavern.TABLE_Y)


## Угол места на овале: «я» внизу (90°), остальные — по часовой стрелке через левый край.
func _angle(seat: int) -> float:
	var rel := (seat - _me + _n) % _n
	return deg_to_rad(90.0 + rel * 360.0 / _n)


func _on_oval(seat: int, k: float, radii: Vector2) -> Vector2:
	var a := _angle(seat)
	return _tc() + Vector2(cos(a) * radii.x, sin(a) * radii.y) * k


func _slot_pos(seat: int) -> Vector2:
	return _on_oval(seat, 0.66, _bg.felt_radii())


## Кубик стоит рядом с картой, вдоль края стола.
func _die_pos(seat: int) -> Vector2:
	var a := _angle(seat)
	return _slot_pos(seat) + Vector2(sin(a), -cos(a)) * (112.0 if _n <= 5 else 96.0)


func _plate_rect(seat: int) -> Rect2:
	if seat == _me:
		return Rect2(10, size.y - 140, 230, 130)
	var sz := Vector2(204, 112)
	var c := _on_oval(seat, 1.0, K12Tavern.TABLE_RADII)
	var r := Rect2(c - sz / 2.0, sz)
	r.position.x = clampf(r.position.x, 8, size.x - sz.x - 8)
	r.position.y = clampf(r.position.y, TopBar.HEIGHT + 4, size.y - sz.y - 150)
	return r


func _plate_center(seat: int) -> Vector2:
	return _plate_rect(seat).get_center()


# =============================================================================
# Обновление по состоянию
# =============================================================================

func _on_state(v: Dictionary) -> void:
	if _revealing:
		_queued = v
		return
	_apply_state(v)


func _apply_state(v: Dictionary) -> void:
	_v = v
	_me = v["you"]
	_n = v["players"].size()
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	if _dice.size() != _n:
		_build_seats()
	if _needs_reveal():
		_start_reveal()
		return
	_update_dice()
	_update_slots()
	_update_hand()
	_update_plates()
	_update_center()
	_update_overlay()
	_phase_sounds()
	if _v["phase"] == "trick_result":
		Prefs.record_trick(_v)
		_fly_coins()
	elif _v["phase"] == "game_over":
		Prefs.record_game(_v)
		_celebrate()
		if _v.get("tutorial", false):
			Prefs.set_value("tutorial_seen", true)
	if _v.get("tutorial", false):
		_tutorial_hints()
	if _autoplay:
		_autoplay_step.call_deferred()


func _build_seats() -> void:
	for d in _dice:
		d.queue_free()
	_dice.clear()
	_seen_throw.clear()
	K12UI.clear(_plates_layer)
	_plates.clear()
	for s in _n:
		var die := K12Die3D.new()
		_table_layer.add_child(die)
		die.home = _die_pos(s)
		die.felt_center = _tc()
		die.felt_radii = _bg.felt_radii()
		die.position = die.home - die.size / 2.0
		if _n > 5:
			die.scale = Vector2.ONE * 0.8
		var seat := s
		die.thrown.connect(func(vel): _on_my_throw(seat, vel))
		_dice.append(die)
		_seen_throw.append(0)
		var plate := K12Plate.new(false)
		_plates_layer.add_child(plate)
		_plates.append(plate)
	_relayout_all()


func _relayout_all() -> void:
	if _n == 0 or _dice.is_empty():
		return
	for s in _n:
		var die: K12Die3D = _dice[s]
		die.home = _die_pos(s)
		die.felt_center = _tc()
		if not die.is_busy():
			die.position = die.home - die.size / 2.0
		var r := _plate_rect(s)
		_plates[s].position = r.position
		_plates[s].size = r.size
		if _slots.has(s):
			_slots[s].place(_slot_pos(s), 0.0, TABLE_SCALE)
	var reactions := _ui_layer.get_node_or_null("Reactions") as Control
	if reactions:
		reactions.position = Vector2(10, size.y - 178)
	_layout_hand()
	_update_center()


# --- Кубики --------------------------------------------------------------------

func _update_dice() -> void:
	var phase: String = _v["phase"]
	var trick: Dictionary = _v["trick"]
	var show_trick := phase == "trick_result" and not trick.is_empty()
	for s in _n:
		var die: K12Die3D = _dice[s]
		var rolled: bool = _v["rolled"][s]
		var th: Dictionary = _v["throws"][s]
		var face: int = int(_v["faces"][s])
		if th.has("id") and int(th["id"]) != _seen_throw[s]:
			_seen_throw[s] = int(th["id"])
			if die.state in ["dragging", "flying", "settling"]:
				die.set_result(face)
			else:
				var vel := Vector2(float(th.get("vx", 0.0)), float(th.get("vy", 0.0)))
				if vel.length() < 200.0:
					vel = (_tc() - die.home).normalized().rotated(randf_range(-0.6, 0.6)) * 900.0
				die.throw(vel, face)
		elif (phase == "roll" and not rolled) or (phase == "oracle" and _v["pending"].get("seat", -1) == s):
			if die.state not in ["waiting", "dragging", "flying", "settling", "returning"]:
				die.wait_for_roll()
		else:
			die.show_face(face)
		var my_roll: bool = (phase == "roll" and not rolled) or (phase == "oracle" and _v["pending"].get("seat", -1) == s)
		die.draggable = my_roll and s == _me and die.state == "waiting"
		die.crossed = show_trick and trick["dice_cancelled"][s]
		var chains: Array = trick.get("chains", [])
		var chain: String = chains[s] if show_trick and s < chains.size() else ""
		if show_trick:
			die.value_text = chain if chain != "" else "= %d" % trick["values"][s]
		else:
			die.value_text = ""
		if show_trick and trick["winner"] == s:
			die.highlight = Color(K12UI.GOLD, 0.9)
		elif show_trick and trick["second"] == s:
			die.highlight = Color(0.85, 0.88, 0.92, 0.8)
		else:
			die.highlight = Color.TRANSPARENT


func _on_my_throw(seat: int, vel: Vector2) -> void:
	if seat == _me:
		Net.send_action("oracle_roll" if _v.get("phase", "") == "oracle" else "roll", {"vx": vel.x, "vy": vel.y})


# --- Карты на столе --------------------------------------------------------------

func _update_slots() -> void:
	var phase: String = _v["phase"]
	var key := "%d/%d" % [_v["round_no"], _v["trick_no"]]
	var on_table := phase in ["select", "sorcerer", "oracle", "trick_result"]
	# новый розыгрыш или конец раунда — сыгранные карты уходят в сброс
	if not on_table or (phase == "select" and _revealed_key != "" and _revealed_key != key):
		_discard_slots()
		_revealed_key = ""
		_stamped_key = ""
	if not on_table:
		return
	if phase == "select":
		for s in _n:
			var chosen: bool = _v["chosen"][s]
			if chosen and not _slots.has(s):
				var c: K12TableCard
				if s == _me:
					c = _take_from_hand(_v["my_selected"])
				else:
					c = K12TableCard.new("", false)
					_table_layer.add_child(c)
					c.place(_plate_center(s), 0.0, 0.25)
					Sfx.play("card_place", -8, 0.08, 0.05)
				_put_on_slot(s, c)
			elif not chosen and _slots.has(s):
				var c: K12TableCard = _slots[s]
				_slots.erase(s)
				if s == _me:
					_return_to_hand(c)
				else:
					_fly_away(c, _plate_center(s))
		return
	var trick: Dictionary = _v["trick"]
	if not trick.is_empty() and _stamped_key != key:
		_stamped_key = key
		for s in _n:
			if not _slots.has(s):
				continue
			var stamp := ""
			if trick["card_cancelled"][s]:
				stamp = "ОТМЕНЕНА"
			elif trick["suppressed"][s]:
				stamp = "БЕЗ ЭФФЕКТА"
			var c: K12TableCard = _slots[s]
			get_tree().create_timer(0.3).timeout.connect(func():
				if is_instance_valid(c) and c.stamp != stamp:
					c.stamp = stamp
					if stamp != "":
						Sfx.play("card_shove", -8, 0.08, 0.05))
		var award: int = trick["awards"][_me]
		var anyone: bool = trick["awards"].any(func(a): return a > 0)
		get_tree().create_timer(1.0).timeout.connect(func():
			if award > 0:
				Sfx.play("chips_win", -2)
			elif anyone:
				Sfx.play("chip", -8))


# --- Поэтапное вскрытие --------------------------------------------------------------

func _needs_reveal() -> bool:
	var key := "%d/%d" % [_v["round_no"], _v["trick_no"]]
	return _v["phase"] in ["sorcerer", "oracle", "trick_result"] and _v["played"].size() == _n and _revealed_key != key


## Сначала одинаковые карты (и что они отменяются), затем остальные по одной, с паузами.
func _start_reveal() -> void:
	_revealing = true
	_revealed_key = "%d/%d" % [_v["round_no"], _v["trick_no"]]
	K12UI.clear(_overlay)
	_center_panel.visible = false
	var played: Array = _v["played"]
	for s in _n:
		if played[s] == "":
			continue  # зритель (переигровка турнира)
		var old: K12TableCard = _slots.get(s)
		if old != null and old.card == played[s]:
			old.draggable = false
			continue
		var c := K12TableCard.new(played[s], false)
		_table_layer.add_child(c)
		c.base_scale = TABLE_SCALE
		if old:
			c.place(old.center(), old.rotation, TABLE_SCALE)
			old.queue_free()
		else:
			c.place(_plate_center(s), 0.0, 0.25)
			c.move_to(_slot_pos(s), _slot_rot(), TABLE_SCALE, 0.3)
		_slots[s] = c
		_connect_slot(c, s)
	# порядок: по часовой от соседа слева, свою карту — последней
	var order := []
	for i in range(1, _n + 1):
		if played[(_me + i) % _n] != "":
			order.append((_me + i) % _n)
	# одинаковые карты отменяются только внутри своей группы (в обычной игре группа одна)
	var group_of := {}
	var groups: Array = _v.get("groups", [])
	for gi in groups.size():
		for s in groups[gi]:
			group_of[s] = gi
	var key_of := func(s): return "%d/%s" % [group_of.get(s, 0), played[s]]
	var counts := {}
	for s in order:
		counts[key_of.call(s)] = counts.get(key_of.call(s), 0) + 1
	var dups := []
	for s in order:
		if counts[key_of.call(s)] > 1 and not dups.has(key_of.call(s)):
			dups.append(key_of.call(s))
	var speed: float = {"fast": 0.55, "normal": 1.0, "slow": 1.5}.get(_v.get("reveal_speed", "normal"), 1.0)
	var t := create_tween()
	_reveal_tween = t
	t.tween_interval(0.5)
	for k in dups:
		var seats := order.filter(func(s): return key_of.call(s) == k)
		t.tween_callback(_reveal_dup.bind(seats, played[seats[0]]))
		t.tween_interval(REVEAL_DUP * speed)
	for s in order:
		if counts[key_of.call(s)] == 1:
			t.tween_callback(_reveal_one.bind(s))
			t.tween_interval(REVEAL_ONE * speed)
	var finalists: Array = _v["trick"].get("finalists", [])
	if not finalists.is_empty():
		t.tween_callback(_reveal_final.bind(finalists))
		t.tween_interval(REVEAL_DUP * speed)
	t.tween_callback(_finish_reveal)


## Турнир: победители групп выходят в финал, их карты срабатывают снова.
func _reveal_final(finalists: Array) -> void:
	var names := ", ".join(finalists.map(func(s): return _v["players"][s]["name"]))
	_reveal_banner("Финал победителей групп: %s.\nИх карты срабатывают снова!" % names, K12UI.GOLD)
	Sfx.play("chips_soft", -4)
	for s in finalists:
		if not _slots.has(s):
			continue
		var c: K12TableCard = _slots[s]
		c.z_index = 30
		var t := create_tween()
		t.tween_callback(func(): c.move_to(_slot_pos(s), 0.0, 0.75, 0.25))
		t.tween_interval(1.6)
		t.tween_callback(func():
			c.z_index = 0
			c.move_to(_slot_pos(s), _slot_rot(), TABLE_SCALE, 0.3))


## Клик по столу во время вскрытия — открыть всё сразу.
func _input(event: InputEvent) -> void:
	if _revealing and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip_reveal()


func _skip_reveal() -> void:
	if _reveal_tween:
		_reveal_tween.kill()
	for s in _slots:
		var c: K12TableCard = _slots[s]
		c.face_up = true
		c.z_index = 0
		c.place(_slot_pos(s), _slot_rot(), TABLE_SCALE)
	_finish_reveal()


func _reveal_dup(seats: Array, card: String) -> void:
	var names := ", ".join(seats.map(func(s): return _v["players"][s]["name"]))
	_reveal_banner("Одинаковые карты «%s» (%s) — отменяются, эффекта не будет!" % [K12Cards.card_name(card), names], K12UI.RED)
	for s in seats:
		var c: K12TableCard = _slots[s]
		c.z_index = 30
		c.flip(true)
		var t := create_tween()
		t.tween_interval(0.3)
		t.tween_callback(func(): c.move_to(_slot_pos(s), 0.0, 0.72, 0.25))
		t.tween_interval(0.55)
		t.tween_callback(func():
			c.stamp = "ОТМЕНЕНА"
			Sfx.play("card_shove", -2, 0.05, 0.05))
		for i in 4:
			t.tween_property(c, "rotation", 0.12 if i % 2 == 0 else -0.12, 0.06)
		t.tween_property(c, "rotation", 0.0, 0.06)
		t.tween_interval(1.2)
		t.tween_callback(func():
			c.z_index = 0
			c.move_to(_slot_pos(s), _slot_rot(), TABLE_SCALE, 0.3))


func _reveal_one(s: int) -> void:
	var card: String = _v["played"][s]
	_reveal_banner("%s: «%s»
%s" % [_v["players"][s]["name"], K12Cards.card_name(card), K12Cards.card_text(card)], K12UI.CREAM)
	var c: K12TableCard = _slots[s]
	c.z_index = 30
	if c.face_up:
		Sfx.play("card_flip", -6)
	c.flip(true)
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_callback(func(): c.move_to(_slot_pos(s), 0.0, 0.8, 0.25))
	t.tween_interval(1.3)
	t.tween_callback(func():
		c.z_index = 0
		c.move_to(_slot_pos(s), _slot_rot(), TABLE_SCALE, 0.3))


func _reveal_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.add_theme_color_override("font_color", color)
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.size = Vector2(640, 70)
	_banner.position = _tc() + Vector2(-320, -40)
	_banner.text += "\n(клик — пропустить)"


func _finish_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	_banner.add_theme_color_override("font_color", K12UI.CREAM)
	_banner.add_theme_font_size_override("font_size", 19)
	var nv := _queued if not _queued.is_empty() else _v
	_queued = {}
	_apply_state(nv)


func _slot_rot() -> float:
	return deg_to_rad(randf_range(-4, 4))


func _put_on_slot(seat: int, c: K12TableCard) -> void:
	_slots[seat] = c
	c.base_scale = TABLE_SCALE
	c.draggable = seat == _me
	c.move_to(_slot_pos(seat), _slot_rot(), TABLE_SCALE, 0.3)
	_connect_slot(c, seat)


func _connect_slot(c: K12TableCard, seat: int) -> void:
	if c.has_meta("slot_connected"):
		return
	c.set_meta("slot_connected", true)
	c.hovered.connect(func(card: K12TableCard, on: bool):
		if card.dragging or _slots.get(seat) != card:
			return
		var zoom := on and card.face_up
		card.z_index = 40 if zoom else 0
		card.move_to(_slot_pos(seat), 0.0, 0.95 if zoom else TABLE_SCALE, 0.15))
	c.dropped.connect(func(card, at): _on_slot_dropped(seat, card, at))


func _on_slot_dropped(seat: int, card: K12TableCard, at: Vector2) -> void:
	if seat == _me and _v["phase"] == "select" and at.y > size.y - 210:
		Net.send_action("unselect")
		return
	card.move_to(_slot_pos(seat), _slot_rot(), TABLE_SCALE, 0.25)


func _discard_slots() -> void:
	if not _slots.is_empty():
		Sfx.play("card_slide", -6)
	for s in _slots.keys():
		_fly_away(_slots[s], _plate_center(s) if s < _n else Vector2.ZERO)
	_slots.clear()


func _fly_away(c: K12TableCard, to: Vector2) -> void:
	c.draggable = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := c.move_to(to, 0.0, 0.15, 0.4)
	t.tween_property(c, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(c.queue_free)


# --- Рука ----------------------------------------------------------------------

func _hand_target() -> Array:
	var phase: String = _v["phase"]
	var hand: Array = _v["hands"][_me]
	var mine: String = _v["my_selected"]
	var list := []
	for c in _v["deck"]:
		if hand.has(c) and not (phase == "select" and c == mine):
			list.append(c)
	return list


func _update_hand() -> void:
	var target := _hand_target()
	for c in _hand.keys():
		if not target.has(c):
			var tc: K12TableCard = _hand[c]
			_hand.erase(c)
			_fly_away(tc, Vector2(_cx(), size.y + 120))
	for c in target:
		if not _hand.has(c):
			var tc := K12TableCard.new(c, true)
			_hand_layer.add_child(tc)
			tc.place(Vector2(_cx(), size.y + 150), 0.0, HAND_SCALE)
			_add_to_hand(tc)
	var phase: String = _v["phase"]
	var can_play: bool = phase == "select" and _v["my_selected"] == ""
	var can_under: bool = phase == "pick_under" and _v["pending"].get("seats", []).has(_me)
	for c in _hand:
		_hand[c].draggable = true  # таскать можно всегда (сортировка); сыграть — только когда разрешено
	_layout_hand()


func _add_to_hand(tc: K12TableCard) -> void:
	tc.base_scale = HAND_SCALE
	tc.stamp = ""
	if not tc.has_meta("hand_connected"):
		tc.set_meta("hand_connected", true)
		tc.hovered.connect(_on_hand_hover)
		tc.dropped.connect(_on_hand_dropped)
		tc.double_clicked.connect(func(card): _play_card(card))
		tc.drag_started.connect(func(_card):
			Sfx.play("card_slide", -8)
			_layout_hand())
	_hand[tc.card] = tc


func _return_to_hand(tc: K12TableCard) -> void:
	if _hand.has(tc.card):
		tc.queue_free()
		return
	tc.reparent(_hand_layer)
	Sfx.play("card_shove", -4)
	tc.face_up = true
	_add_to_hand(tc)


func _layout_hand() -> void:
	for c in _v.get("deck", []):
		if _hand.has(c) and not _hand_order.has(c):
			_hand_order.append(c)
	var cards := []
	for c in _hand_order:
		if _hand.has(c):
			cards.append(_hand[c])
	var n := cards.size()
	if n == 0:
		return
	var spacing := minf(100.0, 760.0 / n)
	for i in n:
		var tc: K12TableCard = cards[i]
		if tc.dragging:
			continue
		var off := i - (n - 1) / 2.0
		var pos := Vector2(_cx() + off * spacing, size.y - 62 + off * off * 2.2)
		var rot := off * 0.045
		var sc := HAND_SCALE
		tc.z_index = i
		if tc.card == _hover:
			pos.y -= 92
			rot = 0.0
			sc = HOVER_SCALE
			tc.z_index = 50
		tc.move_to(pos, rot, sc, 0.18)


func _on_hand_hover(tc: K12TableCard, on: bool) -> void:
	if tc.dragging or not _hand.values().has(tc):
		return
	if on:
		if _hover != tc.card:
			Sfx.play("card_slide", -18, 0.1, 0.07)
		_hover = tc.card
	elif _hover == tc.card:
		_hover = ""
	_layout_hand()


func _on_hand_dropped(tc: K12TableCard, at: Vector2) -> void:
	if not _hand.values().has(tc):
		return
	var phase: String = _v["phase"]
	if at.y < size.y - 200:
		if phase == "select" and _v["my_selected"] == "":
			_play_card(tc)
			return
		if phase == "pick_under" and _v["pending"].get("seats", []).has(_me):
			_under_card(tc)
			return
	else:
		# отпустили в руке — карта встаёт на новое место веера
		var before := 0
		for c in _hand_order:
			if _hand.has(c) and c != tc.card and _hand[c].center().x < at.x:
				before += 1
		_hand_order.erase(tc.card)
		var pos := 0
		var seen := 0
		while pos < _hand_order.size() and seen < before:
			if _hand.has(_hand_order[pos]):
				seen += 1
			pos += 1
		_hand_order.insert(pos, tc.card)
		Sfx.play("card_slide", -10)
	_hover = ""
	_layout_hand()


func _play_card(tc: K12TableCard) -> void:
	if _v["phase"] != "select" or _v["my_selected"] != "" or not _hand.has(tc.card):
		return
	_hand.erase(tc.card)
	tc.reparent(_table_layer)
	_hover = ""
	Sfx.play("card_place")
	_put_on_slot(_me, tc)
	Net.send_action("select", tc.card)
	_layout_hand()


func _under_card(tc: K12TableCard) -> void:
	_hand.erase(tc.card)
	tc.reparent(_table_layer)
	_fly_away(tc, _dice[_me].center())
	Sfx.play("card_place")
	Net.send_action("under", tc.card)
	_layout_hand()


func _take_from_hand(card: String) -> K12TableCard:
	if _hand.has(card):
		var tc: K12TableCard = _hand[card]
		_hand.erase(card)
		tc.reparent(_table_layer)
		return tc
	var c := K12TableCard.new(card, true)
	_table_layer.add_child(c)
	c.place(Vector2(_cx(), size.y - 60), 0.0, HAND_SCALE)
	return c


# --- Звуки смены фаз -------------------------------------------------------------

func _phase_sounds() -> void:
	var phase: String = _v["phase"]
	var key := "%s/%s" % [_v["round_no"], phase]
	if key == _phase_key:
		return
	var first := _phase_key == ""
	_phase_key = key
	match phase:
		"roll":
			Sfx.play("game_start" if first else "shuffle", -4)
		"pick_under":
			Sfx.play("chips_big", 0.0 if _v["pending"].get("seats", []).has(_me) else -6, 0.03, 1.0)
		"game_over":
			Sfx.play("chips_big")
			get_tree().create_timer(0.35).timeout.connect(func(): Sfx.play("chips_win"))


# --- Таблички --------------------------------------------------------------------

func _update_plates() -> void:
	var phase: String = _v["phase"]
	var trick: Dictionary = _v["trick"]
	var show_trick := phase == "trick_result" and not trick.is_empty()
	if phase == "roll":
		_round_label.text = "Раунд %d · бросок кубиков" % _v["round_no"]
	else:
		_round_label.text = "Раунд %d · розыгрыш %d" % [_v["round_no"], _v["trick_no"]]
	for s in _n:
		var toks: Array = _v["tokens"][s]
		var pts := 0
		for t in toks:
			pts += t
		var under: Array = _v["under"][s]
		var st := ""
		var st_color := K12UI.MUTED
		match phase:
			"roll":
				st = "кубик брошен" if _v["rolled"][s] else "бросает кубик…"
				st_color = K12UI.GREEN if _v["rolled"][s] else K12UI.MUTED
			"select":
				st = "✓ карта на столе" if _v["chosen"][s] else "выбирает карту…"
				st_color = K12UI.GREEN if _v["chosen"][s] else K12UI.MUTED
			"trick_result":
				var award: int = trick["awards"][s]
				if award > 0:
					st = "+%d ПО (%s)" % [award, "победа" if trick["winner"] == s else "2-е место"]
					st_color = K12UI.GOLD
				elif trick["dice_cancelled"][s]:
					st = "кубик отменён"
					st_color = K12UI.RED
		if _v["players"][s].get("bot", false):
			st = "бот · " + st if st != "" else "бот"
		var inactive: bool = not _v.get("active", []).is_empty() and not _v["active"][s]
		if inactive:
			st = "зритель (переигровка)"
		var group := -1
		var groups: Array = _v.get("groups", [])
		if groups.size() > 1:
			for gi in groups.size():
				if groups[gi].has(s):
					group = gi
		var discards: Array = _v.get("discards", [])
		var played_now: Array = discards[s].duplicate() if s < discards.size() else []
		var border := Color("8a6b45")
		if show_trick and trick["winner"] == s:
			border = K12UI.GOLD
		elif _v["pending"].get("seat", -1) == s or _v["pending"].get("seats", []).has(s):
			border = Color("5fb4ef")
		var tip := "Победы в раундах"
		if under.size() > 0:
			tip = "Под кубиком: " + ", ".join(under.map(func(c): return K12Cards.card_name(c)))
		_plates[s].set_data({
			"name": _v["players"][s]["name"] + ("  (вы)" if s == _me else ""),
			"me": s == _me,
			"players": _v["players"],
			"seat": s,
			"my_seat": _me,
			"wins": under.size(),
			"under_tip": tip,
			"tokens": toks,
			"points": pts,
			"hand": -1 if s == _me else _v["hands"][s].size(),
			"status": st,
			"status_color": st_color,
			"border": border,
			"avatar": Net.avatar(int(_v["players"][s].get("steam_id", 0))),
			"played": played_now,
			"group": group,
			"inactive": inactive,
			"crown": _v["phase"] == "game_over" and _v["winner"] == s,
		})


# --- Центр стола -----------------------------------------------------------------

func _names(pred: Callable) -> String:
	var list := []
	for s in _n:
		if pred.call(s):
			list.append(_v["players"][s]["name"])
	return ", ".join(list)


func _update_center() -> void:
	if _v.is_empty():
		return
	var phase: String = _v["phase"]
	var pend: Dictionary = _v["pending"]
	var c := _tc()
	K12UI.clear(_center_panel)
	_center_panel.visible = false
	_auto_label = null
	var text := ""
	match phase:
		"roll":
			if not _v["rolled"][_me]:
				text = "Бросьте кубик: зажмите его левой кнопкой мыши, потяните и отпустите"
			else:
				text = "Ждём бросков: " + _names(func(s): return not _v["rolled"][s])
		"select":
			if _v["my_selected"] == "":
				text = "Перетащите карту из руки на стол (или двойной клик)"
			else:
				text = "Ждём: %s\nСвою карту можно утащить обратно в руку" % _names(func(s): return not _v["chosen"][s])
		"sorcerer":
			text = "Чародей: выберите грань" if pend["seat"] == _me else "%s выбирает грань (Чародей)…" % _v["players"][pend["seat"]]["name"]
		"oracle":
			if pend["seat"] == _me:
				text = "Оракул: перебросьте свой кубик — зажмите его мышью, потяните и отпустите"
			else:
				text = "%s перебрасывает кубик (Оракул)…" % _v["players"][pend["seat"]]["name"]
		"pick_under":
			if not pend.get("seats", []).has(_me):
				text = "Раунд выиграл(и): %s — выбирают карту под кубик…" % ", ".join(pend.get("seats", []).map(func(x): return _v["players"][x]["name"]))
		"trick_result":
			_center_panel.visible = true
			var col := K12UI.vbox(4)
			_center_panel.add_child(col)
			var events := RichTextLabel.new()
			events.custom_minimum_size = Vector2(420, 78)
			events.size_flags_vertical = Control.SIZE_EXPAND_FILL
			events.add_theme_font_size_override("normal_font_size", 13)
			events.add_theme_color_override("default_color", K12UI.CREAM)
			events.text = "\n".join(_v["trick"]["events"])
			col.add_child(events)
			col.add_child(_next_row())
			_center_panel.size = Vector2(440, 124)
			_center_panel.position = c + Vector2(-220, -62)
	_banner.text = text
	_banner.visible = text != ""
	_banner.size = Vector2(560, 60)
	_banner.position = c + Vector2(-280, -34)


func _next_row() -> HBoxContainer:
	var row := K12UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var waiting: Array = _v["waiting"]
	var me_waiting := waiting.has(_v["players"][_me]["name"])
	var btn := K12UI.primary("Далее" if me_waiting else "Ждём остальных…", K12UI.CAP, 170)
	btn.disabled = not me_waiting
	btn.pressed.connect(func(): Net.send_action("next"))
	row.add_child(btn)
	_auto_label = K12UI.label("", K12UI.CAP, K12UI.MUTED)
	row.add_child(_auto_label)
	row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	_process(0)
	return row


func _process(_delta: float) -> void:
	if is_instance_valid(_auto_label):
		var left := maxi(0, ceili((_auto_deadline - Time.get_ticks_msec()) / 1000.0))
		_auto_label.text = "авто через %d с" % left


func _round_summary() -> String:
	var ri: Dictionary = _v["round_info"]
	if ri.is_empty():
		return ""
	var parts := []
	for s in _n:
		var t := "%s: %d ПО" % [_v["players"][s]["name"], ri["sums"][s]]
		if ri["cancelled"][s]:
			t += " (ничья — отменено)"
		parts.append(t)
	return " · ".join(parts)


# --- Модальные окна ----------------------------------------------------------------

func _update_overlay() -> void:
	K12UI.clear(_overlay)
	var phase: String = _v["phase"]
	var pend: Dictionary = _v["pending"]
	if phase == "sorcerer" and pend["seat"] == _me:
		var box := _modal("Чародей: поверните кубик на соседнюю грань", false)
		var row := K12UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for f in pend["options"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(84, 96)
			b.add_theme_stylebox_override("normal", K12UI.box(K12UI.PANEL_LIGHT, 8))
			b.add_theme_stylebox_override("hover", K12UI.box(Color("6b4a2f"), 8, K12UI.GOLD, 2))
			var d := K12DieView.new()
			d.face = f
			d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(d)
			var face: int = f
			b.pressed.connect(func(): Net.send_action("face", face))
			row.add_child(b)
		box.add_child(row)
		box.add_child(K12UI.label("Сейчас на кубике %d." % _v["faces"][_me], K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	elif phase == "pick_under" and pend.get("seats", []).has(_me):
		var box := _modal("Вы выиграли раунд! ★", false)
		box.add_child(K12UI.label(_round_summary(), K12UI.CAP, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		var hint := K12UI.label("Выберите карту, которая уйдёт под ваш кубик (до конца игры её нельзя будет сыграть). Вторая такая карта — победа в игре!", K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
		var row := K12UI.hbox(6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for c in _v["hands"][_me]:
			var cv := K12CardView.new(c, true)
			cv.clickable = true
			cv.pressed.connect(func(card):
				Sfx.play("card_place")
				Net.send_action("under", card))
			row.add_child(cv)
		box.add_child(row)
	elif phase == "round_result":
		var ri: Dictionary = _v["round_info"]
		var box := _modal("Итог раунда %d" % ri.get("round", 0))
		box.add_child(K12UI.label(_round_summary(), K12UI.BODY, K12UI.CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		var winners: Array = ri.get("winners", [])
		if winners.is_empty():
			box.add_child(K12UI.label("Все суммы равны — у раунда нет победителя.", K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		for w in winners:
			var card: String = ri.get("under_cards", {}).get(str(w), "")
			var line := "%s выигрывает раунд ★" % _v["players"][w]["name"]
			if card != "":
				line += " и кладёт под кубик карту «%s»" % K12Cards.card_name(card)
			box.add_child(K12UI.label(line + ".", K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		if not ri.get("playoff_next", []).is_empty():
			box.add_child(K12UI.label("Несколько игроков одновременно набрали вторую победу — они разыграют переигровку из 4 розыгрышей!", K12UI.BODY, K12UI.RED, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(K12UI.label("Жетоны возвращаются в запас. В новом раунде все снова бросают кубики.", K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(_next_row())
	elif phase == "game_over":
		var w: int = _v["winner"]
		var box := _modal("Игра окончена")
		var text := "Вы победили! Да здравствует король!" if w == _me else "%s побеждает и занимает трон Двенадцати королевств!" % _v["players"][w]["name"]
		box.add_child(K12UI.label(text, K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(_results_grid())
		var row := K12UI.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if Net.is_host():
			var again := K12UI.primary("Новая партия", K12UI.BODY, 200)
			again.pressed.connect(Net.end_game)
			row.add_child(again)
			var back := K12UI.button("К выбору игры" if Net.is_party() else "В меню", K12UI.BODY, 200)
			back.pressed.connect(func(): app.back_to_menu())
			row.add_child(back)
		else:
			box.add_child(K12UI.label("Хост решает, что дальше: новая партия или другая игра.", K12UI.CAP, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			var leave := K12UI.button("Покинуть пати", K12UI.BODY, 200)
			LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
			row.add_child(leave)
		box.add_child(row)


func _modal(title: String, dim_bg: bool = true) -> VBoxContainer:
	if dim_bg:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.96), 8, "double")
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var col := K12UI.vbox(14)
	panel.add_child(col)
	col.add_child(K12UI.title(title, K12UI.H1))
	return col


# --- Отладка: автоигра -------------------------------------------------------------

func _autoplay_step() -> void:
	var phase: String = _v["phase"]
	var pend: Dictionary = _v["pending"]
	var key := "%s/%s/%s" % [_v["round_no"], _v["trick_no"], phase]
	if key == _autoplay_done:
		return
	_autoplay_done = key
	var hand: Array = _v["hands"][_me]
	match phase:
		"roll":
			if not _v["rolled"][_me]:
				var die: K12Die3D = _dice[_me]
				var vel := Vector2(randf_range(-900, 900), -1300)
				die.draggable = false
				die.throw(vel)
				Net.send_action("roll", {"vx": vel.x, "vy": vel.y})
		"select":
			if _v["my_selected"] == "" and _hand.size() > 0:
				_play_card(_hand.values().pick_random())
		"sorcerer":
			if pend["seat"] == _me:
				Net.send_action("face", pend["options"].pick_random())
		"oracle":
			if pend["seat"] == _me:
				Net.send_action("oracle_roll", {"vx": 0.0, "vy": -900.0})
		"pick_under":
			if pend.get("seats", []).has(_me):
				Net.send_action("under", hand.pick_random())
		"trick_result", "round_result":
			if _v["waiting"].has(_v["players"][_me]["name"]):
				Net.send_action("next")
		"game_over":
			if not has_meta("done"):
				set_meta("done", true)
				print("AUTOPLAY GAME_OVER winner=%s me=%s rounds=%d" % [_v["players"][_v["winner"]]["name"], _v["players"][_me]["name"], _v["round_no"]])
				get_tree().create_timer(3.0).timeout.connect(get_tree().quit)


# --- Таблица итогов, монеты, финал ---------------------------------------------------

## Итоги партии по раундам: ПО каждого игрока и ★ за выигранный раунд.
func _results_grid() -> Control:
	var rounds: Array = _v.get("round_history", [])
	var grid := GridContainer.new()
	grid.columns = rounds.size() + 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(K12UI.label("Игрок", K12UI.CAP, K12UI.MUTED))
	for r in rounds:
		grid.add_child(K12UI.label("Р%d%s" % [r["round"], " (пер.)" if r.get("playoff", false) else ""], K12UI.CAP, K12UI.MUTED))
	grid.add_child(K12UI.label("Победы", K12UI.CAP, K12UI.MUTED))
	for s in _n:
		var win: bool = _v["winner"] == s
		grid.add_child(K12UI.label(("♛ " if win else "") + _v["players"][s]["name"], K12UI.CAP, K12UI.GOLD if win else K12UI.CREAM))
		for r in rounds:
			var t := "—"
			if r.get("active", []).is_empty() or r["active"][s]:
				t = str(r["sums"][s]) + (" ★" if r.get("winners", []).has(s) else "")
			grid.add_child(K12UI.label(t, K12UI.CAP, K12UI.GOLD if r.get("winners", []).has(s) else K12UI.CREAM))
		grid.add_child(K12UI.label("★".repeat(_v["under"][s].size()), K12UI.CAP, K12UI.GOLD))
	var center := CenterContainer.new()
	center.add_child(grid)
	return center


## Монеты летят из центра стола к табличкам тех, кто получил очки.
func _fly_coins() -> void:
	var key := "%d/%d" % [_v["round_no"], _v["trick_no"]]
	if key == _coins_key:
		return
	_coins_key = key
	var awards: Array = _v["trick"].get("awards", [])
	for s in awards.size():
		if int(awards[s]) <= 0:
			continue
		var coin := K12Plate.Coins.new()
		coin.tokens = [awards[s]]
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_layer.add_child(coin)
		coin.position = _tc() + Vector2(randf_range(-30, 30), randf_range(-20, 20))
		coin.scale = Vector2.ONE * 1.8
		var to := _plate_center(s) - Vector2(12, 12)
		var t := coin.create_tween()
		t.tween_interval(0.2)
		t.tween_property(coin, "position", to, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(coin, "scale", Vector2.ONE, 0.75)
		t.tween_callback(func(): Sfx.play("chip", -6, 0.1, 0.03))
		t.tween_callback(coin.queue_free)


## Победа: корона на табличке, конфетти и победная музыка (один раз).
func _celebrate() -> void:
	if _celebrated:
		return
	_celebrated = true
	Sfx.victory()
	var conf := CPUParticles2D.new()
	conf.position = Vector2(_cx(), -20)
	conf.amount = 160
	conf.lifetime = 4.0
	conf.one_shot = true
	conf.explosiveness = 0.6
	conf.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	conf.emission_rect_extents = Vector2(size.x / 2.0, 10)
	conf.direction = Vector2(0, 1)
	conf.spread = 30.0
	conf.gravity = Vector2(0, 220)
	conf.initial_velocity_min = 80.0
	conf.initial_velocity_max = 220.0
	conf.angular_velocity_min = -360.0
	conf.angular_velocity_max = 360.0
	conf.scale_amount_min = 4.0
	conf.scale_amount_max = 8.0
	var grad := Gradient.new()
	grad.set_color(0, Color("e8c26a"))
	grad.set_color(1, Color("5fb4ef"))
	grad.add_point(0.33, Color("d9534f"))
	grad.add_point(0.66, Color("6fcf6f"))
	conf.color_initial_ramp = grad
	_fx.add_child(conf)
	conf.emitting = true
	get_tree().create_timer(6.0).timeout.connect(conf.queue_free)


# --- Чат: пузыри над табличками ----------------------------------------------------

func _on_chat_bubble(entry: Dictionary) -> void:
	var s: int = entry.get("seat", -1)
	if s < 0 or s >= _n or _plates.is_empty():
		return
	if _bubbles.has(s) and is_instance_valid(_bubbles[s]):
		_bubbles[s].queue_free()
	var b := K12UI.label(str(entry["text"]).left(60), 15 if entry["kind"] == "emote" else 13, K12UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
	b.add_theme_stylebox_override("normal", K12UI.box(Color("f6efdc"), 12, Color("8a6b45"), 2))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(150, 0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(b)
	var r := _plate_rect(s)
	b.position = Vector2(clampf(r.get_center().x - 75, 4, size.x - 160), maxf(r.position.y - 46, 4))
	b.pivot_offset = Vector2(75, 20)
	b.scale = Vector2.ONE * 0.4
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.2)
	t.tween_property(b, "modulate:a", 0.0, 0.4)
	t.tween_callback(b.queue_free)
	_bubbles[s] = b


# --- История розыгрышей ------------------------------------------------------------

func _show_history() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.97), 8, "double")
	margin.add_child(panel)
	var col := K12UI.vbox(8)
	panel.add_child(col)
	var head := K12UI.hbox()
	var title := K12UI.label("История розыгрышей", K12UI.H1, K12UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := K12UI.button("Закрыть", K12UI.CAP)
	close.pressed.connect(layer.queue_free)
	head.add_child(close)
	col.add_child(head)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 14)
	text.add_theme_font_size_override("bold_font_size", 14)
	text.add_theme_color_override("default_color", K12UI.CREAM)
	col.add_child(text)
	var hist: Array = _v.get("history", [])
	if hist.is_empty():
		text.text = "Пока не сыграно ни одного розыгрыша."
		return
	var last_round := -1
	for i in range(hist.size() - 1, -1, -1):
		var h: Dictionary = hist[i]
		if h["round"] != last_round:
			last_round = h["round"]
			text.append_text("\n[b][color=#e8c26a]Раунд %d[/color][/b]\n" % last_round)
		var parts := []
		for s in h["played"].size():
			if h["played"][s] == "":
				continue
			var nm: String = K12Cards.card_name(h["played"][s])
			if h["card_cancelled"][s]:
				nm = "[s]%s[/s]" % nm
			var p := "%s: %s (%d)" % [_v["players"][s]["name"], nm, h["values"][s]]
			if h["awards"][s] > 0:
				p = "[color=#e8c26a]%s +%d[/color]" % [p, h["awards"][s]]
			parts.append(p)
		text.append_text("Розыгрыш %d — %s\n" % [h["trick"], " · ".join(parts)])


# --- Обучение: подсказки ------------------------------------------------------------

const HINTS := {
	"roll": "Это ваш кубик. Зажмите его левой кнопкой мыши, потяните и отпустите — так вы бросите кубик. Выпавшее число — ваша сила в этом раунде: кубик не перебрасывается до конца раунда.",
	"select": "Выберите карту: перетащите её из руки на стол (или дважды кликните). Соперники видят только рубашку. Наведите мышь на карту, чтобы прочитать её эффект. Карты в руке можно переставлять.",
	"trick_result": "Итог розыгрыша. Одинаковые карты отменились, остальные сработали. Победил кубик с наибольшим значением — 2 победных очка (ПО), второе место — 1 ПО. Равные значения отменяют друг друга. Нажмите «Далее».",
	"sorcerer": "Сработал Чародей: его владелец поворачивает кубик на соседнюю грань.",
	"oracle": "Сработал Оракул: его владелец сам перебрасывает кубик мышью.",
	"pick_under": "Раунд окончен: у кого-то 8+ ПО или в руке осталась одна карта. Победитель раунда кладёт одну карту под кубик — это звезда победы. Две звезды — победа в игре!",
	"round_result": "Новый раунд: очки обнуляются, все снова бросают кубики, карты возвращаются в руку (кроме тех, что под кубиком).",
}


func _tutorial_hints() -> void:
	var phase: String = _v["phase"]
	if not HINTS.has(phase) or _hints_shown.has(phase):
		return
	_hints_shown[phase] = true
	if is_instance_valid(_hint_panel):
		_hint_panel.queue_free()
	_hint_panel = PanelContainer.new()
	_hint_panel.add_theme_stylebox_override("panel", K12UI.box(Color(0.12, 0.2, 0.3, 0.96), 12, Color("5fb4ef"), 2))
	_hint_panel.custom_minimum_size = Vector2(380, 0)
	var col := K12UI.vbox(8)
	_hint_panel.add_child(col)
	col.add_child(K12UI.label("Подсказка", K12UI.BODY, Color("5fb4ef")))
	var l := K12UI.label(HINTS[phase], K12UI.CAP)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	col.add_child(l)
	var ok := K12UI.button("Понятно", K12UI.CAP)
	var panel := _hint_panel
	ok.pressed.connect(func(): panel.queue_free())
	col.add_child(ok)
	_fx.add_child(_hint_panel)
	_hint_panel.position = Vector2(size.x - 400, 56)
