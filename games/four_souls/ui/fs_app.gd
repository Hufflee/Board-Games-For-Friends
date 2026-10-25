extends Control
## Корневой экран «The Binding of Isaac: Four Souls»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "four_souls"
const TableScreen := preload("res://games/four_souls/ui/fs_table.gd")
const LobbyScreen := preload("res://games/four_souls/ui/fs_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = FSStyle.theme()
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
	m.add_child(FSStyle.Backdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var p := FSStyle.panel()
	p.custom_minimum_size.x = 620
	center.add_child(p)
	var col := FSStyle.vbox(20)
	p.add_child(col)
	col.add_child(FSStyle.label("THE BINDING OF ISAAC · FOUR SOULS", FSStyle.H1, true))
	col.add_child(FSStyle.label("Четыре души. Восемь друзей. Сделки, сокровища и предательства."))
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return FSStyle.button(t, z), func(t, z): return FSStyle.label(t, z)))
	var local := FSStyle.primary("Играть на одном компьютере")
	local.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
	col.add_child(local)
	var row := FSStyle.hbox()
	for entry in [["Правила", show_rules], ["Настройки", show_settings], ["К выбору игры", back_to_hub]]:
		var b := FSStyle.button(entry[0])
		b.pressed.connect(entry[1])
		row.add_child(b)
	col.add_child(row)
	col.add_child(FSStyle.label(message, FSStyle.CAP))
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Цель.[/b] Первым соберите четыре души. Играйте на 2–8 человек. Переключатель DLC в комнате добавляет расширенные карты и комнаты; без него используется состав третьего присланного мода.

[b]Подготовка.[/b] Каждый получает персонажа, вечный стартовый предмет, три карты лута и 3¢. Открываются два монстра и два сокровища магазина. Каин ходит первым, если он участвует.

[b]Начало хода.[/b] Ваши карты перезаряжаются, вы берёте один лут. За ход можно разыграть один лут, купить одно сокровище за 10¢ и объявить одну атаку. Персонаж позволяет разыграть дополнительный лут, в том числе в чужой ход. Монетами можно расплачиваться с другими игроками.

[b]Ответы.[/b] Любой игрок может сыграть доступный лут или способность до следующего основного действия активного игрока. Таймера и кнопки подтверждения нет. Перед следующим броском, атакой, покупкой или концом хода предыдущие эффекты выполняются, начиная с последнего ответа. Если карта требует ручного выбора, сначала завершите её эффект. Лут требует доступного розыгрыша, поворотные предметы — готовности, платные способности — оплаты по карте.

[b]Эффекты карт.[/b] Как в исходном Tabletop Simulator, сложные эффекты выполняют сами игроки. Прочитайте русскую карту и примените её через панель «Выполнить эффект»: ресурсы, урон, добор, уничтожение, перезарядка и изменение броска. Все операции видны в журнале. Обычные монеты, потерянная душа и брелоки разыгрываются автоматически. Пассивные условия и особые цены активации проверяют участники.

[b]Бой.[/b] Объявите атаку и бросьте кубик мышью. После ответов бросок не ниже защиты монстра наносит ваш урон, иначе урон наносит монстр. Броски продолжаются до смерти одной из сторон. Убитый монстр открывает панель награды: начислите ровно то, что написано на карте, и подтвердите. Пустое место заполняется новой картой; события тоже разрешаются через стек.

[b]Смерть.[/b] Потеряйте одну монету, сбросьте один лут и уничтожьте один невечный предмет. Вечные предметы защищены. Карты поворачиваются, ваш ход заканчивается. В конце хода здоровье игроков и монстров восстанавливается; лишний лут сбрасывается до десяти.

[b]За одним компьютером.[/b] Выберите личный экран и откройте его за шторкой, пока остальные отвернулись. По сети рука каждого игрока закрыта. Ботов нет — эффекты карт требуют решений людей.

[b]Правила:[/b] https://tboi-four-souls.fandom.com/ru/wiki/Правила"""


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
	var panel := FSStyle.panel()
	margin.add_child(panel)
	var col := FSStyle.vbox(10)
	panel.add_child(col)
	col.add_child(FSStyle.label("ПРАВИЛА", FSStyle.H1, true))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", FSStyle.BODY)
	text.add_theme_font_size_override("bold_font_size", FSStyle.BODY)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := FSStyle.primary("Понятно")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return FSStyle.panel()
	st.make_title = func(t: String): return FSStyle.label(t.to_upper(), FSStyle.H1, true)
	st.make_primary = func(t: String): return FSStyle.primary(t)
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
