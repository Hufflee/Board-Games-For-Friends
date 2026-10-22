extends Control
## Корневой экран «Перудо»: меню, лобби, стол. Пати и сеть — общие (Net).

const GAME_ID := "perudo"
const TableScreen := preload("res://games/perudo/ui/perudo_table.gd")
const LobbyScreen := preload("res://games/perudo/ui/perudo_lobby.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")

const PIRATE_MUSIC := ["res://games/perudo/audio/pirate_ship.ogg", "res://games/perudo/audio/pirate_indenture.wav"]
var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = K12UI.theme()
	var deck := K12Tavern.new(false)
	deck.pirate = true
	add_child(deck)
	Sfx.start_music()
	Sfx.set_playlist(PIRATE_MUSIC)  # пиратская музыка, шум моря
	Sfx.set_ambience("res://games/perudo/audio/sea_loop.wav")
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
	var col := K12UI.vbox(14)
	col.custom_minimum_size.x = 460
	center.add_child(col)
	var title := K12UI.title("Перудо", 72)
	title.add_theme_font_override("font", PerudoPirateDecor.font())
	col.add_child(title)
	col.add_child(K12UI.label("☠  пиратские кости лжеца  ☠", K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(K12UI.label("2–8 игроков", K12UI.BODY, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var dice_row := K12UI.hbox(8)
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var faces := [1, 3, 5, 6, 2]
	for i in faces.size():
		dice_row.add_child(PerudoDie.new(faces[i], 44, PerudoCup.seat_color(i)))
	col.add_child(dice_row)
	var bots := K12UI.button("Играть с ботами", K12UI.BODY)
	bots.pressed.connect(func():
		Net.host_offline(GAME_ID)
		Net.set_bots(3))
	col.add_child(bots)
	col.add_child(RoomPanel.make(GAME_ID, func(t, z): return K12UI.button(t, z), func(t, z): return K12UI.label(t, z, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	var row := K12UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules := K12UI.button("Правила", K12UI.BODY, 140)
	rules.pressed.connect(show_rules)
	row.add_child(rules)
	var settings := K12UI.button("Настройки", K12UI.BODY, 140)
	settings.pressed.connect(func(): add_child(SettingsScreen.new()))
	row.add_child(settings)
	col.add_child(row)
	var back := K12UI.button("← К выбору игры", K12UI.BODY)
	back.pressed.connect(back_to_hub)
	col.add_child(back)
	var status := K12UI.label(message, K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
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


const RULES_TEXT := """[b]Цель.[/b] Сохранить свои кости. Побеждает последний, у кого они остались.

[b]Раунд.[/b] Все трясут стаканы и смотрят только на свои кости. По кругу каждый либо делает [b]ставку[/b] — «на всём столе не меньше N костей номинала X», — либо кричит [b]«Дудо!»[/b] (не верю) или [b]«Калзак!»[/b] (ставка верна ровно) на ставку предыдущего игрока.

[b]Единицы — джокеры.[/b] При подсчёте они считаются костью любого номинала (кроме ставок на сами единицы).

[b]Повышение ставки.[/b]
• Больше костей — любой номинал; столько же костей — только номинал выше.
• На единицы можно перейти, уменьшив количество вдвое (с округлением вверх): после «5 пятёрок» — «3 единицы».
• С единиц на другой номинал — не меньше удвоенного количества, и ставка должна быть выше последней ставки не на единицы: после «6 пятёрок» → «3 единицы» можно «6 шестёрок», но не «6 двоек».

[b]«Дудо!»[/b] Все поднимают стаканы и считают названный номинал вместе с единицами. Если костей меньше ставки — кость теряет поставивший, иначе — тот, кто крикнул «Дудо». Проигравший начинает следующий раунд.

[b]«Калзак!»[/b] Вы утверждаете, что костей ровно столько, сколько в ставке. Угадали — возвращаете себе одну кость (не больше, чем было на старте), нет — теряете кость. Следующий раунд начинаете вы.

[b]Мапуто.[/b] Игрок с последней костью, начиная раунд, может объявить Мапуто: единицы не джокеры, а номинал в ставках менять нельзя — только повышать количество."""


func show_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.97), 8, "double")
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var col := K12UI.vbox(10)
	panel.add_child(col)
	var rt := K12UI.title("Правила «Перудо»", K12UI.H1)
	rt.add_theme_font_override("font", PerudoPirateDecor.font())
	col.add_child(rt)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(720, 0)
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.text = RULES_TEXT
	col.add_child(text)
	var close := K12UI.button("Закрыть", K12UI.BODY, 180)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(layer.queue_free)
	col.add_child(close)


func show_settings() -> void:
	add_child(SettingsScreen.new())


## Хост пати уводит всех к выбору игры; остальные/одиночная игра — выходят на стартовый экран.
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
