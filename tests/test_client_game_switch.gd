## Клиентские переключения настоящих app/table до завершения deferred-перехода.
## --headless --audio-driver Dummy --script res://tests/test_client_game_switch.gd -- --case=0 (0..2).
## DirectAPI задаёт роль клиента2, без ENet; payload создаётся настоящими правилами с seed271027.
extends SceneTree

class ClientAPI:
	extends MultiplayerAPIExtension
	var peer: MultiplayerPeer = OfflineMultiplayerPeer.new()
	func _get_unique_id() -> int: return 2
	func _get_remote_sender_id() -> int: return 1
	func _get_peer_ids() -> PackedInt32Array: return PackedInt32Array([1])
	func _get_multiplayer_peer() -> MultiplayerPeer: return peer
	func _set_multiplayer_peer(value: MultiplayerPeer) -> void: peer = value
	func _poll() -> Error: return OK
	func _object_configuration_add(_object: Object, _configuration: Variant) -> Error: return OK
	func _object_configuration_remove(_object: Object, _configuration: Variant) -> Error: return OK
	func _rpc(_target: int, _object: Object, _method: StringName, _args: Array) -> Error: return OK

class ErrorCapture:
	extends Logger
	var stage := "подготовка"
	var entries: Array[Dictionary] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_notify: bool, error_type: int, traces: Array[ScriptBacktrace]) -> void:
		var stack: Array[String] = []
		for trace in traces:
			# Только кадры вызовов, без локальных переменных/тайных игровых данных.
			for i in trace.get_frame_count():
				stack.append("%s:%d %s" % [trace.get_frame_file(i), trace.get_frame_line(i), trace.get_frame_function(i)])
		entries.append({"stage": stage, "file": file, "line": line, "function": function,
			"code": code, "rationale": rationale, "type": error_type, "stack": stack})

var net: Node
var capture := ErrorCapture.new()
var checks := 0
var failed := 0
var sequence: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("CLIENT SWITCH НЕСОВПАДЕНИЕ: ", label)

func payload(game: String) -> Dictionary:
	var players: Array = []
	for i in 4:
		players.append({"name": "Тест%d" % i, "bot": false, "team": i % 2, "color": i})
	var rules: RefCounted
	match game:
		"wavelength":
			rules = load("res://games/wavelength/logic/wl_rules.gd").new()
			rules.new_game(players, false, 271027)
		"hues_and_cues":
			rules = load("res://games/hues_and_cues/logic/hc_rules.gd").new()
			rules.new_game(players, 0, false, 271027)
		_:
			rules = load("res://games/ready_set_bet/logic/rsb_rules.gd").new()
			rules.new_game(players, 271027)
	var v: Dictionary = rules.get_view(1, false)
	v.merge({"game": game, "game_id": game, "game_paused": false, "turn_total": 60,
		"turn_left": 60, "auto_in": 0, "clock": true}, true)
	return v

func lobby(game: String, active: bool) -> Dictionary:
	return {"party_game": game, "in_game": active, "mode": "enet", "settings": net.settings.duplicate(true),
		"members": [{"name": "Тест0", "peer": 1, "kind": "host", "team": 0, "color": 0},
			{"name": "Тест1", "peer": 2, "kind": "player", "team": 1, "color": 1}],
		"code": "", "seated": [1, 2] if active else []}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var index := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): index = arg.trim_prefix("--case=").to_int()
	if index < 0 or index > 2:
		quit(2)
		return
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.set_process(false)
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	check(not net.is_host(), "Выполняется настоящая клиентская ветка Net")
	var pairs := [["wavelength", "hues_and_cues"], ["hues_and_cues", "wavelength"], ["wavelength", "ready_set_bet"]]
	var old_game: String = pairs[index][0]
	var next_game: String = pairs[index][1]
	net.party_game = old_game
	net._apply_lobby(lobby(old_game, true))
	net._apply_state(payload(old_game))
	var app: Control = load("res://games/%s/ui/main.tscn" % old_game).instantiate()
	root.add_child(app)
	current_scene = app
	# Дать исходному столу получить в том числе deferred начальный view Wavelength.
	for i in 3: await process_frame
	var old_table: Node = app.screen
	check(is_instance_valid(old_table), "Исходный настоящий стол создан")
	check(capture.entries.is_empty(), "До переключения нет ошибок подготовки")
	net.party_game_changed.connect(func(_game: String): sequence.append("party_game_changed"))
	net.lobby_changed.connect(func(): sequence.append("lobby_changed"))
	net.game_started.connect(func(): sequence.append("game_started"))
	net.state_changed.connect(func(_v: Dictionary): sequence.append("state_changed"))
	print("CLIENT SWITCH BEGIN case=", index, " pair=", old_game, "->", next_game)
	var before := capture.entries.size()
	if index != 1:
		capture.stage = "return_lobby"
		net._apply_lobby(lobby("", false))
		check(net.view.is_empty() and not net.in_game, "Возврат очистил клиентский view до сигналов")
	capture.stage = "select_lobby"
	net._apply_lobby(lobby(next_game, false if index != 1 else true))
	check(is_instance_valid(app) and app.is_inside_tree(), "Старый app ещё в дереве до deferred перехода")
	check(is_instance_valid(old_table) and old_table.is_inside_tree(), "Старый table ещё в дереве в том же кадре")
	capture.stage = "started_before_state"
	# Штатная команда хоста синхронно вызывает подписчиков старого app.
	net._rpc_started()
	check(is_instance_valid(old_table) and old_table.is_queued_for_deletion(), "Прежний table queue_free, но ещё жив")
	capture.stage = "new_state_same_frame"
	net._apply_state(payload(next_game))
	check(net.game_id == next_game and net.view.game_id == next_game, "Net сохранил правильный новый view")
	print("CLIENT SWITCH SIGNALS ", JSON.stringify(sequence))
	var transition_errors := capture.entries.size() - before
	check(transition_errors == 0, "Ни новый game_started, ни новый view не ломают старый app/table")
	for entry in capture.entries:
		print("CLIENT SWITCH ERROR ", JSON.stringify(entry))
	print("CLIENT SWITCH RESULT case=", index, " checks=", checks, " failed=", failed,
		" transition_errors=", transition_errors, " process_alive=true")
	# Не ждём загрузки хаба: весь исследуемый интервал заканчивается до deferred смены сцены.
	# Штатный exit1 означает обнаруженное утверждение/ScriptError, а не нативный crash.
	OS.remove_logger(capture)
	quit(1 if failed or not capture.entries.is_empty() else 0)
