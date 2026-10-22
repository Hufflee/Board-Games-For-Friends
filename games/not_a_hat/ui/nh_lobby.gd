extends Control
## Лобби «Это не шляпа!»: игроки, сколько подарков у каждого, время на ход, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(NHStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := NHStyle.panel(24)
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	_body = NHStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	NHStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	NHStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(NHStyle.label("Подключение…", NHStyle.BODY))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := NHStyle.hbox(16)
	var t := NHStyle.label("Это не шляпа!", NHStyle.H1, NHStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = NHStyle.button("← К выбору игры", NHStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = NHStyle.button("Покинуть пати", NHStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = NHStyle.button("Выйти в меню", NHStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		var tl := NHStyle.label("Тест на одном компьютере: вы ходите за того, чья сейчас очередь. Подарки на столе не подсматриваются — игра на память!", NHStyle.CAP, NHStyle.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tl)
	_body.add_child(NHStyle.label("ИГРОКИ · от 3 до %d (вдвоём — с двумя подарками)" % Net.MAX_PLAYERS, NHStyle.CAP, NHStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, NHStyle.BODY, NHStyle.INK, "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := NHStyle.hbox(8)
		var add := NHStyle.button("+ Игрок", NHStyle.CAP)
		add.disabled = members.size() >= Net.MAX_PLAYERS
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := NHStyle.button("− Игрок", NHStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)
	_body.add_child(NHStyle.label("НАСТРОЙКИ", NHStyle.CAP, NHStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var each := int(s.get("nh_cards", 1))
	if host:
		var r := NHStyle.hbox(8)
		r.add_child(NHStyle.label("Подарков перед каждым:", NHStyle.BODY))
		for opt in [[1, "1 — обычная игра"], [2, "2 — сложнее"]]:
			var b := NHStyle.button(opt[1], NHStyle.CAP)
			UISel.pick(b, each == opt[0])
			var v: int = opt[0]
			b.pressed.connect(func(): Net.set_setting("nh_cards", v))
			r.add_child(b)
		_body.add_child(r)
	else:
		_body.add_child(NHStyle.label("Подарков перед каждым: %d" % each, NHStyle.BODY))
	_body.add_child(TurnClock.settings_row(func(tx, z): return NHStyle.button(tx, z), func(tx, z): return NHStyle.label(tx, z)))
	var start_row := NHStyle.hbox(12)
	if host:
		var start := NHStyle.primary("Дарим подарки!", NHStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(NHStyle.label("Ждём, когда хост начнёт игру…", NHStyle.BODY, NHStyle.MUTED))
	_body.add_child(start_row)
	_error = NHStyle.label("", NHStyle.CAP, NHStyle.BAD)
	_body.add_child(_error)
