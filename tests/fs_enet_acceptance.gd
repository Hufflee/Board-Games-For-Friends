extends SceneTree
## Два настоящих процесса Net/ENet. Управление JSON-командами из build/fs_acceptance.
## FS_ROLE=host|client, FS_PORT=24687, FS_RUN=имя каталога; APPDATA задаёт запускающий скрипт.
var net: Node
var role := OS.get_environment("FS_ROLE")
var folder := "res://build/fs_acceptance/" + OS.get_environment("FS_RUN")
var last_command := -1
var elapsed := 0.0
var journal: FileAccess

func _initialize() -> void:
	boot.call_deferred()

func boot() -> void:
	net = root.get_node("Net")
	DirAccess.make_dir_recursive_absolute(folder)
	journal = FileAccess.open(folder + "/" + role + "-states.jsonl", FileAccess.WRITE)
	net.my_name = "Проверка-хост" if role == "host" else "Проверка-клиент"
	net.state_changed.connect(on_state)
	net.chat_received.connect(on_chat)
	var port := int(OS.get_environment("FS_PORT"))
	var result: int = net.host_enet(port, "four_souls") if role == "host" else net.join_enet("127.0.0.1", port)
	print("ПОДКЛЮЧЕНИЕ ", role, " ", result, " ПРОФИЛЬ ", OS.get_user_data_dir())

func on_state(view: Dictionary) -> void:
	journal.store_line(JSON.stringify(view))
	journal.flush()

func on_chat(entry: Dictionary) -> void:
	var output := FileAccess.open(folder + "/" + role + "-chat.jsonl", FileAccess.READ_WRITE)
	if output == null:
		output = FileAccess.open(folder + "/" + role + "-chat.jsonl", FileAccess.WRITE)
	output.seek_end()
	output.store_line(JSON.stringify(entry))

func _process(delta: float) -> bool:
	if net == null:
		return false
	elapsed += delta
	if elapsed < 0.025:
		return false
	elapsed = 0.0
	var path := folder + "/" + role + "-command.json"
	if FileAccess.file_exists(path):
		var command = JSON.parse_string(FileAccess.get_file_as_string(path))
		if command is Dictionary and int(command.id) > last_command:
			last_command = int(command.id)
			print("КОМАНДА ", JSON.stringify(command))
			match str(command.kind):
				"start": print("СТАРТ ", net.start_game())
				"pause": net.set_paused(bool(command.arg))
				"chat": net.send_chat(str(command.arg))
				"leave": net.leave()
				"join": net.join_enet("127.0.0.1", int(OS.get_environment("FS_PORT")))
				"quit": quit()
				_: net.send_action(str(command.kind), integer_arguments(command.get("arg")))
	var snapshot := {"command":last_command,"in_game":net.in_game,"members":net.members.size(),"view":net.view}
	if role == "host" and net.fours != null:
		# Только наблюдение для проверки приватности, без записи в объект правил.
		snapshot["audit_hands"] = net.fours.hands
		snapshot["disconnected"] = net.disconnected
		snapshot["seat_peers"] = net.seat_peers
		snapshot["audit_players"] = net.fours.players
	var out := FileAccess.open(folder + "/" + role + "-snapshot.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(snapshot))
	out.close()
	return false

## JSON читает числа как float; UI отправляет целочисленные индексы и id карт.
func integer_arguments(value):
	if value is float:
		return int(value)
	if value is Dictionary:
		for key in value:
			value[key] = integer_arguments(value[key])
	if value is Array:
		for i in value.size():
			value[i] = integer_arguments(value[i])
	return value
