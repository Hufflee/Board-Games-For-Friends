extends Control
## Лобби «Длины волны»: режим (команды / кооператив), выбор команд, старт, чат.

const TEAM_NAMES := ["Левое полушарие", "Правое полушарие"]
const TEAM_COLORS := [Color("5f7fbf"), Color("d9895a")]

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	add_child(preload("res://games/wavelength/ui/wl_backdrop.gd").new())
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
	var hotseat: bool = data["mode"] == "offline"
	var settings: Dictionary = data["settings"]
	var coop: bool = settings.get("wl_mode", "teams") == "coop"

	var head := HCStyle.hbox(16)
	var tv := HCStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HCStyle.caption("Лобби"))
	tv.add_child(HCStyle.label("Длина волны", HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
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
	if hotseat:
		_body.add_child(HCStyle.label("На одном компьютере: телепат смотрит на экран, остальные отворачиваются.", HCStyle.CAP, HCStyle.SAGE))

	# игроки / команды
	var members: Array = data["members"]
	if coop:
		_body.add_child(HCStyle.caption("Команда · %d" % members.size()))
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
						# «местного» игрока хост переводит между командами
						var local_i := i - Net.join_order.size()
						var sw := HCStyle.button("⇄", HCStyle.CAP)
						sw.tooltip_text = "В другую команду"
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
	if hotseat and host:
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

	if data.get("in_game", false) and not data.get("seated", []).has(multiplayer.get_unique_id()):
		_body.add_child(HCStyle.label("Сейчас идёт партия — вы присоединитесь в следующей.", HCStyle.BODY, HCStyle.SAGE))

	_body.add_child(HCStyle.caption("Настройки"))
	if host:
		var mode_row := HCStyle.hbox(8)
		mode_row.add_child(HCStyle.label("Режим:", HCStyle.BODY))
		for m in [["teams", "Две команды"], ["coop", "Кооператив (все вместе)"]]:
			var b := HCStyle.button(m[1], HCStyle.CAP)
			UISel.pick(b, settings.get("wl_mode", "teams") == m[0])
			var mid: String = m[0]
			b.pressed.connect(func(): Net.set_setting("wl_mode", mid))
			mode_row.add_child(b)
		_body.add_child(mode_row)
	else:
		_body.add_child(HCStyle.label("Режим: " + ("кооператив" if coop else "две команды"), HCStyle.BODY))
	_body.add_child(TurnClock.settings_row(func(t, z): return HCStyle.button(t, z), func(t, z): return HCStyle.label(t, z)))

	var start_row := HCStyle.hbox(12)
	if host:
		var start := HCStyle.primary("Начать игру", HCStyle.BODY, 220)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
		if not coop:
			var sh := HCStyle.button("Перемешать команды", HCStyle.CAP)
			sh.pressed.connect(Net.shuffle_teams)
			start_row.add_child(sh)
	else:
		start_row.add_child(HCStyle.label("Ждём, когда хост начнёт игру…", HCStyle.BODY, HCStyle.MUTED))
	_body.add_child(start_row)
	_body.add_child(HCStyle.label("Кооператив — от 2 игроков, команды — минимум по 2 в каждой.", HCStyle.CAP, HCStyle.MUTED))
	_error = HCStyle.label("", HCStyle.CAP, HCStyle.CLAY)
	_body.add_child(_error)
