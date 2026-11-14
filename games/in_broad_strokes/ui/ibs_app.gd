extends Control
## Лобби и стол «В общих чертах». Запуск из хаба.
## Вид — IBSStyle (калька / синька, docs/styleboard_in_broad_strokes_tracing.png): сверху пометка от руки
## «что делать», слева планшеты, под ними инструменты художника, справа роль, слово (только художникам),
## попытки и одна главная кнопка фазы; «Сдаться» — тихая, по удержанию.
## Логика — на хосте (IBSRules); стол показывает view и шлёт действия через Net.

const Board := preload("res://games/in_broad_strokes/ui/ibs_board.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const RULES_TEXT := """[b]Команда.[/b] Все играют вместе. Один игрок — Искусствовед — угадывает слово, остальные — Художники — рисуют его по очереди на прозрачных листах.

[b]Слой.[/b] Художник видит слово и проводит на своём листе две прямые или одну кривую — только чёрным. Затем лист накладывается на прежние слои, и картинка понемногу складывается.

[b]Догадка.[/b] После каждого слоя у Искусствоведа две попытки (можно пропустить). Если ответ — другая форма слова, художник может его засчитать.

[b]Планшеты.[/b] На всю партию 25 листов. Каждый слой тратит лист; не угадали слово — сдача тратит ещё один. Игра кончается, когда листы закончились. Чем больше слов угадано, тем лучше."""

var board: Control
var tools: HBoxContainer
var side: VBoxContainer
var action_slot: VBoxContainer
var hint: Label
var screen: Control
var top: TopBar
var state: Dictionary = {}
var history: Array[String] = []  # попытки по текущему слову (видят все)
var _history_key := ""
var _last_score := 0
var _result_correct := false
var _guess_text := ""


class Backdrop:
	extends Control
	func _draw() -> void:
		IBSStyle.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _ready() -> void:
	Net.lobby_changed.connect(_lobby_changed)
	Net.game_started.connect(_table)
	Net.game_ended.connect(_lobby)
	Net.state_changed.connect(_draw_state)
	Net.session_closed.connect(_menu)
	Net.party_game_changed.connect(_party_changed)
	Prefs.changed.connect(_refresh)
	_refresh()


func _party_changed(id: String) -> void:
	if id != "in_broad_strokes":
		get_tree().change_scene_to_file("res://hub/hub.tscn")


func _refresh() -> void:
	if Net.in_game:
		_table()
	elif Net.in_session():
		_lobby()
	else:
		_menu()


func _lobby_changed() -> void:
	if not Net.in_game and Net.party_game == "in_broad_strokes":
		_lobby()


func _base() -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = IBSStyle.make_theme()
	var bg := Backdrop.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _button(caption: String, fs: int = IBSStyle.BODY, kind: String = "secondary") -> Button:
	var b := Button.new()
	b.text = caption
	IBSStyle.style_button(b, kind, fs)
	b.custom_minimum_size.y = 40
	return b


func _bar_button(caption: String, fs: int = 14) -> Button:
	return _button(caption, fs, "quiet")


func _room_button(caption: String, fs: int = IBSStyle.BODY) -> Button:
	return _button(caption, fs)


func _add(n: Node, caption: String, callback: Callable, kind: String = "secondary") -> Button:
	var b := _button(caption, IBSStyle.BODY, kind)
	n.add_child(b)
	b.pressed.connect(callback)
	return b


func _label(n: Node, caption: String, fs: int = IBSStyle.BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	var l := IBSStyle.label(caption, fs, kind, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(l)
	return l


func _room_label(caption: String, font_size: int) -> Label:
	return IBSStyle.label(caption, font_size)


func _panel(pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", IBSStyle.panel(pad))
	return p


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
	col.add_child(IBSStyle.heading("В общих чертах", 48))
	_label(col, "Рисуем слово по слою на прозрачных листах", IBSStyle.BODY, "regular", "muted")
	col.add_child(RoomPanel.make("in_broad_strokes", _room_button, _room_label))
	_add(col, "Проверка на одном компьютере", func() -> void:
		Net.host_offline("in_broad_strokes")
		Net.set_bots(1))
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
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)
	page.add_child(IBSStyle.heading("В общих чертах", 48))
	_label(page, "Лобби · 2–8 игроков · кооператив, 25 прозрачных листов", IBSStyle.BODY, "regular", "muted")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var members: Array = Net.lobby_view.get("members", [])
	var host := Net.is_host()
	var left := _panel(18)
	left.custom_minimum_size.x = 420
	body.add_child(left)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 8)
	left.add_child(lc)
	lc.add_child(IBSStyle.heading("Игроки · %d из 8" % members.size(), 26))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	lc.add_child(grid)
	for member: Dictionary in members:
		grid.add_child(PlayerTag.make(member, members, IBSStyle.BODY, IBSStyle.c("ink")))
	if host:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		lc.add_child(row)
		if Net.mode == "offline":
			_add(row, "− Игрок", func() -> void: Net.set_bots(Net.bots - 1)).disabled = members.size() <= 2
			_add(row, "+ Игрок", func() -> void: Net.set_bots(Net.bots + 1)).disabled = members.size() >= 8
		else:
			_add(row, "Пригласить друзей", Net.invite_friends)
	var right := _panel(18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 10)
	right.add_child(rc)
	rc.add_child(IBSStyle.heading("Словарь", 26))
	var dict_row := HBoxContainer.new()
	dict_row.add_theme_constant_override("separation", 10)
	rc.add_child(dict_row)
	var current := str(Net.settings.get("ibs_words", "simple"))
	for option: Array in [["simple", "Простые слова", "200 слов, которые легко нарисовать"], ["shared", "Общий словарь", "1000 слов — сложнее и неожиданнее"]]:
		var key: String = option[0]
		var card := _dict_card(option[1], option[2], current == key, not host)
		card.pressed.connect(func() -> void: Net.set_setting("ibs_words", key))
		dict_row.add_child(card)
	rc.add_child(HSeparator.new())
	rc.add_child(IBSStyle.heading("Как играть", 26))
	for line in ["Искусствовед не видит слово — его видят художники.", "Художник проводит на листе две прямые или одну кривую.", "Листы накладываются друг на друга — картинка растёт.", "После каждого слоя — две попытки угадать."]:
		_label(rc, "— " + line, IBSStyle.BODY)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	page.add_child(foot)
	var back := _button("В хаб", IBSStyle.BODY, "quiet")
	back.custom_minimum_size.x = 420
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.add_child(back)
	LeaveGuard.wire(back, "Выйти из лобби?", "Вы вернётесь в хаб.", _leave)
	var error := IBSStyle.label("", IBSStyle.CAP, "regular", "red")
	if host:
		var start := _button("Начать игру", 20, "primary")
		start.custom_minimum_size = Vector2(320, 56)
		start.disabled = members.size() < 2
		start.pressed.connect(func() -> void: error.text = Net.start_game())
		foot.add_child(start)
	else:
		var wait := IBSStyle.label("Ждём, когда хост начнёт игру", IBSStyle.BODY, "bold", "muted")
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(wait)
	foot.add_child(error)


## Карточка выбора словаря: выбранная — рамка чертёжного цвета (у гостя — только просмотр).
func _dict_card(title: String, caption: String, on: bool, locked: bool) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_pressed = on
	card.disabled = locked
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, 72)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.bg_color = IBSStyle.c("bg")
		box.border_color = IBSStyle.c("panel_edge")
		box.set_border_width_all(1)
		var chosen: bool = state_name in ["pressed", "hover_pressed"] or (state_name == "disabled" and on)
		if chosen:
			box.border_color = IBSStyle.c("accent")
			box.set_border_width_all(3)
		if state_name in ["hover", "hover_pressed"]:
			box.bg_color = box.bg_color.lightened(0.05)
		card.add_theme_stylebox_override(state_name, box)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texts.offset_left = 12
	texts.offset_right = -12
	card.add_child(texts)
	texts.add_child(IBSStyle.label(("✓ " if on else "") + title, 17, "bold", "ink"))
	texts.add_child(IBSStyle.label(caption, 13, "regular", "muted"))
	return card


# --- Стол ----------------------------------------------------------------------

func _table() -> void:
	_base()
	top = TopBar.make(screen, "В общих чертах", _bar_button, null, IBSStyle.c("ink"), IBSStyle.font("title"))
	top.info.add_theme_font_override("font", IBSStyle.font("bold"))
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
	margin.offset_top = TopBar.HEIGHT + 6.0
	margin.offset_left = 24
	margin.offset_right = -24
	margin.offset_bottom = -8
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	margin.add_child(main)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(left)
	hint = IBSStyle.heading("", 26, "accent")
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.custom_minimum_size.y = 40
	left.add_child(hint)
	board = Board.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.draft_changed.connect(_on_draft)
	left.add_child(board)
	tools = HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.custom_minimum_size.y = 44
	left.add_child(tools)
	var right := _panel(18)
	right.custom_minimum_size.x = 352
	main.add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	right.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	side = VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	action_slot = VBoxContainer.new()
	action_slot.add_theme_constant_override("separation", 8)
	col.add_child(action_slot)
	if not Net.view.is_empty():
		_draw_state(Net.view)


func _popup(title: String, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.1, 0.18, 0.7)
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
	col.add_child(IBSStyle.heading(title, 34))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", IBSStyle.font("regular"))
	body.add_theme_font_override("bold_font", IBSStyle.font("bold"))
	body.add_theme_font_size_override("normal_font_size", IBSStyle.BODY)
	body.add_theme_font_size_override("bold_font_size", IBSStyle.BODY)
	body.add_theme_color_override("default_color", IBSStyle.c("ink"))
	col.add_child(body)
	var close := _button("Понятно", IBSStyle.BODY, "primary")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 200
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)


func _rules() -> void:
	_popup("Правила «В общих чертах»", RULES_TEXT)


func _settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func() -> PanelContainer: return _panel(24)
	settings.make_title = func(text: String) -> Control: return IBSStyle.heading(text, 34)
	settings.make_primary = func(text: String) -> Button: return _button(text, IBSStyle.BODY, "primary")
	settings.ink = IBSStyle.c("ink")
	add_child(settings)


func _send(kind: String, arg: Dictionary = {}) -> void:
	arg["serial"] = state.serial
	Net.send_action(kind, arg)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _name(seat: int) -> String:
	return str(state.names[seat]) if seat >= 0 and seat < state.names.size() else "?"


## Попытки по текущему слову: хост их не хранит, поэтому стол ведёт историю сам по смене view.
func _track_history() -> void:
	var round_key := "%d/%d" % [state.critic, state.artist if state.layers.is_empty() else -1]
	if state.layers.is_empty() and state.phase == "draw" and round_key != _history_key:
		history.clear()
		_history_key = round_key
	if state.phase in ["judge", "result", "guess", "draw"] and not str(state.guess).is_empty():
		var layer: int = state.layers.size()
		var entry := "Слой %d: «%s»" % [layer, state.guess]
		var known := history.any(func(h: String) -> bool: return h.begins_with(entry))
		if not known:
			history.append(entry + (" — на проверке" if state.phase == "judge" else " — мимо"))
		elif state.phase != "judge":
			for i in history.size():
				if history[i].begins_with(entry) and history[i].ends_with("на проверке"):
					history[i] = entry + " — мимо"


func _draw_state(next: Dictionary) -> void:
	var was_phase: String = state.get("phase", "")
	state = next
	if not is_instance_valid(board) or not board.is_inside_tree() or not state.has("layers"):
		return
	if state.phase == "result" and was_phase != "result":
		_result_correct = int(state.score) > _last_score
	if state.phase != "result":
		_last_score = int(state.score)
	_track_history()
	board.present(state)
	top.info.text = "Листов осталось %d · угадано %d" % [state.remaining, state.score]
	_update_hint()
	_update_tools()
	_update_side()
	_update_action()


func _mine() -> bool:
	return state.seat >= 0 and state.seat == state.turn


func _update_hint() -> void:
	var mine := _mine()
	var text := ""
	match state.phase:
		"draw":
			text = "Ваш ход: проведите на листе %s" % ("одну кривую" if board.curve else "две прямые") if mine else "Рисует %s — слой %d" % [_name(state.artist), state.layers.size() + 1]
		"merge":
			text = "Слои совмещаются…"
		"guess":
			text = "Ваш ход: что нарисовано? Попыток: %d" % state.attempts if mine else "%s угадывает · попыток: %d" % [_name(state.critic), state.attempts]
		"judge":
			text = "Засчитать «%s»? Это форма загаданного слова?" % state.guess if mine else "%s проверяет ответ «%s»" % [_name(state.artist), state.guess]
		"result":
			text = ("Угадано: «%s»!" if _result_correct else "Не угадали: было «%s»") % state.word
		"end":
			text = "Листы закончились · угадано слов: %d" % state.score
	if state.turn >= 0 and not mine and state.get("hotseat", false) and state.phase in ["draw", "guess", "judge"]:
		text = "Передайте ход: следующим ходит %s" % _name(state.turn)
	hint.text = text


func _update_tools() -> void:
	_clear(tools)
	var drawing: bool = _mine() and state.phase == "draw"
	tools.visible = drawing
	if not drawing:
		return
	var straight := _button("╱ ╲   Две прямые", 16, "tool")
	var curved := _button("◠   Одна кривая", 16, "tool")
	for b in [straight, curved]:
		b.toggle_mode = true
		b.custom_minimum_size.x = 200
		tools.add_child(b)
	straight.button_pressed = not board.curve
	curved.button_pressed = board.curve
	straight.pressed.connect(_set_mode.bind(false))
	curved.pressed.connect(_set_mode.bind(true))
	_add(tools, "Стереть", board.clear_draft, "quiet")


func _set_mode(curve: bool) -> void:
	board.set_curve(curve)
	_update_tools()
	_update_hint()
	board.queue_redraw()


func _on_draft() -> void:
	if is_instance_valid(action_slot) and state.has("phase"):
		_update_action()


func _update_side() -> void:
	_clear(side)
	var critic: bool = state.seat == state.critic
	var role := "зритель"
	if state.seat >= 0:
		role = "искусствовед" if critic else ("художник · рисует сейчас" if state.seat == state.artist else "художник")
	if state.seat >= 0 or not state.get("hotseat", false):
		_label(side, "ВЫ — " + role.to_upper(), IBSStyle.CAP, "bold", "muted")
	else:
		_label(side, "ИСКУССТВОВЕД — " + _name(state.critic).to_upper(), IBSStyle.CAP, "bold", "muted")
	if not str(state.word).is_empty():
		var tape := PanelContainer.new()
		var tb := StyleBoxFlat.new()
		tb.bg_color = IBSStyle.c("tape")
		tb.set_corner_radius_all(2)
		tb.set_content_margin_all(12)
		tape.add_theme_stylebox_override("panel", tb)
		tape.rotation_degrees = -1.5
		var w := IBSStyle.heading("Слово: " + str(state.word), 34)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tape.add_child(w)
		side.add_child(tape)
		if state.phase not in ["result", "end"]:
			_label(side, "Искусствовед слово не видит. Рисуйте по слою — после каждого у него две попытки.", IBSStyle.CAP, "regular", "muted")
	elif critic and state.phase not in ["result", "end"]:
		side.add_child(IBSStyle.heading("Что это?", 34))
		_label(side, "Слово видят только художники. Угадывайте после каждого слоя.", IBSStyle.CAP, "regular", "muted")
	if state.phase == "guess" and critic:
		var dots := HBoxContainer.new()
		dots.add_theme_constant_override("separation", 6)
		for i in 2:
			dots.add_child(IBSStyle.label("●" if i < state.attempts else "○", 18, "regular", "accent"))
		dots.add_child(IBSStyle.label("попыток на этот слой: %d" % state.attempts, IBSStyle.CAP, "regular", "muted"))
		side.add_child(dots)
	side.add_child(HSeparator.new())
	side.add_child(IBSStyle.heading("Попытки " + ("ваши" if critic else _name(state.critic)), 24))
	if history.is_empty():
		_label(side, "Пока не было", IBSStyle.BODY, "regular", "muted")
	for h in history:
		_label(side, h, IBSStyle.BODY, "regular", "muted")


func _update_action() -> void:
	_clear(action_slot)
	var mine := _mine()
	var phase: String = state.phase
	if state.turn >= 0 and not mine and state.get("hotseat", false) and phase in ["draw", "guess", "judge"]:
		_main("Передать ход · " + _name(state.turn), func() -> void: _send("ibs_seat", {"seat": state.turn}))
	elif mine and phase == "draw":
		var go := _main("Совместить слои", func() -> void: _send("draw", {"strokes": board.draft}))
		go.disabled = board.draft.is_empty()
		go.tooltip_text = "Сначала проведите линию" if board.draft.is_empty() else ""
	elif mine and phase == "guess":
		var field := LineEdit.new()
		field.placeholder_text = "Ваш ответ"
		field.max_length = 80
		field.text = _guess_text
		field.custom_minimum_size.y = 48
		field.add_theme_font_size_override("font_size", 20)
		action_slot.add_child(field)
		var go := _main("Угадать", func() -> void: _guess(field.text))
		go.disabled = field.text.strip_edges().is_empty()
		field.text_changed.connect(func(value: String) -> void:
			_guess_text = value
			go.disabled = value.strip_edges().is_empty())
		field.text_submitted.connect(_guess)
		field.call_deferred("grab_focus")
		_add(action_slot, "Пас — ждать следующий слой", func() -> void: _send("pass"))
	elif mine and phase == "judge":
		_main("Засчитать «%s»" % state.guess, func() -> void: _send("accept"))
		_add(action_slot, "Не то слово", func() -> void: _send("reject"))
	elif Net.is_host() and phase == "result":
		_main("Следующее слово", func() -> void: _send("next"))
	elif phase == "end":
		action_slot.add_child(IBSStyle.heading("Угадано слов: %d" % state.score, 30))
		if Net.is_host():
			_main("В лобби", Net.end_game)
	if Net.is_host() and phase in ["draw", "guess", "judge"]:
		var give := _button("Сдаться — удерживайте", 15, "danger")
		action_slot.add_child(give)
		LeaveGuard.wire(give, "Сдаться?", "Слово откроется, команда потратит дополнительный лист.", func() -> void: _send("give_up"))


func _guess(value: String) -> void:
	if value.strip_edges().is_empty():
		return
	_guess_text = ""
	_send("guess", {"word": value.strip_edges()})


func _main(caption: String, callback: Callable) -> Button:
	var b := _button(caption, 20, "primary")
	b.custom_minimum_size.y = 52
	b.clip_text = true
	b.pressed.connect(callback)
	action_slot.add_child(b)
	return b
