## Уже правильный Hues root при пустом party_game; границы технических полей Diag.
## --headless --audio-driver Dummy, отдельный APPDATA; production не меняется.
extends "res://tests/test_client_game_switch_fixed.gd"

func _run() -> void:
	OS.add_logger(capture)
	net = root.get_node("Net")
	net.set_process(false)
	set_multiplayer(ClientAPI.new())
	net.mode = "enet"
	net.party_game = "hues_and_cues"
	net._apply_lobby(lobby("hues_and_cues", true))
	net._apply_state(tagged("hues_and_cues", "right-A"))
	var app := make_app("hues_and_cues")
	await frames(4)
	check(app.screen.get("_v").get("game", "") == "hues_and_cues", "Настоящий правильный Hues root готов")
	var receiver := Receiver.new()
	app.add_child(receiver)
	net.state_changed.connect(receiver.state)
	net.game_started.connect(receiver.start)
	var diag_before := diag_links()
	check(diag_before > 0, "Diag глобально подключён")
	# Fixture границы: актуальная сцена уже B, Net ещё не получил новое lobby после reset.
	net.party_game = ""
	capture.stage = "already right root"
	net._apply_lobby(lobby("hues_and_cues", true))
	check(net.is_connected("game_started", Callable(app, "_on_game_started")), "Правильная Hues app не отключена по current_scene")
	check(net.is_connected("state_changed", receiver.state), "Подписчик правильного root сохранён")
	net._rpc_started("hues_and_cues", "right-B")
	check(receiver.starts == 0, "Start всё ещё ждёт свежий view")
	var fresh := tagged("hues_and_cues", "right-B")
	net._apply_state(fresh)
	check(receiver.starts == 1 and receiver.states == 1, "Правильный root получает start/state ровно один раз")
	check(net.view == fresh and app.screen.get("_v") == fresh, "Настоящий новый Hues table получает полный правильный view")
	check(diag_links() == diag_before, "Глобальный Diag не отключён")
	await frames(4)
	check(current_scene == app and app.is_inside_tree(), "Правильный root не отправлен в Hub")
	var diag: Node = root.get_node("Diag")
	var accepted: Dictionary = diag._safe_details({"ожидаемая_партия": "x".repeat(128), "подписок": 0, "поколение": 1000000})
	check(accepted.size() == 3, "Границы128 символов и0/1e6 приняты")
	var rejected: Dictionary = diag._safe_details({"игра_пакета": "x".repeat(129), "подписок": 1000001, "поколение": -1})
	check(rejected.is_empty(), "129 символов/1e6+1/отрицательные значения отвергнуты")
	rejected = diag._safe_details({"предыдущая_игра": {"hand": "LOW_SECRET_ROOT"}, "игра_команды": 7,
		"партия_пакета": ["LOW_SECRET_ROOT"], "подписок": 1.0, "поколение": true,
		"payload": {"api_key": "LOW_SECRET_ROOT"}, "неизвестно": "LOW_SECRET_ROOT"})
	check(rejected.is_empty(), "Неизвестные payload и неверные типы всех категорий не проходят")
	diag.mark("LOW_ROOT_FILTER", {"предыдущая_игра": "wavelength", "ожидаемая_партия": "right-B", "подписок": 4,
		"payload": "LOW_SECRET_ROOT", "поколение": ["LOW_SECRET_ROOT"]})
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(diag.FLAG))
	check(marker.context.get("ожидаемая_партия") == "right-B" and marker.context.get("подписок") == 4, "Разрешённые метаданные доходят до настоящего marker")
	check(not FileAccess.get_file_as_string(diag.FLAG).contains("LOW_SECRET_ROOT") and not diag.report_text().contains("LOW_SECRET_ROOT"), "Неизвестные payload не записаны в marker/report")
	var hard_errors := capture.entries.filter(func(e: Dictionary) -> bool: return int(e.type) != 1).size()
	check(hard_errors == 0, "Нет ScriptError/engine errors")
	for entry in capture.entries: print("ROOT DIAGNOSTIC ", JSON.stringify(entry))
	print("CURRENT ROOT: checks=", checks, " failed=", failed, " errors=", hard_errors)
	net.leave()
	app.queue_free()
	current_scene = null
	await frames(4)
	OS.remove_logger(capture)
	await root.get_node("Sfx").request_quit(1 if failed or hard_errors else 0)
