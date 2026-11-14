extends Control
## Лобби и стол «Первый контакт». Запуск из хаба.
## Вид — FCStyle (папирус и язык корабля, docs/styleboard_first_contact_papyrus.png): строка «что делать»
## над полем, поле 5×5 из вырезанных предметов с подписями игры, справа — бирюзовая панель знаков,
## словарь знаков землянина или клавиатура знаков инопланетянина, внизу одна главная кнопка.
## Логика партии — на хосте (FCRules в fc_rules.gd); стол показывает view и шлёт действия через Net.

const Rules := preload("res://games/first_contact/logic/fc_rules.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const LETTERS := "АБВГД"
const PHASES := {"opening": "Нулевой ход", "ask": "Учимся языку", "teach": "Ответ инопланетян", "clue": "Подсказка инопланетянина", "vote": "Тайное голосование", "result": "Результат", "end": "Итоги"}
const RULES_TEXT := """[b]Кто есть кто.[/b] Земляне учат язык инопланетян. Инопланетяне видят свои задания — нужные предметы светятся на их экране — и знают, каким знаком обозначается каждый признак.

[b]Учимся языку.[/b] Землянин в свой ход отмечает от одного до пяти предметов-примеров. Инопланетяне отвечают одним знаком — признаком, общим для этих примеров. Записывайте догадки в словарь знаков: «△ — наверное, «Большое»».

[b]Подсказка.[/b] Инопланетянин складывает из знаков подсказку к одному из своих предметов. Черта над знаком — отрицание: «не …».

[b]Голосование.[/b] Земляне тайно отмечают предмет, на который указывает подсказка. Угадавшие получают благосклонность, найденный предмет уходит инопланетянину.

[b]Конец.[/b] Инопланетянин побеждает, когда соберёт свои предметы. Среди землян выигрывает самый благосклонный, при равенстве — тот, кто лучше выучил язык."""

var screen: Control
var top: TopBar
var state: Dictionary = {}
var selected: Array[int] = []
var signs: Array[int] = []
var banner_chip: PanelContainer
var banner_text: Label
var board_area: Control
var tiles: Array = []
var ship: PanelContainer
var side: VBoxContainer
var action_slot: VBoxContainer
var preview: Control
var error: Label
## Цвета задания по инопланетянам (обычная партия — один, сложная — несколько): бирюза, фиалка, янтарь.
var faction_colors: Array[Color] = []


class Backdrop:
	extends Control
	func _draw() -> void:
		FCStyle.draw_backdrop(self, Rect2(Vector2.ZERO, size))


class ItemTile:
	extends Button
	## Клетка поля: вырезанный предмет и подпись игры. Рамки: выбранная — охра, цель инопланетянина —
	## цвет задания со свечением, пример — пунктир, найденный — затемнён с меткой, запретный — крест.
	var item := 0
	var picked := false
	var target_color := Color.TRANSPARENT
	var owned_color := Color.TRANSPARENT
	var example := false
	var forbidden := false
	var voters := ""

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for state_name in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.bg_color = FCStyle.c("panel")
		box.border_color = Color(FCStyle.c("panel_edge"), 0.45)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		box.shadow_color = FCStyle.c("shadow")
		box.shadow_size = 3
		box.shadow_offset = Vector2(0, 2)
		if is_hovered():
			box.bg_color = box.bg_color.lightened(0.04) if not FCStyle.dark() else box.bg_color.lightened(0.08)
		if target_color.a > 0:
			box.bg_color = Color(target_color, 0.2)
			box.border_color = target_color
			box.set_border_width_all(3)
			box.shadow_color = Color(target_color, 0.45)
			box.shadow_size = 8
			box.shadow_offset = Vector2.ZERO
		if example:
			# пример землянина — заметно: охристая заливка, толстая рамка со свечением (владелец, 14.11)
			if target_color.a == 0:
				box.bg_color = Color(FCStyle.c("ochre"), 0.22)
			box.border_color = FCStyle.c("ochre")
			box.set_border_width_all(5)
			box.shadow_color = Color(FCStyle.c("ochre"), 0.55)
			box.shadow_size = 10
			box.shadow_offset = Vector2.ZERO
		if picked:
			box.border_color = FCStyle.c("ochre")
			box.set_border_width_all(4)
		draw_style_box(box, r)
		var tex := FCStyle.item_texture(item)
		var inner := Rect2(r.position + Vector2(8, 6), r.size - Vector2(16, 34))
		var aspect := float(tex.get_width()) / tex.get_height()
		var w := minf(inner.size.x, inner.size.y * aspect)
		var img := Rect2(inner.get_center() - Vector2(w, w / aspect) / 2, Vector2(w, w / aspect))
		var fade := 0.35 if owned_color.a > 0 or forbidden else 1.0
		draw_texture_rect(tex, img, false, Color(1, 1, 1, fade))
		var f := FCStyle.font("title")
		var name: String = FCStyle.ITEM_NAMES[item] if item < FCStyle.ITEM_NAMES.size() else "?"
		var fs := 15
		var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while tw > size.x - 12 and fs > 10:
			fs -= 1
			tw = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) / 2, size.y - 10), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(FCStyle.c("ink"), fade if fade < 1 else 1.0))
		var bold := FCStyle.font("bold")
		if example:
			var tag := "ПРИМЕР"
			var tw2 := bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14
			var chip := StyleBoxFlat.new()
			chip.bg_color = FCStyle.c("ochre")
			chip.set_corner_radius_all(4)
			draw_style_box(chip, Rect2(8, 8, tw2, 20))
			draw_string(bold, Vector2(15, 23), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FCStyle.c("ochre_ink"))
		if picked:
			draw_circle(Vector2(size.x - 14, 14), 11, FCStyle.c("ochre"))
			draw_string(bold, Vector2(size.x - 20, 20), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FCStyle.c("ochre_ink"))
		if owned_color.a > 0:
			draw_circle(Vector2(size.x - 14, 14), 11, owned_color)
			draw_string(bold, Vector2(size.x - 20, 20), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FCStyle.c("alien_ink"))
		if forbidden:
			draw_line(Vector2(10, 10), Vector2(size.x - 10, size.y - 10), Color(FCStyle.c("muted"), 0.6), 3)
			draw_line(Vector2(size.x - 10, 10), Vector2(10, size.y - 10), Color(FCStyle.c("muted"), 0.6), 3)
		if voters != "":
			var vw := bold.get_string_size(voters, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10
			var vb := StyleBoxFlat.new()
			vb.bg_color = FCStyle.c("ochre")
			vb.set_corner_radius_all(4)
			draw_style_box(vb, Rect2(6, 6, vw, 18))
			draw_string(bold, Vector2(11, 20), voters, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FCStyle.c("ochre_ink"))


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
	if id != "first_contact":
		get_tree().change_scene_to_file("res://hub/hub.tscn")


func _refresh() -> void:
	faction_colors = [FCStyle.c("alien"), Color("b48cff") if FCStyle.dark() else Color("7b55c9"), Color("ffb347") if FCStyle.dark() else Color("c9741c")]
	if Net.in_game:
		_table()
	elif Net.in_session():
		_lobby()
	else:
		_menu()


func _lobby_changed() -> void:
	if not Net.in_game and Net.party_game == "first_contact":
		_lobby()


func _base() -> void:
	_close_peek()
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = FCStyle.make_theme()
	var bg := Backdrop.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _button(caption: String, fs: int = FCStyle.BODY, kind: String = "secondary") -> Button:
	var b := Button.new()
	b.text = caption
	FCStyle.style_button(b, kind, fs)
	b.custom_minimum_size.y = 40
	return b


func _bar_button(caption: String, fs: int = 14) -> Button:
	return _button(caption, fs, "quiet")


func _room_button(caption: String, fs: int = FCStyle.BODY) -> Button:
	return _button(caption, fs)


func _add(n: Node, caption: String, callback: Callable, kind: String = "secondary") -> Button:
	var b := _button(caption, FCStyle.BODY, kind)
	n.add_child(b)
	b.pressed.connect(callback)
	return b


func _label(n: Node, caption: String, fs: int = FCStyle.BODY, kind: String = "regular", color_key: String = "ink") -> Label:
	var l := FCStyle.label(caption, fs, kind, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_child(l)
	return l


func _room_label(caption: String, font_size: int) -> Label:
	return FCStyle.label(caption, font_size)


func _panel(pad: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", FCStyle.panel(pad))
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
	col.add_child(FCStyle.heading("Первый контакт", 44))
	_label(col, "Земляне учат язык инопланетян", FCStyle.BODY, "regular", "muted")
	col.add_child(RoomPanel.make("first_contact", _room_button, _room_label))
	_add(col, "Проверка на одном компьютере", func() -> void:
		Net.host_offline("first_contact")
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
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	page.add_child(FCStyle.heading("Первый контакт", 44))
	_label(page, "Лобби · 2–7 игроков: земляне и инопланетяне", FCStyle.BODY, "regular", "muted")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var members: Array = Net.lobby_view.get("members", [])
	var host := Net.is_host()
	var left := _panel(16)
	left.custom_minimum_size.x = 380
	body.add_child(left)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override("separation", 8)
	left.add_child(lc)
	lc.add_child(FCStyle.heading("Игроки · %d из 7" % members.size(), 20))
	for member: Dictionary in members:
		lc.add_child(PlayerTag.make(member, members, FCStyle.BODY, FCStyle.c("ink")))
	if host:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		lc.add_child(row)
		if Net.mode == "offline":
			_add(row, "− Игрок", func() -> void: Net.set_bots(Net.bots - 1)).disabled = members.size() <= 2
			_add(row, "+ Игрок", func() -> void: Net.set_bots(Net.bots + 1)).disabled = members.size() >= 7
		else:
			_add(row, "Пригласить друзей", Net.invite_friends)
	var right := _panel(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 10)
	right.add_child(rc)
	rc.add_child(FCStyle.heading("Настройки", 20))
	var options := [["fc_hard", "Сложный режим", "Несколько инопланетян со своими заданиями · от 4 игроков", members.size() < 4],
		["fc_opening", "Нулевой ход", "Перед игрой земляне узнают знаки нескольких признаков", false]]
	for option: Array in options:
		var key: String = option[0]
		var on := bool(Net.settings.get(key, false))
		var card := _toggle_card(option[1], option[2], on, not host or option[3])
		card.pressed.connect(func() -> void: Net.set_setting(key, not on))
		rc.add_child(card)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	page.add_child(foot)
	var back := _button("В хаб", FCStyle.BODY, "quiet")
	back.custom_minimum_size.x = 380
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.add_child(back)
	LeaveGuard.wire(back, "Выйти из лобби?", "Вы вернётесь в хаб.", _leave)
	if host:
		var start := _button("Начать игру", 20, "primary")
		start.custom_minimum_size = Vector2(320, 56)
		start.disabled = members.size() < 2
		start.pressed.connect(func() -> void: error.text = Net.start_game())
		foot.add_child(start)
	else:
		var wait := FCStyle.label("Ждём, когда хост начнёт игру", FCStyle.BODY, "bold", "muted")
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(wait)
	error = FCStyle.label("", FCStyle.CAP, "regular", "ochre")
	foot.add_child(error)


## Карточка-переключатель лобби вместо CheckButton (его ползунок плохо виден в тёмной теме).
func _toggle_card(title: String, caption: String, on: bool, locked: bool) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_pressed = on
	card.disabled = locked
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size.y = 68
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.bg_color = FCStyle.c("tile")
		var chosen: bool = state_name in ["pressed", "hover_pressed"] or (state_name == "disabled" and on)
		if chosen:
			box.bg_color = Color(FCStyle.c("ochre"), 0.18)
			box.border_color = FCStyle.c("ochre")
			box.set_border_width_all(2)
		if state_name in ["hover", "hover_pressed"]:
			box.bg_color = box.bg_color.lightened(0.05)
		if state_name == "disabled":
			box.bg_color = Color(box.bg_color, 0.55)
		card.add_theme_stylebox_override(state_name, box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", -2)
	row.add_child(texts)
	texts.add_child(FCStyle.label(title, 16, "bold", "ink" if not locked or on else "muted"))
	texts.add_child(FCStyle.label(caption, 13, "regular", "muted"))
	var badge := FCStyle.label("ВКЛ" if on else "ВЫКЛ", 13, "bold", "ochre" if on else "muted")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	return card


# --- Стол ----------------------------------------------------------------------

func _table() -> void:
	_base()
	top = TopBar.make(screen, "Первый контакт", _bar_button, null, FCStyle.c("ink"), FCStyle.font("title"))
	top.info.add_theme_font_override("font", FCStyle.font("bold"))
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
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(left)
	var banner := _panel(10)
	left.add_child(banner)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	banner.add_child(brow)
	banner_chip = PanelContainer.new()
	banner_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_chip.add_child(FCStyle.label("", 15, "bold", "ochre_ink"))
	brow.add_child(banner_chip)
	banner_text = FCStyle.label("", FCStyle.BODY, "bold")
	banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brow.add_child(banner_text)
	var board := _panel(12)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(board)
	board_area = Control.new()
	board_area.resized.connect(_layout_tiles)
	board.add_child(board_area)
	tiles.clear()
	for i in 25:
		var tile := ItemTile.new()
		tile.tooltip_text = ""
		tile.pressed.connect(_pick_card.bind(i))
		tile.mouse_entered.connect(_peek.bind(i))
		tile.mouse_exited.connect(_close_peek)
		board_area.add_child(tile)
		tiles.append(tile)
	for col in 5:
		var l := FCStyle.label(LETTERS[col], 15, "bold", "muted")
		l.name = "Col%d" % col
		board_area.add_child(l)
	for row in 5:
		var l := FCStyle.label(str(row + 1), 15, "bold", "muted")
		l.name = "Row%d" % row
		board_area.add_child(l)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 368
	main.add_child(right)
	ship = PanelContainer.new()
	ship.add_theme_stylebox_override("panel", FCStyle.ship_panel(14))
	right.add_child(ship)
	var side_panel := _panel(14)
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(side_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(scroll)
	side = VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	action_slot = VBoxContainer.new()
	action_slot.add_theme_constant_override("separation", 8)
	right.add_child(action_slot)
	if not Net.view.is_empty():
		_draw_state(Net.view)


func _layout_tiles() -> void:
	if not is_instance_valid(board_area):
		return
	var area := board_area.size
	var gap := 8.0
	var tw := (area.x - 28.0 - 4 * gap) / 5.0
	var th := (area.y - 24.0 - 4 * gap) / 5.0
	for i in tiles.size():
		var tile: ItemTile = tiles[i]
		tile.position = Vector2(28 + (i % 5) * (tw + gap), 24 + (i / 5) * (th + gap))
		tile.size = Vector2(tw, th)
	for col in 5:
		var l: Label = board_area.get_node("Col%d" % col)
		l.position = Vector2(28 + col * (tw + gap) + tw / 2 - 5, -4)
	for row in 5:
		var l: Label = board_area.get_node("Row%d" % row)
		l.position = Vector2(4, 24 + row * (th + gap) + th / 2 - 12)


func _popup(title: String, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.04, 0.08, 0.75)
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
	col.add_child(FCStyle.heading(title, FCStyle.H1))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", FCStyle.font("regular"))
	body.add_theme_font_override("bold_font", FCStyle.font("bold"))
	body.add_theme_font_size_override("normal_font_size", FCStyle.BODY)
	body.add_theme_font_size_override("bold_font_size", FCStyle.BODY)
	body.add_theme_color_override("default_color", FCStyle.c("ink"))
	col.add_child(body)
	var close := _button("Понятно", FCStyle.BODY, "primary")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 200
	close.pressed.connect(overlay.queue_free)
	col.add_child(close)


func _rules() -> void:
	_popup("Правила «Первого контакта»", RULES_TEXT)


func _settings() -> void:
	var settings := Settings.new()
	settings.make_panel = func() -> PanelContainer: return _panel(24)
	settings.make_title = func(text: String) -> Control: return FCStyle.heading(text, FCStyle.H1)
	settings.make_primary = func(text: String) -> Button: return _button(text, FCStyle.BODY, "primary")
	settings.ink = FCStyle.c("ink")
	add_child(settings)


func _send(kind: String, payload: Dictionary = {}) -> void:
	payload["serial"] = state.serial
	Net.send_action(kind, payload)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _name(seat: int) -> String:
	return str(state.names[seat]) if seat >= 0 and seat < state.names.size() else "?"


func _slot_name(slot: int) -> String:
	return "%s%d" % [LETTERS[slot % 5], (slot / 5) + 1]


func _item_name(slot: int) -> String:
	var id: int = state.cards[slot]
	return FCStyle.ITEM_NAMES[id] if id < FCStyle.ITEM_NAMES.size() else _slot_name(slot)


func _glyph(sign: Dictionary) -> String:
	return ("‾" if sign.get("negative", false) else "") + Rules.GLYPHS[sign.symbol]


func _set_banner(chip: String, text: String, kind: String) -> void:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	box.set_content_margin_all(4)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.bg_color = FCStyle.c("ochre") if kind == "mine" else (FCStyle.c("alien") if kind == "alien" else FCStyle.c("tile"))
	banner_chip.add_theme_stylebox_override("panel", box)
	var l: Label = banner_chip.get_child(0)
	l.text = chip.to_upper()
	l.add_theme_color_override("font_color", FCStyle.c("ochre_ink") if kind == "mine" else (FCStyle.c("alien_ink") if kind == "alien" else FCStyle.c("muted")))
	banner_chip.visible = chip != ""
	banner_text.text = text


func _draw_state(view: Dictionary) -> void:
	if not is_instance_valid(board_area) or not board_area.is_inside_tree() or not view.has("cards"):
		return
	if state.get("serial", -1) != view.serial or state.get("seat", -2) != view.seat:
		selected.clear()
		signs.clear()
	_close_peek()
	state = view
	top.info.text = "Раунд %d · %s" % [view.round, PHASES.get(view.phase, "")]
	var mine: bool = view.seat >= 0 and view.seat == view.turn
	_update_banner(mine)
	_update_tiles()
	_update_ship()
	_update_side(mine)
	_update_action(mine)
	_layout_tiles()


func _can_vote() -> bool:
	return state.phase == "vote" and state.seat >= 0 and not state.alien and state.seat not in state.answered


func _update_banner(mine: bool) -> void:
	var who := _name(state.turn)
	var waiting_pass: bool = not mine and state.get("hotseat", false) and state.turn >= 0
	match state.phase:
		"opening":
			_set_banner("Ваш ход" if mine else "Ходит", "Нулевой ход: спросите, каким знаком обозначают признак" if mine else who + " спрашивает знак признака", "mine" if mine else "idle")
		"ask":
			_set_banner("Ваш ход" if mine else "Ходит", "Отметьте от 1 до 5 предметов-примеров и подтвердите" if mine else who + " выбирает предметы-примеры", "mine" if mine else "idle")
		"teach":
			if state.alien:
				_set_banner("Вы — инопланетянин", "Покажите знак признака, общего для предметов-примеров", "alien")
			else:
				_set_banner("Ждём", "Инопланетяне отвечают знаком на ваши примеры", "idle")
		"clue":
			if mine:
				_set_banner("Вы — инопланетянин", "Сложите из знаков подсказку к светящемуся предмету", "alien")
			else:
				_set_banner("Ходит", who + " составляет подсказку", "idle")
		"vote":
			if _can_vote():
				_set_banner("Ваш голос", "Отметьте предмет, на который указывает подсказка, и подтвердите", "mine")
			elif not state.alien and state.seat >= 0:
				_set_banner("Голос принят", "Ждём остальных землян", "idle")
			else:
				_set_banner("Ждём", "Земляне тайно голосуют", "idle")
		"result":
			_set_banner("Результат", "Голоса открыты — отметки на предметах", "idle")
		"end":
			_set_banner("Итоги", "Игра окончена", "idle")
	if waiting_pass:
		_set_banner("Передайте ход", "Следующим ходит %s — передайте ему управление" % who, "mine")


func _update_tiles() -> void:
	var can_pick: bool = (state.seat == state.turn and state.phase == "ask") or _can_vote()
	var votes_on := {}
	for seat in state.votes:
		for slot: int in state.votes[seat]:
			votes_on[slot] = (votes_on.get(slot, "") + " " if votes_on.has(slot) else "") + _name(int(seat)).substr(0, 1)
	for i in 25:
		var tile: ItemTile = tiles[i]
		tile.item = state.cards[i]
		tile.picked = selected.has(i)
		tile.target_color = Color.TRANSPARENT
		for faction in state.targets.size():
			if i in state.targets[faction]:
				tile.target_color = faction_colors[faction % faction_colors.size()]
		tile.forbidden = i in state.forbidden
		tile.owned_color = faction_colors[int(state.owned[i]) % faction_colors.size()] if state.owned.has(i) else Color.TRANSPARENT
		tile.example = i in state.examples and state.phase == "teach"
		tile.voters = votes_on.get(i, "")
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_pick and not state.owned.has(i) else Control.CURSOR_ARROW
		tile.queue_redraw()


## Бирюзовая панель «корабля»: текущая подсказка или последний знак.
func _update_ship() -> void:
	_clear(ship)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	ship.add_child(col)
	var glyphs: Array[String] = []
	for sign: Dictionary in state.clue:
		glyphs.append(_glyph(sign))
	var caption := ""
	var line := ""
	if not glyphs.is_empty():
		caption = "ПОДСКАЗКА · " + (_name(state.humans + state.active_alien) if state.active_alien >= 0 else "")
		line = "   ".join(glyphs)
	elif state.alien and state.phase == "clue" and state.seat == state.turn:
		caption = "ВАША ПОДСКАЗКА"
		var draft: Array[String] = []
		for code in signs:
			draft.append("‾" if code == 0 else ("‾" if code < 0 else "") + Rules.GLYPHS[state.language[absi(code) - 1]])
		line = "   ".join(draft) + "  ▏"
	elif not state.teaching.is_empty():
		caption = "ПОСЛЕДНИЙ ЗНАК"
		line = Rules.GLYPHS[state.teaching.back().symbol]
	else:
		caption = "ЯЗЫК КОРАБЛЯ"
		line = "· · ·"
	col.add_child(FCStyle.label(caption, 13, "bold", "alien"))
	var big := FCStyle.label(line, 40, "regular", "alien")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(big)
	if line.contains("‾"):
		var hint := FCStyle.label("‾ — отрицание: «не …»", 13, "regular", "alien")
		hint.modulate.a = 0.75
		col.add_child(hint)


func _update_side(mine: bool) -> void:
	_clear(side)
	if state.alien and (state.phase == "teach" or (state.phase == "clue" and mine)):
		_sign_keyboard()
		return
	# словарь знаков: каждый показанный знак → примеры и ваша догадка
	side.add_child(FCStyle.heading("Словарь знаков", 20))
	var notes_by_glyph := {}
	for feature in state.notes:
		notes_by_glyph[int(state.notes[feature])] = Rules.FEATURES[int(feature)]
	var shown := {}  # знак → список примеров без повторов
	for entry: Dictionary in state.teaching:
		var symbol: int = entry.symbol
		var items: Array = shown.get(symbol, [])
		for slot: int in entry.get("slots", []):
			if _item_name(slot) not in items:
				items.append(_item_name(slot))
		if entry.has("feature") and "признак «%s»" % Rules.FEATURES[entry.feature] not in items:
			items.append("признак «%s»" % Rules.FEATURES[entry.feature])
		shown[symbol] = items
	if shown.is_empty():
		_label(side, "Знаков пока не было. Покажите инопланетянам примеры — они ответят знаком.", 13, "regular", "muted")
	for symbol: int in shown:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		side.add_child(row)
		var g := FCStyle.label(Rules.GLYPHS[symbol], 26, "regular", "alien")
		g.custom_minimum_size.x = 32
		row.add_child(g)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", -3)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(texts)
		texts.add_child(FCStyle.label((notes_by_glyph[symbol] + "?") if notes_by_glyph.has(symbol) else "?", 15, "bold"))
		var ex := FCStyle.label(", ".join(shown[symbol]), 13, "regular", "muted")
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(ex)
	if not state.alien and state.seat >= 0 and state.phase != "end":
		_note_picker()
	if state.phase in ["result", "end"] and not state.votes.is_empty():
		side.add_child(HSeparator.new())
		side.add_child(FCStyle.heading("Голоса", 18))
		for seat in state.votes:
			var choices: Array[String] = []
			for slot: int in state.votes[seat]:
				var matched: bool = state.owned.get(slot, -1) == state.active_alien
				choices.append(_item_name(slot) + (" ✓" if matched else " — мимо"))
			_label(side, "%s: %s" % [_name(int(seat)), ", ".join(choices)], 14)
	side.add_child(HSeparator.new())
	side.add_child(FCStyle.heading("Земляне", 18))
	for i in state.humans:
		var row := HBoxContainer.new()
		var n := FCStyle.label(_name(i) + (" · вы" if i == state.seat else ""), 15, "bold" if i == state.seat else "regular")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var status := "%d ✦" % state.favor[i]
		if state.phase == "vote" and i not in state.answered:
			status = "голосует…"
		row.add_child(FCStyle.label(status, 15, "bold", "ochre" if status.ends_with("✦") else "muted"))
		side.add_child(row)
	if state.low:
		_label(side, "Жетоны запаса: %d" % maxi(0, state.energy), 14, "regular", "muted")
	if state.phase == "end":
		side.add_child(HSeparator.new())
		_label(side, ("Победил инопланетянин " + _name(state.winner)) if state.winner >= 0 else "Запас жетонов исчерпан", 16, "bold")
		var winners: Array[String] = []
		var best := Vector2i(-1, -1)
		for i in state.humans:
			var value := Vector2i(state.favor[i], state.knowledge[i] if i < state.knowledge.size() else 0)
			if value.x > best.x or (value.x == best.x and value.y > best.y):
				best = value
				winners.clear()
			if value == best:
				winners.append(_name(i))
		_label(side, "Лучшие земляне: " + ", ".join(winners), 16, "bold")


## Клавиатура инопланетянина: знак крупно + признак мелко (инопланетянин знает язык).
func _sign_keyboard() -> void:
	var teach: bool = state.phase == "teach"
	side.add_child(FCStyle.label("ЗНАКИ КОРАБЛЯ", 13, "bold", "alien"))
	_label(side, "Нажмите знак признака, общего для примеров" if teach else "Нажмите знаки по порядку; ‾ — отрицание следующего знака", 13, "regular", "muted")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	side.add_child(grid)
	for feature in Rules.FEATURES.size():
		var b := Button.new()
		FCStyle.style_button(b, "alien", 13)
		b.text = "%s  %s" % [Rules.GLYPHS[state.language[feature]], Rules.FEATURES[feature]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(158, 36)
		b.clip_text = true
		b.add_theme_font_override("font", FCStyle.font("regular"))
		b.tooltip_text = Rules.FEATURES[feature]
		if teach:
			b.pressed.connect(func() -> void: _send("teach", {"feature": feature}))
		else:
			b.pressed.connect(func() -> void:
				var negative: bool = signs.size() > 0 and signs.back() == 0
				if negative:
					signs.pop_back()
				signs.append((feature + 1) * (-1 if negative else 1))
				_update_ship())
		grid.add_child(b)
	if not teach:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		side.add_child(row)
		var neg := Button.new()
		FCStyle.style_button(neg, "alien", 15)
		neg.text = "‾ Отрицание"
		neg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		neg.pressed.connect(func() -> void:
			if signs.is_empty() or signs.back() != 0:
				signs.append(0))
		neg.pressed.connect(_update_ship)
		row.add_child(neg)
		_add(row, "Стереть", func() -> void:
			signs.clear()
			_update_ship(), "quiet")


## Заметка землянина: «знак = признак» — догадки сохраняются у хоста.
func _note_picker() -> void:
	side.add_child(HSeparator.new())
	side.add_child(FCStyle.heading("Записать догадку", 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	var symbol := OptionButton.new()
	for value in Rules.GLYPHS:
		symbol.add_item(value)
	symbol.custom_minimum_size.x = 64
	row.add_child(symbol)
	row.add_child(FCStyle.label("=", 17, "bold", "muted"))
	var feature := OptionButton.new()
	for i in Rules.FEATURES.size():
		feature.add_item(Rules.FEATURES[i])
	feature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(feature)
	# сразу после сообщения инопланетянина выбран его первый знак (владелец, 14.11); без подсказки —
	# последний показанный знак. Если догадка к этому знаку уже записана — подставить и её.
	var glyph := -1
	if not state.clue.is_empty():
		glyph = int(state.clue[0].symbol)
	elif not state.teaching.is_empty():
		glyph = int(state.teaching.back().symbol)
	if glyph >= 0:
		symbol.select(glyph)
		for known in state.notes:
			if int(state.notes[known]) == glyph:
				feature.select(int(known))
	_add(side, "Записать", func() -> void: _send("note", {"feature": feature.selected, "symbol": symbol.selected}))


## Одна главная кнопка фазы под правой колонкой.
func _update_action(mine: bool) -> void:
	_clear(action_slot)
	var phase: String = state.phase
	if not mine and state.get("hotseat", false) and state.turn >= 0:
		_main_button("Передать ход · " + _name(state.turn), func() -> void: _send("fc_seat", {"seat": state.turn}))
		return
	if (mine and phase == "ask") or _can_vote():
		var names: Array[String] = []
		for slot in selected:
			names.append(_slot_name(slot))
		var caption := ("Показать примеры" if phase == "ask" else "Подтвердить голос") + (" · " + ", ".join(names) if not names.is_empty() else "")
		var b := _main_button(caption, func() -> void: _send("ask" if phase == "ask" else "vote", {"slots": selected.duplicate()}))
		b.disabled = selected.is_empty()
	elif mine and phase == "opening":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		action_slot.add_child(row)
		var feature := OptionButton.new()
		var choices: Array[int] = []
		for id in Rules.FEATURES.size():
			if not state.teaching.any(func(entry: Dictionary) -> bool: return entry.get("feature", -1) == id):
				choices.append(id)
				feature.add_item(Rules.FEATURES[id])
		feature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(feature)
		var ask := _button("Спросить знак", FCStyle.BODY, "primary")
		ask.pressed.connect(func() -> void: _send("opening", {"feature": choices[feature.selected]}))
		row.add_child(ask)
	elif state.alien and phase == "clue" and mine:
		var b := _main_button("Отправить подсказку", func() -> void: _send("clue", {"signs": signs.filter(func(code: int) -> bool: return code != 0)}))
		b.disabled = signs.filter(func(code: int) -> bool: return code != 0).is_empty()
	elif phase == "result" and Net.is_host():
		_main_button("Продолжить", func() -> void: _send("next"))
	elif phase == "end" and Net.is_host():
		_main_button("В лобби", Net.end_game)


func _main_button(caption: String, callback: Callable) -> Button:
	var b := _button(caption, FCStyle.BODY, "primary")
	b.custom_minimum_size.y = 52
	b.clip_text = true
	b.pressed.connect(callback)
	action_slot.add_child(b)
	return b


func _pick_card(index: int) -> void:
	var can_pick: bool = (state.seat == state.turn and state.phase == "ask") or (_can_vote() and not state.owned.has(index))
	if not can_pick:
		return
	if selected.has(index):
		selected.erase(index)
	else:
		var limit := 5 if state.phase == "ask" else (2 if state.names.size() == 2 else 1)
		if selected.size() >= limit:
			selected.pop_front()
		selected.append(index)
	_update_tiles()
	_update_action(state.seat == state.turn)


## Крупный просмотр предмета рядом с клеткой (с той стороны, где больше места), не на ней.
func _peek(index: int) -> void:
	_close_peek()
	var tile: ItemTile = tiles[index]
	var panel := _panel(10)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 92
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var image := TextureRect.new()
	image.texture = FCStyle.item_texture(tile.item)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(240, 170)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(image)
	var title := FCStyle.heading(FCStyle.ITEM_NAMES[tile.item], 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var slot := FCStyle.label(_slot_name(index), 14, "bold", "muted")
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(slot)
	screen.add_child(panel)
	var at := tile.get_global_rect()
	var x := at.end.x + 8 if index % 5 < 3 else at.position.x - 268
	panel.position = Vector2(x, clampf(at.position.y - 40, TopBar.HEIGHT + 8, screen.size.y - 270))
	preview = panel


func _close_peek() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = null
