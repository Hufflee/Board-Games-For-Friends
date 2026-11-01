extends Control
## Технический вход в три JSON-примера. Позже этот стол открывает библиотека редактора.

const Style := preload("res://games/custom/ui/cg_style.gd")
const Session := preload("res://games/custom/logic/cg_session.gd")
const Table := preload("res://games/custom/ui/cg_table.gd")
var _screen: Control
var _error: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.lobby_changed.connect(_lobby_changed)
	Net.session_closed.connect(show_menu)
	Net.party_game_changed.connect(_party_changed)
	Prefs.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	theme = Style.theme()
	if Net.in_game and Net.is_custom_game(Net.party_game):
		show_table()
	elif Net.in_session() and Net.is_custom_game(Net.party_game):
		show_lobby()
	elif Net.in_session():
		get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)
	else:
		show_menu()

func _replace(control: Control) -> void:
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	_screen = control
	_screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_screen)

func _center() -> VBoxContainer:
	var root := ColorRect.new()
	root.color = Style.bg()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	panel.add_theme_stylebox_override("panel", Style.box(Style.panel(), 24))
	center.add_child(panel)
	var col := Style.column()
	panel.add_child(col)
	_replace(root)
	return col

func show_menu(_reason: String = "") -> void:
	var col := _center()
	var selected := str(Net.settings.get("cg_selected", ""))
	var custom: bool = Session.Library.uuid_valid(selected) and not Session.Library.load_game(selected).is_empty()
	var game_id := "custom:" + selected if custom else "cg"
	col.add_child(Style.heading(str(Session.Library.load_game(selected).meta.title) if custom else "ПРИМЕРЫ РЕДАКТОРА"))
	col.add_child(Style.label("Три игры из блоков · 2–8 участников · без ботов"))
	col.add_child(RoomPanel.make(game_id, Style.button, Style.label))
	var local := Style.primary("Играть на одном компьютере")
	local.pressed.connect(func():
		Net.host_offline(game_id)
		Net.set_bots(1))
	col.add_child(local)
	var back := Style.button("В хаб")
	back.pressed.connect(_hub)
	col.add_child(back)

