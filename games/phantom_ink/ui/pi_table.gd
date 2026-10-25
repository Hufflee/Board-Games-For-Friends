extends Control
## Общий планшет и личный экран. Ни одна закрытая подсказка не передаётся соперникам.
var app: Node
var _v: Dictionary = {}
var _body: VBoxContainer
var _top: TopBar
var _selected: Array = []
var _unlocked_seat := -2
var _preview: Control
var _knock: AudioStreamPlayer

func _ready() -> void:
	add_child(PIStyle.Backdrop.new())
	_knock = AudioStreamPlayer.new()
	_knock.bus = "SFX"
	_knock.volume_db = -8.0
	_knock.stream = load("res://games/phantom_ink/audio/knock.wav")
	add_child(_knock)
	_top = TopBar.make(self, "Призрачные чернила", func(t, z): return PIStyle.button(t, z), null, PIStyle.ink(), PIStyle.font("title"))
	_top.chat.z_index = 80
	for entry in [["Правила", app.show_rules], ["Настройки", app.show_settings], ["Выйти", app.back_to_hub]]:
		var b := PIStyle.button(entry[0], PIStyle.CAP)
		if entry[0] == "Выйти":
			LeaveGuard.wire(b, "Выйти?", "Покинуть сеанс?", entry[1])
		else:
			b.pressed.connect(entry[1])
		_top.actions.add_child(b)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 24
	margin.offset_right = -24
	margin.offset_top = TopBar.HEIGHT + 16
	margin.offset_bottom = -16
	add_child(margin)
	_body = PIStyle.vbox(12)
	margin.add_child(_body)
	Net.state_changed.connect(_changed)
	_changed(Net.view)

func _changed(view: Dictionary) -> void:
	if view.is_empty():
		return
	if not _v.is_empty() and _v.phase == "judge" and int(view.revision) > int(_v.revision) and (view.phase == "guess" or view.phase == "game_over" and view.winner >= 0):
		_knock.play()
	_v = view
	PIStyle.clear(_body)
	if is_instance_valid(_preview):
		_preview.queue_free()
	var team_name: String = ["Солнце", "Луна"][int(view.team)]
	_top.info.text = "Сеанс завершён" if view.phase == "game_over" else "%s · ход %d / 8" % [team_name, mini(8, view.rows[int(view.team)].size() + (0 if view.phase in ["clue", "writing", "judge", "guess"] else 1))]
	if Net.mode == "offline":
		var row := PIStyle.hbox(8)
		var select := OptionButton.new()
		for i in view.players.size():
			select.add_item("%s · %s" % [view.players[i].name, PIData.ROLES[int(view.roles[i])]])
		select.select(int(view.seat))
		select.item_selected.connect(func(seat: int):
			_unlocked_seat = -2
			_selected.clear()
			Net.pi_switch_seat(seat))
		row.add_child(select)
		var pass_button := PIStyle.button("Передать ход нужному игроку", PIStyle.CAP)
		pass_button.pressed.connect(func():
			_unlocked_seat = -2
			_selected.clear()
			Net.pi_switch_seat(int(view.actor)))
		row.add_child(pass_button)
		_body.add_child(row)
		if _unlocked_seat != int(view.seat):
			_curtain()
			return
	var main := PIStyle.hbox(16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(main)
	var board := PIStyle.hbox(16)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(board)
	for t in 2:
		_board_team(board, t)
	var side := PIStyle.panel()
	side.custom_minimum_size.x = 340
	main.add_child(side)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sc)
	var col := PIStyle.vbox(12)
	col.custom_minimum_size.x = 304
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	var role: int = view.role
	col.add_child(PIStyle.label(PIData.ROLES[role] if role >= 0 else "Зритель", PIStyle.BODY, true))
	_controls(col)
	var history := PIStyle.button("Открытый сброс · %d" % view.discard.size(), PIStyle.CAP)
	history.pressed.connect(_discard)
	col.add_child(history)

func _curtain() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(center)
	var panel := PIStyle.panel()
	panel.custom_minimum_size.x = 600
	center.add_child(panel)
	var col := PIStyle.vbox(24)
	panel.add_child(col)
	col.add_child(PIStyle.label("Передайте экран: " + str(_v.players[int(_v.seat)].name), PIStyle.H1, true))
	col.add_child(PIStyle.label(PIData.ROLES[int(_v.role)]))
	col.add_child(PIStyle.label("Другие игроки должны отвернуться.", PIStyle.BODY))
	var open := PIStyle.primary("Я готов · открыть мой экран")
	open.pressed.connect(func():
		_unlocked_seat = int(_v.seat)
		_changed(_v))
	col.add_child(open)

