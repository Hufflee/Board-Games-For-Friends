extends SceneTree
## Узел трёхпроцессной проверки Net/ENet The Gang; команды и атомарные снимки в build.
var net: Node
var role := OS.get_environment("TG_ROLE")
var folder := "res://build/the_gang_research/enet"
var last_id := -1
var elapsed := 0.0

func _initialize() -> void:
	_boot.call_deferred()

func _boot() -> void:
	net = root.get_node("Net")
	net.my_name = role
	DirAccess.make_dir_recursive_absolute(folder)
	net.state_changed.connect(func(view: Dictionary):
		var journal := FileAccess.open(folder + "/" + role + "-views.jsonl", FileAccess.READ_WRITE)
		if journal == null:
			journal = FileAccess.open(folder + "/" + role + "-views.jsonl", FileAccess.WRITE)
		journal.seek_end()
		journal.store_line(JSON.stringify(view)))
	var port := int(OS.get_environment("TG_PORT"))
	if role == "host":
		net.host_enet(port, "the_gang")
	else:
		net.join_enet("127.0.0.1", port)

func _process(delta: float) -> bool:
	if net == null:
		return false
	elapsed += delta
	if elapsed < 0.05:
		return false
	elapsed = 0
	var command_path := folder + "/" + role + "-command.json"
	if FileAccess.file_exists(command_path):
		var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(command_path))
		if command is Dictionary and int(command.get("id", -1)) > last_id:
			last_id = int(command.id)
			match str(command.kind):
				"start": net.start_game()
				"pause": net.set_paused(bool(command.arg))
				"setting": net.set_setting(str(command.arg.key), int(command.arg.value))
				"leave": net.leave()
				"join": net.join_enet("127.0.0.1", int(OS.get_environment("TG_PORT")))
				"party": net.return_to_party()
				"quit":
					net.leave()
					await root.get_node("Sfx").request_quit()
				_:
					var argument: Dictionary = {}
					for key: String in command.get("arg", {}):
						argument[key] = int(command.arg[key])
					net.send_action(str(command.kind), argument)
	var snapshot := {"command": last_id, "in_game": net.in_game, "party": net.party_game, "mode": net.mode, "lobby": net.lobby_view, "view": net.view}
	if role == "host":
		snapshot["members"] = net.members.size()
		snapshot["seat_peers"] = net.seat_peers
		snapshot["disconnected"] = net.disconnected
		if net.gang != null:
			snapshot["audit_hands"] = net.gang.hands
	var target := folder + "/" + role + "-snapshot.json"
	var output := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	output.store_string(JSON.stringify(snapshot))
	output.close()
	DirAccess.rename_absolute(target + ".tmp", target)
	return false
