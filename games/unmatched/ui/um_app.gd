extends Control
## Меню, лобби и стол Unmatched. Владельца действия и правила определяет Net.

const GAME_ID := "unmatched"
const Table := preload("res://games/unmatched/ui/table.tscn")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
const Style := preload("res://games/unmatched/ui/um_style.gd")
const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const HERO_MODES := ["free", "random", "pick2", "pick3"]

var _screen: Control
var _playing := false
var _message := ""
var _handoff_actor := -1


func _ready() -> void:
	theme = K12UI.theme()
	Net.game_started.connect(_show_table)
	Net.game_ended.connect(_show_lobby)
	Net.lobby_changed.connect(_lobby_changed)
	Net.state_changed.connect(_show_state)
	Net.session_closed.connect(_closed)
	Net.party_game_changed.connect(_game_changed)
	if Net.in_game and Net.party_game == GAME_ID:
		_show_table()
	else:
		_show_lobby()


func _switch(screen: Control) -> void:
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_lobby() -> void:
	_playing = false
	var settings: Dictionary = Net.settings if Net.is_host() else Net.lobby_view.get("settings", {})
	var arena := str(settings.get("um_arena", "marmoreal"))
	var colors := Style.palette(arena, Prefs.dark_theme())
	theme = Style.make_theme(colors)
	var root := Control.new()
	_switch(root)
	var background := TextureRect.new()
	background.texture = Art.texture("res://games/unmatched/art/backgrounds/%s.webp" % arena)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(colors.bg, 0.52)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.frame(colors.panel, colors.rim, 20))
	center.add_child(panel)
	var col := K12UI.vbox(12)
	col.custom_minimum_size.x = 430
	panel.add_child(col)
	var title := Label.new()
	title.text = "Unmatched"
	title.add_theme_font_override("font", Style.TITLE)
	title.add_theme_font_size_override("font_size", 52)
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Битва легенд · Том 1 и том 2"
	subtitle.add_theme_font_size_override("font_size", 18)
	col.add_child(subtitle)
	if not Net.in_session():
		var local := K12UI.primary("За одним компьютером", K12UI.BODY)
		Style.primary(local, colors)
		local.pressed.connect(func(): Net.host_offline(GAME_ID))
		col.add_child(local)
		col.add_child(RoomPanel.make(GAME_ID, func(t: String, z: int): return K12UI.button(t, z),
			func(t: String, z: int): return K12UI.label(t, z, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)))
	else:
		_build_lobby(col)
	if not _message.is_empty():
		var message := K12UI.label(_message, K12UI.BODY)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(message)
	var back := K12UI.button("К выбору игр", K12UI.BODY)
	back.pressed.connect(_leave)
	col.add_child(back)


