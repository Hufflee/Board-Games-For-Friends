extends "res://tests/test_the_gang_ui.gd"
## Узкая проверка окон без повторения полной UI-партии; настоящие клики.

func _run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(9)
	check(net.start_game().is_empty(), "Подготовлены десять мест")
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await create_timer(1.0).timeout
	var preferences := root.get_node("Prefs")
	for mode in ["light", "dark"]:
		preferences.theme_mode = mode
		preferences.changed.emit()
		await frames(15)
		await pick_seat(9)
		await click(app.find_child("PeekCards", true, false))
		await shot("table-10-" + mode)
		await click(app.find_child("Rules", true, false))
		await shot("rules-" + mode)
		await click(app.find_child("CloseRules", true, false))
		await click(app.find_child("Settings", true, false))
		await shot("settings-" + mode)
		await click(app.find_child("CloseSettings", true, false))
	print("THE GANG POPUPS: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
