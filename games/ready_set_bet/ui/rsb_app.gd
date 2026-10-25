extends Control
## Корневой экран «Ready Set Bet»: свой стиль ипподрома 80-х, меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "ready_set_bet"
const TableScreen := preload("res://games/ready_set_bet/ui/rsb_table.gd")
const LobbyScreen := preload("res://games/ready_set_bet/ui/rsb_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RSBStyle.sync_prefs()  # светлая / тёмная тема (Настройки)
	get_tree().root.theme = RSBStyle.theme()
	Prefs.changed.connect(_on_prefs)
	Sfx.start_music()
	Sfx.set_playlist(RSBStyle.MUSIC)
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
	var bg := TextureRect.new()
	bg.texture = load("res://games/ready_set_bet/art/cover.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.75, 0.72, 0.68)
	m.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.06, 0.03, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var card := RSBStyle.panel()
	card.custom_minimum_size = Vector2(540, 0)
	center.add_child(card)
	var col := RSBStyle.vbox(12)
	card.add_child(col)
	var horses := RSBStyle.hbox(2)
	horses.alignment = BoxContainer.ALIGNMENT_CENTER
	for h in [0, 2, 3, 4, 5, 6, 8]:
		horses.add_child(RSBStyle.pic(RSBStyle.tex("horse_%d" % h), Vector2(56, 40)))
	col.add_child(horses)
	col.add_child(RSBStyle.title("Ready Set Bet", 50))  # логотип
	var sub := RSBStyle.label("Скачки в реальном времени: ставьте пораньше — ради лучших коэффициентов, или дождитесь, кто вырвется вперёд, — пока не прозвучало «Ставок больше нет!».", RSBStyle.CAP, RSBStyle.INK, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return RSBStyle.button(t, z), func(t, z): return RSBStyle.label(t, z, RSBStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	var test := RSBStyle.primary("Попробовать на одном компьютере", RSBStyle.BODY)
	test.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	test.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(1))
	col.add_child(test)
	var row := RSBStyle.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := RSBStyle.button("Правила", RSBStyle.BODY, 150)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := RSBStyle.button("Настройки", RSBStyle.BODY, 150)
	settings.pressed.connect(show_settings)
	row.add_child(settings)
	row.add_child(ThemeToggle.make(func(t, z): return RSBStyle.button(t, z), RSBStyle.BODY))  # солнце / луна — тема
	col.add_child(row)
	var back := RSBStyle.button("← К выбору игры", RSBStyle.CAP)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := RSBStyle.label(message, RSBStyle.CAP, RSBStyle.RED, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] 4 забега. Ставьте на лошадей прямо во время скачки. После 4-го забега побеждает тот, у кого больше денег.

[b]Забег.[/b] Дом (программа) бросает два кубика: сумма двигает лошадь 2/3, 4, 5 … 10, 11/12 на клетку. Одинаковый результат два раза подряд — [b]бонусный ход[/b]: синие +3, оранжевые +2, красные +1, у чёрной 7 бонуса нет (третий бросок подряд бонус не даёт, четвёртый — снова даёт). Первая лошадь на 15-й клетке — победитель, забег кончается сразу.

[b]Ставки.[/b] Жетоны 2, 3, 3, 4, 5 (при 7–8 игроках — без одной «3»). Перетащите жетон на ячейку поля — или кликните по ячейке и выберите жетон. В одной ячейке — один жетон, кто первый — того и ячейка. Поставленный жетон не снять. Когда красную линию пересечёт [b]третья[/b] лошадь — «Ставок больше нет!».

[b]Ячейки.[/b] «Победит» — 1-е место; «В двойке» — 1–2; «В тройке» — 1–3. Цвет победителя; «7 — пятой или хуже». Пари: «лошадь обгонит…» (ничья — проигрыш). Экзотические финиши — по одному вашему жетону на карту. Чем правее ячейка — тем выгоднее.

[b]Ничьи.[/b] Если за 2-е место ничья — все они вторые и третьи, остальные не в тройке. Ничья за 3-е — все третьи.

[b]Выплаты.[/b] Выигрыш = номинал жетона × коэффициент ячейки. Проигрыш — штраф в красном кружке (без кружка — бесплатно). В минус уйти нельзя.

[b]VIP-карты.[/b] После забегов 1–3 каждому по 2 карты — одну оставляете (перетащите в ложу или дважды кликните). Бонус-жетоны добавляют ставку: при проигрыше к штрафу ячейки прибавляется их штраф, «2» — наоборот отменяет штраф."""


func show_rules() -> void:
	var layer := Control.new()
	layer.z_index = 100  # правила доступны поверх окна паузы
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.03, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 130)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	layer.add_child(margin)
	var panel := RSBStyle.panel()
	margin.add_child(panel)
	var col := RSBStyle.vbox(10)
	panel.add_child(col)
	col.add_child(RSBStyle.title("Правила", RSBStyle.H1))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := RSBStyle.primary("Понятно", RSBStyle.BODY, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	var st := SettingsScreen.new()
	# окно настроек — в оформлении окна правил этой игры
	st.make_panel = func(): return RSBStyle.panel()
	st.make_title = func(t: String): return RSBStyle.title(t, RSBStyle.H1)
	st.make_primary = func(t: String): return RSBStyle.primary(t, RSBStyle.BODY, 160)
	st.ink = RSBStyle.INK
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
	if RSBStyle.sync_prefs():
		get_tree().reload_current_scene.call_deferred()
