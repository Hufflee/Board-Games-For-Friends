extends Control
## Корневой экран «Оттенков и подсказок»: своя спокойная тема, меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "hues_and_cues"
const TableScreen := preload("res://games/hues_and_cues/ui/hc_table.gd")
const LobbyScreen := preload("res://games/hues_and_cues/ui/hc_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")
const LOGO_CELLS := [8, 64, 129, 233, 318, 413, 446, 207, 290]

const SKIP_INTRO_META := &"hc_skip_intro_once"  # передача флага через полную перезагрузку темы
var _intro_pending := true
var screen: Control


func _ready() -> void:
	var root := get_tree().root
	_intro_pending = not bool(root.get_meta(SKIP_INTRO_META, false))
	if root.has_meta(SKIP_INTRO_META):
		root.remove_meta(SKIP_INTRO_META)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HCStyle.sync_prefs()  # светлая / тёмная тема (Настройки)
	get_tree().root.theme = HCStyle.theme()
	Prefs.changed.connect(_on_prefs)
	Sfx.start_music()
	Sfx.set_playlist(HCStyle.MUSIC)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(_on_game_started)
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
	m.add_child(HCBackdrop.new(true))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var col := HCStyle.vbox(16)
	col.custom_minimum_size.x = 560
	center.add_child(col)
	col.add_child(HCStyle.logo_strip(LOGO_CELLS, 26))
	col.add_child(HCStyle.title("Hues and Cues", 54))
	var stroke := HCStyle.BrushStroke.new(380, 14)
	stroke.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(stroke)
	var sub := HCStyle.label("Опишите цвет одним словом — и посмотрите, насколько близко попадут друзья.", HCStyle.BODY, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	col.add_child(Control.new())
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return HCStyle.button(t, z), func(t, z): return HCStyle.label(t, z, HCStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	var test := HCStyle.primary("Попробовать на одном компьютере", HCStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Тестовый режим: игроки по очереди за одним компьютером"
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(2))
	col.add_child(test)
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


func _on_game_started() -> void:
	_intro_pending = true
	show_table()


func show_table() -> void:
	var t := TableScreen.new()
	t.play_intro = _intro_pending
	_intro_pending = false
	t.app = self
	_set_screen(t)


const RULES_TEXT := """[b]Цель.[/b] Ведущий описывает цвет с поля 30×16 короткими подсказками, остальные ставят фишки на оттенок, который он имел в виду. Чем ближе — тем больше очков.

[b]1. Карта.[/b] Ведущий тянет карту с четырьмя цветами и тайно выбирает один.

[b]2. Подсказка из одного слова.[/b] Нельзя: базовые названия цветов (красный, оранжевый, жёлтый, зелёный, голубой, синий, фиолетовый, розовый, коричневый, белый, чёрный, серый), положение на поле, буквы и цифры, предметы в комнате, повтор уже звучавшей подсказки. Необычные названия цветов («лаванда», «шартрез») — можно.

[b]3. Первые догадки[/b] — по часовой стрелке, по одной фишке. В одной клетке — только одна фишка.

[b]4. Вторая подсказка[/b] — до двух слов, по тем же правилам (и без «светлее/темнее»). Ведущий может спасовать — тогда подсчёт сразу.

[b]5. Вторые догадки[/b] — против часовой стрелки, на любую свободную клетку.

[b]Подсчёт.[/b] Вокруг загаданного цвета кладётся рамка 3×3.
• Точно в цвет — 3 очка; фишка в рамке — 2; вплотную к рамке (и по диагонали) — 1.
• Ведущий — 1 очко за каждую фишку в рамке (втроём — 2 очка).

[b]Crazy colors.[/b] Отдельный режим в лобби. Каждый раунд цвета переходят между неподвижными клетками по вложенным кольцам, по часовой или против часовой стрелки. Движение разгоняется, затем тормозит; цветовые группы сохраняются. В течение 6 секунд плавно появляется один из четырёх фильтров: синий, зелёный, красный или чёрно-белый. Ведущий тоже видит вступление с фильтром; после остановки у него фильтр плавно исчезает. Центр 2×2 даёт 3 очка, кольцо до 6×6 — 2, до 10×10 — 1. Центр включает загаданную клетку и соседей справа/снизу; у края сдвигается внутрь. Ведущий получает очки за фишки в области 6×6.

[b]Конец игры.[/b] При 3–6 игроках каждый ведёт дважды, при 7–8 — один раз. Больше очков — победа. При ничьей играют ещё раунды: ведут те, кто не претендует на победу, пока один из лидеров не вырвется вперёд."""


func show_rules() -> void:
	var layer := Control.new()
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


## Сменили тему в настройках — пересобрать экран в новой палитре (партия продолжается: стол строится из Net.view).
func _on_prefs() -> void:
	if HCStyle.sync_prefs():
		# новая тема — вступление (окрашивание поля) проигрывается заново
		get_tree().reload_current_scene.call_deferred()
