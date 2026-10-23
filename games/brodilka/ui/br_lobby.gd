extends Control
## Лобби «Большой бродилки»: игроки (2–8), стартовые монеты, время на ход, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(BRStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := BRStyle.panel(24)
	card.custom_minimum_size = Vector2(640, 0)
	center.add_child(card)
	_body = BRStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	BRStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	BRStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(BRStyle.label("Подключение…", BRStyle.BODY))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := BRStyle.hbox(16)
	var t := BRStyle.label("Большая бродилка", BRStyle.H1, BRStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = BRStyle.button("← К выбору игры", BRStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = BRStyle.button("Покинуть пати", BRStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = BRStyle.button("Выйти в меню", BRStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.theme_type_variation = "QuietButton"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		var tl := BRStyle.label("Игра на одном компьютере: ходите по очереди за всех — экран показывает, чей сейчас ход.", BRStyle.CAP, BRStyle.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tl)
	_body.add_child(BRStyle.label("ИГРОКИ · от 2 до 8", BRStyle.CAP, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, BRStyle.BODY, BRStyle.INK, "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := BRStyle.hbox(8)
		var add := BRStyle.button("+ Игрок", BRStyle.CAP)
		add.disabled = members.size() >= 8
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := BRStyle.button("− Игрок", BRStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)
	_body.add_child(BRStyle.label("НАСТРОЙКИ", BRStyle.CAP, BRStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var coins := int(s.get("br_start_coins", 0))
	if host:
		var r := BRStyle.hbox(8)
		r.add_child(BRStyle.label("Монеты на старте:", BRStyle.BODY))
		for opt in [[0, "10 (как в правилах)"], [10, "20"], [20, "30"]]:
			var b := BRStyle.button(opt[1], BRStyle.CAP)
			UISel.pick(b, coins == opt[0])
			var v: int = opt[0]
			b.pressed.connect(func(): Net.set_setting("br_start_coins", v))
			r.add_child(b)
		_body.add_child(r)
	else:
		_body.add_child(BRStyle.label("Монеты на старте: %d" % (10 + coins), BRStyle.BODY))
	_body.add_child(TurnClock.settings_row(func(tx, z): return BRStyle.button(tx, z), func(tx, z): return BRStyle.label(tx, z)))
	var start_row := BRStyle.hbox(12)
	if host:
		var start := BRStyle.primary("В путь!", BRStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(BRStyle.label("Ждём, когда хост начнёт игру…", BRStyle.BODY, BRStyle.MUTED))
	_body.add_child(start_row)
	_error = BRStyle.label("", BRStyle.CAP, BRStyle.RED)
	_body.add_child(_error)
