extends Control
## Меню, лобби и стол Unmatched. Владельца действия и правила определяет Net.

const GAME_ID := "unmatched"
const Table := preload("res://games/unmatched/ui/table.tscn")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Match := preload("res://games/unmatched/logic/um_match.gd")
const Style := preload("res://games/unmatched/ui/um_style.gd")
const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const BoardView := preload("res://games/unmatched/ui/um_board_view.gd")
const Complexity := preload("res://games/unmatched/logic/um_complexity.gd")
const HeroCards := preload("res://games/unmatched/ui/um_hero_cards.gd")
const HeroPicker := preload("res://games/unmatched/ui/um_hero_picker.gd")
const HERO_MODES := ["free", "random", "pick2", "pick3"]

var _screen: Control
var _playing := false
var _message := ""
var _handoff_actor := -1
var _hero_preview: HeroCards
var _hero_sort_by_complexity := false


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
	_hero_preview = null
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_lobby() -> void:
	# Обновление лобби могло быть отложено до начала партии.
	if Net.in_game and Net.party_game == GAME_ID:
		return
	_playing = false
	var settings: Dictionary = Net.settings if Net.is_host() else Net.lobby_view.get("settings", {})
	var members: Array = Net.lobby_view.get("members", [])
	var total := Net.player_total() if Net.is_host() else members.size()
	var arena := str(settings.get("um_arena", "marmoreal"))
	if arena in Match.Maps.HIDDEN_ARENAS:
		arena = "random"
	var colors := Style.palette(arena, Prefs.dark_theme())
	theme = Style.make_theme(colors)
	var root := Control.new()
	_switch(root)
	var background := TextureRect.new()
	background.texture = Art.backdrop(arena)
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
	var center := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		center.add_theme_constant_override("margin_%s" % side, 24)
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 24)
	center.add_child(layout)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel_height := 536.0
	if Net.in_session() and settings.get("um_hero_mode", "free") == "free":
		panel_height = 672.0 if total > 2 else 560.0
	panel.custom_minimum_size.y = minf(panel_height, size.y - 48.0)
	panel.add_theme_stylebox_override("panel", Style.frame(colors.panel, colors.rim, 20))
	layout.add_child(panel)
	var col := K12UI.vbox(12)
	col.custom_minimum_size.x = 280
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	scroll.add_child(col)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Unmatched"
	title.add_theme_font_override("font", Style.TITLE)
	title.add_theme_font_size_override("font_size", 52)
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Битва легенд и дополнения"
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
		layout.add_child(_lobby_preview(arena, settings, total, colors))
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
		col.add_child(K12UI.label("  ·  ".join(names), K12UI.BODY, get_theme_color("font_color", "Label")))
	var lobby_settings: Dictionary = Net.settings if Net.is_host() else Net.lobby_view.get("settings", {})
	var field := OptionButton.new()
	field.name = "ArenaChoice"
	field.fit_to_longest_item = false
	field.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	field.custom_minimum_size.x = 280
	field.get_popup().add_theme_color_override("font_disabled_color",
		Color("bca8b5") if Prefs.dark_theme() else Color("775f70"))
	var arena: String = lobby_settings.get("um_arena", "marmoreal")
	if arena in Match.Maps.HIDDEN_ARENAS:
		arena = "random"
		if Net.is_host():
			Net.set_setting.call_deferred("um_arena", arena)
	var seats := 4 if total > 2 else 2
	var incompatible := arena != "random" and not Match.Maps.supports(arena, seats)
	field.add_item("Случайное")
	field.set_item_metadata(0, "random")
	field.select(0)
	var arena_keys: Array = Match.Maps.NAMES.keys()
	arena_keys.sort_custom(func(a: String, b: String) -> bool:
		var first := Match.Maps.Battlefields.complexity(a)
		var second := Match.Maps.Battlefields.complexity(b)
		return Match.Maps.NAMES[a] < Match.Maps.NAMES[b] if first == second else first < second)
	for capacity: int in [2, 4]:
		field.add_separator("Поля на %d человека" % capacity)
		for key: String in arena_keys:
			if Match.Maps.supports(key, 4) != (capacity == 4):
				continue
			var mechanic := Match.Maps.Battlefields.mechanic(key)
			field.add_item(Match.Maps.NAMES[key] + (" · " + mechanic if not mechanic.is_empty() else ""))
			var index := field.item_count - 1
			field.set_item_metadata(index, key)
			field.set_item_disabled(index, capacity < seats)
			if arena == key:
				field.select(index)
	field.disabled = not Net.is_host()
	field.item_selected.connect(func(index: int): Net.set_setting("um_arena", field.get_item_metadata(index)))
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
	if total == 3:
		var double_player := OptionButton.new()
		double_player.name = "DoublePlayerChoice"
		for index in 3:
			double_player.add_item(str(members[index].name) if index < members.size() else "Игрок %d" % (index + 1))
		double_player.select(clampi(int(lobby_settings.get("um_double_player", 1)), 0, 2))
		double_player.disabled = not Net.is_host()
		double_player.item_selected.connect(Net.set_unmatched_double_player)
		col.add_child(_lobby_row("Два героя в одной команде", double_player))
		if Net.mode != "offline":
			var claim := K12UI.button("Я играю за двоих", K12UI.BODY)
			claim.pressed.connect(func(): Net.set_unmatched_double_player(0))
			col.add_child(claim)
	var duplicate_heroes := current_mode == "free" and _build_hero_selectors(col, members, total, lobby_settings)
	if duplicate_heroes:
		var warning := K12UI.label(Match.DUPLICATE_HEROES, K12UI.BODY)
		warning.add_theme_color_override("font_color", Color("ff646f") if Prefs.dark_theme() else Color("9d1634"))
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(warning)
	if Net.is_host():
		var start := K12UI.primary("Начать партию", K12UI.BODY)
		start.disabled = duplicate_heroes or incompatible
		if incompatible:
			start.tooltip_text = "Для этой партии выберите поле на 4 человека"
		Style.primary(start, Style.palette(str(lobby_settings.get("um_arena", "marmoreal")), Prefs.dark_theme()))
		start.pressed.connect(func():
			_message = Net.start_game()
			if not _message.is_empty():
				_show_lobby.call_deferred())
		col.add_child(start)
	else:
		col.add_child(K12UI.label("Ожидаем начала партии", K12UI.BODY, get_theme_color("font_color", "Label")))


