extends Control
## Лобби Gloom: игроки (2–5), время на ход, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(GLStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := GLStyle.panel(24)
	card.custom_minimum_size = Vector2(660, 0)
	center.add_child(card)
	_body = GLStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	GLStyle.restyle_chat(chat)
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	GLStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(GLStyle.label("Подключение…", GLStyle.BODY))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := GLStyle.hbox(16)
	var t := GLStyle.label("Gloom", GLStyle.H1, GLStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = GLStyle.button("← К выбору игры", GLStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = GLStyle.button("Покинуть пати", GLStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = GLStyle.button("Выйти в меню", GLStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		var tl := GLStyle.label("Тест на одном компьютере: вы ходите за того, чья сейчас очередь, — его карты и семья показываются внизу.", GLStyle.CAP, GLStyle.MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tl)
	_body.add_child(GLStyle.label("ИГРОКИ · от 2 до 5", GLStyle.CAP, GLStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var members: Array = data["members"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, GLStyle.BODY, GLStyle.INK, "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	if data["mode"] == "offline" and host:
		var lrow := GLStyle.hbox(8)
		var add := GLStyle.button("+ Игрок", GLStyle.CAP)
		add.disabled = members.size() >= 5
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := GLStyle.button("− Игрок", GLStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)
	_body.add_child(GLStyle.label("НАСТРОЙКИ", GLStyle.CAP, GLStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var sets := str(s.get("gl_sets", "base"))
	var sets_opts := [["base", "Gloom"], ["all", "Gloom + дополнения"], ["gm", "Gloomier"], ["mix", "Смешать всё"]]
	if host:
		var r := GLStyle.hbox(8)
		r.add_child(GLStyle.label("Карты:", GLStyle.BODY))
		for opt in sets_opts:
			var b := GLStyle.button(opt[1], GLStyle.CAP)
			UISel.pick(b, sets == opt[0])
			var v: String = opt[0]
			b.pressed.connect(func(): Net.set_setting("gl_sets", v))
			r.add_child(b)
		_body.add_child(r)
	else:
		var nm := "Gloom"
		for opt in sets_opts:
			if opt[0] == sets:
				nm = opt[1]
		_body.add_child(GLStyle.label("Карты: " + nm, GLStyle.BODY))
	var notes := {
		"base": "Классика: 4 семьи раздаются случайно. Вчетвером каждый откладывает одного персонажа, впятером из отложенных собирается пятая семья.",
		"all": "Классика + «Незваные гости» и «Неспокойные мертвецы»: гости переходят из семьи в семью, истории дают бонусы, нежить и жива, и приносит очки.",
		"gm": "Gloomier: ночь в Хемлок-Холле. Все персонажи — из одного дома, каждый по очереди выбирает себе четверых. В центре — 2 гостя или истории.",
		"mix": "Всё вместе: классические семьи, гости и истории всех наборов и общая колода из 264 карт.",
	}
	var fam_note := GLStyle.label(notes.get(sets, notes["base"]), GLStyle.CAP, GLStyle.MUTED)
	fam_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(fam_note)
	_body.add_child(TurnClock.settings_row(func(tx, z): return GLStyle.button(tx, z), func(tx, z): return GLStyle.label(tx, z)))
	var start_row := GLStyle.hbox(12)
	if host:
		var start := GLStyle.primary("Начать трагедию", GLStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(GLStyle.label("Ждём, когда хост начнёт игру…", GLStyle.BODY, GLStyle.MUTED))
	_body.add_child(start_row)
	_error = GLStyle.label("", GLStyle.CAP, GLStyle.BLOOD)
	_body.add_child(_error)
