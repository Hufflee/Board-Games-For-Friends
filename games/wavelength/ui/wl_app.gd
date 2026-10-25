extends Control
## Корневой экран «Длины волны»: спокойная светлая тема как у Word Slam, меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "wavelength"
const TableScreen := preload("res://games/wavelength/ui/wl_table.gd")
const LobbyScreen := preload("res://games/wavelength/ui/wl_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HCStyle.sync_prefs()  # светлая / тёмная тема (Настройки)
	get_tree().root.theme = HCStyle.theme()
	Prefs.changed.connect(_on_prefs)
	Sfx.start_music()
	Sfx.set_playlist(HCStyle.MUSIC)
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
	m.add_child(preload("res://games/wavelength/ui/wl_backdrop.gd").new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := HCStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	var dial := WLDial.new()
	dial.custom_minimum_size = Vector2(300, 160)
	dial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dial.target = 68.0
	dial.cover = 0.0
	dial.value = 62.0
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(dial)
	col.add_child(HCStyle.title("Длина волны", 52))
	var sub := HCStyle.label("Угадайте мысли друг друга: телепат даёт подсказку, команда ставит стрелку на шкале. 2–8 игроков.", HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	col.add_child(Control.new())
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return HCStyle.button(t, z), func(t, z): return HCStyle.label(t, z, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	var hot := HCStyle.primary("Играть на одном компьютере", HCStyle.BODY)
	hot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hot.tooltip_text = "Телепат смотрит на экран, остальные отворачиваются"
	hot.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
	col.add_child(hot)
	var row := HCStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := HCStyle.button("Правила", HCStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := HCStyle.button("Настройки", HCStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	row.add_child(ThemeToggle.make(func(t, z): return HCStyle.button(t, z), HCStyle.BODY))  # солнце / луна — тема
	col.add_child(row)
	var back := HCStyle.button("← К выбору игры", HCStyle.BODY)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := HCStyle.label(message, HCStyle.BODY, HCStyle.CLAY, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] Две команды — «Левое» и «Правое полушарие» — по очереди пытаются поставить стрелку как можно ближе к центру скрытой цветной зоны. Первой до 10 очков! Вторая команда ходит второй, поэтому ей нужно 9.

[b]Ход.[/b] Телепат активной команды видит, где цветная зона. Он выбирает одну из двух пар противоположностей на карточке (например, «Холодное — Горячее») и даёт подсказку: что-то, что, по его мнению, находится на этой шкале там же, где центр зоны. Например, «Кофе» — чуть ближе к «горячему».

[b]Команда телепата[/b] обсуждает подсказку и двигает стрелку (тащите её мышью). Телепат молчит! Когда договорились — «Мы решили».

[b]Другая команда[/b] угадывает: центр зоны [b]левее[/b] или [b]правее[/b] стрелки.

[b]Очки.[/b] Команда телепата получает 2, 3 или 4 очка — в зависимости от того, в какую полосу попала стрелка (на границе — большее). Другая команда получает 1 очко за верное «левее/правее», но ничего, если стрелка попала в центр.

[b]Правило догоняющего.[/b] Если команда получила 4 очка и всё ещё проигрывает — она сразу ходит ещё раз.

[b]Победа.[/b] Как только у кого-то 10+ очков — побеждает команда с большим счётом. При ничьей каждая команда делает ещё по ходу.

[b]Подсказки:[/b] одна мысль; ничего не выдумывать; по делу; без однокоренных слов и синонимов с карточки; без чисел. Лучше коротко — до пяти слов.

[b]Кооператив.[/b] Все в одной команде, 7 карточек. Попадание в центр — 3 очка и ещё одна карточка. «Левее/правее» нет. В конце — оценка вашего результата."""


func show_rules() -> void:
	var layer := Control.new()
	layer.z_index = 100  # правила доступны поверх окна паузы
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.13, 0.1, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 150)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)
	var panel := HCStyle.panel(28)
	margin.add_child(panel)
	var col := HCStyle.vbox(12)
	panel.add_child(col)
	col.add_child(HCStyle.label("Правила", HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_constant_override("line_separation", 4)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := HCStyle.primary("Понятно", HCStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return HCStyle.panel(28)
	st.make_title = func(t: String): return HCStyle.label(t, HCStyle.H1, HCStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, "title")
	st.make_primary = func(t: String): return HCStyle.primary(t, HCStyle.BODY, 160)
	st.ink = HCStyle.INK
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


## Сменили тему в настройках — пересобрать экран в новой палитре (партия продолжается: стол строится из Net.view).
func _on_prefs() -> void:
	if HCStyle.sync_prefs():
		get_tree().reload_current_scene.call_deferred()
