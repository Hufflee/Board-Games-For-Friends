extends SceneTree
## Экран победы (06.11): аватарки Steam во всех играх, включая Мачи Коро и Clocktower (раньше там всегда
## рисовался цветной кружок). Место без steam_id во view находит аватар через участника пати с тем же ником.
## Запуск с окном: godot --audio-driver Dummy --path . --script res://tests/test_victory_avatars.gd
var checks := 0
var errors := 0
var net: Node


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("machi_koro")
	check(net.start_game() == "", "партия Мачи Коро подготовлена")
	net.set_process(false)
	var rules: Object = net.mk
	var face := load("res://games/brodilka/art/cards/pawn_3.png") as Texture2D
	net._avatars[223344] = face
	net._avatars[223345] = face
	rules.players[0].steam_id = 223344
	rules.players[1].erase("steam_id")
	rules.players[1].name = "Друг без id"
	net.members[77] = {"name": "Друг без id", "steam_id": 223345, "color": 2}
	rules.phase = "game_over"
	rules.winner = 0
	rules.revision += 1
	net.steam_ok = true
	net._push_state()
	var app: Control = load("res://games/machi_koro/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await create_timer(1.2).timeout
	var screen: Control = app.find_child("VictoryScreen", true, false)
	check(screen != null, "экран победы открыт")
	if screen != null:
		var winner: Control = screen._cards[0]
		var avatar: TextureRect = winner.get_node("Avatar")
		check(avatar.texture == face, "у победителя аватар Steam, а не кружок")
		check(winner.get_node_or_null("Initials") == null or not winner.get_node("Initials").visible, "инициалы не рисуются поверх аватара")
		var other: Control = screen._cards[1]
		check((other.get_node("Avatar") as TextureRect).texture == face, "место без steam_id нашло аватар участника пати по нику")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
		root.get_texture().get_image().save_png("res://build/shots/victory_avatars_mk.png")
	net.members.erase(77)
	print("VICTORY AVATARS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
