extends Control
## Лобби «Опасных слов»: команды, подземелье, монстр, проклятия, время, старт, чат.

var app: Node

var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	_body = DWStyle.vbox(12)
	margin.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	DWStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(DWStyle.label("Подключение…", DWStyle.BODY))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := DWStyle.hbox(16)
	var title := DWStyle.title("Опасные слова", DWStyle.H1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if Net.is_party() and host:
		var back := DWStyle.button("← К выбору игры (пати сохранится)", DWStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
		head.add_child(back)
	elif Net.is_party():
		var leave_p := DWStyle.button("Покинуть пати", DWStyle.CAP)
		LeaveGuard.wire(leave_p, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		head.add_child(leave_p)
	else:
		var leave := DWStyle.button("Выйти в меню", DWStyle.CAP)
		leave.pressed.connect(func(): app.back_to_menu())
		head.add_child(leave)
	_body.add_child(head)
	if data["mode"] == "offline":
		_body.add_child(DWStyle.label("Тест на одном компьютере: все видят всё, вы действуете за обе команды.", DWStyle.CAP, DWStyle.MUTED))

	# команды
	var members: Array = data["members"]
	var cols := DWStyle.hbox(16)
	for team in 2:
		var p := DWStyle.panel(DWStyle.TEAM_COLORS[team])
		p.custom_minimum_size = Vector2(320, 0)
		var v := DWStyle.vbox(6)
		p.add_child(v)
		var head_row := DWStyle.hbox(8)
		var fig := TextureRect.new()
		fig.texture = DWStyle.art("team_%d" % team)
		fig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
		fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fig.custom_minimum_size = Vector2(46, 46)
		head_row.add_child(fig)
		head_row.add_child(DWStyle.label(DWData.TEAM_NAMES[team], DWStyle.BODY, DWStyle.TEAM_COLORS[team], HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(head_row)
		for i in members.size():
			var m: Dictionary = members[i]
			if int(m.get("team", -1)) == team:
				var row := DWStyle.hbox(8)
				row.add_child(PlayerTag.make(m, members, 17, DWStyle.TEXT))
				if m["kind"] == "local" and host:
					var local_i := i - Net.join_order.size()
					var sw := DWStyle.button("⇄", DWStyle.CAP)
					sw.pressed.connect(func(): Net.set_local_team(local_i, 1 - team))
					row.add_child(sw)
				v.add_child(row)
		var join := DWStyle.button("Перейти сюда", DWStyle.CAP)
		join.pressed.connect(func(): Net.set_team(team))
		v.add_child(join)
		cols.add_child(p)
	var free := DWStyle.vbox(4)
	for m in members.filter(func(m): return not int(m.get("team", -1)) in [0, 1]):
		free.add_child(PlayerTag.make(m, members, 15, DWStyle.MUTED, " — без команды"))
	cols.add_child(free)
	_body.add_child(cols)

	# настройки
	var opts := DWStyle.panel()
	opts.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ov := DWStyle.vbox(8)
	opts.add_child(ov)
	ov.add_child(DWStyle.label("Подземелье", DWStyle.BODY, DWStyle.PUMPKIN, HORIZONTAL_ALIGNMENT_LEFT, true))
	if host:
		var r1 := DWStyle.hbox(8)
		r1.add_child(DWStyle.label("Комнаты:", DWStyle.BODY))
		for opt in [["3-7", "3 · 4 · 5 · 6 · 7"], ["even", "2 · 4 · 6 · 8 · 10"]]:
			var b := DWStyle.button(opt[1], DWStyle.CAP)
			UISel.pick(b, s.get("dw_rooms", "3-7") == opt[0])
			var val: String = opt[0]
			b.pressed.connect(func(): Net.set_setting("dw_rooms", val))
			r1.add_child(b)
		ov.add_child(r1)
		var r2 := DWStyle.hbox(6)
		r2.add_child(DWStyle.label("Монстр:", DWStyle.BODY))
		for mid in ["random", "troll", "dragon", "mummy", "demon", "vampire"]:
			var b := DWStyle.button("Случайный" if mid == "random" else DWData.MONSTERS[mid]["name"], DWStyle.CAP)
			UISel.pick(b, s.get("dw_monster", "random") == mid)
			var mm: String = mid
			b.pressed.connect(func(): Net.set_setting("dw_monster", mm))
			r2.add_child(b)
		ov.add_child(r2)
		var r3 := DWStyle.hbox(14)
		var hard := CheckBox.new()
		hard.text = "Злобный монстр"
		hard.button_pressed = s.get("dw_hard", false)
		hard.toggled.connect(func(on): Net.set_setting("dw_hard", on))
		r3.add_child(hard)
		var curses := CheckBox.new()
		curses.text = "Проклятия"
		curses.button_pressed = s.get("dw_curses", true)
		curses.toggled.connect(func(on): Net.set_setting("dw_curses", on))
		r3.add_child(curses)
		var stay := CheckBox.new()
		stay.text = "Не сгорают"
		stay.tooltip_text = "Проклятие комнаты действует каждый раунд, пока команда в ней (по правилам — только один раз)"
		stay.button_pressed = s.get("dw_curses_stay", false)
		stay.disabled = not s.get("dw_curses", true)
		stay.toggled.connect(func(on): Net.set_setting("dw_curses_stay", on))
		r3.add_child(stay)
		r3.add_child(DWStyle.label("Время на ход:", DWStyle.BODY))
		for sec in [45, 60, 90]:
			var b := DWStyle.button("%d с" % sec, DWStyle.CAP)
			UISel.pick(b, int(s.get("dw_time", 60)) == sec)
			var ss: int = sec
			b.pressed.connect(func(): Net.set_setting("dw_time", ss))
			r3.add_child(b)
		ov.add_child(r3)
	else:
		var mname: String = "случайный" if s.get("dw_monster", "random") == "random" else DWData.MONSTERS[s["dw_monster"]]["name"]
		ov.add_child(DWStyle.label("Монстр: %s%s · проклятия: %s · время: %d с" % [mname, " (злобный)" if s.get("dw_hard", false) else "", ("да, не сгорают" if s.get("dw_curses_stay", false) else "да") if s.get("dw_curses", true) else "нет", int(s.get("dw_time", 60))], DWStyle.BODY))
	_body.add_child(opts)

	if data["mode"] == "offline" and host:
		var lrow := DWStyle.hbox(10)
		var add := DWStyle.button("+ Игрок", DWStyle.CAP)
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := DWStyle.button("− Игрок", DWStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		_body.add_child(lrow)

	var start_row := DWStyle.hbox(12)
	if host:
		var start := DWStyle.button("Спуститься в подземелье!", DWStyle.BODY, 320)
		start.theme_type_variation = "SelectedButton"  # главное действие — тыквенной заливкой
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
		if Net.is_party():
			var sh := DWStyle.button("Перемешать команды", DWStyle.CAP)
			sh.pressed.connect(Net.shuffle_teams)
			start_row.add_child(sh)
	else:
		start_row.add_child(DWStyle.label("Ждём, когда хост начнёт игру…", DWStyle.BODY, DWStyle.MUTED))
	_body.add_child(start_row)
	_error = DWStyle.label("", DWStyle.BODY, DWStyle.BLOOD)
	_body.add_child(_error)
