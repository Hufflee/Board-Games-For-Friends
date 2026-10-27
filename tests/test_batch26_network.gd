extends Node
## Четыре настоящих ENet-участника: приватность командного чата и сохранение пати.
var role := OS.get_environment("BATCH_ROLE")
var checks := 0
var errors := 0
var ready_peers := {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func wait_for(predicate: Callable) -> bool:
	for i in 200:
		if predicate.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(3))
	Net.my_name = role
	var port := int(OS.get_environment("BATCH_PORT"))
	if role == "host":
		check(Net.host_enet(port, "wavelength") == OK, "Хост открывает ENet")
		Net.set_bots(0)
		check(await wait_for(func(): return Net.members.size() == 4), "Четыре участника подключены")
		Net.set_team(1)
		stage.rpc("teams")
		check(await wait_for(func(): return ready_peers.size() == 3), "Команды выбраны")
		check(Net.start_game() == "", "Партия запускается")
		await get_tree().create_timer(0.5).timeout
		Net.send_chat("PUBLIC")
		ready_peers.clear()
		stage.rpc("chat")
		check(await wait_for(func(): return ready_peers.size() == 3), "Командные сообщения отправлены")
		await get_tree().create_timer(0.4).timeout
		check(has_text("TEAM1") and not has_text("TEAM0"), "Хост получает только свою команду")
		ready_peers.clear()
		stage.rpc("verify")
		check(await wait_for(func(): return ready_peers.size() == 3), "Клиенты проверили приватность")
		Net.return_to_party()
		await get_tree().create_timer(0.5).timeout
		ready_peers.clear()
		stage.rpc("party")
		check(await wait_for(func(): return ready_peers.size() == 3), "Клиенты остались в пати")
		finish.rpc()
		finish()
	else:
		check(Net.join_enet("127.0.0.1", port) == OK, "Клиент подключается")

func has_text(value: String) -> bool:
	return Net.chat_log.any(func(entry): return entry.get("text", "") == value)

@rpc("authority", "reliable")
func stage(value: String) -> void:
	if value == "teams":
		Net.set_team(0 if role in ["a", "c"] else 1)
		await get_tree().create_timer(0.2).timeout
	elif value == "chat":
		check(Net.in_game and not Net.game_id.is_empty(), "Сетевой клиент знает текущую партию")
		check(Net.chat_team() == (0 if role in ["a", "c"] else 1), "Своя команда вычислена")
		if role != "c":
			Net.send_chat("TEAM0" if role == "a" else "TEAM1", "chat", true)
	elif value == "verify":
		check(has_text("PUBLIC"), "Общий чат доступен всем")
		check(has_text("TEAM0") == (role in ["a", "c"]), "Приватность первой команды")
		check(has_text("TEAM1") == (role == "b"), "Приватность второй команды")
	elif value == "party":
		check(Net.mode == "enet" and Net.party_game == "", "Выбор игры с сохранением соединения")
		check(not Net.in_game and Net.view.is_empty(), "Старое игровое состояние очищено")
		check(Net.lobby_view.get("members", []).size() == 4, "Все участники сохранились")
		check(Net.chat_team() == -1, "Командный канал вне игры недоступен")
	ack.rpc_id(1)

@rpc("any_peer", "reliable")
func ack() -> void:
	ready_peers[multiplayer.get_remote_sender_id()] = true

@rpc("authority", "reliable")
func finish() -> void:
	print("NETWORK ", role, " Проверок: ", checks, ", ошибок: ", errors)
	get_tree().quit(1 if errors else 0)