func _lobby_preview(arena: String, settings: Dictionary, total: int, colors: Dictionary) -> VBoxContainer:
	var preview := K12UI.vbox(8)
	preview.name = "LobbyPreview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := K12UI.label(Match.Maps.NAMES.get(arena, "Случайное поле"), K12UI.BODY, colors.ink)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_child(title)
	if Match.Maps.NAMES.has(arena):
		var board := BoardView.new()
		board.mouse_filter = MOUSE_FILTER_IGNORE
		board.outline_color = colors.rim
		board.custom_minimum_size = Vector2(0, 392)
		preview.add_child(board)
		board.present(arena, [], {})
	else:
		preview.add_child(K12UI.label("Поле определится при старте", K12UI.BODY, colors.ink, HORIZONTAL_ALIGNMENT_CENTER))
	var mode: String = settings.get("um_hero_mode", "free")
	if mode != "free":
		var note := "Персонажи определятся при старте" if mode == "random" else "Выбор персонажей откроется при старте"
		preview.add_child(K12UI.label(note, K12UI.BODY, colors.ink, HORIZONTAL_ALIGNMENT_CENTER))
		return preview
	var seats := 4 if total == 3 else clampi(total, 2, 4)
	var selected: Array = Array(settings.get("um_heroes", []))
	if selected.size() != seats:
		selected = Match.DEFAULT_HEROES.slice(0, seats)
	var heroes := HBoxContainer.new()
	heroes.add_theme_constant_override("separation", 8)
	preview.add_child(heroes)
	for hero: String in selected:
		var cards := HeroCards.new()
		cards.show_hero(hero)
		cards.tooltip_text = Roster.HEROES.get(hero, {}).get("name", "")
		cards.size_flags_horizontal = SIZE_EXPAND_FILL
		cards.custom_minimum_size.y = 232
		cards.mouse_filter = MOUSE_FILTER_STOP
		cards.focus_mode = FOCUS_ALL
		heroes.add_child(cards)
		cards.mouse_entered.connect(_show_hero_preview.bind(cards))
		cards.mouse_exited.connect(_hide_hero_preview)
		cards.focus_entered.connect(_show_hero_preview.bind(cards))
		cards.focus_exited.connect(_hide_hero_preview)
	return preview


