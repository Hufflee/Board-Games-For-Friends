extends Control
## Стол «Опасных слов»: подземелье (комнаты, команды, монстр, проклятия), панели команд,
## центральная панель по фазе и роли (ловушки / объясняю / угадываю / ловлю ловушки).

var app: Node

var _v := {}
var _me := 0
var _act := 0  # тест на одном компьютере: за какую команду действуем

var _dungeon: Control
var _top: TopBar
var _teams: Array = []  # две панели команд
var _center: PanelContainer
var _center_key := ""
var _dungeon_key := ""
var _teams_key := ""
var _timer_label: Label
var _timer_bar: ProgressBar
var _wrong_label: Label
var _cand_edit: LineEdit
var _cand_draft := ""
var _cand_box: VBoxContainer
var _cand_key := ""
var _last_tick := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(DWNight.new())
	_dungeon = Control.new()
	_dungeon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_dungeon.offset_top = TopBar.HEIGHT
	_dungeon.offset_bottom = TopBar.HEIGHT + 168
	_dungeon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dungeon)
	for t in 2:
		var p := DWStyle.panel(DWStyle.TEAM_COLORS[t])
		p.custom_minimum_size = Vector2(250, 0)
		add_child(p)
		_teams.append(p)
	_center = DWStyle.panel(DWStyle.PUMPKIN)
	add_child(_center)

	_top = TopBar.make(self, "Опасные слова", func(t, z): return DWStyle.button(t, z), null, DWStyle.TEXT, DWStyle.font("bold"))
	_top.coin_center = true  # монетка — по центру сверху
	_top.z_index = 60  # выше панелей стола
	var rules := DWStyle.button("Правила", DWStyle.CAP)
	rules.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules)
	var settings := DWStyle.button("Настройки", DWStyle.CAP)
	settings.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(settings)
	var leave: Button
	if Net.is_party() and Net.is_host():
		leave = DWStyle.button("Завершить партию", DWStyle.CAP)
		LeaveGuard.wire(leave, "Завершить партию для всех?", "Все вернутся в лобби игры, пати сохранится.", Net.end_game)
	elif Net.is_party():
		leave = DWStyle.button("Покинуть пати", DWStyle.CAP)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из партии и из пати.", func(): app.leave_party())
	else:
		leave = DWStyle.button("Выйти", DWStyle.CAP)
		LeaveGuard.wire(leave, "Выйти из партии?", "Игра закончится, вы вернётесь в меню.", func(): app.back_to_menu())
	_top.actions.add_child(leave)

	resized.connect(_layout)
	Net.chat_received.connect(_on_chat_bubble)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state.call_deferred(Net.view)


func _layout() -> void:
	var w := size.x
	_teams[0].position = Vector2(12, TopBar.HEIGHT + 176)
	_teams[0].size = Vector2(250, 0)
	_teams[1].position = Vector2(w - 262, TopBar.HEIGHT + 176)
	_teams[1].size = Vector2(250, 0)
	_center.position = Vector2(276, TopBar.HEIGHT + 176)
	_center.size = Vector2(w - 552, 0)
	_center.custom_minimum_size = Vector2(w - 552, 0)


# --- Роли ---------------------------------------------------------------------------

func _test() -> bool:
	return _v.get("show_all", false)


## Моя команда (в тестовом режиме — та, за которую сейчас действуем).
func _team() -> int:
	return _act if _test() else int(_v["my_team"])


func _name(s: int) -> String:
	return _v["players"][s]["name"]


func _send(kind: String, arg := {}) -> void:
	if _test():
		arg["team"] = _act
	Net.send_action(kind, arg)