func show_lobby() -> void:
	var col := _center()
	var custom: bool = Net.party_game.begins_with("custom:")
	col.add_child(Style.heading(str(Net.cg_transfer.manifest.get("title", "Пользовательская игра")) if custom else "ПОЛЬЗОВАТЕЛЬСКАЯ ИГРА"))
	var choice := OptionButton.new()
	choice.custom_minimum_size.y = 40
	for title: String in Session.TITLES:
		choice.add_item(title)
	var options: Dictionary = Net.lobby_view.get("settings", Net.settings)
	choice.select(maxi(0, Session.EXAMPLES.find(str(options.get("cg_example", "card_race")))))
	choice.disabled = not Net.is_host()
	choice.item_selected.connect(func(index: int): Net.set_setting("cg_example", Session.EXAMPLES[index]))
	if not custom:
		col.add_child(choice)
	else:
		choice.queue_free()
		col.add_child(Style.label(_download_status()))
	var names := GridContainer.new()
	names.columns = 2
	names.add_theme_constant_override("h_separation", 24)
	col.add_child(names)
	var local_index := 0
	var members: Array = Net.lobby_view.get("members", [])
	for i in members.size():
		var member: Dictionary = members[i]
		var row := Style.row()
		row.add_child(PlayerTag.make(member, members, 16, Style.ink()))
		var team := OptionButton.new()
		team.add_item("Команда 1")
		team.add_item("Команда 2")
		team.select(clampi(int(member.get("team", 0)), 0, 1))
		var local: bool = member.get("kind") == "local"
		var local_seat := local_index
		if local:
			local_index += 1
		team.disabled = not (Net.is_host() and local or int(member.get("peer", -1)) == Net.multiplayer.get_unique_id())
		team.item_selected.connect(func(index: int):
			if local:
				Net.set_local_team(local_seat, index)
			else:
				Net.set_team(index))
		row.add_child(team)
		var role := OptionButton.new()
		var definitions: Array = Net.cg_transfer.manifest.get("roles", [{"id": "leader", "name": "Ведущий"}, {"id": "player", "name": "Игрок"}]) if custom else [{"id": "leader", "name": "Ведущий"}, {"id": "player", "name": "Игрок"}]
		var role_ids: Array = []
		for definition: Dictionary in definitions:
			role.add_item(str(definition.get("name", definition.id)))
			role_ids.append(str(definition.id))
		var roles: Array = options.get("cg_roles", [])
		var role_id := str(roles[i]) if i < roles.size() else ("leader" if i == 0 else "player")
		role.select(maxi(0, role_ids.find(role_id)))
		role.disabled = not Net.is_host()
		role.item_selected.connect(func(index: int):
			var next_roles: Array = options.get("cg_roles", []).duplicate()
			while next_roles.size() < members.size():
				next_roles.append("leader" if next_roles.is_empty() and role_ids.has("leader") else ("player" if role_ids.has("player") else str(role_ids[0])))
			next_roles[i] = role_ids[index]
			Net.set_setting("cg_roles", next_roles))
		row.add_child(role)
		names.add_child(row)
	var timer_row := Style.row()
	timer_row.add_child(Style.label("Время хода"))
	var timer := OptionButton.new()
	var times := [0, 30, 60, 120]
	for seconds: int in times:
		timer.add_item("Без ограничения" if seconds == 0 else "%d с" % seconds)
	timer.select(maxi(0, times.find(int(options.get("turn_time", 0)))))
	timer.disabled = not Net.is_host()
	timer.item_selected.connect(func(index: int): Net.set_setting("turn_time", times[index]))
	timer_row.add_child(timer)
	col.add_child(timer_row)
	if Net.mode == "offline" and Net.is_host():
		var row := Style.row()
		for delta: int in [-1, 1]:
			var button := Style.button("− Игрок" if delta < 0 else "+ Игрок")
			button.disabled = Net.bots <= 1 if delta < 0 else Net.bots >= 7
			button.pressed.connect(func(): Net.set_bots(Net.bots + delta))
			row.add_child(button)
		col.add_child(row)
	col.add_child(Style.label("Личные руки скрыты. Офлайн выбирайте место перед просмотром руки."))
	if Net.is_host():
		var start := Style.primary("Начать партию")
		start.disabled = custom and not Net.cg_transfer.can_start()
		start.pressed.connect(func(): _error.text = Net.start_game())
		col.add_child(start)
	else:
		col.add_child(Style.label("Ждём хоста…"))
	var back := Style.button("К выбору игры")
	LeaveGuard.wire(back, "Выйти?", "Вернуться в хаб.", back_to_hub)
	col.add_child(back)
	_error = Style.label("")
	col.add_child(_error)

func show_table() -> void:
	if Net.party_game.begins_with("custom:") and not _package_ready():
		var col := _center()
		col.add_child(Style.heading("ЗАГРУЗКА ИГРЫ"))
		col.add_child(Style.label(_download_status()))
		return
	var table := Table.new()
	table.app = self
	_replace(table)

func back_to_hub() -> void:
	if Net.mode == "offline" and Net.settings.get("cg_editor_return", false):
		Net.settings["cg_editor_return"] = false
		Net.leave()
		get_tree().change_scene_to_file.call_deferred("res://editor/main.tscn")
		return
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		_hub()

func _hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _lobby_changed() -> void:
	if Net.is_custom_game(Net.party_game):
		if not Net.in_game:
			show_lobby()
		elif not is_instance_valid(_screen) or _screen.get_script() != Table:
			show_table()

func _party_changed(id: String) -> void:
	if not Net.is_custom_game(id):
		_hub()

func _package_ready() -> bool:
	return Net.cg_transfer.verified.get(Net.multiplayer.get_unique_id(), "") == Net.cg_transfer.manifest.get("hash", "missing")

func _download_status() -> String:
	if not Net.cg_transfer.error.is_empty():
		return str(Net.cg_transfer.error)
	if _package_ready():
		if Net.is_host() and not Net.cg_transfer.can_start():
			return "Ждём загрузки игры у друзей…"
		return "Игра загружена и проверена"
	var received: int = Net.cg_transfer.progress.get(1, 0)
	var total: int = Net.cg_transfer.manifest.get("size", 0)
	return "Загружается игра: %.1f / %.1f МБ" % [received / 1048576.0, total / 1048576.0]
