extends Control
## Лобби и стол Green Team Wins. Запуск из хаба.
## Вид — GTWStyle (пати-викторина, docs/styleboard_green_team_wins_party.png): слева крупная карта и её
## русский перевод (при наведении — ещё крупнее), под ней игроки цветом команды; справа — варианты
## ответа и одна зелёная главная кнопка, после ответов — группы ответов с очками.
## Логика — на хосте (GTWRules); стол показывает view и шлёт действия через Net.

const ART := "res://games/green_team_wins/art/"
const Rules := preload("res://games/green_team_wins/logic/gtw_rules.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const QUESTIONS := 15
const RULES_TEXT := """[b]Цель.[/b] Пятнадцать вопросов без правильных ответов. Отвечайте так, как, по-вашему, ответит большинство, — и окажетесь в зелёной команде.

[b]Ответ.[/b] Все отвечают одновременно и тайно: выбирают вариант на карте или пишут свой ответ, если на карте пропуск.

[b]Очки.[/b] Кто ответил как самый популярный ответ (минимум два голоса), становится зелёным. Попасть в зелёную команду — 1 очко, удержаться в ней — 2. Если популярных ответов несколько поровну, зелёными остаются только те, кто уже был зелёным и дал один из них.

[b]Свои ответы.[/b] После раскрытия хост объединяет одинаковые по смыслу ответы: нажмите один ответ, затем другой.

[b]Победа.[/b] После пятнадцатого вопроса побеждает тот, у кого больше всего очков."""

var screen: Control
var top: TopBar
var translations: Dictionary = {}
var state: Dictionary = {}
var option := ""
var merge_seat := -1
var draft := ""
var card_box: HBoxContainer
var card_image: TextureRect
var card_id := ""
var players_row: HFlowContainer
var right: VBoxContainer
var edit: LineEdit
var preview: Control


class Backdrop:
	extends Control
	func _draw() -> void:
		GTWStyle.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _ready() -> void:
	var content: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://games/green_team_wins/logic/translations.json"))
	if content is Dictionary:
		translations = content
	Net.lobby_changed.connect(_lobby_changed)
	Net.game_started.connect(_table)
	Net.game_ended.connect(_lobby)
	Net.state_changed.connect(_draw_state)
	Net.session_closed.connect(_menu)
	Net.party_game_changed.connect(_party_changed)
	Prefs.changed.connect(_refresh)
	_refresh()


func _party_changed(id: String) -> void:
	if id != "green_team_wins":
		get_tree().change_scene_to_file("res://hub/hub.tscn")


func _refresh() -> void:
	if Net.in_game:
		_table()
	elif Net.in_session():
		_lobby()
	else:
		_menu()


func _lobby_changed() -> void:
	if not Net.in_game and Net.party_game == "green_team_wins":
		_lobby()


func _base() -> void:
	_close_preview()
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = GTWStyle.make_theme()
	var bg := Backdrop.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _button(caption: String, fs: int = GTWStyle.BODY, kind: String = "secondary") -> Button:
	var b := Button.new()
	b.text = caption
	GTWStyle.style_button(b, kind, fs)
	b.custom_minimum_size.y = 44
	return b


func _bar_button(caption: String, fs: int = 14) -> Button:
	return _button(caption, fs, "quiet")


func _room_button(caption: String, fs: int = GTWStyle.BODY) -> Button:
	return _button(caption, fs)


func _add(n: Node, caption: String, callback: Callable, kind: String = "secondary") -> Button:
	var b := _button(caption, GTWStyle.BODY, kind)
	n.add_child(b)
	b.pressed.connect(callback)
	return b


func _label(n: Node, caption: String, fs: int = GTWStyle.BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	var l := GTWStyle.label(caption, fs, kind, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(l)
	return l


func _room_label(caption: String, font_size: int) -> Label:
	return GTWStyle.label(caption, font_size)


func _panel(pad: int = 16, fill := "panel") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", GTWStyle.panel(pad, fill))
	return p


## Фишка игрока цветом команды: зелёная / оранжевая.
func _chip(text: String, team: String, size: int = 15) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = GTWStyle.c(team)
	box.border_color = GTWStyle.c("outline")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", box)
	var ink := "green_ink" if team == "green" else ("orange_ink" if team == "orange" else "ink")
	chip.add_child(GTWStyle.label(text, size, "bold", ink))
	return chip


# --- Меню и лобби ------------------------------------------------------------

func _menu(_reason: String = "") -> void:
	_base()
	var center := CenterContainer.new()
	screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 460
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	col.add_child(GTWStyle.heading("Green Team Wins", 40))
	_label(col, "Отвечай как большинство — будь в зелёной команде", GTWStyle.BODY, "regular", "muted")
	col.add_child(RoomPanel.make("green_team_wins", _room_button, _room_label))
	_add(col, "Проверка на одном компьютере", func() -> void:
		Net.host_offline("green_team_wins")
		Net.set_bots(2))
	_add(col, "В хаб", _leave, "quiet")


func _leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://hub/hub.tscn")


func _lobby() -> void:
	_base()
	var margin := MarginContainer.new()
	screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	page.add_child(GTWStyle.heading("Green Team Wins", 40))
	_label(page, "Лобби · 3–12 игроков · 15 вопросов", GTWStyle.BODY, "regular", "muted")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var members: Array = Net.lobby_view.get("members", [])
	var host := Net.is_host()
	var left := _panel(18)
	left.custom_minimum_size.x = 460
	body.add_child(left)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 8)
	left.add_child(lc)
	lc.add_child(GTWStyle.heading("Игроки · %d из 12" % members.size(), 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	lc.add_child(grid)
	for member: Dictionary in members:
		grid.add_child(PlayerTag.make(member, members, GTWStyle.BODY, GTWStyle.c("ink")))
	if host:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		lc.add_child(row)
		if Net.mode == "offline":
			_add(row, "− Игрок", func() -> void: Net.set_bots(Net.bots - 1)).disabled = members.size() <= 3
			_add(row, "+ Игрок", func() -> void: Net.set_bots(Net.bots + 1)).disabled = members.size() >= 12
		else:
			_add(row, "Пригласить друзей", Net.invite_friends)
	var right_panel := _panel(18)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 12)
	right_panel.add_child(rc)
	rc.add_child(GTWStyle.heading("Как играть", 22))
	for line in ["Все отвечают на вопрос тайно и одновременно.", "Ответили как большинство — вы в зелёной команде.", "Попасть в зелёные — 1 очко, удержаться — 2.", "Свои ответы хост объединяет по смыслу."]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := _chip("✓", "green", 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var l := _label(row, line, GTWStyle.BODY)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rc.add_child(row)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	page.add_child(foot)
	var back := _button("В хаб", GTWStyle.BODY, "quiet")
	back.custom_minimum_size.x = 460
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.add_child(back)
	LeaveGuard.wire(back, "Выйти из лобби?", "Вы вернётесь в хаб.", _leave)
	var error := GTWStyle.label("", GTWStyle.CAP, "regular", "orange")
	if host:
		var start := _button("Начать игру", 22, "primary")
		start.custom_minimum_size = Vector2(320, 60)
		start.disabled = members.size() < 3
		start.pressed.connect(func() -> void: error.text = Net.start_game())
		foot.add_child(start)
	else:
		var wait := GTWStyle.label("Ждём, когда хост начнёт игру", GTWStyle.BODY, "bold", "muted")
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(wait)
	foot.add_child(error)


# --- Стол ----------------------------------------------------------------------

func _table() -> void:
	_base()
	card_id = ""
	top = TopBar.make(screen, "Green Team Wins", _bar_button, null, GTWStyle.c("ink"), GTWStyle.font("title"))
	top.info.add_theme_font_override("font", GTWStyle.font("title"))
	_add(top.actions, "Правила", _rules, "quiet")
	_add(top.actions, "Настройки", _settings, "quiet")
	_add(top.actions, "Тема", func() -> void:
		Prefs.theme_mode = "light" if Prefs.dark_theme() else "dark"
		Prefs.save()
		Prefs.changed.emit(), "quiet")
	var back := _button("Выйти", 14, "quiet")
	top.actions.add_child(back)
	LeaveGuard.wire(back, "Выйти из игры?", "Вы вернётесь в хаб.", _leave)
	var margin := MarginContainer.new()
	screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = TopBar.HEIGHT + 8.0
	margin.offset_left = 24
	margin.offset_right = -24
	margin.offset_bottom = -8
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	margin.add_child(main)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 600
	main.add_child(left)
	var card_panel := _panel(20)
	card_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(card_panel)
	card_box = HBoxContainer.new()
	card_box.add_theme_constant_override("separation", 20)
	card_panel.add_child(card_box)
	players_row = HFlowContainer.new()
	players_row.add_theme_constant_override("h_separation", 8)
	players_row.add_theme_constant_override("v_separation", 8)
	players_row.custom_minimum_size.y = 72
	left.add_child(players_row)
	var right_panel := _panel(20)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right_panel)
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right_panel.add_child(right)
	if not Net.view.is_empty():
		_draw_state(Net.view)


func _popup(title: String, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.03, 0.1, 0.12, 0.7)
	overlay.z_index = 110
	overlay.add_to_group("pause_allowed")
	screen.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(24)
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 160
	panel.offset_right = -160
	panel.offset_top = 64
	panel.offset_bottom = -40
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(GTWStyle.heading(title, GTWStyle.H1))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", GTWStyle.font("regular"))
	body.add_theme_font_override("bold_font", GTWStyle.font("bold"))
	body.add_theme_font_size_override("normal_font_size", GTWStyle.BODY)
	body.add_theme_font_size_override("bold_font_size", GTWStyle.BODY)
	body.add_theme_color_override("default_color", GTWStyle.c("ink"))
	col.add_child(body)
	var close := _button("Понятно", GTWStyle.BODY, "primary")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 200
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)


func _rules() -> void:
	_popup("Правила Green Team Wins", RULES_TEXT)


func _settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func() -> PanelContainer: return _panel(24)
	settings.make_title = func(text: String) -> Control: return GTWStyle.heading(text, GTWStyle.H1)
	settings.make_primary = func(text: String) -> Button: return _button(text, GTWStyle.BODY, "primary")
	settings.ink = GTWStyle.c("ink")
	add_child(settings)


func _send(kind: String, payload: Dictionary = {}) -> void:
	payload["round"] = state.round
	Net.send_action(kind, payload)


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Перевод карты: вопрос и список вариантов «1. …».
func _translation() -> Dictionary:
	var text := str(translations.get(state.card, ""))
	var question := ""
	var options: Array[String] = []
	for line in text.split("\n", false):
		var stripped := line.strip_edges()
		if stripped.length() > 2 and stripped[0].is_valid_int() and stripped[1] == ".":
			options.append(stripped.substr(2).strip_edges())
		elif question.is_empty():
			question = stripped
		else:
			question += " " + stripped
	if question.is_empty() and not options.is_empty():
		question = "Что выберете?"  # карты «это или то»: на карте только два варианта
	return {"question": question, "options": options}


func _option_count() -> int:
	return 3 if str(state.card).begins_with("three") else (2 if str(state.card).begins_with("two") else 0)


## Текст ответа: для вариантов — «Яблоко», для своих — как написал игрок.
func _answer_text(raw: String) -> String:
	var options: Array = _translation().options
	if raw.is_valid_int() and int(raw) >= 1 and int(raw) <= options.size():
		return options[int(raw) - 1]
	return raw


func _draw_state(next: Dictionary) -> void:
	if is_instance_valid(edit) and edit.is_inside_tree():
		draft = edit.text
	if next.get("round", -2) != state.get("round", -1) or next.get("seat", -2) != state.get("seat", -1):
		option = ""
		merge_seat = -1
		draft = ""
	state = next
	if not is_instance_valid(right) or not right.is_inside_tree() or not state.has("card"):
		return
	top.info.text = "Итоги" if state.phase == "end" else "Вопрос %d из %d" % [state.round + 1, QUESTIONS]
	if card_id != str(state.card):
		_build_card()
	_build_players()
	_clear(right)
	match state.phase:
		"answer":
			_answer_ui()
		"group", "result":
			_groups_ui()
		"end":
			_end_ui()


func _build_card() -> void:
	card_id = str(state.card)
	_close_preview()
	_clear(card_box)
	card_image = TextureRect.new()
	card_image.texture = load(ART + card_id + ".webp")
	card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_image.custom_minimum_size = Vector2(300, 418)
	card_image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://hub/card_corners.gdshader")
	card_image.material = mat
	card_image.mouse_filter = Control.MOUSE_FILTER_STOP
	card_image.mouse_entered.connect(_show_preview)
	card_image.mouse_exited.connect(_close_preview)
	card_box.add_child(card_image)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 10)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_child(text)
	var tr := _translation()
	var lines: Array[Label] = [_label(text, "ПО-РУССКИ", GTWStyle.CAP, "bold", "muted"),
		_label(text, tr.question if not tr.question.is_empty() else "Перевод этой карты ещё не добавлен.", 22, "bold")]
	for i in tr.options.size():
		lines.append(_label(text, "%d. %s" % [i + 1, tr.options[i]], GTWStyle.BODY, "regular", "muted"))
	if _option_count() == 0:
		lines.append(_label(text, "Впишите своё слово вместо пропуска", GTWStyle.CAP, "regular", "muted"))
	lines.append(_label(text, "Ответьте как большинство — и будете в зелёной команде", GTWStyle.CAP, "regular", "muted"))
	for line in lines:
		line.custom_minimum_size.x = 220


func _build_players() -> void:
	_clear(players_row)
	for s in state.names.size():
		var mark := ""
		if state.phase == "answer":
			mark = "  ✓" if s in state.answered else "  …"
		elif state.gain.size() > s and int(state.gain[s]) > 0 and state.phase != "group":
			mark = "  +%d" % state.gain[s]
		var me := " · вы" if s == state.seat else ""
		players_row.add_child(_chip("%s%s · %d%s" % [state.names[s], me, state.scores[s], mark], "green" if state.green[s] else "orange"))


func _answer_ui() -> void:
	if state.get("spectator", false):
		right.add_child(GTWStyle.heading("Игроки отвечают", GTWStyle.H1))
		_label(right, "Ответили %d из %d" % [state.answered.size(), state.names.size()], GTWStyle.BODY, "regular", "muted")
		return
	if state.get("hotseat", false) and state.seat < 0:
		right.add_child(GTWStyle.heading("Кто отвечает?", GTWStyle.H1))
		_label(right, "Передайте компьютер игроку и нажмите его имя — остальные не подглядывают.", GTWStyle.CAP, "regular", "muted")
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		right.add_child(flow)
		for s in state.names.size():
			if not s in state.answered:
				_add(flow, state.names[s], func() -> void: _send("gtw_seat", {"seat": s}))
		return
	if state.seat in state.answered:
		right.add_child(GTWStyle.heading("Ответ принят", GTWStyle.H1))
		_label(right, "Ждём остальных: ответили %d из %d. Ответы откроются у всех сразу." % [state.answered.size(), state.names.size()], GTWStyle.BODY, "regular", "muted")
		return
	right.add_child(GTWStyle.heading("Ваш ответ", GTWStyle.H1))
	_label(right, "Ответили %d из %d · выбор тайный, откроется у всех сразу" % [state.answered.size(), state.names.size()], GTWStyle.CAP, "regular", "muted")
	var go := _button("", 22, "primary")
	go.custom_minimum_size.y = 60
	if _option_count() == 0:
		edit = LineEdit.new()
		edit.text = draft
		edit.max_length = 80
		edit.placeholder_text = "Ваше слово"
		edit.custom_minimum_size.y = 64
		edit.add_theme_font_override("font", GTWStyle.font("bold"))
		edit.add_theme_font_size_override("font_size", 24)
		var field := GTWStyle.panel(14)
		field.shadow_offset = Vector2.ZERO
		edit.add_theme_stylebox_override("normal", field)
		var focus := GTWStyle.panel(14)
		focus.border_color = GTWStyle.c("green")
		focus.set_border_width_all(4)
		focus.shadow_offset = Vector2.ZERO
		edit.add_theme_stylebox_override("focus", focus)
		right.add_child(edit)
		edit.text_changed.connect(func(s: String) -> void:
			draft = s
			_update_go(go))
		edit.text_submitted.connect(_submit)
		edit.call_deferred("grab_focus")
	else:
		var options: Array = _translation().options
		for i in _option_count():
			var value := str(i + 1)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			right.add_child(row)
			var num := PanelContainer.new()
			var nb := StyleBoxFlat.new()
			nb.bg_color = GTWStyle.c("bg")
			nb.border_color = GTWStyle.c("outline")
			nb.set_border_width_all(3)
			nb.set_corner_radius_all(22)
			num.add_theme_stylebox_override("panel", nb)
			num.custom_minimum_size = Vector2(44, 44)
			num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var nl := GTWStyle.label(value, 22, "title")
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num.add_child(nl)
			row.add_child(num)
			var b := _button("  " + (options[i] if i < options.size() else "Вариант " + value), 22, "option")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 72
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.toggle_mode = true
			b.button_pressed = option == value
			b.pressed.connect(func() -> void:
				option = value
				_draw_state(state))
			row.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(go)
	go.pressed.connect(func() -> void: _submit(draft if _option_count() == 0 else option))
	_update_go(go)


func _update_go(go: Button) -> void:
	var value := draft.strip_edges() if _option_count() == 0 else option
	go.disabled = value.is_empty()
	if value.is_empty():
		go.text = "Впишите слово" if _option_count() == 0 else "Выберите вариант"
	else:
		go.text = "Ответить: " + (_answer_text(value) if _option_count() > 0 else value)
	go.clip_text = true


func _submit(value: String) -> void:
	if not value.strip_edges().is_empty():
		_send("answer", {"answer": value.strip_edges()})


## Группы ответов (после раскрытия): самый популярный — зелёный. В фазе «group» хост объединяет
## похожие свои ответы — нажатием на одну группу, затем на другую.
func _groups_ui() -> void:
	var grouping: bool = state.phase == "group"
	var host := Net.is_host()
	right.add_child(GTWStyle.heading("Объедините похожие ответы" if grouping and host else "Ответы открыты", GTWStyle.H1))
	var groups := {}  # ключ группы → места
	for s in state.answers:
		var key := str(state.groups.get(s, state.answers[s]))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(int(s))
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return groups[a].size() > groups[b].size())
	var hint := ""
	if grouping:
		hint = "Нажмите ответ, затем похожий на него — они объединятся" if host else "Хост объединяет одинаковые по смыслу ответы"
		if host and merge_seat >= 0:
			hint = "Теперь нажмите ответ, с которым объединить"
	else:
		var winners: Array = keys.filter(func(k: String) -> bool: return groups[k].any(func(s: int) -> bool: return int(state.gain[s]) > 0))
		hint = "Больше всего — «%s»: эти игроки зелёные" % _group_title(groups[winners[0]]) if not winners.is_empty() else "Нет ответа минимум с двумя голосами — зелёных нет"
	_label(right, hint, GTWStyle.CAP, "regular", "muted")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for key: String in keys:
		var seats: Array = groups[key]
		var won := not grouping and seats.any(func(s: int) -> bool: return int(state.gain[s]) > 0)
		var picked := grouping and merge_seat >= 0 and merge_seat in seats
		var card := Button.new() if grouping and host else null
		var box := GTWStyle.panel(14, "inset")
		box.shadow_offset = Vector2(0, 3) if won or picked else Vector2.ZERO
		if won:
			box.bg_color = Color(GTWStyle.c("green"), 0.35)
		if picked:
			box.border_color = GTWStyle.c("green")
			box.set_border_width_all(4)
		var holder: Control
		if card != null:
			card.focus_mode = Control.FOCUS_NONE
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for st in ["normal", "hover", "pressed"]:
				var b := box.duplicate()
				if st == "hover":
					b.bg_color = b.bg_color.lightened(0.06)
				card.add_theme_stylebox_override(st, b)
			card.pressed.connect(_merge.bind(seats[0]))
			holder = card
		else:
			holder = PanelContainer.new()
			holder.add_theme_stylebox_override("panel", box)
		list.add_child(holder)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := GTWStyle.label(_group_title(seats), 22, "bold")
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var votes := seats.size()
		head.add_child(GTWStyle.label("%d голос%s" % [votes, "" if votes % 10 == 1 and votes != 11 else ("а" if votes % 10 in [2, 3, 4] and not votes in [12, 13, 14] else "ов")], 16, "bold", "muted"))
		col.add_child(head)
		var who := HFlowContainer.new()
		who.mouse_filter = Control.MOUSE_FILTER_IGNORE
		who.add_theme_constant_override("h_separation", 8)
		who.add_theme_constant_override("v_separation", 6)
		col.add_child(who)
		for s: int in seats:
			var raw := str(state.answers[s])
			var text: String = state.names[s]
			if _option_count() == 0 and Rules.answer_key(raw) != Rules.answer_key(_group_title(seats)):
				text += " «%s»" % raw
			if not grouping and int(state.gain[s]) > 0:
				text += " +%d" % state.gain[s]
			var chip := _chip(text, "green" if (not grouping and state.green[s]) else "orange", 15)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			who.add_child(chip)
		if card != null:
			card.custom_minimum_size.y = 96
			var m := MarginContainer.new()
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
				m.add_theme_constant_override(side, 14)
			m.add_child(col)
			card.add_child(m)
		else:
			holder.add_child(col)
	if grouping and host:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		right.add_child(row)
		_add(row, "Сбросить", func() -> void: _send("reset_groups"))
		var go := _add(row, "Подсчитать очки", func() -> void: _send("score"), "primary")
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.custom_minimum_size.y = 60
	elif state.phase == "result" and host:
		var go := _add(right, "Подвести итоги" if state.round == QUESTIONS - 1 else "Следующий вопрос", func() -> void: _send("next"), "primary")
		go.custom_minimum_size.y = 60
	elif state.phase == "result":
		_label(right, "Следующий вопрос откроет хост", GTWStyle.CAP, "regular", "muted")


