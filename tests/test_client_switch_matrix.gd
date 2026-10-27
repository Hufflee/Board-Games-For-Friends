extends "res://tests/test_client_game_switch.gd"
## Матрица настоящих игровых UI: каждой игре передаётся view её настоящих правил.
## Это проверка запуска/смены схем, не аудит карточных эффектов и не сетевая партия.

var factory: GDScript

func make_payload(game: String) -> Dictionary:
	var server: Node = factory.new()
	root.add_child(server)
	var server_path := server.get_path()
	var server_api := SceneMultiplayer.new()
	server_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	set_multiplayer(server_api, server_path)
	server.host_offline(game)
	server.set_bots(3)
	var result: String = server.start_game()
	check(result.is_empty(), "Подготовка реальных правил: " + game + " · " + result)
	var data: Dictionary = server._seat_view(1, [], 0.0, false) if result.is_empty() else {}
	server.leave()
	set_multiplayer(null, server_path)
	server.free()
	return data

func _run() -> void:
	await process_frame
	net = root.get_node("Net")
	net.set_process(false)
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	factory = GDScript.new()
	factory.source_code = "extends \"res://games/king_of_12/net/net.gd\"\nfunc _ready() -> void:\n\tset_process(false)\nfunc _send_view(_peer: int, _view: Dictionary) -> void:\n\tpass\n"
	check(factory.reload() == OK, "Тестовый хост использует настоящие методы Net")
	OS.add_logger(capture)
	var registry: GDScript = load("res://hub/games.gd")
	var visited: Array[String] = []
	for description: Dictionary in registry.LIST:
		var game: String = registry.play_id(description)
		if game in visited:
			continue
		visited.append(game)
		var data := make_payload(game)
		if data.is_empty():
			continue
		var lobby_data := lobby(game, true)
		net._apply_lobby(lobby_data)
		net._rpc_started(game, str(data.game_id))
		net._apply_state(data)
		if current_scene == null:
			var app: Control = load(str(description.scene)).instantiate()
			root.add_child(app)
			current_scene = app
		var frames := 0
		while frames < 180 and (current_scene == null or current_scene.scene_file_path != str(description.scene)):
			frames += 1
			await process_frame
		for index in 4:
			await process_frame
		check(current_scene != null and current_scene.scene_file_path == str(description.scene), "Открылась собственная сцена: " + game)
		check(net.view.get("game", "") == game and net.view.get("game_id", "") == data.game_id, "View принадлежит текущей игре: " + game)
		print("CLIENT MATRIX GAME ", game)
	var errors := capture.entries.filter(func(entry: Dictionary): return int(entry.type) != 1)
	check(errors.is_empty(), "Во всех переходах нет ошибок схем/компиляции UI")
	for entry: Dictionary in errors:
		print("CLIENT MATRIX ERROR ", JSON.stringify(entry))
	print("CLIENT MATRIX: games=", visited.size(), " checks=", checks, " failed=", failed, " script_errors=", errors.size())
	OS.remove_logger(capture)
	net.leave()
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	for index in 4:
		await process_frame
	await root.get_node("Sfx").request_quit(1 if failed else 0)
