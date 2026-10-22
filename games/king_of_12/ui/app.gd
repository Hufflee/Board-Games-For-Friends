extends Control
## Корневой экран: переключает меню, лобби и стол.
##
## Отладочные аргументы (после «--»):
##   --demo            партия ботов без участия человека
##   --shots=<папка>   сохранять скриншоты каждые 1.5 с (вместе с --demo)
##   --host-ip / --join-ip=<адрес>   быстрый тест по сети

const MenuScreen := preload("res://games/king_of_12/ui/menu.gd")
const LobbyScreen := preload("res://games/king_of_12/ui/lobby.gd")
const TableScreen := preload("res://games/king_of_12/ui/table.gd")
const RulesScreen := preload("res://games/king_of_12/ui/rules_screen.gd")
const SettingsScreen := preload("res://games/king_of_12/ui/settings_screen.gd")
const StatsScreen := preload("res://games/king_of_12/ui/stats_screen.gd")

var screen: Control
var _shots_dir := ""
var _shot_no := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = K12UI.theme()
	add_child(K12Tavern.new(false))
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(show_table)
	Net.session_closed.connect(func(reason): show_menu(reason))
	Net.game_ended.connect(show_lobby)
	Net.party_game_changed.connect(_on_party_game)
	Sfx.start_music()
	Sfx.set_playlist([])  # музыка таверны
	# пришли со стартового экрана с уже открытой сессией (приглашение Steam / вход по коду)
	if Net.is_party() and Net.party_game != "king_of_12" and not Net.lobby_view.is_empty():
		_go_hub()
	elif Net.in_game or not Net.view.is_empty():
		show_table()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()
	_handle_debug_args()


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
	screen = s
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(s)


func show_menu(message: String = "") -> void:
	var m := MenuScreen.new()
	m.app = self
	m.message = message
	_set_screen(m)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.app = self
	_set_screen(l)


func show_table() -> void:
	var t := TableScreen.new()
	t.app = self
	_set_screen(t)


func show_rules() -> void:
	var r := RulesScreen.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)


func show_settings() -> void:
	add_child(SettingsScreen.new())


func show_stats() -> void:
	add_child(StatsScreen.new())


## Обучающая партия: двое неторопливых ботов, подсказки на каждом шаге.
func start_tutorial() -> void:
	Net.host_offline()
	Net.tutorial = true
	Net.bot_delay = 1.6
	Net.set_setting("deck_mode", "first")
	Net.set_setting("promo", "")
	Net.set_bots(2)
	Net.start_game()
	Net.auto_advance_time = 600.0


## Вернуться на стартовый экран со списком игр. Хост пати уводит туда всех (пати сохраняется).
func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()  # _on_party_game откроет стартовый экран
		return
	Net.leave()
	_go_hub()


## Выйти из лобби/партии: участник пати покидает её, хост — уводит всех к выбору игры,
## в игре с ботами — просто в меню игры.
func back_to_menu() -> void:
	if Net.is_party():
		back_to_hub()
		return
	Net.leave()
	show_menu()


## Покинуть пати совсем (для участника, не хоста).
func leave_party() -> void:
	Net.leave()
	_go_hub()


func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)


func _on_party_game(game_id: String) -> void:
	if game_id != "king_of_12":
		_go_hub()


func _on_lobby_changed() -> void:
	if Net.is_party() and Net.party_game != "king_of_12":
		_go_hub()
		return
	if not Net.in_game and not (screen is LobbyScreen) and Net.in_session():
		show_lobby()


func _handle_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			Net.my_name = a.trim_prefix("--name=")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots_dir = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	var args := OS.get_cmdline_user_args()
	if args.has("--demo"):
		Net.auto_advance_time = 2.5
		Net.host_offline()
		Net.set_bots(3)
		Net.start_game()
		Net.rules.players[0]["bot"] = true
		Net.seat_peers[0] = 1  # человек остаётся зрителем на месте 0
	elif args.has("--host-ip"):
		Net.host_enet()
	elif args.has("--steam-host"):
		Net.host_steam()
	elif args.has("--offline-lobby"):
		Net.host_offline()
	if args.has("--input-test"):
		var dbg: Node = load("res://games/king_of_12/ui/debug_input.gd").new()
		dbg.app = self
		dbg.shots_dir = _shots_dir
		_shots_dir = ""
		add_child(dbg)
	if args.has("--show-rules"):
		show_rules()
	for a in args:
		if a.begins_with("--autostart="):
			var need := int(a.trim_prefix("--autostart="))
			Net.lobby_changed.connect(func():
				if Net.is_host() and not Net.in_game and Net.members.size() >= need:
					Net.start_game.call_deferred())
		elif a.begins_with("--join-ip="):
			Net.join_enet(a.trim_prefix("--join-ip="))
	if _shots_dir != "":
		var t := Timer.new()
		t.wait_time = 0.5
		t.autostart = true
		t.timeout.connect(_take_shot)
		add_child(t)


func _take_shot() -> void:
	_shot_no += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%03d.png" % [_shots_dir, _shot_no])
	var max_shots := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-max="):
			max_shots = int(a.trim_prefix("--shots-max="))
	if _shot_no >= max_shots or (Net.rules != null and Net.rules.phase == "game_over" and _shot_no > 3):
		get_tree().quit()
