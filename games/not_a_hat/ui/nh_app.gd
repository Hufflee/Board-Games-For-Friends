extends Control
## Корневой экран «Это не шляпа!»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "not_a_hat"
const TableScreen := preload("res://games/not_a_hat/ui/nh_table.gd")
const LobbyScreen := preload("res://games/not_a_hat/ui/nh_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = NHStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(NHStyle.MUSIC)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(_on_closed)
	Net.party_game_changed.connect(_on_party_game)
	if Net.is_party() and Net.party_game != GAME_ID and not Net.lobby_view.is_empty():
		_go_hub()
	elif Net.in_game or not Net.view.is_empty():
		show_table()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
	screen = s
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(s)


func show_menu(message: String = "") -> void:
	var m := Control.new()
	m.add_child(NHStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := NHStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	var cards := NHStyle.hbox(-30)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [[0, 1, -8.0], [-1, -1, 4.0], [78, 1, 12.0]]:
		var c := NHCard.new(spec[0], spec[1])
		c.rotation_degrees = spec[2]
		cards.add_child(c)
	col.add_child(cards)
	col.add_child(NHStyle.title("ЭТО НЕ ШЛЯПА!", 60))
	var sub := NHStyle.label("Дарите друг другу подарки рубашкой вверх и называйте их вслух. Помните, что у кого лежит, — или блефуйте!", NHStyle.BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var rp := NHStyle.panel(14)
	rp.add_child(RoomPanel.make(GAME_ID, func(t, z): return NHStyle.button(t, z), func(t, z): return NHStyle.label(t, z, NHStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(rp)
	var test := NHStyle.primary("Попробовать на одном компьютере", NHStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Тест: вы ходите за всех игроков по очереди"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(2))
	col.add_child(test)
	var row := NHStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := NHStyle.button("Правила", NHStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := NHStyle.button("Настройки", NHStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := NHStyle.button("← К выбору игры", NHStyle.CAP)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := NHStyle.label(message, NHStyle.CAP, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Цель.[/b] Наберите как можно меньше штрафных карт. Игра заканчивается, когда у кого-то 3 штрафа; побеждает тот, у кого их меньше всех.

[b]Начало.[/b] У каждого перед собой подарок. Сначала все подарки открыты — запомните их! Потом их переворачивают рубашкой вверх.

[b]Дарим.[/b] Первый игрок берёт подарок из магазина (его видят все) и дарит его соседу — по стрелке на рубашке: влево или вправо. Даря, он говорит: «У меня для тебя подарок: …» — выберите, что это.

[b]«Спасибо!»[/b] Получатель принимает подарок и кладёт его [b]сверху[/b] своего столбика. Теперь у него два подарка — и он дарит свой [b]старый[/b] (нижний) подарок дальше, тоже по стрелке и тоже называя его. Новый подарок передаривать нельзя — это невежливо!

[b]«Это не …!»[/b] Если получатель думает, что даритель ошибся или блефует, он отказывается. Подарок открывают: ошибся тот, кто был неправ. Он забирает карту себе как штраф, берёт новый подарок из магазина и дарит его.

[b]Советы.[/b] Забыли, что у вас лежит? Не подавайте вида — блефуйте! Уверены? Притворитесь, что сомневаетесь, — пусть соперник откажется и ошибётся.

[b]Сложнее.[/b] В лобби можно выбрать «по 2 подарка» — у каждого столбик из двух карт (так можно играть и вдвоём)."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 100  # выше панелей стола (у них поднятый z_index)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)
	var panel := NHStyle.panel(26)
	margin.add_child(panel)
	var col := NHStyle.vbox(10)
	panel.add_child(col)
	col.add_child(NHStyle.label("ПРАВИЛА", NHStyle.H1, NHStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", NHStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", NHStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := NHStyle.primary("Понятно", NHStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	st.z_index = 100  # выше панелей стола
	add_child(st)


func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
		return
	Net.leave()
	_go_hub()


func back_to_menu() -> void:
	if Net.is_party():
		back_to_hub()
		return
	Net.leave()
	show_menu()


func leave_party() -> void:
	Net.leave()
	_go_hub()


func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)


func _on_party_game(game_id: String) -> void:
	if game_id != GAME_ID:
		_go_hub()


func _on_lobby_changed() -> void:
	if Net.is_party() and Net.party_game != GAME_ID:
		_go_hub()
		return
	if not Net.in_game and not (screen is LobbyScreen) and Net.in_session() and Net.view.is_empty():
		show_lobby()


func _on_closed(reason: String) -> void:
	show_menu(reason)