func _show_hero_preview(source: HeroCards) -> void:
	if not is_instance_valid(_hero_preview):
		_hero_preview = HeroCards.new()
		_hero_preview.name = "HeroCardZoom"
		_hero_preview.z_index = 100
		_screen.add_child(_hero_preview)
	_hero_preview.show_hero(source.hero)
	var height := minf(560.0, minf(size.y - 48.0, (size.x - 48.0) / HeroCards.PAIR_RATIO))
	var width := height * HeroCards.PAIR_RATIO
	_hero_preview.size = Vector2(width, height)
	var source_left := source.global_position.x - _screen.global_position.x
	var x := source_left - width - 16.0
	if x < 24.0:
		x = source_left + source.size.x + 16.0
	_hero_preview.position = Vector2(clampf(x, 24.0, size.x - width - 24.0), (size.y - height) * 0.5)
	_hero_preview.show()


func _hide_hero_preview() -> void:
	if is_instance_valid(_hero_preview):
		_hero_preview.hide()


func _build_hero_selectors(col: VBoxContainer, members: Array, total: int, settings: Dictionary) -> bool:
	var seats := 4 if total == 3 else clampi(total, 2, 4)
	var selected: Array = Array(settings.get("um_heroes", []))
	if selected.size() != seats:
		selected = Match.DEFAULT_HEROES.slice(0, seats)
	var selectors := K12UI.vbox(6)
	col.add_child(selectors)
	for place in seats:
		var choose := HeroPicker.new()
		choose.name = "HeroSelect%d" % place
		choose.fit_to_longest_item = false
		choose.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var difficulty := K12UI.label("", 14, get_theme_color("font_color", "Label"))
		difficulty.name = "HeroDifficulty%d" % place
		var picker := K12UI.vbox(2)
		picker.add_child(choose)
		picker.add_child(difficulty)
		var roster: Array = Roster.HEROES.keys()
		var hero: String = selected[place] if Roster.HEROES.has(selected[place]) else roster[0]
		choose.configure(hero, _hero_sort_by_complexity)
		choose.sort_changed.connect(func(enabled: bool) -> void: _hero_sort_by_complexity = enabled)
		_show_selected_hero(choose, difficulty, hero)
		var owner: int = Match.controllers_for(total, int(settings.get("um_double_player", 1)))[place]
		var local_owner: bool = Net.mode == "offline" or (owner < members.size() and members[owner].get("peer", 0) == multiplayer.get_unique_id())
		choose.disabled = not local_owner
		choose.hero_selected.connect(func(key: String) -> void:
			_show_selected_hero(choose, difficulty, key)
			Net.set_unmatched_hero(place, key))
		var name := str(members[owner].name) if owner < members.size() else "Игрок %d" % (owner + 1)
		selectors.add_child(_lobby_row("%s · %s" % ["А" if place % 2 == 0 else "Б", name], picker))
		picker.custom_minimum_size.x = 184
	return Match.has_duplicate_heroes(selected)


func _show_selected_hero(choose: OptionButton, difficulty: Label, hero: String) -> void:
	choose.text = Roster.HEROES[hero].name
	difficulty.text = Complexity.label(hero)
	choose.tooltip_text = "%s · %s" % [choose.text, difficulty.text]


func _lobby_row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var caption := Label.new()
	caption.text = title
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 96
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	control.custom_minimum_size.x = 160
	if control is OptionButton:
		control.fit_to_longest_item = false
		control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