func _build_lobby(col: VBoxContainer) -> void:
	var members: Array = Net.lobby_view.get("members", [])
	var total := Net.player_total() if Net.is_host() else members.size()
	if not members.is_empty():
		var names := PackedStringArray()
		for member: Dictionary in members:
			names.append(member.name)
		col.add_child(K12UI.label("  ·  ".join(names), K12UI.BODY))
	var lobby_settings: Dictionary = Net.settings if Net.is_host() else Net.lobby_view.get("settings", {})
	var field := OptionButton.new()
	var arenas := ["marmoreal", "sarpedon", "gardens"]
	for name: String in ["Мармореал", "Сарпедон", "Висячие сады"]:
		field.add_item(name)
	field.select(maxi(0, arenas.find(lobby_settings.get("um_arena", "marmoreal"))))
	field.disabled = not Net.is_host()
	field.item_selected.connect(func(index: int): Net.set_setting("um_arena", arenas[index]))
	col.add_child(field)
	var hero_mode := OptionButton.new()
	for title: String in ["На выбор игрока", "Случайный", "Выбор из двух", "Выбор из трёх"]:
		hero_mode.add_item(title)
	var current_mode: String = lobby_settings.get("um_hero_mode", "free")
	hero_mode.select(maxi(0, HERO_MODES.find(current_mode)))
	hero_mode.disabled = not Net.is_host()
	hero_mode.item_selected.connect(func(index: int): Net.set_setting("um_hero_mode", HERO_MODES[index]))
	col.add_child(_lobby_row("Персонажи", hero_mode))
	if Net.mode == "offline" and Net.is_host():
		var count := OptionButton.new()
		for n in range(2, 5):
			count.add_item("%d участника" % n)
		count.select(clampi(total - 2, 0, 2))
		count.item_selected.connect(func(index: int):
			Net.set_setting("um_heroes", [])
			Net.set_bots(index + 1))
		col.add_child(count)
	if current_mode == "free":
		_build_hero_selectors(col, members, total, lobby_settings)
	if Net.is_host():
		var start := K12UI.primary("Начать партию", K12UI.BODY)
		Style.primary(start, Style.palette(str(lobby_settings.get("um_arena", "marmoreal")), Prefs.dark_theme()))
		start.pressed.connect(func():
			_message = Net.start_game()
			if not _message.is_empty():
				_show_lobby.call_deferred())
		col.add_child(start)
	else:
		col.add_child(K12UI.label("Ожидаем начала партии", K12UI.BODY))


func _build_hero_selectors(col: VBoxContainer, members: Array, total: int, settings: Dictionary) -> void:
	var seats := 4 if total == 3 else clampi(total, 2, 4)
	var selected: Array = Array(settings.get("um_heroes", []))
	if selected.size() != seats:
		selected = Match.DEFAULT_HEROES.slice(0, seats)
	for place in seats:
		var choose := OptionButton.new()
		var roster: Array = []
		for hero: String in Roster.HEROES:
			if hero == selected[place] or not hero in selected:
				roster.append(hero)
				choose.add_item(Roster.HEROES[hero].name)
		choose.select(roster.find(selected[place]))
		var owner := 1 if total == 3 and place == 3 else place
		var local_owner: bool = Net.mode == "offline" or (owner < members.size() and members[owner].get("peer", 0) == multiplayer.get_unique_id())
		choose.disabled = not local_owner
		choose.item_selected.connect(func(index: int): Net.set_unmatched_hero(place, roster[index]))
		var name := str(members[owner].name) if owner < members.size() else "Игрок %d" % (owner + 1)
		col.add_child(_lobby_row("%s · %s" % ["А" if place % 2 == 0 else "Б", name], choose))


func _lobby_row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var caption := Label.new()
	caption.text = title
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	control.custom_minimum_size.x = 184
	row.add_child(control)
	return row


func _show_table() -> void:
	if _playing:
		return
	_playing = true
	_handoff_actor = -1
	var table := Table.instantiate()
	_switch(table)
	table.action_requested.connect(Net.send_action)
	table.submitted.connect(func(answer: Dictionary): Net.send_action("combat", answer))
	table.hand_requested.connect(func(place: int): Net.send_action("view_hand", {"seat": place}))
	table.handoff_confirmed.connect(func(): Net.send_action("handoff", {}))
	table.exit_requested.connect(_leave)
	table.wire_party_menu()
	if not Net.view.is_empty():
		_show_state(Net.view)


func _show_state(view: Dictionary) -> void:
	if view.get("game") != GAME_ID:
		return
	if not _playing:
		_show_table()
		return
	_screen.present(view)
	if view.get("handoff", false):
		if _handoff_actor != int(view.actor):
			_handoff_actor = int(view.actor)
			_screen.hide_for_handoff(view.actor_name)
	else:
		_handoff_actor = -1


func _lobby_changed() -> void:
	if not Net.in_game:
		_show_lobby.call_deferred()


func _game_changed(game: String) -> void:
	if game != GAME_ID:
		get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)


func _closed(message: String) -> void:
	_message = message
	_show_lobby()


func _leave() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)
