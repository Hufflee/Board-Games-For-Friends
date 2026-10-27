## Положительный повтор клиентского lifecycle. CS_CASE=0..3, Dummy/свой APPDATA.
## Наследует только fixture/view/logger исходного repro; baseline не изменён.
extends "res://tests/test_client_game_switch.gd"

class Receiver:
	extends Node
	var states := 0
	var starts := 0
	var navigation := 0
	func state(_v: Dictionary) -> void: states += 1
	func start() -> void: starts += 1
	func party(_game: String) -> void: navigation += 1

var starts := 0
var states := 0
var start_games: Array[String] = []

func tagged(game: String, match_id: String) -> Dictionary:
	var v := payload(game)
	v.game_id = match_id
	return v

func make_app(game: String) -> Control:
	var app: Control = load("res://games/%s/ui/main.tscn" % game).instantiate()
	root.add_child(app)
	current_scene = app
	return app

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func diag_links() -> int:
	var total := 0
	for signal_name in ["state_changed", "lobby_changed", "game_started"]:
		for link in net.get_signal_connection_list(signal_name):
			if link.callable.get_object() == root.get_node("Diag"): total += 1
	return total

func transition(index: int) -> void:
	var pairs := [["wavelength", "hues_and_cues"], ["hues_and_cues", "wavelength"], ["wavelength", "ready_set_bet"]]
	var old_game: String = pairs[index][0]
	var next_game: String = pairs[index][1]
	net.party_game = old_game
	net._apply_lobby(lobby(old_game, true))
	net._apply_state(tagged(old_game, "исходная"))
	var app := make_app(old_game)
	await frames()
	var table: Node = app.screen
	var receiver := Receiver.new()
	app.add_child(receiver)
	net.state_changed.connect(receiver.state)
	net.game_started.connect(receiver.start)
	net.party_game_changed.connect(receiver.party)
	var diag_before := diag_links()
	check(diag_before > 0, "Diag действительно подключён до ухода")
	check(capture.entries.is_empty(), "Исходная app/table без ScriptError")
	capture.stage = "смена игры"
	if index != 1: net._apply_lobby(lobby("", false))
	net._apply_lobby(lobby(next_game, index == 1))
	check(net.view.is_empty(), "Даже active lobby новой игры очищает старый cache")
	check(is_instance_valid(app) and app.is_inside_tree(), "App ещё жива до deferred перехода")
	check(app.screen == table and not table.is_queued_for_deletion(), "Уход не пересоздал прежний стол")
	check(receiver.navigation == 1, "Старому UI разрешён ровно один навигационный выход")
	var previous_starts := starts
	net._rpc_started(next_game, "новая")
	check(starts == previous_starts, "Started ждёт соответствующий свежий view")
	check(receiver.starts == 0 and app.screen == table, "Старый UI не получает started и не создаёт стол")
	var fresh := tagged(next_game, "новая")
	net._apply_state(fresh)
	check(net.view == fresh and net.game_id == "новая", "Сохранён полный правильный новый view")
	check(starts == previous_starts + 1 and start_games.back() == next_game, "Started видит уже новую схему")
	check(receiver.states == 0 and receiver.starts == 0, "Ни одного чужого события старому UI")
	check(diag_links() == diag_before, "Глобальный Diag не отключён")
	# Ждём настоящий deferred выход через Hub и автоподхват выбранной игры.
	for i in 360:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == "res://games/%s/ui/main.tscn" % next_game:
			break
	check(current_scene != null and current_scene.scene_file_path == "res://games/%s/ui/main.tscn" % next_game, "Hub подхватил уже выбранную новую игру")
	await frames(5)
	if current_scene != null and current_scene.get("screen") != null:
		var new_table: Node = current_scene.screen
		check(new_table.get("_v") is Dictionary and new_table.get("_v").get("game", "") == next_game, "Настоящий новый стол получил только свою схему")
	else:
		check(false, "Новый стол создан")