func _on_state(v: Dictionary) -> void:
	var prev_phase: String = _v.get("phase", "")
	_v = v
	_me = v["you"]
	if _test() and v["phase"] in ["turn_ready", "turn"] and prev_phase != v["phase"] and prev_phase in ["traps", "defuse", "turn_result", "round_result"]:
		_act = int(v["turn_team"])
	_layout()
	var dkey := "%s/%s/%d/%s/%s/%d/%d/%s" % [str(v["rooms"]), str(v["pos"]), v["monster_pos"], str(v["curse_rooms"]), str(v["fighting"]), _team(), v["round_no"], v["phase"]]
	if dkey != _dungeon_key:
		_dungeon_key = dkey
		_draw_dungeon()
	var tkey := "%s/%s/%s/%s/%d/%s/%d" % [str(v["ready"]), str(v.get("ready_votes", [])), str(v["pos"]), v["phase"], v["turn_team"], str(v["active_curses"]), _act]
	if tkey != _teams_key:
		_teams_key = tkey
		_draw_teams()
	var key := "%s/%d/%d/%d/%s/%s/%s" % [v["phase"], v["round_no"], v["turn_team"], _act, str(v["ready"]), str(v.get("ready_votes", [])), str(v.get("waiting", []))]
	if v["phase"] in ["turn", "turn_ready"]:
		key = "%s/%d/%d/%d" % [v["phase"], v["round_no"], v["turn_team"], _act]
	if key != _center_key:
		_center_key = key
		_build_center()
		_phase_sound(prev_phase)
	_update_live()


func _phase_sound(prev: String) -> void:
	var phase: String = _v["phase"]
	if phase == prev:
		return
	match phase:
		"turn_result":
			var e: Dictionary = _v["turn_log"][-1]
			if e["ok"]:
				Sfx.play("chips_win")
			else:
				Sfx.play("card_shove", 0)
				Sfx.play("die_throw", -4)
		"traps":
			Sfx.play("shuffle", -4)
		"game_over":
			Sfx.victory()


# --- Подземелье -----------------------------------------------------------------------

func _draw_dungeon() -> void:
	DWStyle.clear(_dungeon)
	_top.info.text = "Раунд %d из %d" % [_v["round_no"], DWRules.MAX_ROUNDS]
	var rooms: Array = _v["rooms"]
	var tile := 132.0
	var gap := 10.0
	var total := rooms.size() * tile + (rooms.size() - 1) * gap
	var x0 := (size.x - total) / 2.0
	for i in rooms.size():
		var x := x0 + i * (tile + gap)
		var room := TextureRect.new()
		room.texture = DWStyle.art("room_%d" % rooms[i])
		room.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
		room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		room.position = Vector2(x, 30)
		room.size = Vector2(tile, tile)
		room.modulate = Color(0.85, 0.8, 1.0) if i != _v["monster_pos"] else Color(1.0, 0.75, 0.75)
		# подсказка при наведении: что ждёт в этом раунде
		room.mouse_filter = Control.MOUSE_FILTER_STOP
		if i == _v["monster_pos"]:
			room.tooltip_text = "%s
