extends Control
## Вход, постоянное лобби и стол Clocktower. Обновления состояния не заменяют экран.
const Style := preload("res://games/blood_on_the_clocktower/ui/bc_style.gd")
const ID := "blood_on_the_clocktower"
var screen: Control
var mode := ""
var handbook: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = Style.theme()
	get_tree().root.theme = theme
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.session_closed.connect(show_menu)
	Net.lobby_changed.connect(_lobby_changed)
	Net.party_game_changed.connect(_party_changed)
	if Net.party_game == ID and Net.in_game: show_table()
	elif Net.party_game == ID and Net.in_session(): show_lobby()
	elif Net.in_session(): _go_hub()
	else: show_menu()

func _replace(node: Control, next_mode: String) -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	mode = next_mode
	screen = node
	node.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(node)

func show_menu(_message: String = "") -> void:
	if mode == "menu": return
	var root := Control.new()
	preload("res://games/blood_on_the_clocktower/ui/bc_art.gd").backdrop(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box())
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	col.add_child(Style.label("Кровь на часовой башне", Style.H1, Style.INK, true))
	col.add_child(Style.label("5–15 игроков и рассказчик · три сценария", Style.SMALL, Style.MUTED))
	col.add_child(RoomPanel.make(ID, Style.button, Style.label))
	var lan := HBoxContainer.new()
	var address := LineEdit.new()
	address.placeholder_text = "Адрес хоста локальной сети"
	address.custom_minimum_size.x = 300
	lan.add_child(address)
	var host := Style.button("Создать LAN", Style.SMALL)
	host.pressed.connect(func(): Net.host_enet(Net.PORT, ID))
	lan.add_child(host)
	var join := Style.button("Войти", Style.SMALL)
	join.pressed.connect(func(): Net.join_enet(address.text.strip_edges()))
	lan.add_child(join)
	col.add_child(lan)
	var local := Style.button("Соло-проверка разных мест")
	local.name = "SoloGame"
	local.pressed.connect(func():
		Net.host_offline(ID)
		Net.set_bots(7))
	col.add_child(local)
	var book := Style.button("Справочник")
	book.pressed.connect(show_handbook)
	col.add_child(book)
	var back := Style.button("К выбору игры", Style.SMALL)
	back.pressed.connect(_go_hub)
	col.add_child(back)
	_replace(root, "menu")

func show_lobby() -> void:
	if mode == "lobby": return
	var lobby := preload("res://games/blood_on_the_clocktower/ui/bc_lobby.gd").new()
	lobby.app = self
	_replace(lobby, "lobby")

func show_table() -> void:
	if mode == "table": return
	var table := load("res://games/blood_on_the_clocktower/ui/bc_table.gd").new() as Control
	table.app = self
	_replace(table, "table")

func show_handbook() -> void:
	if is_instance_valid(handbook):
		handbook.show()
		return
	handbook = preload("res://games/blood_on_the_clocktower/ui/bc_handbook.gd").new()
	handbook.z_index = 120
	handbook.add_to_group("pause_allowed")
	handbook.closed.connect(func(): handbook.hide())
	add_child(handbook)

func show_settings() -> void:
	var settings := preload("res://games/king_of_12/ui/settings_screen.gd").new()
	settings.ink = Style.INK
	add_child(settings)

func back_to_hub() -> void:
	if Net.is_party() and Net.is_host(): Net.return_to_party()
	else:
		Net.leave()
		_go_hub()

func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _lobby_changed() -> void:
	if Net.party_game == ID and not Net.in_game: show_lobby()

func _party_changed(id: String) -> void:
	if id != ID: _go_hub()
