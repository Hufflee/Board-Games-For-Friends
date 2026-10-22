extends Control
## Лобби «Тип Топ»: игроки, экспертный вариант, время на ход, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(TTStyle.Rays.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := TTStyle.bubble(24)
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	_body = TTStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _ink(text: String, size: int = 15, weight: String = "regular") -> Label:
	return TTStyle.label(text, size, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, weight)


func _rebuild() -> void:
	TTStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(_ink("Подключение…", 20))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := TTStyle.hbox(16)
	var t := TTStyle.label(app.title_text(), TTStyle.H1, TTStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = TTStyle.button("← К выбору игры", TTStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = TTStyle.button("Покинуть пати", TTStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = TTStyle.button("Выйти в меню", TTStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		_body.add_child(_ink("Тест на одном компьютере: в списке игроков на столе выбирайте, кто сейчас пишет ответ.", 13))
	_body.add_child(_ink("ИГРОКИ · кооператив, от 4 до %d" % Net.MAX_PLAYERS, 13, "bold"))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, 16, TTStyle.INK, "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := TTStyle.hbox(8)
		var add := TTStyle.button("+ Игрок", TTStyle.CAP)
		add.disabled = members.size() >= Net.MAX_PLAYERS
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := TTStyle.button("− Игрок", TTStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)
	_body.add_child(_ink("НАСТРОЙКИ", 13, "bold"))
	if host:
		var ex := CheckBox.new()
		ex.text = "Экспертный вариант (капитан называет номера, порядок любой)"
		ex.add_theme_color_override("font_color", TTStyle.INK)
		ex.add_theme_color_override("font_pressed_color", TTStyle.INK)
		ex.button_pressed = s.get("tt_expert", false)
		ex.toggled.connect(func(on): Net.set_setting("tt_expert", on))
		_body.add_child(ex)
	else:
		_body.add_child(_ink("Экспертный вариант: %s" % ("да" if s.get("tt_expert", false) else "нет")))
	_body.add_child(TurnClock.settings_row(func(tx, z): return TTStyle.button(tx, z), func(tx, z): return _ink(tx, z)))
	var start_row := TTStyle.hbox(12)
	if host:
		var start := TTStyle.primary("Поехали!", TTStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(_ink("Ждём, когда хост начнёт игру…", 16))
	_body.add_child(start_row)
	_error = TTStyle.label("", TTStyle.CAP, Color("e0393e"))
	_body.add_child(_error)
