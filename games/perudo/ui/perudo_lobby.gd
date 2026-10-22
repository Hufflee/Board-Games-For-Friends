extends Control
## Лобби «Перудо»: игроки, боты, число костей, Мапуто, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	_body = K12UI.vbox(14)
	margin.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	K12UI.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(K12UI.label("Подключение…", K12UI.BODY))
		return
	var host := Net.is_host()
	var settings: Dictionary = data["settings"]

	var head := K12UI.hbox(16)
	var title := K12UI.label("Перудо — лобби", K12UI.H1, K12UI.GOLD)
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

	var players_panel := K12UI.panel()
	players_panel.custom_minimum_size.x = 560
	players_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pv := K12UI.vbox(6)
	players_panel.add_child(pv)
	_body.add_child(players_panel)
	pv.add_child(K12UI.label("Игроки (%d/%d)" % [data["members"].size(), Net.MAX_PLAYERS], K12UI.BODY, K12UI.GOLD))
	var kind_text := {"host": "хост", "player": "игрок", "bot": "бот"}
	for m in data["members"]:
		var row := K12UI.hbox(8)
		row.add_child(K12Plate.Avatar.make(null, m["name"]))
		row.add_child(PlayerTag.make(m, data["members"], 18, K12UI.CREAM, " — " + kind_text[m["kind"]]))
		pv.add_child(row)
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

	var opts := K12UI.panel()
	opts.custom_minimum_size.x = 560
	opts.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ov := K12UI.vbox(8)
	opts.add_child(ov)
	_body.add_child(opts)
	ov.add_child(K12UI.label("Настройки партии", K12UI.BODY, K12UI.GOLD))
	var dice_n := int(settings.get("perudo_dice", 5))
	var maputo_on := bool(settings.get("perudo_maputo", true))
	if host:
		var drow := K12UI.hbox(10)
		drow.add_child(K12UI.label("Костей у каждого на старте:", K12UI.BODY))
		for n in [3, 4, 5, 6]:
			var b := K12UI.button(str(n), K12UI.BODY, 44)
			UISel.pick(b, n == dice_n)
			b.pressed.connect(func(): Net.set_setting("perudo_dice", n))
			drow.add_child(b)
		ov.add_child(drow)
		var mp := CheckBox.new()
		mp.text = "Раунд Мапуто (игрок с последней костью может его объявить)"
		mp.button_pressed = maputo_on
		mp.toggled.connect(func(on): Net.set_setting("perudo_maputo", on))
		ov.add_child(mp)
	else:
		ov.add_child(K12UI.label("Костей на старте: %d · Мапуто: %s" % [dice_n, "да" if maputo_on else "нет"], K12UI.BODY))

	if data.get("in_game", false) and not data.get("seated", []).has(multiplayer.get_unique_id()):
		_body.add_child(K12UI.label("Сейчас идёт партия — вы сядете за стол в следующей.", K12UI.BODY, K12UI.GOLD))

	ov.add_child(TurnClock.settings_row(func(t, z): return K12UI.button(t, z), func(t, z): return K12UI.label(t, z)))
	var start_row := K12UI.hbox(12)
	if host:
		var start := K12UI.button("Начать игру", K12UI.BODY, 260)
		start.disabled = data["members"].size() < 2
		if not start.disabled:
			start.theme_type_variation = "SelectedButton"  # главное действие — золотом
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
		if data["members"].size() < 2:
			start_row.add_child(K12UI.label("Нужно минимум 2 игрока — позовите друзей или добавьте бота.", K12UI.CAP, K12UI.MUTED))
	else:
		start_row.add_child(K12UI.label("Ждём, когда хост начнёт игру…", K12UI.BODY, K12UI.MUTED))
	_body.add_child(start_row)
	_error = K12UI.label("", K12UI.BODY, K12UI.RED)
	_body.add_child(_error)
