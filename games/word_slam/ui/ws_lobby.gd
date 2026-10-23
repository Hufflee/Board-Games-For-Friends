extends Control
## Лобби «Word Slamа»: команды (или один рассказчик), количество карт, имена, время часов, старт, чат.

const TEAM_NAMES := ["Синие", "Оранжевые"]
const TEAM_COLORS := [Color("5f7fbf"), Color("d9895a")]

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(HCBackdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := HCStyle.panel(26)
	card.custom_minimum_size = Vector2(720, 0)
	center.add_child(card)
	_body = HCStyle.vbox(12)
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
	var solo: bool = s.get("ws_mode", "teams") == "solo"
	var head := HCStyle.hbox(16)
	var tv := HCStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HCStyle.caption("Лобби"))
	tv.add_child(HCStyle.label("Word Slam", HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	head.add_child(tv)
	var back: Button
	if Net.is_party() and host:
		back = HCStyle.button("← К выбору игры", HCStyle.CAP)
		back.tooltip_text = "Пати сохранится"
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = HCStyle.button("Покинуть пати", HCStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = HCStyle.button("Выйти в меню", HCStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	if data["mode"] == "offline":
		_body.add_child(HCStyle.label("Тест на одном компьютере: справа на столе выберите, за кого смотреть.", HCStyle.CAP, HCStyle.SAGE))

	var members: Array = data["members"]
	if solo:
		_body.add_child(HCStyle.caption("Игроки · рассказчик меняется по кругу"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 18)
		for m in members:
			flow.add_child(PlayerTag.make(m, members, 16, HCStyle.INK))
		_body.add_child(flow)
	else:
		var cols := HCStyle.hbox(14)
		for team in 2:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", HCStyle.box(Color(TEAM_COLORS[team], 0.08), 14, Color(TEAM_COLORS[team], 0.6), 1))
			HCStyle.ACCENT_FX.border(p, HCStyle.DUSK)
			p.custom_minimum_size = Vector2(300, 0)
			var v := HCStyle.vbox(6)
			p.add_child(v)
			v.add_child(HCStyle.label(TEAM_NAMES[team], HCStyle.BODY, TEAM_COLORS[team].darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
			for i in members.size():
				var m: Dictionary = members[i]
				if int(m.get("team", -1)) == team:
					var row := HCStyle.hbox(8)
					row.add_child(PlayerTag.make(m, members, 16, HCStyle.INK))
					if m["kind"] == "local" and host:
						var local_i := i - Net.join_order.size()
						var sw := HCStyle.button("⇄", HCStyle.CAP)
						sw.pressed.connect(func(): Net.set_local_team(local_i, 1 - team))
						row.add_child(sw)
					v.add_child(row)
			var join := HCStyle.button("Перейти сюда", HCStyle.CAP)
			join.pressed.connect(func(): Net.set_team(team))
			v.add_child(join)
			cols.add_child(p)
		_body.add_child(cols)
		var free := members.filter(func(m): return not int(m.get("team", -1)) in [0, 1])
		if not free.is_empty():
			_body.add_child(HCStyle.label("Без команды: " + ", ".join(free.map(func(m): return m["name"])), HCStyle.CAP, HCStyle.MUTED))
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

	_body.add_child(HCStyle.caption("Настройки"))
	var count := WSData.INTRO_CARDS if s.get("ws_cards", "standard") == "intro" else WSData.standard_cards(members.size())
	if host:
		var r0 := HCStyle.hbox(8)
		r0.add_child(HCStyle.label("Режим:", HCStyle.BODY))
		for opt in [["teams", "Две команды"], ["solo", "Один рассказчик"]]:
			var b := HCStyle.button(opt[1], HCStyle.CAP)
			UISel.pick(b, s.get("ws_mode", "teams") == opt[0])
			var val: String = opt[0]
			b.pressed.connect(func(): Net.set_setting("ws_mode", val))
			r0.add_child(b)
		_body.add_child(r0)
		var r1 := HCStyle.hbox(8)
		r1.add_child(HCStyle.label("Карты:", HCStyle.BODY))
		for opt in [["standard", "обычная игра"], ["intro", "вводная (10 простых)"]]:
			var b := HCStyle.button(opt[1], HCStyle.CAP)
			UISel.pick(b, s.get("ws_cards", "standard") == opt[0])
			var val: String = opt[0]
			b.pressed.connect(func(): Net.set_setting("ws_cards", val))
			r1.add_child(b)
		r1.add_child(HCStyle.label("· %d карт" % count, HCStyle.CAP, HCStyle.MUTED))
		_body.add_child(r1)
		var r2 := HCStyle.hbox(8)
		r2.add_child(HCStyle.label("Время на ход:", HCStyle.BODY))
		for sec in [30, 60, 90, 120]:
			var b := HCStyle.button("%d с" % sec, HCStyle.CAP)
			UISel.pick(b, int(s.get("ws_time", 60)) == sec)
			var ss: int = sec
			b.pressed.connect(func(): Net.set_setting("ws_time", ss))
			r2.add_child(b)
		var names := CheckBox.new()
		names.text = "Имена (фильмы, книги, люди)"
		names.button_pressed = s.get("ws_names", true)
		names.toggled.connect(func(on): Net.set_setting("ws_names", on))
		r2.add_child(names)
		_body.add_child(r2)
	else:
		_body.add_child(HCStyle.label("%s · %d карт · на ход %d с%s" % ["Один рассказчик" if solo else "Две команды", count, int(s.get("ws_time", 60)), " · с именами" if s.get("ws_names", true) else ""], HCStyle.BODY))

	var start_row := HCStyle.hbox(12)
	if host:
		var start := HCStyle.primary("Ворд! Слэм!", HCStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
		if Net.is_party() and not solo:
			var sh := HCStyle.button("Перемешать команды", HCStyle.CAP)
			sh.pressed.connect(Net.shuffle_teams)
			start_row.add_child(sh)
	else:
		start_row.add_child(HCStyle.label("Ждём, когда хост начнёт игру…", HCStyle.BODY, HCStyle.MUTED))
	_body.add_child(start_row)
	_error = HCStyle.label("", HCStyle.CAP, HCStyle.CLAY)
	_body.add_child(_error)
