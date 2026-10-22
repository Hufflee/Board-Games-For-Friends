extends Control
## Лобби «Оттенков и подсказок»: игроки и их цвета фишек, круги ведущих, вариант для новичков, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(HCBackdrop.new(true))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := HCStyle.panel(28)
	card.custom_minimum_size = Vector2(700, 0)
	center.add_child(card)
	_body = HCStyle.vbox(14)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	HCStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	HCStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(HCStyle.label("Подключение…", HCStyle.BODY, HCStyle.MUTED))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := HCStyle.hbox(16)
	var tv := HCStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HCStyle.caption("Лобби"))
	var title := HCStyle.label("Hues and Cues", HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	tv.add_child(title)
	head.add_child(tv)
	if Net.is_party() and host:
		var back := HCStyle.button("← К выбору игры", HCStyle.CAP)
		back.tooltip_text = "Пати сохранится"
		back.pressed.connect(func(): app.back_to_hub())
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(back)
	elif Net.is_party():
		var leave_p := HCStyle.button("Покинуть пати", HCStyle.CAP)
		LeaveGuard.wire(leave_p, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		leave_p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(leave_p)
	else:
		var leave := HCStyle.button("Выйти в меню", HCStyle.CAP)
		leave.pressed.connect(func(): app.back_to_menu())
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(leave)
	_body.add_child(head)
	if data["mode"] == "offline":
		_body.add_child(HCStyle.label("Тест на одном компьютере: передавайте мышь по кругу — программа сама подставит, чей ход.", HCStyle.CAP, HCStyle.SAGE))

	# игроки
	_body.add_child(HCStyle.caption("Игроки · от 3 до %d" % Net.MAX_PLAYERS))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	for i in members.size():
		var row := HCStyle.hbox(10)
		row.custom_minimum_size.x = 300
		row.add_child(HCStyle.dot(HCStyle.piece_color(i), 18))
		var m: Dictionary = members[i]
		row.add_child(PlayerTag.make(m, members, 16, HCStyle.INK, "  · хост" if m["kind"] == "host" else ""))
		grid.add_child(row)
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := HCStyle.hbox(8)
		var add := HCStyle.button("+ Игрок", HCStyle.CAP)
		add.disabled = members.size() >= Net.MAX_PLAYERS
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := HCStyle.button("− Игрок", HCStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)

	# настройки
	_body.add_child(HCStyle.caption("Настройки"))
	var laps := int(s.get("hc_laps", 0))
	if host:
		var r1 := HCStyle.hbox(8)
		r1.add_child(HCStyle.label("Каждый ведёт:", HCStyle.BODY))
		for opt in [[0, "по правилам"], [1, "1 раз"], [2, "2 раза"]]:
			var b := HCStyle.button(opt[1], HCStyle.CAP)
			UISel.pick(b, laps == opt[0])
			var val: int = opt[0]
			b.pressed.connect(func(): Net.set_setting("hc_laps", val))
			r1.add_child(b)
		_body.add_child(r1)
		var free := CheckBox.new()
		free.text = "Вариант для новичков: ведущий выбирает любой цвет на поле"
		free.button_pressed = s.get("hc_free", false)
		free.toggled.connect(func(on): Net.set_setting("hc_free", on))
		_body.add_child(free)
	else:
		var lt: String = {0: "по правилам (до 6 игроков — дважды, больше — один раз)", 1: "один раз", 2: "два раза"}[laps]
		_body.add_child(HCStyle.label("Каждый ведёт: %s%s" % [lt, " · ведущий выбирает любой цвет" if s.get("hc_free", false) else ""], HCStyle.BODY))

	_body.add_child(TurnClock.settings_row(func(t, z): return HCStyle.button(t, z), func(t, z): return HCStyle.label(t, z)))
	var start_row := HCStyle.hbox(12)
	if host:
		var start := HCStyle.primary("Начать игру", HCStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(HCStyle.label("Ждём, когда хост начнёт игру…", HCStyle.BODY, HCStyle.MUTED))
	_body.add_child(start_row)
	_error = HCStyle.label("", HCStyle.CAP, HCStyle.CLAY)
	_body.add_child(_error)
