## Узкое воспроизведение: WL app остаётся меню после leave, затем подключение к Hues.
## --headless --audio-driver Dummy --script res://tests/test_client_switch_rejoin.gd, свой APPDATA.
extends "res://tests/test_client_game_switch_fixed.gd"

func _run() -> void:
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.set_process(false)
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	net.party_game = "wavelength"
	net._apply_lobby(lobby("wavelength", true))
	net._apply_state(tagged("wavelength", "rejoin-A"))
	var app := make_app("wavelength")
	await frames(4)
	check(not net.is_host() and app.screen.get("_v").get("game", "") == "wavelength", "Исходный настоящий WL стол клиента")
	# Штатный disconnect вызывает leave и session_closed; настоящая app показывает меню.
	net._on_server_disconnected()
	await frames(4)
	var menu: Control = app.screen
	check(net.party_game == "" and net.mode == "" and net.view.is_empty(), "Leave очистил party_game/mode/view")
	check(current_scene == app and menu.get("_v") == null, "Прежняя WL app остаётся настоящим меню")
	check(capture.entries.is_empty(), "До повторного подключения нет ошибок")
	var observer := Receiver.new()
	app.add_child(observer)
	net.game_started.connect(observer.start)
	net.state_changed.connect(observer.state)
	capture.stage = "повторное подключение при previous_game пусто"
	# Только роль/транспортный fixture; реальные ENet-процессы в этой фазе не нужны.
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	net._apply_lobby(lobby("hues_and_cues", true))
	check(app.is_inside_tree(), "App ещё не вышла до deferred перехода")
	net._rpc_started("hues_and_cues", "rejoin-B")
	check(app.screen == menu, "До fresh view started не пересоздал старый стол")
	var fresh := tagged("hues_and_cues", "rejoin-B")
	net._apply_state(fresh)
	check(net.view == fresh and net.game_id == "rejoin-B", "Net хранит правильный fresh Hues view")
	check(observer.starts == 0 and observer.states == 0, "Старая app не получает start/state другой игры")
	check(app.screen == menu, "В старой app не создаётся WL стол для Hues")
	var script_errors := capture.entries.filter(func(e: Dictionary) -> bool: return int(e.type) == 2).size()
	check(script_errors == 0, "Нет ошибок схемы при rejoin")
	for entry in capture.entries:
		print("REJOIN DIAGNOSTIC ", JSON.stringify(entry))
	print("REJOIN RESULT: checks=", checks, " failed=", failed, " script_errors=", script_errors,
		" old_starts=", observer.starts, " old_states=", observer.states, " process_alive=true")
	OS.remove_logger(capture)
	quit(1 if failed or script_errors else 0)