## Название группы: вариант карты или самый частый из своих ответов.
func _group_title(seats: Array) -> String:
	var counts := {}
	for s: int in seats:
		var t := _answer_text(str(state.answers[s]))
		counts[t] = int(counts.get(t, 0)) + 1
	var best := ""
	for t: String in counts:
		if best.is_empty() or counts[t] > counts[best]:
			best = t
	return best


func _merge(seat: int) -> void:
	if merge_seat < 0:
		merge_seat = seat
		_draw_state(state)
	else:
		var from := merge_seat
		merge_seat = -1
		if state.groups[from] != state.groups[seat]:
			_send("merge", {"from": from, "into": seat})
		else:
			_draw_state(state)


func _end_ui() -> void:
	var winners: Array[String] = []
	for s: int in state.results:
		winners.append(state.names[s])
	right.add_child(GTWStyle.heading("Победа!", 32))
	_label(right, ", ".join(winners), 26, "bold")
	right.add_child(HSeparator.new())
	var order: Array = range(state.names.size())
	order.sort_custom(func(a: int, b: int) -> bool: return state.scores[a] > state.scores[b])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s: int in order:
		var row := HBoxContainer.new()
		var n := GTWStyle.label(state.names[s], GTWStyle.BODY, "bold" if s in state.results else "regular")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(GTWStyle.label("%d очк." % state.scores[s], GTWStyle.BODY, "bold", "ink" if s in state.results else "muted"))
		list.add_child(row)
	if Net.is_host():
		var go := _add(right, "В лобби", Net.end_game, "primary")
		go.custom_minimum_size.y = 60


## Крупный просмотр карты при наведении: карта ~500 px и перевод рядом (поверх стола, не мешает ответу —
## окно ставится левее правой панели и исчезает, как только курсор уходит с карты).
func _show_preview(_anchor: Control = null) -> void:
	_close_preview()
	var overlay := _panel(18)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(row)
	var image := TextureRect.new()
	image.texture = card_image.texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(380, 530)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://hub/card_corners.gdshader")
	image.material = mat
	row.add_child(image)
	var text := VBoxContainer.new()
	text.custom_minimum_size.x = 300
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var tr := _translation()
	# у меток с переносом обязательно ширина: без неё перенос «по букве» раздувает окно в высоту
	var lines: Array[Label] = [_label(text, "ПЕРЕВОД", GTWStyle.CAP, "bold", "muted"), _label(text, tr.question, 24, "bold")]
	for i in tr.options.size():
		lines.append(_label(text, "%d. %s" % [i + 1, tr.options[i]], 20))
	for line in lines:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.custom_minimum_size.x = 300
	overlay.z_index = 92
	screen.add_child(overlay)
	overlay.position = Vector2(48, TopBar.HEIGHT + 32)
	preview = overlay


func _close_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = null
