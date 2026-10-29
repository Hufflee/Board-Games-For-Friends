extends "res://tests/test_ws_guess_reentrancy28.gd"
## WS29: интеграция настройки Net, видимый порядок каталога и лобби 720p обеих тем.


func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("word_slam")
	net.set_bots(3)
	net.set_process(false)
	check(net.settings.get("ws_catalog", "") == "basic", "Net по умолчанию выбирает базовый каталог")
	for catalog in ["simplified", "basic"]:
		net.set_setting("ws_catalog", catalog)
		check(net.start_game().is_empty(), "Net запускает режим " + catalog)
		check(net.wslam.catalog_mode == catalog, "Настройка дошла до правил " + catalog)
		var initial: Dictionary = net.wslam.catalog_order.duplicate(true)
		for storyteller in net.wslam.storytellers:
			net.wslam.set_ready(storyteller)
		net._push_state()
		await build_app()
		table._as = net.wslam.storytellers[0]
		table._on_state(net.view)
		await settle()
		var shown: Array = table._chips.keys()
		var expected: Array = []
		for cat in WSData.CATEGORIES:
			expected.append_array(net.wslam.catalog_order[cat])
		check(shown == expected, "Видимый каталог следует порядку хоста " + catalog)
		check((initial != net.wslam.catalog_order) == (catalog == "basic"), "Net сохраняет различие режимов " + catalog)
		app.queue_free()
		await settle()
		net.end_game()
	for theme_mode in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = theme_mode
		app = load("res://games/word_slam/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		var catalog_buttons := 0
		for button: Button in app.screen.find_children("*", "Button", true, false):
			if button.text in ["Базовый · перемешивать", "Упрощённый · по порядку", "Ворд! Слэм!"]:
				catalog_buttons += 1
				check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "Кнопка лобби видима: " + button.text)
		check(catalog_buttons == 3, "Два режима и старт присутствуют в лобби")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/ws29/lobby-%s.png" % theme_mode)
		app.queue_free()
		await settle()
	print("WS29 SETTINGS: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