func _board_team(parent: Control, t: int) -> void:
	var p := PIStyle.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var col := PIStyle.vbox(8)
	p.add_child(col)
	col.add_child(PIStyle.label("☀  СОЛНЦЕ" if t == 0 else "☾  ЛУНА", PIStyle.H1, true))
	var names := PackedStringArray()
	for i in _v.players.size():
		if int(int(_v.roles[i]) / 2) == t:
			names.append(str(_v.players[i].name) + (" · дух" if int(_v.roles[i]) % 2 == 1 else ""))
	var names_label := PIStyle.label(" · ".join(names), PIStyle.CAP)
	names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(names_label)
	for i in 8:
		var data: Dictionary = _v.rows[t][i] if i < _v.rows[t].size() else {}
		var text := str(i + 1) + ("  ◉  " if PIData.EYES[t].has(i) else "      ")
		if not data.is_empty():
			if data.wrong and not str(data.text).is_empty():
				data = data.duplicate()
				data.text = str(data.text).left(-1) + str(data.text).right(1) + "̶"
			text += ("→ " if data.kind == "guess" else "") + str(data.text) + str(data.get("pending", "")) + ("." if data.complete else "") + ("  ✕" if data.wrong else "")
		else:
			text += "—"
		var row := PIStyle.button(text, PIStyle.BODY)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 44
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if bool(data.get("wrong", false)):
			row.add_theme_color_override("font_color", Color("c96e63"))
		var eye: bool = _v.phase == "eye" and _v.can_act and data.get("kind", "") == "clue" and not data.get("complete", true)
		row.disabled = not eye and not data.has("question")
		if eye:
			row.pressed.connect(func(): _send("eye", [t, i]))
		elif data.has("question"):
			row.pressed.connect(func(): _question_popup(int(data.question)))
		col.add_child(row)

func _note(col: Control, text: String) -> void:
	var l := PIStyle.label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)

func _button(col: Control, text: String, kind: String, arg = null, primary: bool = false) -> Button:
	var b := PIStyle.primary(text) if primary else PIStyle.button(text)
	b.pressed.connect(func(): _send(kind, arg))
	col.add_child(b)
	return b

func _send(kind: String, arg = null) -> void:
	var payload = arg.duplicate(true) if arg is Array or arg is Dictionary else arg
	_selected.clear()
	Net.send_action(kind, payload)