Раунд с боссом" % DWData.MONSTERS[_v["monster"]]["name"]
		elif _v["curse_rooms"].has(str(i)):
			room.tooltip_text = "Раунд с проклятьем"
		else:
			room.tooltip_text = "Обычный раунд"
		_dungeon.add_child(room)
		if _v["curse_rooms"].has(str(i)):
			var cb := TextureRect.new()
			cb.texture = DWStyle.art("curse_back")
			cb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
			cb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cb.position = Vector2(x + tile - 54, 22)
			cb.size = Vector2(56, 40)
			var here: bool = _v["pos"][0] == i or _v["pos"][1] == i
			cb.tooltip_text = "Раунд с проклятьем" + ("" if here else "
Откроется, когда команда начнёт раунд в этой комнате")
			cb.mouse_filter = Control.MOUSE_FILTER_STOP
			_dungeon.add_child(cb)
		if i == _v["monster_pos"]:
			var boss: String = DWData.MONSTERS[_v["monster"]]["name"]
			var fight: bool = _v["fighting"][0] or _v["fighting"][1]
			_figure("monster_" + _v["monster"], Vector2(x + tile / 2.0 - 40, 46), 84, boss + "
Раунд с боссом" + ("" if fight else "
Битва — когда команда дойдёт до его комнаты"))
		for t in 2:
			if _v["pos"][t] == i:
				var dx := 6.0 if t == 0 else tile - 58
				var tip := ("Ваша команда (%s)" if t == _team() else "Команда %s") % DWData.TEAM_NAMES[t]
				_figure("team_%d" % t, Vector2(x + dx, 98), 54, tip)


func _figure(name: String, p: Vector2, side: float, tip: String = "") -> void:
	var f := TextureRect.new()
	f.texture = DWStyle.art(name)
	f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	f.position = p
	f.size = Vector2(side, side)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE if tip == "" else Control.MOUSE_FILTER_STOP
	f.tooltip_text = tip
	_dungeon.add_child(f)


# --- Команды --------------------------------------------------------------------------

func _draw_teams() -> void:
	for t in 2:
		var p: PanelContainer = _teams[t]
		DWStyle.clear(p)
		var v := DWStyle.vbox(5)
		p.add_child(v)
		v.add_child(DWStyle.label(DWData.TEAM_NAMES[t] + (" — вы" if t == _team() and not _test() else ""), DWStyle.BODY, DWStyle.TEAM_COLORS[t], HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(DWStyle.label("Комната %d" % _v["rooms"][_v["pos"][t]], DWStyle.CAP, DWStyle.MUTED))
		for s in _v["players"].size():
			if _v["players"][s]["team"] != t:
				continue
			var row := DWStyle.hbox(6)
			if s == _v["explainers"][t]:
				var torch := TextureRect.new()
				torch.texture = DWStyle.art("torch_%d" % t)
				torch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
				torch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				torch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				torch.custom_minimum_size = Vector2(44, 20)
				torch.tooltip_text = "Объясняет в этом раунде"
				row.add_child(torch)
			row.add_child(PlayerTag.make_seat(_v["players"], s, _me, 16, DWStyle.TEXT if s != _me or _test() else DWStyle.PUMPKIN))
			v.add_child(row)
		var st := ""
		match _v["phase"]:
			"traps":
				st = "ловушки готовы" if _v["ready"][t] else "пишет ловушки…"
			"turn_ready", "turn":
				st = "объясняет!" if _v["turn_team"] == t else "ловит ловушки"
		if st != "":
			v.add_child(DWStyle.label(st, DWStyle.CAP, DWStyle.SLIME if st in ["ловушки готовы", "объясняет!"] else DWStyle.MUTED))
		if _v["fighting"][t]:
			v.add_child(_rule_card("Бой с монстром: " + DWData.MONSTERS[_v["monster"]]["name"], DWData.MONSTERS[_v["monster"]]["hard" if _v["hard"] else "text"], DWStyle.BLOOD))
		for id in _v["active_curses"][t]:
			v.add_child(_rule_card("Проклятие: " + DWData.CURSES[id]["name"], DWData.CURSES[id]["text"], DWStyle.VIOLET))


func _rule_card(title: String, text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", DWStyle.box(Color(0.08, 0.03, 0.12, 0.95), 10, color, 2, Color(color, 0.35)))
	var v := DWStyle.vbox(2)
	p.add_child(v)
	v.add_child(DWStyle.label(title, DWStyle.CAP, color, HORIZONTAL_ALIGNMENT_LEFT, true))
	var l := DWStyle.label(text, DWStyle.CAP, DWStyle.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 210
	v.add_child(l)
	return p


# --- Центральная панель -------------------------------------------------------------

func _build_center() -> void:
	# недописанная ловушка переживает перестройку панели (её вызывают голоса и слова соперников)
	var draft := ""
	if is_instance_valid(_cand_edit):
		draft = _cand_edit.text
	_cand_draft = draft
	DWStyle.clear(_center)
	_cand_edit = null
	_cand_box = null
	_timer_label = null
	_timer_bar = null
	_wrong_label = null
	var col := DWStyle.vbox(10)
	_center.add_child(col)
	if _test():
		var row := DWStyle.hbox(8)
		row.add_child(DWStyle.label("Тест: действую за", DWStyle.CAP, DWStyle.MUTED))
		for t in 2:
			var b := DWStyle.button(DWData.TEAM_NAMES[t], DWStyle.CAP)
			UISel.pick(b, _act == t)
			var tt := t
			b.pressed.connect(func():
				_act = tt
				_center_key = ""
				_on_state(_v))
			row.add_child(b)
		col.add_child(row)
	match _v["phase"]:
		"traps":
			_build_traps(col)
		"defuse":
			_build_defuse(col)
		"turn_ready", "turn":
			_build_turn(col)
		"turn_result":
			_build_turn_result(col)
		"round_result":
			_build_round_result(col)
		"game_over":
			_build_game_over(col)


func _big_word(text: String, color: Color = DWStyle.PUMPKIN, size: int = DWStyle.H1) -> Label:
	var l := DWStyle.label(text.to_upper(), size, color, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.add_theme_font_override("font", DWStyle.font("word"))
	l.add_theme_color_override("font_outline_color", Color("1a0505"))
	l.add_theme_constant_override("outline_size", 8)
	return l


func _hint(text: String, color: Color = DWStyle.TEXT, size: int = DWStyle.BODY) -> Label:
	var l := DWStyle.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _timer_row(col: VBoxContainer) -> void:
	var row := DWStyle.hbox(10)
	_timer_label = DWStyle.label("", DWStyle.BODY, DWStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_timer_label.custom_minimum_size.x = 120
	row.add_child(_timer_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 14)
	_timer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer_bar.add_theme_stylebox_override("background", DWStyle.box(Color("0d0714"), 6))
	_timer_bar.add_theme_stylebox_override("fill", DWStyle.box(DWStyle.VIOLET, 6))
	row.add_child(_timer_bar)
	col.add_child(row)


## Ловушки: видим слово соперника; команда предлагает слова в общее поле и голосует.
## В ловушки попадают слова с наибольшим числом голосов. Голос — кружок цвета игрока.
func _build_traps(col: VBoxContainer) -> void:
	var me := _team()
	var victim := 1 - me
	if me < 0:
		col.add_child(_hint("Команды пишут ловушки…"))
		return
	col.add_child(_hint("Слово, которое будет объяснять команда «%s»:" % DWData.TEAM_NAMES[victim], DWStyle.MUTED))
	col.add_child(_big_word(_v["secret"][victim]))
	var n: int = _v["trap_lines"][me]
	var need: int = _v["words_needed"][me]
	var scribbles: bool = _v["active_curses"][victim].has("scribbles")
	var tip := "Предлагайте слова и голосуйте — в ловушки попадут %d с наибольшим числом голосов." % need
	if scribbles:
		tip = "Безумные каракули: до 10 ловушек, время ограничено! Предлагайте и голосуйте."
	elif need > n:
		tip += " (Демон: в некоторых строках по два слова.)"
	col.add_child(_hint(tip, DWStyle.MUTED, DWStyle.CAP))
	if scribbles:
		_timer_row(col)
	var ready: bool = _v["ready"][me]
	if not ready:
		var add := DWStyle.hbox(8)
		add.alignment = BoxContainer.ALIGNMENT_CENTER
		_cand_edit = LineEdit.new()
		_cand_edit.placeholder_text = "Слово-ловушка… (Enter)"
		_cand_edit.custom_minimum_size.x = 280
		_cand_edit.max_length = 40
		_cand_edit.text_submitted.connect(func(_t): _propose())
		_cand_edit.text = _cand_draft
		_cand_edit.caret_column = _cand_draft.length()
		add.add_child(_cand_edit)
		var b := DWStyle.button("Предложить", DWStyle.CAP)
		b.pressed.connect(_propose)
		add.add_child(b)
		col.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 130
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cand_box = DWStyle.vbox(3)
	_cand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cand_box)
	col.add_child(scroll)
	_cand_key = ""
	_refresh_cands()
	var act := DWStyle.hbox(12)
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	var my_vote: bool = (_v.get("ready_votes", [[], []])[me] as Array).has(_me) and not _test()
	var done := DWStyle.button("Изменить" if ready or my_vote else "Готово — ловушки расставлены", DWStyle.BODY)
	if not ready and not my_vote:
		done.theme_type_variation = "SelectedButton"
	done.tooltip_text = "Команда готова, когда нажмут все её игроки"
	done.pressed.connect(func(): _send("dw_ready", {"on": not (ready or my_vote)}))
	act.add_child(done)
	# кто из команды уже нажал «Готово»
	var team_players := []
	for s in _v["players"].size():
		if int(_v["players"][s]["team"]) == me:
			team_players.append(_v["players"][s])
	var voted := []
	for s in (_v.get("ready_votes", [[], []])[me] as Array):
		voted.append(_v["players"][int(s)]["name"])
	if ready:
		voted = team_players.map(func(p): return p["name"])
	act.add_child(ReadyDots.make(team_players, voted))
	act.add_child(DWStyle.label("Соперник: %s" % ("готов" if _v["ready"][victim] else "пишет…"), DWStyle.CAP, DWStyle.MUTED))
	col.add_child(act)


func _propose() -> void:
	if _cand_edit == null or _cand_edit.text.strip_edges() == "":
		return
	_send("dw_cand", {"word": _cand_edit.text.strip_edges()})
	_cand_edit.clear()
	_cand_edit.grab_focus()
	Sfx.play("chip", -6)


## Общее поле предложений: слово, голоса (кружки цветов игроков), кнопки голоса / удаления / «ужаса».
func _refresh_cands() -> void:
	if _cand_box == null or not is_instance_valid(_cand_box):
		return
	var me := _team()
	var list: Array = _v["cands"][me] if me >= 0 else []
	var key := str(list) + str(_v["horror_cand"]) + str(_v["ready"])
	if key == _cand_key:
		return
	_cand_key = key
	DWStyle.clear(_cand_box)
	var need: int = _v["words_needed"][me]
	var ready: bool = _v["ready"][me]
	var horror_on: bool = _v["active_curses"][1 - me].has("horror")
	var my_seat := _vote_seat()
	# порядок как в итоговом списке: больше голосов — выше
	var order := range(list.size())
	order.sort_custom(func(a, b):
		var va: int = list[a]["votes"].size()
		var vb: int = list[b]["votes"].size()
		return va > vb or (va == vb and a < b))
	if list.is_empty():
		_cand_box.add_child(_hint("Пока пусто — предложите первое слово!", DWStyle.MUTED, DWStyle.CAP))
	for rank in order.size():
		var i: int = order[rank]
		var c: Dictionary = list[i]
		var chosen := rank < need
		var row := DWStyle.hbox(8)
		row.add_child(DWStyle.label("✔" if chosen else "·", DWStyle.BODY, DWStyle.SLIME if chosen else DWStyle.MUTED))
		var w := DWStyle.label(str(c["w"]), DWStyle.BODY, DWStyle.TEXT if chosen else DWStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, chosen)
		w.custom_minimum_size.x = 170
		row.add_child(w)
		var dots := DWStyle.hbox(2)
		dots.custom_minimum_size.x = 120
		for s in c["votes"]:
			var d := TextureRect.new()
			d.texture = PlayerTag.dot(Net.color_of(int(_v["players"][s].get("color", 0))), 18)
			d.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			d.tooltip_text = _name(s)
			d.mouse_filter = Control.MOUSE_FILTER_PASS
			dots.add_child(d)
		row.add_child(dots)
		if not ready:
			var mine: bool = c["votes"].has(my_seat)
			var vb := DWStyle.button("− голос" if mine else "+ голос", DWStyle.CAP)
			var ii: int = i
			vb.pressed.connect(func(): _send("dw_vote", {"i": ii}))
			row.add_child(vb)
			if int(c["by"]) == my_seat:
				var del := DWStyle.button("×", DWStyle.CAP)
				del.tooltip_text = "Убрать своё предложение"
				del.pressed.connect(func(): _send("dw_cand_del", {"i": ii}))
				row.add_child(del)
		if horror_on:
			var hb := CheckBox.new()
			hb.text = "ужас"
			hb.tooltip_text = "Слово ужаса: попавшись в него, соперник отступит на комнату"
			hb.button_pressed = _v["horror_cand"][me] == i
			hb.disabled = ready
			var hi: int = i
			hb.toggled.connect(func(on):
				if on:
					_send("dw_horror", {"i": hi}))
			row.add_child(hb)
		_cand_box.add_child(row)


## За кого голосуем: я (в тесте на одном компьютере — первый игрок выбранной команды).
func _vote_seat() -> int:
	if not _test():
		return _me
	for s in _v["players"].size():
		if int(_v["players"][s]["team"]) == _act:
			return s
	return _me


func _build_defuse(col: VBoxContainer) -> void:
	var me := _team()
	col.add_child(_big_word("Обезвреженная ловушка", DWStyle.VIOLET, DWStyle.H1))
	var cursed := -1
	for t in 2:
		if _v["active_curses"][t].has("defuse") and _v["crossed"][t] < 0:
			cursed = t
	if cursed < 0:
		return
	if me == 1 - cursed:
		col.add_child(_hint("Назовите число — эта строка будет вычеркнута из списка ловушек команды «%s»:" % DWData.TEAM_NAMES[cursed]))
		var row := DWStyle.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in range(1, int(_v["trap_lines"][cursed]) + 1):
			var b := DWStyle.button(str(i), DWStyle.BODY, 48)
			var n := i
			b.pressed.connect(func(): _send("dw_defuse", {"n": n}))
			row.add_child(b)
		col.add_child(row)
	else:
		col.add_child(_hint("Соперник выбирает номер ловушки, которую вычеркнут из вашего списка…", DWStyle.MUTED))


## Ход: объясняющий / угадывающие / ловцы ловушек.
func _build_turn(col: VBoxContainer) -> void:
	var t: int = _v["turn_team"]
	var exp_seat: int = _v["explainers"][t]
	var me := _team()
	var reading: bool = _v["phase"] == "turn_ready"
	var is_explainer: bool = _test() and me == t or (not _test() and _me == exp_seat)
	col.add_child(_hint("Объясняет %s (команда «%s»)" % [_name(exp_seat), DWData.TEAM_NAMES[t]], DWStyle.TEAM_COLORS[t], DWStyle.BODY))
	_timer_row(col)
	_wrong_label = DWStyle.label("", DWStyle.BODY, DWStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_wrong_label)
	if is_explainer and reading:
		# слово скрыто, пока объясняющий не готов: нажал — слово открылось и пошло время
		col.add_child(_hint("Ваше слово готово. Когда будете готовы — откройте его, и часы перевернутся.", DWStyle.MUTED))
		var hidden := PanelContainer.new()
		hidden.add_theme_stylebox_override("panel", DWStyle.box(DWStyle.PANEL_2, 14, DWStyle.VIOLET_DIM, 2))
		hidden.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hidden.add_child(_big_word("• • • • • •", DWStyle.MUTED, DWStyle.H1))
		col.add_child(hidden)
		var go := DWStyle.button("Начать объяснение", DWStyle.BODY, 280)
		go.theme_type_variation = "SelectedButton"
		go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func():
			go.disabled = true
			Sfx.play("card_flip")
			_send("dw_start"))
		col.add_child(go)
	elif is_explainer:
		col.add_child(_hint("Ваше слово:", DWStyle.MUTED))
		col.add_child(_big_word(_v["secret"][t], DWStyle.PUMPKIN, DWStyle.H1))
		col.add_child(_hint("Объясняйте голосом. Нельзя однокоренные, примеры, имена собственные, «звучит как…».", DWStyle.MUTED, DWStyle.CAP))
		var ok := DWStyle.button("Отгадали!", DWStyle.H1, 300)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ok.add_theme_color_override("font_color", DWStyle.SLIME)
		ok.disabled = reading
		ok.pressed.connect(func(): _send("dw_guessed"))
		col.add_child(ok)
	elif me == t:
		col.add_child(_hint("Ждём, пока %s начнёт объяснение…" % _name(exp_seat) if reading else "Слушайте объяснение и угадывайте вслух!", DWStyle.TEXT, DWStyle.BODY))
	if me == 1 - t or _test():
		if not is_explainer or _test():
			col.add_child(_hint("Их слово: «%s». Ловите ловушки!" % str(_v["secret"][t]).to_upper(), DWStyle.PUMPKIN, DWStyle.BODY))
		var traps: Array = _v["traps"][1 - t]
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 6)
		for i in traps.size():
			var word: String = traps[i]
			if word == "":
				continue
			var crossed: bool = _v["crossed"][1 - t] == i
			var b := DWStyle.button("%d. %s%s" % [i + 1, word, "  ☠" if _v["horror"][1 - t] == i else ""], DWStyle.CAP)
			b.disabled = crossed or reading
			b.tooltip_text = "Объясняющий сказал это слово (или однокоренное) — ловушка!"
			var li := i
			var tw := word
			b.pressed.connect(func():
				LeaveGuard.ask(b, "Ловушка «%s»?" % tw, "Вы уверены, что это слово сказал объясняющий %s, а не кто-то другой?" % _name(exp_seat), "Да, ловушка!", func():
					Sfx.play("card_shove", 0)
					_send("dw_trap", {"line": li}), "Нет, отмена"))
			grid.add_child(b)
		col.add_child(grid)
		var row2 := DWStyle.hbox(10)
		row2.alignment = BoxContainer.ALIGNMENT_CENTER
		var viol := DWStyle.button("Нарушение", DWStyle.BODY)
		viol.tooltip_text = "Однокоренное с секретным словом, пример, имя собственное, «звучит как…», жест"
		viol.disabled = reading
		viol.pressed.connect(func(): _send("dw_violation"))
		row2.add_child(viol)
		var wr := DWStyle.button("+1 неверная догадка", DWStyle.BODY)
		wr.disabled = reading
		wr.pressed.connect(func(): _send("dw_wrong"))
		row2.add_child(wr)
		col.add_child(row2)


func _reason_text(e: Dictionary) -> String:
	match e["reason"]:
		"guessed":
			return "Отгадали!"
		"trap":
			return "Ловушка!"
		"horror":
			return "Слово ужаса! Команда отступает на комнату"
		"violation":
			return "Нарушение правил"
		"guesses":
			return "Закончились догадки"
		"time":
			return "Время вышло"
	return ""


func _build_turn_result(col: VBoxContainer) -> void:
	var e: Dictionary = _v["turn_log"][-1]
	var t: int = e["team"]
	col.add_child(_big_word(_reason_text(e), DWStyle.SLIME if e["ok"] else DWStyle.BLOOD, DWStyle.H1))
	col.add_child(_hint("Слово команды «%s» было: «%s»" % [DWData.TEAM_NAMES[t], str(e["word"]).to_upper()], DWStyle.TEXT, DWStyle.BODY))
	if e["ok"]:
		if _v["winners"].has(t):
			col.add_child(_hint("Монстр повержен!", DWStyle.SLIME, DWStyle.BODY))
		else:
			col.add_child(_hint("«%s» проходит в комнату %d" % [DWData.TEAM_NAMES[t], _v["rooms"][_v["pos"][t]]], DWStyle.SLIME))
	var traps: Array = _v["traps"][1 - t]
	if not traps.is_empty():
		var shown := []
		for i in traps.size():
			if traps[i] != "":
				shown.append(("[%s]" if i == e.get("line", -1) else "%s") % traps[i])
		col.add_child(_hint("Ловушки соперника: " + ", ".join(shown), DWStyle.MUTED, DWStyle.CAP))
	col.add_child(_next_button())


func _build_round_result(col: VBoxContainer) -> void:
	col.add_child(_big_word("Конец раунда %d" % _v["round_no"], DWStyle.PUMPKIN, DWStyle.H1))
	for e in _v["turn_log"]:
		if e.has("team"):
			col.add_child(_hint("«%s»: %s — %s" % [DWData.TEAM_NAMES[e["team"]], str(e["word"]).to_upper(), _reason_text(e)], DWStyle.SLIME if e["ok"] else DWStyle.TEXT))
		elif e.get("monster_moved", false):
			col.add_child(_hint("Обе команды провалились — %s подкрадывается на комнату ближе!" % DWData.MONSTERS[_v["monster"]]["name"], DWStyle.BLOOD, DWStyle.BODY))
	col.add_child(_next_button())


func _build_game_over(col: VBoxContainer) -> void:
	var w: Array = _v["winners"]
	var text := ""
	if _v["monster_won"]:
		text = "Монстр победил! Восемь раундов прошли…"
	elif w.size() == 2:
		text = "Обе команды одолели монстра — общая победа!"
	elif w.size() == 1:
		text = "Победа: «%s»!" % DWData.TEAM_NAMES[w[0]]
	col.add_child(DWStyle.title(text, DWStyle.H1, DWStyle.BLOOD if _v["monster_won"] else DWStyle.PUMPKIN))
	var row := DWStyle.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.is_host():
		var again := DWStyle.button("Новая партия", DWStyle.BODY, 190)
		again.pressed.connect(Net.end_game)
		row.add_child(again)
		var back := DWStyle.button("К выбору игры" if Net.is_party() else "В меню", DWStyle.BODY, 190)
		back.pressed.connect(func(): app.back_to_menu())
		row.add_child(back)
	else:
		var leave := DWStyle.button("Покинуть пати", DWStyle.BODY, 190)
		LeaveGuard.wire(leave, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
		row.add_child(leave)
	col.add_child(row)


func _next_button() -> Control:
	var row := DWStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var me_waiting: bool = _v.get("waiting", []).has(_name(_me)) or _test()
	var b := DWStyle.button("Дальше" if me_waiting else "Ждём остальных…", DWStyle.BODY, 200)
	b.disabled = not me_waiting
	b.pressed.connect(func(): Net.send_action("next"))
	row.add_child(b)
	row.add_child(ReadyDots.make(_v["players"], ReadyDots.pressed_next(_v)))
	return row


# --- Живые элементы: таймер, догадки, ловушки соперников по команде ----------------

func _update_live() -> void:
	var left: float = _v.get("time_left", 0.0)
	var total: float = maxf(1.0, _v.get("time_total", 60.0))
	if is_instance_valid(_timer_label):
		_timer_label.text = "%d с" % ceili(left)
		_timer_label.add_theme_color_override("font_color", DWStyle.BLOOD if left <= 10 else DWStyle.TEXT)
	if is_instance_valid(_timer_bar):
		_timer_bar.max_value = total
		_timer_bar.value = left
	if _v["phase"] == "turn" and ceili(left) != _last_tick:
		_last_tick = ceili(left)
		Sfx.countdown(_last_tick)
	if is_instance_valid(_wrong_label):
		var t: int = _v["turn_team"]
		var mx: int = _v["max_guesses"][t]
		_wrong_label.text = "Неверных догадок: %d из %s" % [_v["wrong"], "∞" if mx >= 99 else str(mx)]
	if _v["phase"] == "traps":
		_refresh_cands()


# --- Реплики: окошко у панели команды того, кто сказал ----------------------------------

var _bubbles := {}


func _on_chat_bubble(entry: Dictionary) -> void:
	var s: int = int(entry.get("seat", -1))
	if entry.get("kind", "") == "system" or _v.is_empty() or s < 0 or s >= (_v["players"] as Array).size():
		return
	var t: int = int(_v["players"][s]["team"])
	if _bubbles.has(s) and is_instance_valid(_bubbles[s]):
		_bubbles[s].queue_free()
	var b := DWStyle.label("%s: %s" % [entry["name"], str(entry["text"]).left(60)], DWStyle.CAP, DWStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var sb := DWStyle.box(DWStyle.PANEL_2, 12, DWStyle.TEAM_COLORS[t], 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", sb)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(200, 0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.z_index = 50
	add_child(b)
	var panel: Control = _teams[t]
	b.position = Vector2(panel.position.x + 25, panel.position.y + panel.size.y + 12)
	b.pivot_offset = Vector2(100, 16)
	b.scale = Vector2.ONE * 0.4
	Sfx.play("hover", -6, 0.1, 0.1)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(b, "modulate:a", 0.0, 0.4)
	tw.tween_callback(b.queue_free)
	_bubbles[s] = b
