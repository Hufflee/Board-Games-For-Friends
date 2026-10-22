extends Control
## Лобби «Алольского атлета»: игроки (2–6), время на ход, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(AAStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := AAStyle.panel(24)
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	_body = AAStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	AAStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	AAStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(AAStyle.label("Подключение…", AAStyle.BODY))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := AAStyle.hbox(16)
	var t := AAStyle.label("Алольский атлет", AAStyle.H1, AAStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = AAStyle.button("← К выбору игры", AAStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = AAStyle.button("Покинуть пати", AAStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = AAStyle.button("Выйти в меню", AAStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		var tl := AAStyle.label("Тест на одном компьютере: вы ходите за того, чья сейчас очередь.", AAStyle.CAP, AAStyle.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tl)
	_body.add_child(AAStyle.label("ИГРОКИ · от 2 до 6", AAStyle.CAP, AAStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, AAStyle.BODY, AAStyle.INK, "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := AAStyle.hbox(8)
		var add := AAStyle.button("+ Игрок", AAStyle.CAP)
		add.disabled = members.size() >= 6
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := AAStyle.button("− Игрок", AAStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)
	_body.add_child(AAStyle.label("НАСТРОЙКИ", AAStyle.CAP, AAStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var note := AAStyle.label("4 гонки на 4 островах: Мелемеле, Акала, Ула-Ула и Пони. 70 гонщиков с умениями — карты и умения на русском.", AAStyle.CAP, AAStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(note)
	_body.add_child(TurnClock.settings_row(func(tx, z): return AAStyle.button(tx, z), func(tx, z): return AAStyle.label(tx, z)))
	var start_row := AAStyle.hbox(12)
	if host:
		var start := AAStyle.primary("На старт!", AAStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(AAStyle.label("Ждём, когда хост начнёт игру…", AAStyle.BODY, AAStyle.MUTED))
	_body.add_child(start_row)
	_error = AAStyle.label("", AAStyle.CAP, AAStyle.BAD)
	_body.add_child(_error)
