extends Control
## Стол «Оттенков и подсказок»: поле в центре, подсказки сверху, игроки и счёт справа,
## панель действия снизу (выбор цвета / подсказка / ход / итог раунда).

var app: Node
var play_intro := false  # только начало партии, не обновления состояния

var _v := {}
var _me := 0
var _board: HCBoard
var _round_label: Label
var _top: TopBar
var _top_dark := false
var _hover_label: Label
var _cues_row: HBoxContainer
var _players_box: VBoxContainer
var _history_box: VBoxContainer
var _side: PanelContainer
var _action: PanelContainer
var _action_key := ""
var _cue_edit: LineEdit
var _cue_error: Label
var _auto_label: Label
var _auto_deadline := 0
var _revealed_round := -1
var _celebrated := false
var _distorted_round := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(HCBackdrop.new(true))

	_board = HCBoard.new()
	if play_intro and not Net.view.get("distorted", false):
		_board.play_reveal()
	_board.cell_clicked.connect(_on_cell)
	_board.cell_hovered.connect(func(c): _hover_label.text = HCData.coord(c) if c >= 0 else "")
	add_child(_board)

	var top := HCStyle.hbox(14)
	top.name = "Top"
	add_child(top)
	_cues_row = HCStyle.hbox(10)
	_cues_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cues_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_cues_row)
	# общая верхняя полоса: название, раунд, часы, чат и кнопки
	_top = TopBar.make(self, "Hues and Cues", func(t, z): return HCStyle.button(t, z), null, HCStyle.INK, HCStyle.font("bold"))
	# монетка — по центру под правой панелью игроков
	_top.coin_at = func() -> Vector2:
		var r := _side.get_global_rect()
		return Vector2(r.get_center().x, r.end.y + 38.0)
	_top.info.add_theme_font_override("font", HCStyle.font("bold"))
	_round_label = _top.info
	var rules := HCStyle.button("Правила", 14)
	rules.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules)
	var settings := HCStyle.button("Настройки", 14)
	settings.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(settings)
	_top.actions.add_child(ThemeToggle.make(func(t, z): return HCStyle.button(t, z), 14))  # солнце / луна — тема
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = HCStyle.button("Завершить партию", 14)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = HCStyle.button("Покинуть пати", 14)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = HCStyle.button("Выйти", 14)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	_top.actions.add_child(leave)
	HCStyle.restyle_chat(_top.chat)
	_tint_top()

	_side = HCStyle.panel(16)
	var sv := HCStyle.vbox(8)
	_side.add_child(sv)
	sv.add_child(HCStyle.caption("Игроки"))
	_players_box = HCStyle.vbox(4)
	sv.add_child(_players_box)
	sv.add_child(HCStyle.separator())
	sv.add_child(HCStyle.caption("Подсказки игры"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_box = HCStyle.vbox(4)
	_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_history_box)
	sv.add_child(scroll)
	add_child(_side)

	_action = HCStyle.panel(14)
	add_child(_action)
	if play_intro and not Net.view.get("distorted", false):
		# панель хода (у ведущего — выбор из четырёх оттенков) — после вступления, вместе с затемнением поля
		_action.visible = false
		_board.reveal_finished.connect(func():
			_action.visible = true
			_action.modulate.a = 0.0
			_action.create_tween().tween_property(_action, "modulate:a", 1.0, HCBoard.DIM_IN).set_trans(Tween.TRANS_SINE))
	_hover_label = HCStyle.label("", HCStyle.CAP, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, "bold")
	add_child(_hover_label)

	ChatBubbles.attach(self, func(t: String) -> Control:
		var b := HCStyle.label(t, HCStyle.CAP, HCStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_stylebox_override("normal", HCStyle.box(HCStyle.SURFACE, 14, HCStyle.LINE, 1, HCStyle.SHADOW, 10))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 240
		return b, Vector2(-620, 70))

	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state(Net.view)


func _tint_top() -> void:  # цвета полосы следуют за темой (INK меняется)
	_top_dark = HCStyle.dark
	_top.title.add_theme_color_override("font_color", Color(HCStyle.INK, 0.55))
	_top.info.add_theme_color_override("font_color", HCStyle.INK)


func _layout() -> void:
	var w := size.x
	var h := size.y
	var side_w := 270.0
	var top := get_node("Top") as Control
	top.position = Vector2(20, TopBar.HEIGHT + 4)
	top.size = Vector2(w - 40, 46)
	_board.position = Vector2(12, 106)
	_board.size = Vector2(w - side_w - 44, h - 106 - 124)
	_side.position = Vector2(w - side_w - 20, 110)
	_side.size = Vector2(side_w, h - 110 - 76)
	_action.position = Vector2(24, h - 116)
	_action.size = Vector2(w - side_w - 72, 100)
	_hover_label.position = Vector2(w - side_w - 140, h - 140)
	_hover_label.size = Vector2(90, 20)


# --- Роли --------------------------------------------------------------------------

func _hotseat() -> bool:
	return _v.get("hotseat", false)


func _am_giver() -> bool:
	return _hotseat() or _me == _v["giver"]


func _am_guesser() -> bool:
	return int(_v["guesser"]) >= 0 and (_hotseat() or _me == _v["guesser"])


func _name(s: int) -> String:
	return _v["players"][s]["name"]


# --- Состояние ---------------------------------------------------------------------

func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	var prev_pieces: int = _v.get("pieces", []).size()
	_v = v
	_me = v["you"]
	_auto_deadline = Time.get_ticks_msec() + int(v.get("auto_in", 0)) * 1000
	var phase: String = v["phase"]
	if phase != prev_phase and phase == "pick":
		Sfx.play("card_flip", -6)
	if v["pieces"].size() > prev_pieces:
		Sfx.play("chip", -4, 0.08)
	_round_label.text = ("Переигровка · раунд %d" % v["round_no"]) if v["tiebreak"] else "Раунд %d из %d" % [v["round_no"], v["total_rounds"]]
	if v.get("coop", false):
		_round_label.text += " · кооператив: общий счёт %d из %d" % [int(v["scores"][0]), int(v["coop_goal"])]
	if _top_dark != HCStyle.dark:
		_tint_top()
	_update_board(phase)
	if v.get("distorted", false):
		_round_label.text += " · Crazy colors"
	_update_cues()
	_update_players()
	_update_history()
	var key := "%s/%d/%d/%d/%s" % [phase, v["round_no"], v["guesser"], v["pieces"].size(), ",".join(v.get("waiting", []))]
	if key != _action_key:
		_action_key = key
		_update_action()


func _update_board(phase: String) -> void:
	_board.set_pieces(_v["pieces"])
	_board.card = _v["card"]
	_board.free_pick = _v["free_pick"]
	var altered: bool = _v.get("distorted", false)
	_board.distorted = altered
	if altered:
		var giver_view: bool = (_hotseat() and phase in ["prepare", "pick", "cue1", "cue2"]) or (not _hotseat() and _me == int(_v["giver"]))
		var filter_id := int(_v.get("round_filter", -1))
		if _distorted_round != int(_v["round_no"]):
			_distorted_round = int(_v["round_no"])
			_board.play_distorted_round(_v["color_order"], filter_id, int(_v["board_seed"]), float(_v["spin_start"]), float(_v["spin_turns"]), giver_view)
		_board.set_filter_view(filter_id, giver_view, phase != "prepare")
	var seat_for_color: int = _v["guesser"] if _hotseat() and int(_v["guesser"]) >= 0 else _me
	_board.my_color = HCStyle.piece_color(seat_for_color)
	if phase == "pick" and _am_giver():
		_board.mode = "pick"
	elif phase in ["guess1", "guess2"] and _am_guesser():
		_board.mode = "place"
	else:
		_board.mode = "none"
	var target: int = _v["target"]
	var secret_ok := not _hotseat() or phase in ["pick", "cue1", "cue2", "reveal", "game_over"]
	_board.target = target if secret_ok else -1
	if phase in ["reveal", "game_over"]:
		var pts := {}
		for d in _v["result"].get("details", []):
			pts[d["cell"]] = d["pts"]
		_board.points = pts
		if phase == "reveal" and _revealed_round != int(_v["round_no"]):
			_revealed_round = int(_v["round_no"])
			_board.frame_t = 0.0
			if target >= 0:
				Sfx.play("card_slide", -4)
				var t := create_tween()
				t.tween_interval(0.3)
				t.tween_property(_board, "frame_t", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.tween_callback(func(): Sfx.play("chips_win", -6))
		elif phase == "game_over":
			_board.frame_t = 1.0
	else:
		_board.points = {}
		_board.frame_t = 0.0


func _update_cues() -> void:
	HCStyle.clear(_cues_row)
	var cues: Array = _v["cues"]
	if cues.is_empty():
		_cues_row.add_child(HCStyle.label("Подсказки ещё нет", HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, "medium"))
		return
	for i in cues.size():
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", HCStyle.box(HCStyle.CARD, 22, HCStyle.LINE, 1, HCStyle.SHADOW, 10))
		var row := HCStyle.hbox(10)
		var n := HCStyle.label("%d" % (i + 1), HCStyle.CAP, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		var badge := PanelContainer.new()
		var bsb := HCStyle.box(HCStyle.SAGE if i == 0 else HCStyle.DUSK, 10)
		bsb.set_content_margin_all(2)
		bsb.content_margin_left = 7
		bsb.content_margin_right = 7
		badge.add_theme_stylebox_override("panel", bsb)
		badge.add_child(n)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		row.add_child(HCStyle.label(str(cues[i]), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		pill.add_child(row)
		_cues_row.add_child(pill)
	if _v["passed"]:
		_cues_row.add_child(HCStyle.label("второй подсказки не будет", HCStyle.CAP, HCStyle.MUTED))


func _update_players() -> void:
	HCStyle.clear(_players_box)
	var gained: Array = _v["result"].get("gained", []) if _v["phase"] in ["reveal", "game_over"] else []
	var placed := {}
	for p in _v["pieces"]:
		placed[p["seat"]] = placed.get(p["seat"], 0) + 1
	for s in _v["players"].size():
		var row := PanelContainer.new()
		var active: bool = s == int(_v["guesser"]) or (s == int(_v["giver"]) and _v["phase"] in ["pick", "cue1", "cue2"])
		var sb := HCStyle.box(Color(HCStyle.SAGE, 0.12) if active else Color.TRANSPARENT, 10)
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		row.add_theme_stylebox_override("panel", sb)
		var h := HCStyle.hbox(8)
		var nv := HCStyle.vbox(-2)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := PlayerTag.make_seat(_v["players"], s, _me, 15, HCStyle.INK, " (вы)" if s == _me and not _hotseat() else "")
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.clip_text = true
		nv.add_child(nm)
		var sub := ""
		if s == int(_v["giver"]):
			sub = "ведущий"
		elif s == int(_v["guesser"]):
			sub = "ставит фишку…"
		elif placed.has(s):
			sub = "фишек: %d" % placed[s]
		if sub != "":
			nv.add_child(HCStyle.label(sub, HCStyle.CAP, HCStyle.SAGE if s == int(_v["giver"]) else HCStyle.MUTED))
		h.add_child(nv)
		if s < gained.size() and int(gained[s]) > 0:
			h.add_child(HCStyle.label("+%d" % gained[s], HCStyle.CAP, HCStyle.SAGE, HORIZONTAL_ALIGNMENT_RIGHT, "bold"))
		var sc := HCStyle.label(str(_v["scores"][s]), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_RIGHT, "title")
		sc.custom_minimum_size.x = 30
		h.add_child(sc)
		row.add_child(h)
		_players_box.add_child(row)


func _update_history() -> void:
	HCStyle.clear(_history_box)
	var hist: Array = _v["history"].duplicate()
	hist.reverse()
	for e in hist:
		var row := HCStyle.hbox(8)
		var t: int = e["target"]
		if t >= 0:
			row.add_child(HCStyle.swatch(HCData.color(int(e.get("color", t))), 20, 5))
		var txt := HCStyle.label(" · ".join(e["cues"]) if not e["cues"].is_empty() else "—", HCStyle.CAP, HCStyle.INK)
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(txt)
		_history_box.add_child(row)
	if hist.is_empty():
		_history_box.add_child(HCStyle.label("Пока пусто", HCStyle.CAP, HCStyle.MUTED))


# --- Панель действия ---------------------------------------------------------------

func _update_action() -> void:
	HCStyle.clear(_action)
	_cue_edit = null
	_auto_label = null
	var row := HCStyle.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action.add_child(row)
	var giver: int = _v["giver"]
	match _v["phase"]:
		"prepare":
			row.add_child(_wait_text("Цвета набирают скорость · дождитесь остановки…"))
		"pick":
			if _am_giver():
				var col := HCStyle.vbox(2)
				col.add_child(HCStyle.label("Ваша карта" if not _hotseat() else "Карта ведущего (%s)" % _name(giver), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
				col.add_child(HCStyle.label("Выберите любой цвет на поле" if _v["free_pick"] else "Выберите один из четырёх цветов — здесь или на поле", HCStyle.CAP, HCStyle.MUTED))
				row.add_child(col)
				if not _v["free_pick"]:
					for c in _v["card"]:
						row.add_child(_card_button(c))
			else:
				row.add_child(_wait_text("%s тянет карту и выбирает цвет…" % _name(giver)))
		"cue1", "cue2":
			if _am_giver():
				_cue_form(row, _v["phase"] == "cue2")
			else:
				row.add_child(_wait_text("%s придумывает %s…" % [_name(giver), "подсказку из одного слова" if _v["phase"] == "cue1" else "вторую подсказку (до двух слов)"]))
		"guess1", "guess2":
			var g: int = _v["guesser"]
			var second: bool = _v["phase"] == "guess2"
			if _am_guesser():
				row.add_child(HCStyle.dot(HCStyle.piece_color(g), 22))
				var col := HCStyle.vbox(2)
				col.add_child(HCStyle.label(("Ход: %s" % _name(g)) if _hotseat() else "Ваш ход", HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
				col.add_child(HCStyle.label("Кликните по клетке, которую описывает подсказка" + (" — вторая фишка, на любую свободную клетку" if second else ""), HCStyle.CAP, HCStyle.MUTED))
				row.add_child(col)
			else:
				row.add_child(HCStyle.dot(HCStyle.piece_color(g), 18))
				row.add_child(_wait_text("Ставит фишку: %s" % _name(g)))
			if Net.is_host() and not _hotseat():
				var skip := HCStyle.button("Пропустить ход", HCStyle.CAP)
				skip.tooltip_text = "Если игрок вылетел или отошёл"
				skip.pressed.connect(func(): Net.send_action("hc_skip"))
				row.add_child(skip)
		"reveal":
			_reveal_panel(row)
		"game_over":
			_game_over_panel(row)


func _wait_text(text: String) -> Label:
	return HCStyle.label(text, HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, "medium")


func _card_button(cell: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(76, 70)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := _board.base_color(cell)
	b.add_theme_stylebox_override("normal", HCStyle.box(col, 12, Color.WHITE, 3, HCStyle.SHADOW, 8))
	b.add_theme_stylebox_override("hover", HCStyle.box(col.lightened(0.06), 12, HCStyle.INK, 3, Color(0, 0, 0, 0.2), 12))
	b.add_theme_stylebox_override("pressed", HCStyle.box(col, 12, HCStyle.INK, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.text = HCData.coord(cell)
	b.add_theme_font_override("font", HCStyle.font("bold"))
	b.add_theme_font_size_override("font_size", 14)
	var txt := Color.WHITE if col.get_luminance() < 0.6 else HCStyle.INK_ART
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, txt)
	b.pressed.connect(func(): _on_cell(cell))
	return b


func _cue_form(row: HBoxContainer, second: bool) -> void:
	var t: int = _v["target"]
	if t >= 0:
		var sw := HCStyle.swatch(_board.base_color(t), 56, 12)
		row.add_child(sw)
	var col := HCStyle.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := "Подсказка из одного слова" if not second else "Вторая подсказка — до двух слов"
	if _hotseat():
		head += " (ведущий: %s)" % _name(_v["giver"])
	col.add_child(HCStyle.label(head + (" · ваш цвет %s" % HCData.coord(t) if t >= 0 else ""), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var line := HCStyle.hbox(8)
	_cue_edit = LineEdit.new()
	_cue_edit.placeholder_text = "например: «лаванда»" if not second else "например: «морская волна»"
	_cue_edit.max_length = 40
	_cue_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_edit.add_theme_font_size_override("font_size", 18)
	_cue_edit.text_submitted.connect(func(_t): _send_cue(second))
	_cue_edit.text_changed.connect(func(_t): _cue_error.text = "")
	line.add_child(_cue_edit)
	var send := HCStyle.primary("Дать подсказку", HCStyle.BODY)
	send.pressed.connect(func(): _send_cue(second))
	line.add_child(send)
	if second:
		var pass_b := HCStyle.button("Пас — считать сразу", HCStyle.CAP)
		pass_b.tooltip_text = "Если первая подсказка удалась — не давать вторую, подсчёт сразу"
		pass_b.pressed.connect(func(): Net.send_action("hc_pass"))
		line.add_child(pass_b)
	col.add_child(line)
	_cue_error = HCStyle.label("Нельзя: базовые цвета, цифры и координаты, повтор; во второй — «светлее/темнее».", HCStyle.CAP, HCStyle.MUTED)
	col.add_child(_cue_error)
	row.add_child(col)
	_cue_edit.grab_focus.call_deferred()


func _send_cue(second: bool) -> void:
	if _cue_edit == null:
		return
	var err := HCRules.check_cue(_cue_edit.text, 2 if second else 1, _v["used_cues"])
	if err != "":
		_cue_error.text = err
		_cue_error.add_theme_color_override("font_color", HCStyle.CLAY)
		Sfx.play("card_shove", -8)
		return
	Net.send_action("hc_cue", _cue_edit.text)


func _reveal_panel(row: HBoxContainer) -> void:
	var r: Dictionary = _v["result"]
	var t: int = r.get("target", -1)
	if r.get("skipped", false) or t < 0:
		row.add_child(_wait_text("Ведущий вылетел — раунд пропущен"))
	else:
		row.add_child(HCStyle.swatch(_board.base_color(t), 56, 12))
		var col := HCStyle.vbox(2)
		col.add_child(HCStyle.label("Загадан цвет %s" % HCData.coord(t), HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
		var parts := []
		var gained: Array = r["gained"]
		for s in gained.size():
			if int(gained[s]) > 0:
				parts.append("%s +%d" % [_name(s), gained[s]])
		col.add_child(HCStyle.label(" · ".join(parts) if not parts.is_empty() else "Никто не попал в рамку", HCStyle.CAP, HCStyle.MUTED))
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
	var right := HCStyle.vbox(2)
	var next := HCStyle.primary("Дальше", HCStyle.BODY, 140)
	next.pressed.connect(func():
		next.disabled = true
		Net.send_action("next"))
	right.add_child(next)
	_auto_label = HCStyle.label("", HCStyle.CAP, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	right.add_child(_auto_label)
	right.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	row.add_child(right)


func _game_over_panel(row: HBoxContainer) -> void:
	var winners: Array = _v["winners"]
	var names := winners.map(func(s): return _name(s))
	var col := HCStyle.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := ("Победа: %s" % names[0]) if names.size() == 1 else "Общая победа: %s" % ", ".join(names)
	var sub := "%d очков" % _v["scores"][winners[0]] if not winners.is_empty() else ""
	if _v.get("coop", false):
		var team := int(_v["scores"][0])
		var goal := int(_v["coop_goal"])
		text = "Цель взята — вы видите цвета одинаково!" if team >= goal else "Не хватило %d очк. до цели" % (goal - team)
		sub = "Общий счёт: %d из %d" % [team, goal]
	col.add_child(HCStyle.label(text, HCStyle.BODY, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	col.add_child(HCStyle.label(sub, HCStyle.CAP, HCStyle.MUTED))
	row.add_child(col)
	if not _celebrated and not winners.is_empty():
		_celebrated = true
		Sfx.victory()
	if Net.is_host():
		var again := HCStyle.primary("Новая партия", HCStyle.BODY)
		again.pressed.connect(Net.end_game)
		row.add_child(again)
		var back := HCStyle.button("К выбору игры" if Net.is_party() else "В меню", HCStyle.BODY)
		back.pressed.connect(func(): app.back_to_menu())
		row.add_child(back)
	else:
		var leave := HCStyle.button("Покинуть пати", HCStyle.BODY)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		row.add_child(leave)


func _on_cell(cell: int) -> void:
	if _board._reveal_active:
		return
	match _v.get("phase", ""):
		"pick":
			Net.send_action("hc_pick", cell)
		"guess1", "guess2":
			Net.send_action("hc_place", cell)


func _process(_delta: float) -> void:
	if _v.get("distorted", false):
		_action.visible = not _board._reveal_active or _v.get("phase", "") == "prepare"
	if _auto_label != null and is_instance_valid(_auto_label):
		var left := maxi(0, (_auto_deadline - Time.get_ticks_msec()) / 1000)
		var waiting: Array = _v.get("waiting", [])
		_auto_label.text = ("ждём: %s · " % ", ".join(waiting) if not waiting.is_empty() else "") + "сами через %d с" % left
