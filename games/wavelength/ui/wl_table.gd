extends Control
## Стол «Длины волны»: счёт команд, подсказка, шкала со стрелкой, карточка, панель действий по роли.

const TEAM_NAMES := ["Левое полушарие", "Правое полушарие"]
const TEAM_COLORS := [Color("5f7fbf"), Color("d9895a")]

var app: Node

var _top: TopBar
var _v := {}
var _me := 0
var _dial: WLDial
var _clue_label: Label
var _card_row: HBoxContainer
var _teams_box: HBoxContainer
var _panel: PanelContainer
var _banner: Label
var _fx: Control
var _clue_edit: LineEdit
var _auto_label: Label
var _auto_deadline := 0

var _peek := false  # на одном компьютере: телепат открыл экран
var _send_wait := 0.0
var _pending_dial := -1.0
var _revealed_turn := -1
var _celebrated := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := preload("res://games/wavelength/ui/wl_backdrop.gd").new()
	add_child(backdrop)
	var col := HCStyle.vbox(6)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16
	col.offset_right = -16
	col.offset_top = TopBar.HEIGHT + 16  # панели команд не прилипают к полосе
	col.offset_bottom = -8
	add_child(col)

	var top := HCStyle.hbox(10)
	_teams_box = HCStyle.hbox(12)
	_teams_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_teams_box)
	var buttons := HCStyle.hbox(6)  # кнопки игры — в верхней полосе (TopBar)
	var rules := HCStyle.button("Правила", HCStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var settings := HCStyle.button("Настройки", HCStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	buttons.add_child(settings)
	buttons.add_child(ThemeToggle.make(func(t, z): return HCStyle.button(t, z), HCStyle.CAP))  # солнце / луна — тема
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = HCStyle.button("Завершить партию", HCStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся к выбору игры, пати сохранится.", Net.return_to_party)
	elif Net.is_party():
		leave = HCStyle.button("Покинуть пати", HCStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = HCStyle.button("Выйти", HCStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	buttons.add_child(leave)
	col.add_child(top)

	_clue_label = HCStyle.label("", HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER, "title")
	col.add_child(_clue_label)

	_dial = WLDial.new()
	_dial.custom_minimum_size = Vector2(600, 300)
	_dial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dial.dial_moved.connect(_on_dial_moved)
	_dial.drag_finished.connect(_flush_dial)
	col.add_child(_dial)
	backdrop.dial = _dial

	_card_row = HCStyle.hbox(12)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_card_row)

	_panel = HCStyle.panel(18)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size.x = 640
	col.add_child(_panel)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_banner = HCStyle.label("", HCStyle.H1, HCStyle.SAGE, HORIZONTAL_ALIGNMENT_CENTER, "title")
	_banner.add_theme_color_override("font_outline_color", HCStyle.BG)
	_banner.add_theme_constant_override("outline_size", 10)
	_fx.add_child(_banner)

	_top = TopBar.make(self, "Длина волны", func(t, z): return HCStyle.button(t, z), null, HCStyle.INK, HCStyle.font("bold"))
	_top.coin_center = true  # монетка — по центру сверху
	for c in buttons.get_children():
		buttons.remove_child(c)
		_top.actions.add_child(c)
	HCStyle.restyle_chat(_top.chat)
	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := HCStyle.label(t, HCStyle.CAP, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_stylebox_override("normal", HCStyle.box(HCStyle.SURFACE, 14, HCStyle.LINE, 1, HCStyle.SHADOW, 10))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-270, 180))

	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	var prev_turn: int = _v.get("turn_no", -1)
	_v = v
	_me = v["you"]
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	if int(v["turn_no"]) != prev_turn:
		_peek = false
	var phase: String = v["phase"]
	_update_info()
	_update_teams()
	_update_clue()
	_update_card()
	_update_dial(phase, prev_phase)
	if phase != prev_phase or int(v["turn_no"]) != prev_turn:
		_update_panel()
	elif phase == "reveal":
		_update_panel()  # обновить, кто ещё смотрит итог


func _update_info() -> void:
	var ph: String = _v.get("phase", "")
	if ph == "game_over":
		_top.info.text = "Игра окончена"
		return
	var who := ""
	if _v.has("psychic") and not _v.get("coop", false):
		who = TEAM_NAMES[int(_v.get("active_team", 0))]
	var names := {"card": "выбор карточки", "clue": "подсказка", "guess": "угадывание", "reveal": "итог"}
	var p: String = names.get(ph, ph)
	_top.info.text = ("%s: %s" % [who.get_slice(" ", 0), p]) if who != "" else p.capitalize()


# --- Роли ---------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false)


func _team_of(s: int) -> int:
	return int(_v["players"][s].get("team", 0))


func _am_psychic() -> bool:
	return _hotseat() or _me == _v["psychic"]


func _am_guesser() -> bool:
	return _hotseat() or (_team_of(_me) == _v["active_team"] and _me != _v["psychic"])


func _am_other() -> bool:
	return _hotseat() or _team_of(_me) != _v["active_team"]


func _psychic_name() -> String:
	return _v["players"][_v["psychic"]]["name"]


func _pair() -> Array:
	var side: int = _v["side"]
	return _v["card"][side] if side >= 0 else []


# --- Отрисовка ----------------------------------------------------------------------

func _update_teams() -> void:
	HCStyle.clear(_teams_box)
	var teams := [0] if _v["coop"] else [0, 1]
	for t in teams:
		var active: bool = _v["active_team"] == t and not _v["coop"]
		var p := PanelContainer.new()
		var tc: Color = TEAM_COLORS[t] if not _v["coop"] else HCStyle.SAGE
		p.add_theme_stylebox_override("panel", HCStyle.box(HCStyle.SURFACE, 16, tc if active else Color(HCStyle.LINE, 0.8), 2 if active else 1, HCStyle.SHADOW, 12))
		p.custom_minimum_size.x = 380 if not _v["coop"] else 560
		var v := HCStyle.vbox(2)
		p.add_child(v)
		var head := HCStyle.hbox(8)
		var nm := HCStyle.label("Команда" if _v["coop"] else TEAM_NAMES[t], HCStyle.BODY, tc.darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT, "bold")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		var score := HCStyle.label(str(_v["scores"][t]), HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
		head.add_child(score)
		v.add_child(head)
		if not _v["coop"]:
			v.add_child(_track(int(_v["scores"][t]), int(_v.get("goals", [10, 10])[t]), TEAM_COLORS[t]))
		else:
			var sc := int(_v["scores"][0])
			v.add_child(_track(sc, WLRules.COOP_GOAL, HCStyle.SAGE))
			var nx := WLRules.coop_next(sc)
			var info := "Цель — %d очков («Вы победили!») · карточек осталось: %d" % [WLRules.COOP_GOAL, _v["cards_left"]]
			if not nx.is_empty() and sc >= WLRules.COOP_GOAL:
				info = "Цель взята! До «%s» — ещё %d · карточек: %d" % [nx[1], int(nx[0]) - sc, _v["cards_left"]]
			v.add_child(HCStyle.label(info, HCStyle.CAP, HCStyle.MUTED))
		var ml := HFlowContainer.new()
		for s in _v["players"].size():
			if _team_of(s) == t or _v["coop"]:
				var sfx := ""
				if s == _v["psychic"]:
					sfx += " (телепат)"
				if s == _me and not _hotseat():
					sfx += " — вы"
				ml.add_child(PlayerTag.make_seat(_v["players"], s, _me, 13, HCStyle.INK, sfx))
		v.add_child(ml)
		_teams_box.add_child(p)
	if _v["tiebreak"]:
		_teams_box.add_child(HCStyle.label("Ничья!\nДоп. ходы", HCStyle.BODY, HCStyle.CLAY, HORIZONTAL_ALIGNMENT_LEFT, "bold"))


func _track(score: int, goal: int, color: Color) -> Control:
	var row := HCStyle.hbox(4)
	for i in range(1, goal + 1):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(26, 8)
		dot.add_theme_stylebox_override("panel", HCStyle.box(color if i <= score else HCStyle.SURFACE_2, 4))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
	return row


func _update_clue() -> void:
	var phase: String = _v["phase"]
	if _v["clue"] != "":
		_clue_label.text = "%s: «%s»" % [_psychic_name(), _v["clue"]]
	elif phase == "card":
		_clue_label.text = "Телепат %s выбирает карточку…" % _psychic_name()
	elif phase == "clue":
		_clue_label.text = "Телепат %s придумывает подсказку…" % _psychic_name()
	else:
		_clue_label.text = ""


func _update_card() -> void:
	HCStyle.clear(_card_row)
	var pair := _pair()
	if pair.is_empty():
		return
	for i in 2:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", HCStyle.box(HCStyle.DUSK if i == 0 else HCStyle.CLAY, 14, Color.TRANSPARENT, 0, HCStyle.SHADOW, 10))
		box.custom_minimum_size = Vector2(280, 0)
		var l := HCStyle.label(("← " if i == 0 else "") + pair[i] + (" →" if i == 1 else ""), HCStyle.BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		box.add_child(l)
		_card_row.add_child(box)


func _update_dial(phase: String, prev_phase: String) -> void:
	if not _dial.dragging:
		_dial.value = float(_v["dial"])
	_dial.guess_side = _v["lr"] if phase in ["reveal", "game_over"] else ""
	_dial.can_drag = phase == "guess" and _am_guesser()
	var target: float = _v["target"]
	var show_target: bool = target >= 0.0 and (phase in ["reveal", "game_over"] or (_v["psychic"] == _me and not _hotseat()) or (_hotseat() and _peek))
	_dial.target = target if show_target else -1.0
	if phase == "reveal" and _revealed_turn != int(_v["turn_no"]):
		_revealed_turn = int(_v["turn_no"])
		_reveal_anim()
	elif phase in ["reveal", "game_over"]:
		_dial.cover = 0.0
	elif show_target and phase in ["card", "clue"]:
		_dial.cover = 0.0
	else:
		_dial.cover = 1.0


func _reveal_anim() -> void:
	_dial.cover = 1.0
	Sfx.play("card_slide", -2)
	var t := create_tween()
	t.tween_property(_dial, "cover", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(_show_points)


func _show_points() -> void:
	var r: Dictionary = _v["result"]
	var pts: int = r.get("points", 0)
	var text := ""
	if pts == 4:
		text = "В ЦЕНТР! +%d" % (3 if _v["coop"] else 4)
		Sfx.play("chips_big")  # победная тема — только в конце партии
	elif pts > 0:
		text = "+%d" % pts
		Sfx.play("chips_win")
	else:
		text = "Мимо!"
		Sfx.play("card_shove")
	_banner.text = text
	_banner.size = Vector2(500, 60)
	_banner.position = Vector2(size.x / 2.0 - 250, _dial.global_position.y + 90)
	_banner.scale = Vector2.ONE * 0.5
	_banner.pivot_offset = Vector2(250, 30)
	_banner.modulate.a = 1.0
	var t := create_tween()
	t.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.2)
	t.tween_property(_banner, "modulate:a", 0.0, 0.5)


# --- Панель действий -----------------------------------------------------------------

func _update_panel() -> void:
	HCStyle.clear(_panel)
	_auto_label = null
	var col := HCStyle.vbox(8)
	_panel.add_child(col)
	var phase: String = _v["phase"]
	match phase:
		"card":
			if _hotseat() and not _peek:
				col.add_child(_hint("Передайте компьютер телепату: %s. Остальные — не смотрите на экран!" % _psychic_name()))
				col.add_child(_center_btn("Я телепат — показать", func():
					_peek = true
					_update_dial(phase, phase)
					_update_panel()))
			elif _am_psychic():
				col.add_child(_hint("Цветная зона открыта только вам. Выберите сторону карточки:"))
				var row := HCStyle.hbox(10)
				row.alignment = BoxContainer.ALIGNMENT_CENTER
				for i in 2:
					var pair: Array = _v["card"][i]
					var b := HCStyle.button("%s — %s" % [pair[0], pair[1]], HCStyle.BODY)
					var idx := i
					b.pressed.connect(func(): Net.send_action("wl_side", idx))
					row.add_child(b)
				col.add_child(row)
			else:
				col.add_child(_hint("Телепат %s смотрит на цветную зону и выбирает карточку." % _psychic_name()))
		"clue":
			if _am_psychic() and (not _hotseat() or _peek):
				col.add_child(_hint("Придумайте подсказку: что на этой шкале стоит там же, где центр зоны?"))
				var row := HCStyle.hbox(8)
				_clue_edit = LineEdit.new()
				_clue_edit.placeholder_text = "например: Кофе"
				_clue_edit.max_length = 80
				_clue_edit.custom_minimum_size.x = 420
				_clue_edit.text_submitted.connect(func(t): _send_clue())
				row.add_child(_clue_edit)
				var give := HCStyle.primary("Дать подсказку", HCStyle.BODY)
				give.pressed.connect(_send_clue)
				row.add_child(give)
				col.add_child(row)
				col.add_child(HCStyle.label("Одна мысль · ничего не выдумывать · без однокоренных слов и чисел · до 5 слов", HCStyle.CAP, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
				_clue_edit.grab_focus.call_deferred()
			else:
				col.add_child(_hint("Телепат %s придумывает подсказку…" % _psychic_name()))
		"guess":
			if _hotseat():
				col.add_child(_hint("Экран закрыт. Команда «%s» обсуждает подсказку и тащит стрелку. Телепат молчит!" % _team_name(_v["active_team"])))
			if _am_guesser():
				if not _hotseat():
					col.add_child(_hint("Обсудите подсказку и тащите стрелку мышью. Договорились — жмите «Мы решили»."))
				col.add_child(_center_btn("Мы решили!", func():
					_flush_dial()
					Sfx.play("chip")
					Net.send_action("wl_lock")))
			elif _me == _v["psychic"]:
				col.add_child(_hint("Вы телепат — молчите и не подавайте вида :)"))
			else:
				col.add_child(_hint("Команда «%s» ставит стрелку. Сбивайте их с толку в чате!" % _team_name(_v["active_team"])))
		"side":
			if _am_other():
				col.add_child(_hint("Команда «%s»: центр зоны левее или правее стрелки? Верно — +1 очко." % _team_name(1 - int(_v["active_team"]))))
				var row := HCStyle.hbox(14)
				row.alignment = BoxContainer.ALIGNMENT_CENTER
				var left := HCStyle.button("← Левее", HCStyle.BODY, 180)
				left.pressed.connect(func(): Net.send_action("wl_lr", "left"))
				row.add_child(left)
				var right := HCStyle.button("Правее →", HCStyle.BODY, 180)
				right.pressed.connect(func(): Net.send_action("wl_lr", "right"))
				row.add_child(right)
				col.add_child(row)
			else:
				col.add_child(_hint("Другая команда угадывает: левее или правее…"))
		"reveal":
			col.add_child(_hint(_result_text()))
			var row := HCStyle.hbox(10)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			var me_waiting: bool = _v.get("waiting", []).has(_v["players"][_me]["name"]) or _hotseat()
			var btn := HCStyle.primary("Далее" if me_waiting else "Ждём остальных…", HCStyle.BODY, 200)
			btn.disabled = not me_waiting
			btn.pressed.connect(func(): Net.send_action("next"))
			row.add_child(btn)
			_auto_label = HCStyle.label("", HCStyle.CAP, HCStyle.MUTED)
			row.add_child(_auto_label)
			row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
			col.add_child(row)
		"game_over":
			col.add_child(HCStyle.title(_final_text(), HCStyle.H1))
			if _v["coop"]:
				col.add_child(_hint("Счёт: %d — «%s»" % [_v["scores"][0], WLRules.coop_rating(int(_v["scores"][0]))]))
			if not _celebrated:
				_celebrated = true
				Sfx.victory()
			var row := HCStyle.hbox(12)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			if Net.is_host():
				var again := HCStyle.primary("Новая партия", HCStyle.BODY, 190)
				again.pressed.connect(Net.end_game)
				row.add_child(again)
				var back := HCStyle.button("К выбору игры" if Net.is_party() else "В меню", HCStyle.BODY, 190)
				back.pressed.connect(func(): app.back_to_menu())
				row.add_child(back)
			else:
				var leave := HCStyle.button("Покинуть пати", HCStyle.BODY, 190)
				LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
				row.add_child(leave)
			col.add_child(row)


func _team_name(t: int) -> String:
	return "Команда" if _v["coop"] else TEAM_NAMES[t]


func _result_text() -> String:
	var r: Dictionary = _v["result"]
	var pts: int = r.get("points", 0)
	var t: int = r.get("team", 0)
	var s := ""
	if _v["coop"]:
		s = "Попадание: %d очк." % (3 if pts == 4 else pts)
		if pts == 4:
			s += " В центр — ещё одна карточка!"
	else:
		s = "«%s» получает %d очк." % [_team_name(t), pts]
		if r.get("lr", "") != "":
			var guessed: bool = r.get("other_points", 0) > 0
			if pts == 4:
				s += " Стрелка в центре — «левее/правее» не приносит очков."
			else:
				s += " «%s» %s (+%d)." % [_team_name(1 - t), "угадала сторону" if guessed else "не угадала сторону", r.get("other_points", 0)]
		var gl: Array = _v.get("goals", [10, 10])
		if pts == 4 and int(_v["scores"][t]) - int(gl[t]) < int(_v["scores"][1 - t]) - int(gl[1 - t]):
			s += " Правило догоняющего: ещё один ход!"
	return s


func _final_text() -> String:
	if _v["coop"]:
		var sc := int(_v["scores"][0])
		return "Победа! Вы на одной волне!" if sc >= WLRules.COOP_GOAL else "Не хватило %d очк. до цели" % (WLRules.COOP_GOAL - sc)
	return "Победа: «%s»!" % TEAM_NAMES[int(_v["winner"])]


func _hint(text: String) -> Label:
	var l := HCStyle.label(text, HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	return l


func _center_btn(text: String, cb: Callable) -> Button:
	var b := HCStyle.primary(text, HCStyle.BODY, 260)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b


func _send_clue() -> void:
	if is_instance_valid(_clue_edit) and _clue_edit.text.strip_edges() != "":
		Sfx.play("card_place")
		Net.send_action("wl_clue", _clue_edit.text.strip_edges())
		_peek = false


# --- Стрелка: отправка не чаще ~15 раз в секунду ----------------------------------

func _on_dial_moved(value: float) -> void:
	_pending_dial = value


func _flush_dial() -> void:
	if _pending_dial >= 0.0:
		Net.send_action("wl_dial", _pending_dial)
		_pending_dial = -1.0


func _process(delta: float) -> void:
	_send_wait += delta
	if _pending_dial >= 0.0 and _send_wait >= 0.066:
		_send_wait = 0.0
		_flush_dial()
	if is_instance_valid(_auto_label):
		_auto_label.text = "авто через %d с" % maxi(0, ceili((_auto_deadline - Time.get_ticks_msec()) / 1000.0))
