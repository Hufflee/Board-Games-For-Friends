extends Control
## Лобби: игроки, боты, выбор набора карт, старт.
## Раскладка: две колонки (игроки и режим | набор карт), справа место под чат,
## внизу — всегда видимая панель с главной кнопкой «Начать игру».

var app: Node

var _body: VBoxContainer
var _cols_left: VBoxContainer
var _cols_right: VBoxContainer
var _footer: HBoxContainer
var _error: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_right", 480)  # справа — чат
	add_child(margin)
	var outer := K12UI.vbox(14)
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_body = K12UI.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_footer = K12UI.hbox(16)
	outer.add_child(_footer)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	K12UI.clear(_body)
	K12UI.clear(_footer)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(K12UI.label("Подключение…", K12UI.BODY))
		return
	var host := Net.is_host()
	var settings: Dictionary = data["settings"]

	var head := K12UI.hbox(16)
	var title := K12UI.label("Лобби", K12UI.H1, K12UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if Net.is_party() and host:
		var back := K12UI.button("← К выбору игры (пати сохранится)", K12UI.BODY)
		back.pressed.connect(func(): app.back_to_hub())
		head.add_child(back)
	elif Net.is_party():
		var leave_p := K12UI.button("Покинуть пати", K12UI.BODY)
		LeaveGuard.wire(leave_p, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		head.add_child(leave_p)
	else:
		var leave := K12UI.button("Выйти в меню", K12UI.BODY)
		leave.pressed.connect(func(): app.back_to_menu())
		head.add_child(leave)
	_body.add_child(head)

	var mode_text := {"steam": "Steam (только друзья)", "enet": "по IP", "offline": "с ботами, без сети"}
	_body.add_child(K12UI.label("Режим: " + mode_text.get(data["mode"], data["mode"]), K12UI.BODY, K12UI.MUTED))
	if data["code"] != "":
		var code_row := K12UI.hbox(10)
		code_row.add_child(K12UI.label("Код лобби:" if data["mode"] == "steam" else "Адрес:", K12UI.BODY))
		var code := K12UI.label(data["code"], K12UI.BODY, K12UI.GOLD)
		code_row.add_child(code)
		var copy := K12UI.button("Скопировать", K12UI.CAP)
		copy.pressed.connect(func(): DisplayServer.clipboard_set(str(data["code"]).split(",")[0]))
		code_row.add_child(copy)
		if data["mode"] == "steam" and host:
			var invite := K12UI.button("Пригласить друзей (Steam)", K12UI.CAP)
			invite.pressed.connect(Net.invite_friends)
			code_row.add_child(invite)
		_body.add_child(code_row)

	var cols := K12UI.hbox(18)
	_cols_left = K12UI.vbox(14)
	_cols_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cols_left.size_flags_stretch_ratio = 0.8
	_cols_right = K12UI.vbox(14)
	_cols_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_cols_left)
	cols.add_child(_cols_right)
	_body.add_child(cols)

	# --- Игроки ---
	var players_panel := K12UI.panel()
	var pv := K12UI.vbox(6)
	players_panel.add_child(pv)
	_cols_left.add_child(players_panel)
	pv.add_child(K12UI.label("Игроки (%d/%d)" % [data["members"].size(), Net.MAX_PLAYERS], K12UI.BODY, K12UI.GOLD))
	var kind_text := {"host": "хост", "player": "игрок", "bot": "бот"}
	for m in data["members"]:
		pv.add_child(PlayerTag.make(m, data["members"], 18, K12UI.CREAM, "  — " + kind_text[m["kind"]]))
	if host:
		var bot_row := K12UI.hbox(10)
		var add := K12UI.button("+ Бот", K12UI.BODY)
		add.disabled = data["members"].size() >= Net.MAX_PLAYERS
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		bot_row.add_child(add)
		var rem := K12UI.button("− Бот", K12UI.BODY)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		bot_row.add_child(rem)
		pv.add_child(bot_row)

	# --- Набор карт ---
	var deck_panel := K12UI.panel()
	var dv := K12UI.vbox(8)
	deck_panel.add_child(dv)
	_cols_right.add_child(deck_panel)
	dv.add_child(K12UI.label("Набор карт", K12UI.BODY, K12UI.GOLD))
	var modes := [["first", "Первая партия"], ["random", "Случайный (Рыцарь + 6, ≥2 с ◆)"], ["manual", "Выбрать вручную (7 карт)"]]
	var promos := [["", "Без промокарты"], [K12Cards.COLLECTOR, "+ Коллекционер"], [K12Cards.FAUN, "+ Фавн"]]
	if host:
		var row := K12UI.hbox(10)
		row.add_child(_option(modes, settings["deck_mode"], func(v): Net.set_setting("deck_mode", v)))
		row.add_child(_option(promos, settings["promo"], func(v): Net.set_setting("promo", v)))
		dv.add_child(row)
	else:
		var mode_name := ""
		for m in modes:
			if m[0] == settings["deck_mode"]:
				mode_name = m[1]
		var promo_name := ""
		for p in promos:
			if p[0] == settings["promo"]:
				promo_name = p[1]
		dv.add_child(K12UI.label("%s, %s (выбирает хост)" % [mode_name, promo_name.to_lower()], K12UI.BODY))

	if settings["deck_mode"] == "manual" and host:
		var grid := GridContainer.new()
		grid.columns = 3
		for c in K12Cards.BASE:
			var cb := CheckBox.new()
			cb.text = K12Cards.card_name(c)
			cb.add_theme_font_size_override("font_size", 16)
			cb.button_pressed = settings["manual"].has(c)
			cb.toggled.connect(func(on):
				var list: Array = Net.settings["manual"].duplicate()
				if on and not list.has(c):
					list.append(c)
				elif not on:
					list.erase(c)
				Net.set_setting("manual", list))
			grid.add_child(cb)
		dv.add_child(grid)
		dv.add_child(K12UI.label("Отмечено: %d из 7" % settings["manual"].size(), K12UI.CAP, K12UI.MUTED))

	var preview: Array = []
	match settings["deck_mode"]:
		"first":
			preview = K12Cards.FIRST_GAME.duplicate()
		"manual":
			preview = K12Cards.BASE.filter(func(c): return settings["manual"].has(c))
	if settings["promo"] != "":
		preview.append(settings["promo"])
	if settings["deck_mode"] == "random":
		dv.add_child(K12UI.label("Карты будут выбраны случайно при старте.", K12UI.CAP, K12UI.MUTED))
	if not preview.is_empty():
		var cards := HFlowContainer.new()
		cards.add_theme_constant_override("h_separation", 6)
		cards.add_theme_constant_override("v_separation", 6)
		for c in preview:
			cards.add_child(K12CardView.new(c, true))
		dv.add_child(cards)

	# --- Режим партии ---
	var mode_panel := K12UI.panel()
	var mv := K12UI.vbox(8)
	mode_panel.add_child(mv)
	_cols_left.add_child(mode_panel)
	mv.add_child(K12UI.label("Режим партии", K12UI.BODY, K12UI.GOLD))
	var count: int = data["members"].size()
	var speeds := [["fast", "Вскрытие карт: быстро"], ["normal", "Вскрытие карт: обычно"], ["slow", "Вскрытие карт: торжественно"]]
	if host:
		var tour := CheckBox.new()
		tour.text = "Турнирные правила (от 5 игроков)"
		tour.tooltip_text = "Группы и финал победителей групп"
		tour.add_theme_font_size_override("font_size", 16)
		tour.button_pressed = settings.get("tournament", true)
		tour.disabled = count < 5
		tour.toggled.connect(func(on): Net.set_setting("tournament", on))
		mv.add_child(tour)
		mv.add_child(_option(speeds, settings.get("reveal_speed", "normal"), func(v): Net.set_setting("reveal_speed", v)))
	else:
		var t := "Турнирные правила: " + ("да" if settings.get("tournament", true) and count >= 5 else "нет")
		for sp in speeds:
			if sp[0] == settings.get("reveal_speed", "normal"):
				t += " · " + sp[1]
		mv.add_child(K12UI.label(t, K12UI.BODY))
	if count >= 5 and settings.get("tournament", true):
		var sizes: Array = K12Rules.GROUP_SIZES.get(count, [])
		var tl := K12UI.label("Игроки делятся на группы %s (состав меняется каждый раунд). Второе место в группе — 1 ПО, победители групп разыгрывают 2 и 1 ПО в финале." % "/".join(sizes.map(func(x): return str(x))), K12UI.CAP, K12UI.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mv.add_child(tl)

	if data.get("in_game", false) and not data.get("seated", []).has(multiplayer.get_unique_id()):
		_body.add_child(K12UI.label("Сейчас идёт партия — вы сядете за стол в следующей. Пока можно общаться в чате.", K12UI.BODY, K12UI.GOLD))

	mv.add_child(TurnClock.settings_row(func(t, z): return K12UI.button(t, z), func(t, z): return K12UI.label(t, z)))

	# --- Старт: всегда видно внизу, главная кнопка выделена золотом ---
	var start_row := _footer
	if host:
		var start := K12UI.primary("Начать игру", K12UI.BODY, 280)
		start.disabled = data["members"].size() < 2
		if not start.disabled:
			start.theme_type_variation = "SelectedButton"
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
		if data["members"].size() < 2:
			start_row.add_child(K12UI.label("Нужно минимум 2 игрока — пригласите друзей или добавьте бота.", K12UI.CAP, K12UI.MUTED))
	else:
		start_row.add_child(K12UI.label("Ждём, когда хост начнёт игру…", K12UI.BODY, K12UI.MUTED))
	_error = K12UI.label("", K12UI.BODY, K12UI.RED)
	_error.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_error)


func _option(items: Array, current: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", 16)
	for i in items.size():
		ob.add_item(items[i][1], i)
		if items[i][0] == current:
			ob.select(i)
	ob.item_selected.connect(func(i): on_pick.call(items[i][0]))
	return ob
