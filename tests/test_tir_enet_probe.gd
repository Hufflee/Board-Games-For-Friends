extends SceneTree
## Узел ограниченного ENet-прогона: JSON-команды и атомарные снимки для runner.
var net: Node
var role := OS.get_environment("TR_ROLE")
var folder := OS.get_environment("TR_OUT")
var last_command := -1
var clock := 0.0

func _init() -> void:
	_boot.call_deferred()

func _boot() -> void:
	net = root.get_node("Net")
	net.my_name = role
	if role == "host":
		net.host_enet(23592, "things_in_rings")
	else:
		net.join_enet("127.0.0.1", 23592)

func _process(delta: float) -> bool:
	if net == null:
		return false
	clock += delta
	if clock < 0.05:
		return false
	clock = 0
	var path := folder + "/" + role + "-command.json"
	if FileAccess.file_exists(path):
		var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.get("id", -1)) > last_command:
			last_command = int(command.id)
			var argument: Dictionary = command.get("arg", {})
			match str(command.kind):
				"start":
					net.start_game()
				"setting":
					net.set_setting(str(argument.key), int(argument.value) if argument.value is float else argument.value)
				"leave":
					net.leave()
				"rejoin":
					net.join_enet("127.0.0.1", 23592)
				"quit":
					net.leave()
					quit()
				_:
					for key: String in ["revision", "mask", "card", "seat"]:
						if argument.has(key):
							argument[key] = int(argument[key])
					net.send_action(str(command.kind), argument)
	var state := {"command": last_command, "view": net.view, "members": net.members.size(), "in_game": net.in_game}
	if role == "host" and net.tir != null:
		state["audit"] = {"hands": net.tir.hands, "rules": net.tir.secret_rules, "phase": net.tir.phase, "disconnected": net.disconnected}
	var target := folder + "/" + role + "-snapshot.json"
	var output := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	output.store_string(JSON.stringify(state))
	output.close()
	DirAccess.rename_absolute(target + ".tmp", target)
	return false
