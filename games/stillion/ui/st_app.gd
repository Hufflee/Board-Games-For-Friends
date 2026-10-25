extends Control
## Корневой экран «Стиллиона»: меню, лобби, стол. Пати и сеть — общие (Net).
## Запуск отдельно: открыть res://games/stillion/ui/main.tscn.

const GAME_ID := "stillion"
const TableScreen := preload("res://games/stillion/ui/st_table.gd")
const LobbyScreen := preload("res://games/stillion/ui/st_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = STStyle.theme()
	Sfx.start_music()
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


## Смена светлой/тёмной темы: тема пересобирается, текущий экран — заново.
func restyle() -> void:
	get_tree().root.theme = STStyle.theme()
	if screen is LobbyScreen:
		show_lobby()
	elif Net.in_game or not Net.view.is_empty():
		show_table()
	else:
		show_menu()


func show_menu(message: String = "") -> void:
	var m := Control.new()
	var bg := STStyle.Backdrop.new()
	bg.image = "bg_circus_approved.png"
	m.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var p := STStyle.panel(28)
	p.custom_minimum_size.x = 620
	center.add_child(p)
	var col := STStyle.vbox(18)
	p.add_child(col)
	var t := STStyle.label("Стиллион", 64, STStyle.RED, HORIZONTAL_ALIGNMENT_CENTER, "title")
	t.add_theme_color_override("font_outline_color", STStyle.INK)
	t.add_theme_constant_override("outline_size", 12)
	col.add_child(t)
	var sub := STStyle.label("Отвечай, пока пушка не выстрелила!", STStyle.BODY, STStyle.muted(), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(sub)
	col.add_child(RoomPanel.make(GAME_ID, func(tx, z): return STStyle.button(tx, z), func(tx, z): return STStyle.label(tx, z)))
	var local := STStyle.primary("Играть на одном компьютере")
	local.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
	col.add_child(local)
	var row := STStyle.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in [["Правила", show_rules], ["Настройки", show_settings], ["К выбору игры", back_to_hub]]:
		var b := STStyle.button(entry[0], STStyle.CAP)
		b.pressed.connect(entry[1])
		row.add_child(b)
	col.add_child(row)
	col.add_child(STStyle.label(message, STStyle.CAP, STStyle.RED, HORIZONTAL_ALIGNMENT_CENTER))
	m.add_child(STStyle.FilmFX.new())
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Цель.[/b] Остаться последним с жизнями. У каждого 3 жизни (хост меняет это в лобби).

[b]Пушка.[/b] Игроки стоят по кругу, в центре — чёрная пушка. Она наводится на игрока и начинает надуваться: горит фитиль. Пока он не догорел, напечатайте ответ на вопрос сверху и нажмите Enter.

[b]Ответили верно[/b] — пушка сдувается и поворачивается к следующему игроку по часовой стрелке. Ему — тот же вопрос, но уже названные ответы не принимаются. [b]Не успели[/b] — выстрел, минус жизнь.

[b]Ошибся — не беда.[/b] Неверный ответ можно исправить, пока горит фитиль. Опечатки в паре букв игра исправит сама.

[b]Редкость ответа.[/b] Чем неочевиднее ответ, тем больше очков шкалы под игроком: Общеизвестно (голубой) — 1, Школьник (тёмно-синий) — 2, Умник (фиолетовый) — 3, Эрудит (красный) — 4. Шкала под игроком заполнилась (по умолчанию 20 очков) — +1 жизнь (не больше начального числа), и шкала обнуляется. С настройкой «Обычные игроки» ответы ценятся на ступень выше: умник — как эрудит, школьник — как умник, менее очевидные общеизвестные — как школьник.

[b]Смена вопроса.[/b] Вопрос меняется, когда на нём прошло 25 секунд или двое потеряли жизнь; перед новым вопросом — короткая пауза «Новый вопрос!». На каждый вопрос фитиль сначала полный (12 секунд), с каждым верным ответом на него — на секунду короче (до 5).

[b]Проверка.[/b] Ответ сначала ищется в списке известных. Если его там нет и у ведущего подключена нейросеть Jev, она решит, подходит ли ответ и насколько он редкий; без Jev засчитываются только ответы из списка."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 100  # правила доступны поверх окна паузы
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
	var panel := STStyle.panel(24)
	margin.add_child(panel)
	var col := STStyle.vbox(10)
	panel.add_child(col)
	col.add_child(STStyle.title("Правила"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", STStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", STStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := STStyle.primary("Понятно", STStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return STStyle.panel(24)
	st.make_title = func(t: String): return STStyle.title(t)
	st.make_primary = func(t: String): return STStyle.primary(t, STStyle.BODY, 160)
	st.ink = STStyle.ink()
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