func _controls(col: Control) -> void:
	var phase: String = _v.phase
	if int(_v.object_card) >= 0:
		var obj := TextureRect.new()
		obj.texture = PIData.card("o", int(_v.object_card))
		obj.custom_minimum_size = Vector2(180, 250)
		obj.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		obj.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(obj)
		obj.mouse_entered.connect(func(): _show_card("o", int(_v.object_card)))
		obj.mouse_exited.connect(_hide_preview)
		_note(col, "Тайный предмет: № %d" % (int(_v.object_slot) + 1) if _v.object_slot >= 0 else "Согласуйте с другим духом номер слова.")
	if phase == "game_over":
		_note(col, "Оба мира молчат. Никто не угадал предмет." if _v.winner < 0 else "Победа команды «%s»!" % ["Солнце", "Луна"][int(_v.winner)])
		if Net.is_host():
			var again := PIStyle.primary("Новый сеанс")
			again.pressed.connect(Net.end_game)
			col.add_child(again)
		return
	if not _v.can_act:
		_note(col, "Ждём: " + str(_v.players[int(_v.actor)].name))
		return
	match phase:
		"object":
			_note(col, "Оба духа должны выбрать одинаковый номер.")
			var row := PIStyle.hbox(4)
			col.add_child(row)
			for i in 6:
				var b := _button(row, str(i + 1), "object", i)
				if int(_v.votes[int(int(_v.role) / 2)]) == i:
					b.theme_type_variation = "PrimaryButton"
		"eye":
			_note(col, "Око: выберите строку любой незаконченной подсказки, чтобы открыть ещё букву.")
			_button(col, "Пропустить око", "eye_skip")
		"turn":
			_note(col, "Выберите 2 вопроса для духа или попробуйте назвать предмет.")
			var ask := _button(col, "Передать два вопроса", "ask", _selected, true)
			ask.disabled = _selected.size() != 2
			_questions(col)
			_button(col, "Угадать предмет", "guess_begin")
			if not _v.refreshed[int(_v.team)]:
				var refresh := PIStyle.button("Заменить 7 вопросов · один раз", PIStyle.CAP)
				refresh.pressed.connect(func(): LeaveGuard.ask(refresh, "Заменить вопросы?", "Вся рука уйдёт в открытый сброс.", "Заменить", func(): _send("refresh")))
				col.add_child(refresh)
		"question":
			_note(col, "На какой вопрос ответите? Другой откроется всем.")
			for q in _v.offered:
				_question_button(col, int(q), func(): _send("question", int(q)))
		"clue":
			var last: Dictionary = _v.rows[int(_v.team)].back()
			_note(col, PIData.question(int(last.question)))
			_note(col, "Введите ответ целиком. Медиумы увидят его по одной букве. Только буквы и пробелы, без однокоренных слов.")
			_entry(col, "Начать писать", "clue", 48)
		"writing":
			_note(col, "Дух пишет… Нажмите, когда поняли подсказку.")
			var stop := _button(col, "Тишина!", "silence", null, true)
			stop.disabled = str(_v.rows[int(_v.team)].back().text).is_empty()
		"guess":
			_note(col, "Введите следующую букву. Когда слово готово — поставьте точку.")
			_entry(col, "Написать букву", "letter", 1)
			_button(col, "Поставить точку · слово готово", "letter", ".")
		"judge":
			var last: Dictionary = _v.rows[int(_v.team)].back()
			_note(col, "Это весь загаданный предмет?" if last.pending == "." else "Буква «%s» верная?" % last.pending)
			_button(col, "Верно · стук", "judge", true, true)
			_button(col, "Неверно · конец хода", "judge", false)

func _entry(col: Control, text: String, kind: String, limit: int) -> void:
	var input := LineEdit.new()
	input.max_length = limit
	input.placeholder_text = "Ответ" if limit > 1 else "Буква или пробел"
	col.add_child(input)
	var error := PIStyle.label("", PIStyle.CAP)
	col.add_child(error)
	var send := PIStyle.primary(text)
	send.pressed.connect(func():
		var valid := RegEx.new()
		valid.compile("^[А-Яа-яЁёA-Za-z ]+$")
		if valid.search(input.text) == null or input.text.strip_edges().is_empty() and limit > 1:
			error.text = "Используйте только буквы и пробелы."
			return
		_send(kind, input.text))
	col.add_child(send)
	input.text_submitted.connect(func(_text): send.pressed.emit())

func _questions(col: Control) -> void:
	for q in _v.hand:
		var b := _question_button(col, int(q), func():
			if _selected.has(q):
				_selected.erase(q)
			elif _selected.size() < 2:
				_selected.append(q)
			_changed(_v))
		if _selected.has(q):
			b.theme_type_variation = "PrimaryButton"

func _question_button(col: Control, q: int, callback: Callable) -> Button:
	var b := PIStyle.button(PIData.question(q), PIStyle.CAP)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.y = 56
	b.pressed.connect(callback)
	b.mouse_entered.connect(func(): _show_card("q", q))
	b.mouse_exited.connect(_hide_preview)
	col.add_child(b)
	return b

func _show_card(kind: String, id: int) -> void:
	_hide_preview()
	var image := TextureRect.new()
	image.texture = PIData.card(kind, id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.position = Vector2(maxf(24, size.x - 720), 96)
	image.size = Vector2(320, minf(size.y - 120, 510))
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.z_index = 70
	add_child(image)
	_preview = image
func _hide_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
func _question_popup(id: int) -> void:
	var popup := AcceptDialog.new()
	popup.title = "Выбранный вопрос"
	popup.dialog_text = PIData.question(id)
	popup.confirmed.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(540, 180))
func _discard() -> void:
	var popup := AcceptDialog.new()
	popup.title = "Открытый сброс"
	var scroll := ScrollContainer.new()
	popup.add_child(scroll)
	var list := PIStyle.vbox(8)
	list.custom_minimum_size.x = 500
	scroll.add_child(list)
	for q in _v.discard:
		_question_button(list, int(q), func(): _question_popup(int(q)))
	popup.confirmed.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(560, 500))