func boundaries() -> void:
	var game := "wavelength"
	net.party_game = game
	net._apply_lobby(lobby(game, true))
	net._apply_state(tagged(game, "A"))
	var app := make_app(game)
	await frames()
	var count := starts
	capture.stage = "samegame новый match"
	net._rpc_started(game, "B")
	check(net.view.is_empty() and starts == count, "Samegame не запускается со старым match cache")
	var b := tagged(game, "B")
	net._apply_state(b)
	check(starts == count + 1 and net.view == b, "Samegame запускается со свежим view B")
	await frames()
	capture.stage = "новый раунд"
	var round_view := b.duplicate(true)
	# Явный transport-fixture: меняется только публичный номер раунда/хода, не игровые правила.
	round_view.turn_no = int(b.turn_no) + 1
	net._apply_state(round_view)
	check(starts == count + 1 and net.view.turn_no == round_view.turn_no, "Новый ход не порождает game_started")
	capture.stage = "legacy started"
	net._rpc_started()
	check(net.view.is_empty() and starts == count + 1, "Legacy без аргументов тоже ждёт view")
	var c := tagged(game, "C")
	net._apply_state(c)
	check(starts == count + 2 and net.view == c, "Legacy получает свежий view перед started")
	await frames()
	capture.stage = "stale payload"
	var state_count := states
	net._apply_state(tagged("hues_and_cues", "чужая"))
	net._rpc_started(game, "D")
	net._apply_state(tagged(game, "C"))
	check(states == state_count and net.view.is_empty(), "Чужая игра и прошлый match заблокированы до state emit")
	var d := tagged(game, "D")
	net._apply_state(d)
	check(starts == count + 3 and net.view == d, "Только ожидаемый match D принят")
	net._rpc_started("hues_and_cues", "чужая")
	check(net.view == d and starts == count + 3, "Старый started другой игры игнорируется")
	await frames()
	capture.stage = "state before started"
	net._rpc_end_game()
	var e := tagged(game, "E")
	net._apply_state(e)
	check(starts == count + 3 and net.view == e, "State перед started сохраняется без раннего start")
	# Уже новая app появляется после fresh cache, до команды started.
	app.free()
	app = make_app(game)
	await frames()
	check(app.screen.get("_v").get("game_id", "") == "E", "Already-new app читает свежий cache E")
	net._rpc_started(game, "E")
	check(starts == count + 4 and net.view == e, "Started с ID использует уже полученный view без очистки")
	await frames()
	check(app.screen.get("_v").get("game_id", "") == "E", "Новый стол после started остаётся на собственной схеме E")

func _run() -> void:
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.set_process(false)
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	check(not net.is_host(), "Роль client2")
	net.game_started.connect(func():
		starts += 1
		start_games.append(str(net.view.get("game", ""))))
	net.state_changed.connect(func(_v: Dictionary): states += 1)
	var index := int(OS.get_environment("CS_CASE"))
	if index < 3: await transition(index)
	else: await boundaries()
	await frames(5)
	var hard_errors := capture.entries.filter(func(e: Dictionary) -> bool: return not (int(e.type) == 1 and e.code == "Godot 3.x SpatialMaterial remapped parameter not found: specular" and e.file == "scene/resources/material.cpp")).size()
	check(hard_errors == 0, "Нет ScriptError во всём сценарии и deferred переходах")
	for entry in capture.entries: print("CLIENT FIXED ERROR ", JSON.stringify(entry))
	print("CLIENT FIXED: case=", index, " checks=", checks, " failed=", failed, " errors=", hard_errors, " warnings=", capture.entries.size() - hard_errors)
	capture.stage = "штатное завершение"
	net.leave()
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await frames(5)
	OS.remove_logger(capture)
	await root.get_node("Sfx").request_quit(1 if failed or hard_errors > 0 else 0)
