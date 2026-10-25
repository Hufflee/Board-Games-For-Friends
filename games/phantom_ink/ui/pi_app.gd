extends Control
## Корневой экран «Призрачные чернила»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "phantom_ink"
const TableScreen := preload("res://games/phantom_ink/ui/pi_table.gd")
const LobbyScreen := preload("res://games/phantom_ink/ui/pi_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = PIStyle.theme()
	Sfx.start_music()
	Sfx.set_playlist(GLStyle.MUSIC)
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
	m.add_child(PIStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var p := PIStyle.panel()
	p.custom_minimum_size.x = 620
	center.add_child(p)
	var col := PIStyle.vbox(20)
	p.add_child(col)
	col.add_child(PIStyle.label("ПРИЗРАЧНЫЕ ЧЕРНИЛА", PIStyle.H1, true))
	col.add_child(PIStyle.label("Два духа. Один тайный предмет."))
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return PIStyle.button(t, z), func(t, z): return PIStyle.label(t, z)))
	var local := PIStyle.primary("Играть на одном компьютере")
	local.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
	col.add_child(local)
	var row := PIStyle.hbox()
	for entry in [["Правила", show_rules], ["Настройки", show_settings], ["К выбору игры", back_to_hub]]:
		var b := PIStyle.button(entry[0])
		b.pressed.connect(entry[1])
		row.add_child(b)
	col.add_child(row)
	col.add_child(PIStyle.label(message, PIStyle.CAP))
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Подготовка.[/b] 4–8 игроков делятся на Солнце и Луну. В каждой команде один дух и хотя бы один медиум. Духи видят одну карту предметов и согласуют номер слова. Медиумы видят только свои 7 вопросов.

[b]Ход команды.[/b] Выберите: задать вопрос или угадать предмет. Солнце начинает. У каждой команды 8 строк; если предмет никто не угадал, обе команды проиграли.

[b]Вопрос.[/b] Медиумы передают духу 2 вопроса. Дух выбирает один, другой уходит в открытый сброс. Дух вводит ответ — только буквы и пробелы, без однокоренных с предметом слов. Ответ появляется по одной букве. Медиумы нажимают «Тишина!», как только поняли подсказку. Если дух дописал ответ, появляется точка. Затем команда добирает 2 вопроса. Свои прежние вопросы можно перечитать, нажав строку подсказки.

[b]Догадка.[/b] Медиум вводит по одной букве. Дух подтверждает каждую стуком — кнопкой «Верно». Ошибочная буква перечёркивается, ход заканчивается. Чтобы закончить слово, медиум ставит точку; дух подтверждает весь предмет. Правильный ответ приносит победу!

[b]Око.[/b] Перед ходом на строке со знаком ока можно открыть ещё одну букву любой прежней подсказки — даже у другой команды. Затем сделайте обычный ход. Если слово уже дописано, откроется точка.

[b]Новая рука.[/b] Один раз за игру команда может сбросить 7 вопросов и взять новые, не тратя ход.

[b]Секретность.[/b] По сети каждому доступна своя роль. На одном компьютере передайте экран нужному игроку и откройте его за закрытой шторкой. Остальные должны отвернуться. Общий чат видят обе команды; тайные вопросы в него не отправляйте."""


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
	var panel := PIStyle.panel()
	margin.add_child(panel)
	var col := PIStyle.vbox(10)
	panel.add_child(col)
	col.add_child(PIStyle.label("ПРАВИЛА", PIStyle.H1, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", PIStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", PIStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := PIStyle.primary("Понятно")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return PIStyle.panel()
	st.make_title = func(t: String): return PIStyle.label(t.to_upper(), PIStyle.H1, true)
	st.make_primary = func(t: String): return PIStyle.primary(t)
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
