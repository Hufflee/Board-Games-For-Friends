extends Control
## Корневой экран «Опасных слов»: своя жуткая тема, меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "dangerous_words"
const TableScreen := preload("res://games/dangerous_words/ui/dw_table.gd")
const LobbyScreen := preload("res://games/dangerous_words/ui/dw_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = DWStyle.theme()
	add_child(DWNight.new())
	Sfx.start_music()
	Sfx.set_playlist(DWStyle.MUSIC)
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
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := DWStyle.vbox(14)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	col.add_child(DWStyle.title("Опасные слова", 72))
	col.add_child(DWStyle.label("Объясняйте слова — и не попадитесь в ловушки!", DWStyle.BODY, DWStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var parade := DWStyle.hbox(6)
	parade.alignment = BoxContainer.ALIGNMENT_CENTER
	for mid in ["vampire", "mummy", "dragon", "demon", "troll"]:
		var pic := TextureRect.new()
		pic.texture = DWStyle.art("monster_" + mid)
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # крупный арт рисуется мелко
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(96, 96)
		parade.add_child(pic)
	col.add_child(parade)
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return DWStyle.button(t, z), func(t, z): return DWStyle.label(t, z, DWStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	col.add_child(DWStyle.label("Объясняйте голосом — зайдите в голосовой чат (Discord и т. п.).", DWStyle.CAP, DWStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var test := DWStyle.button("Попробовать на одном компьютере", DWStyle.BODY)
	test.theme_type_variation = "SelectedButton"  # главное действие меню — тыквой
	test.tooltip_text = "Тестовый режим: все видят всё, действуете за обе команды"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
	col.add_child(test)
	var row := DWStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := DWStyle.button("Правила", DWStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := DWStyle.button("Настройки", DWStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	col.add_child(row)
	var back := DWStyle.button("← К выбору игры", DWStyle.BODY)
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := DWStyle.label(message, DWStyle.BODY, DWStyle.PUMPKIN, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] Две команды пробираются через подземелье. В последней комнате ждёт монстр — победит команда, которая одолеет его первой. Максимум 8 раундов, иначе побеждает монстр.

[b]Ловушки.[/b] В начале раунда обе команды одновременно видят секретное слово, которое будет объяснять соперник, и записывают [b]слова-ловушки[/b] — слова, которые объясняющий наверняка захочет сказать. Ловушек столько, каков номер комнаты соперника. Только существительные, прилагательные, глаголы и числа.

[b]Объяснение (голосом).[/b] Объясняющий видит слово и объясняет его своей команде. Нельзя: однокоренные слова, примеры, имена собственные, «звучит как…», жесты. Команда угадывает вслух, не больше 5 неверных догадок.

[b]Провал[/b] — объясняющий сказал ловушку (или однокоренное), нарушил правила, 5 неверных догадок или время вышло. Соперники жмут «Ловушка!» / «Нарушение» / «+1 догадка». [b]Успех[/b] — объясняющий жмёт «Отгадали!», команда идёт в следующую комнату.

[b]Порядок.[/b] Первой ходит отстающая команда; в одной комнате — по очереди.

[b]Монстр.[/b] Если обе команды провалились, монстр сдвигается на комнату ближе (и толкает проклятия перед собой). Команда в комнате монстра сражается по его особому правилу: отгадала — победа.

[b]Проклятия.[/b] Начав раунд в комнате с проклятием, команда открывает его — оно действует на этот раунд.

[b]Золотое правило.[/b] Ловушку надо поймать сразу (в течение ~3 секунд). Сомневаетесь — обсудите после хода."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 100  # выше панелей стола (у них поднятый z_index)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)
	var panel := DWStyle.panel(DWStyle.PUMPKIN)
	margin.add_child(panel)
	var col := DWStyle.vbox(10)
	panel.add_child(col)
	col.add_child(DWStyle.title("Правила", DWStyle.H1))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", DWStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", DWStyle.BODY)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := DWStyle.button("Закрыть", DWStyle.BODY, 180)
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
