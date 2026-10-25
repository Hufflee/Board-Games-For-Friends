extends Node
## Два процесса ENet: PAUSE_PEER=host / client, порт 24624.
## Запуск: Godot --headless --path . res://tests/test_pause_network.tscn
## Проверяет паузу/продолжение всех игр, полномочия клиента и остановку часов.

var errors := 0
var checks := 0
var acknowledged := false

func check(ok: bool, message: String) -> void:
	checks += 1
	print("ПРОВЕРКА ", message, " = ", ok)
	if not ok:
		errors += 1
		push_error(message)

func _ready() -> void:
	get_tree().create_timer(100).timeout.connect(func(): get_tree().quit(2))
	if OS.get_environment("PAUSE_PEER") == "client":
		check(Net.join_enet("127.0.0.1", 24624) == OK, "подключение клиента")
		return
	check(Net.host_enet(24624) == OK, "запуск хоста")
	while Net.members.size() < 2:
		await get_tree().process_frame
	Net.set_bots(2)
	for game: String in ["king_of_12", "perudo", "wavelength", "dangerous_words", "hues_and_cues",
		"ready_set_bet", "word_slam", "tip_top", "tip_top_18", "not_a_hat", "gloom", "brodilka",
		"phantom_ink", "four_souls", "stillion"]:
		Net.party_game = game
		check(Net.start_game() == "", game + ": старт")
		Net.set_paused(true)
		var phase_time: float = Net._phase_time
		var frozen: Dictionary = Net._seat_view(0, [], 0.0, false).duplicate(true)
		acknowledged = false
		probe.rpc(true, game)
		while not acknowledged:
			await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		check(Net.paused and Net._phase_time == phase_time, game + ": клиент не снял паузу, часы стоят")
		check(Net._seat_view(0, [], 0.0, false) == frozen, game + ": действие клиента на паузе не меняет стол")
		Net.set_paused(false)
		acknowledged = false
		probe.rpc(false, game)
		while not acknowledged:
			await get_tree().process_frame
		Net.end_game()
		await get_tree().process_frame
	finish.rpc()
	await get_tree().create_timer(0.3).timeout
	print("СЕТЕВАЯ ПАУЗА ХОСТ: ", checks, "/", errors)
	get_tree().quit(1 if errors else 0)

@rpc("authority", "reliable")
func probe(on: bool, game: String) -> void:
	await get_tree().create_timer(0.15).timeout
	check(bool(Net.view.get("game_paused", false)) == on and Net.view.get("game") == game,
		game + ": состояние паузы на клиенте " + str(on))
	if on:
		Net.set_paused(false)
		check(bool(Net.view.get("game_paused", false)), game + ": клиент не управляет паузой")
		Net.send_action("roll")
	ack.rpc_id(1)

@rpc("any_peer", "reliable")
func ack() -> void:
	if multiplayer.is_server():
		acknowledged = true

@rpc("authority", "reliable")
func finish() -> void:
	print("СЕТЕВАЯ ПАУЗА КЛИЕНТ: ", checks, "/", errors)
	get_tree().quit(1 if errors else 0)
