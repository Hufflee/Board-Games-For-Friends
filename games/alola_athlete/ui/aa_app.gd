extends Control
## Корневой экран «Алольского атлета»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "alola_athlete"
const TableScreen := preload("res://games/alola_athlete/ui/aa_table.gd")
const LobbyScreen := preload("res://games/alola_athlete/ui/aa_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = AAStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(AAStyle.MUSIC)
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
	m.add_child(AAStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := AAStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	var cards := AAStyle.hbox(-20)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["cards/rowlet", -8.0], ["cards/litten", 0.0], ["cards/popplio", 8.0]]:
		var tr := TextureRect.new()
		tr.texture = AAStyle.tex(spec[0])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(120, 168)
		tr.pivot_offset = Vector2(60, 84)
		tr.rotation_degrees = spec[1]
		cards.add_child(tr)
	col.add_child(cards)
	col.add_child(AAStyle.title("АЛОЛЬСКИЙ АТЛЕТ", 54))
	var sub := AAStyle.label("Гонка покемонов по четырём островам Алолы: соберите команду из четырёх бегунов, и пусть их умения сделают всё остальное!", AAStyle.BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var rp := AAStyle.panel(14)
	rp.add_child(RoomPanel.make(GAME_ID, func(t, z): return AAStyle.button(t, z), func(t, z): return AAStyle.label(t, z, AAStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(rp)
	var test := AAStyle.primary("Попробовать на одном компьютере", AAStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Тест: вы ходите за всех игроков по очереди"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
	col.add_child(test)
	var row := AAStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := AAStyle.button("Правила", AAStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := AAStyle.button("Настройки", AAStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := AAStyle.button("← К выбору игры", AAStyle.CAP)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := AAStyle.label(message, AAStyle.CAP, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
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


const RULES_TEXT := """[b]Цель.[/b] Четыре гонки на четырёх островах. За 1-е место в гонке — золото (3, 4, 4, 5 очков), за 2-е — серебро (1, 2, 2, 3). Больше всего очков после четвёртой гонки — победа.

[b]Драфт.[/b] В ряд выкладывают вдвое больше гонщиков, чем игроков. Игроки берут их по одному «змейкой», пока у каждого не будет четыре.

[b]Перед гонкой[/b] все тайно выбирают одного гонщика (каждый бежит один раз за игру) и, если на трассе есть развилка, — куда свернуть.

[b]Ход.[/b] Бросьте кубик — это [b]основной ход[/b]: гонщик проходит столько клеток. Умения гонщиков меняют броски, двигают других, роняют в обморок, телепортируют. Гонка заканчивается, когда финишировали двое.

[b]Клетки.[/b] Стрелка — пройдите по ней ещё столько клеток (вперёд или назад). «Обморок!» — пропускаете следующий основной ход. Бронзовый значок — сразу +1 очко (или +3). Гора «6 — чтобы пройти» на Ула-Уле: пройти дальше можно только с шестёркой на основном ходу.

[b]Обморок[/b] — гонщик пропускает следующий основной ход, но умения у него работают.

[b]Решения.[/b] Свои умения перед ходом и после броска вы выбираете сами. Ответные умения на чужих ходах (дуэли, «могу пойти следом» и т. п.) игра разыгрывает автоматически — всё видно в журнале гонки."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	var panel := AAStyle.panel(26)
	margin.add_child(panel)
	var col := AAStyle.vbox(10)
	panel.add_child(col)
	col.add_child(AAStyle.label("ПРАВИЛА", AAStyle.H1, AAStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", AAStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", AAStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := AAStyle.primary("Понятно", AAStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	add_child(SettingsScreen.new())


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
