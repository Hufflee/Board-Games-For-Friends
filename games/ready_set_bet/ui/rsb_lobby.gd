extends Control
## Лобби «Ready Set Bet»: игроки и цвета жетонов, скорость забега, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(RSBStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := RSBStyle.panel()
	card.custom_minimum_size = Vector2(680, 0)
	center.add_child(card)
	_body = RSBStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	RSBStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	RSBStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(RSBStyle.label("Подключение…", RSBStyle.BODY, RSBStyle.MUTED))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := RSBStyle.hbox(16)
	var title := RSBStyle.title("Ready Set Bet", RSBStyle.H1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back: Button
	if Net.is_party() and host:
		back = RSBStyle.button("← К выбору игры", RSBStyle.CAP)
		back.tooltip_text = "Пати сохранится"
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = RSBStyle.button("Покинуть пати", RSBStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = RSBStyle.button("Выйти в меню", RSBStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		_body.add_child(RSBStyle.label("Тест на одном компьютере: в списке игроков слева выберите, за кого ставить.", RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))

	_body.add_child(RSBStyle.label("ИГРОКИ · от 2 до %d" % Net.MAX_PLAYERS, RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for i in members.size():
		var row := RSBStyle.hbox(10)
		row.custom_minimum_size.x = 290
		row.add_child(RSBStyle.pic(RSBStyle.token_tex(i, 5, ""), Vector2(30, 30)))
		var m: Dictionary = members[i]
		row.add_child(PlayerTag.make(m, members, 16, RSBStyle.INK, "  · хост" if m["kind"] == "host" else ""))
		grid.add_child(row)
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := RSBStyle.hbox(8)
		var add := RSBStyle.button("+ Игрок", RSBStyle.CAP)
		add.disabled = members.size() >= Net.MAX_PLAYERS
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := RSBStyle.button("− Игрок", RSBStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)

	_body.add_child(RSBStyle.label("ЗАБЕГ", RSBStyle.CAP, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var speed: String = s.get("rsb_speed", "normal")
	var names := {"slow": "медленно", "normal": "обычно", "fast": "быстро"}
	if host:
		var r1 := RSBStyle.hbox(8)
		r1.add_child(RSBStyle.label("Скорость бросков:", RSBStyle.CAP))
		for opt in ["slow", "normal", "fast"]:
			var b := RSBStyle.button(names[opt], RSBStyle.CAP)
			UISel.pick(b, speed == opt)
			var val: String = opt
			b.pressed.connect(func(): Net.set_setting("rsb_speed", val))
			r1.add_child(b)
		_body.add_child(r1)
	else:
		_body.add_child(RSBStyle.label("Скорость бросков: %s" % names[speed], RSBStyle.CAP))
	_body.add_child(RSBStyle.label("Дом (бросает кубики и ведёт забег) — программа. 4 забега, у кого больше денег — тот и победил.", RSBStyle.CAP, RSBStyle.MUTED))

	var start_row := RSBStyle.hbox(12)
	if host:
		var start := RSBStyle.primary("И они стартуют!", RSBStyle.BODY, 260)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(RSBStyle.label("Ждём, когда хост начнёт игру…", RSBStyle.BODY, RSBStyle.MUTED))
	_body.add_child(start_row)
	_error = RSBStyle.label("", RSBStyle.CAP, RSBStyle.RED)
	_body.add_child(_error)
