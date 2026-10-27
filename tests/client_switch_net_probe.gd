## Узел двухпроцессного ENet-повтора. Логи/снимки только метаданные, никаких secret view.
extends "res://tests/test_client_game_switch.gd"

var role := OS.get_environment("CS_ROLE")
var folder := OS.get_environment("CS_OUT")
var last_command := 0
var elapsed := 0.0
var started_games: Array[String] = []
var command_error := ""

func _initialize() -> void:
	boot.call_deferred()

func boot() -> void:
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.my_name = "Проверка_" + role
	net.game_started.connect(func(): started_games.append(str(net.view.get("game", ""))))
	var port := int(OS.get_environment("CS_PORT"))
	if role == "host":
		command_error = str(net.host_enet(port, "wavelength"))
	else:
		command_error = str(net.join_enet("127.0.0.1", port))
		change_scene_to_file("res://hub/hub.tscn")

func _process(delta: float) -> bool:
	if net == null: return false
	elapsed += delta
	if elapsed < 0.05: return false
	elapsed = 0.0
	var path := folder + "/" + role + "-command.json"
	if FileAccess.file_exists(path):
		var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if c is Dictionary and int(c.id) > last_command:
			last_command = int(c.id)
			match str(c.kind):
				"start":
					net.set_bots(2)
					net.set_setting("turn_time", 0)
					command_error = net.start_game()
				"switch":
					# Все три штатные операции в одном кадре хоста, без искусственной перестановки RPC.
					net.return_to_party()
					net.select_game(str(c.game))
					net.set_bots(2)
					command_error = net.start_game()
				"quit":
					net.leave()
					if current_scene != null:
						current_scene.queue_free()
						current_scene = null
					await create_timer(0.2).timeout
					OS.remove_logger(capture)
					await root.get_node("Sfx").request_quit()
	var scene := current_scene.scene_file_path if current_scene != null else ""
	var table_game := ""
	if current_scene != null and current_scene.get("screen") != null:
		var table: Node = current_scene.screen
		if table.get("_v") is Dictionary: table_game = str(table.get("_v").get("game", ""))
	var summary := {"command": last_command, "command_error": command_error, "role": role,
		"members": net.members.size(), "places": net._gp().size() if role == "host" and net.in_game and net._game_obj() != null else 0,
		"mode": net.mode, "in_game": net.in_game, "party": net.party_game,
		"view_game": str(net.view.get("game", "")), "match": str(net.view.get("game_id", "")),
		"scene": scene, "table_game": table_game, "started_games": started_games,
		"errors": capture.entries.filter(func(e: Dictionary) -> bool: return int(e.type) != 1),
		"warnings": capture.entries.filter(func(e: Dictionary) -> bool: return int(e.type) == 1)}
	var target := folder + "/" + role + "-snapshot.json"
	var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary))
	file.close()
	DirAccess.rename_absolute(target + ".tmp", target)
	return false
