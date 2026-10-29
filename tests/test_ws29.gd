extends "res://tests/test_ws_guess_reentrancy28.gd"
## WS29: адресные правила и настоящие жесты InputEvent, 720p обеих тем.
## godot --audio-driver Dummy --script res://tests/test_ws29.gd


func rules_cases() -> void:
	var players := [{"name": "А", "team": 0}, {"name": "Б", "team": 0}, {"name": "В", "team": 1}, {"name": "Г", "team": 1}]
	for catalog in ["basic", "simplified"]:
		var w := WSRules.new()
		w.new_game(players, false, 3, false, true, 29, catalog)
		var before := w.catalog_order.duplicate(true)
		var words := {}
		for cat in WSData.CATEGORIES:
			for id in before[cat]:
				words[id] = WSRules.card_word(id)
		w.set_ready(w.storytellers[0])
		check(w.catalog_order == before, "Каталог не меняется до второго «Слэм»")
		w.set_ready(w.storytellers[1])
		check((w.catalog_order != before) == (catalog == "basic"), "Базовый перемешивает; упрощённый сохраняет порядок")
		for cat in WSData.CATEGORIES:
			var ids: Array = w.catalog_order[cat].duplicate()
			ids.sort()
			var original: Array = before[cat].duplicate()
			original.sort()
			check(ids == original, "Состав категории сохранён: " + cat)
			check(w.catalog_order[cat].all(func(id): return WSRules.card_word(id) == words[id]), "Значения id неизменны: " + cat)
		var shuffled := w.catalog_order.duplicate(true)
		check(not w.set_ready(w.storytellers[0]) and w.catalog_order == shuffled, "Повторный ready не перемешивает ещё раз")
		var sparse := ["", "", "", "", "", "", "", "", "", "noun:0"]
		check(w.set_holders(w.storytellers[0], [sparse, []]), "Слово на четвёртой строке принято")
		check(w.holders[0][0] == sparse, "Пустые строки сохранены")
		check(w.get_view(w.storytellers[1]).holders[0][0] == ["", "", "", "", "", "", "", "", "", "?"], "Чужой вид сохраняет геометрию без слова")
		check(not w.set_holders((w.storytellers[0] + 1) % 2, [["noun:1"], []]), "Чужое действие отвергнуто")
		check(not w.set_holders(w.storytellers[0], [["noun:0", "noun:0"], []]), "Дубль отвергнут")
		check(not w.set_holders(w.storytellers[0], [["noun:9999"], []]), "Несуществующая карта отвергнута")
		check(not w.point(w.storytellers[0], ""), "Пустой слот не карточка для указания")
		w.set_holders(w.storytellers[0], [["", ""], []])
		check(not w.can_guess((w.storytellers[0] + 1) % 2), "Пустые слоты не разрешают догадки")
		w.time_up()
		w.advance()
		check(w.catalog_order == shuffled, "Новый раунд ждёт «Слэм» для следующего shuffle")
		for storyteller in w.storytellers:
			w.set_ready(storyteller)
		check((w.catalog_order != shuffled) == (catalog == "basic"), "Следующий «Слэм» вновь меняет только базовый каталог")


func mouse(at: Vector2, down: int = -1) -> void:
	if down < 0:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		Input.parse_input_event(motion)
	else:
		var button := InputEventMouseButton.new()
		button.position = at
		button.global_position = at
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = down == 1
		Input.parse_input_event(button)
	await process_frame


func drag(from: Vector2, to: Vector2) -> void:
	await mouse(from)
	await mouse(from, 1)
	await settle()
	for step in range(1, 9):
		await mouse(from.lerp(to, step / 8.0))
	await mouse(to, 0)
	await settle()


func slot(index: int) -> Vector2:
	return table._shelves.global_position + table._slot(0, index)


func visible_chip(exclude: Array = []) -> String:
	for id: String in table._chips:
		var button: Button = table._chips[id]
		var clip: Control = button.get_parent().get_parent()
		if not button.disabled and not exclude.has(id) and clip.get_global_rect().encloses(button.get_global_rect()):
			return id
	return ""


func run() -> void:
	await process_frame
	rules_cases()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	root.get_node("Prefs").theme_mode = "light"
	net.host_offline("word_slam")
	net.set_bots(3)
	check(net.start_game().is_empty(), "WS запущен")
	net.set_process(false)
	prepare()
	net.wslam.set_holders(2, [[], []])
	net._push_state()
	await build_app()
	table._as = 2
	table._on_state(net.view)
	await settle()
	var first := visible_chip()
	check(first != "", "Видимая карточка каталога найдена")
	var chip: Button = table._chips[first]
	await drag(chip.get_global_rect().get_center(), slot(9))
	check(net.wslam.holders[0][0].size() == 10 and net.wslam.holders[0][0][9] == first, "Каталог настоящим жестом на строку4")
	check(net.wslam.holders[0][0].slice(0, 9).all(func(id): return id == ""), "Строки1–3 остались пусты")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ws29/free-rows-light.png")
	var second := visible_chip([first])
	await drag(table._chips[second].get_global_rect().get_center(), slot(10))
	check(net.wslam.holders[0][0][10] == second, "Второй захват с первого жеста")
	await drag(slot(9), slot(10))
	check(net.wslam.holders[0][0][9] == second and net.wslam.holders[0][0][10] == first, "Соседние карточки поменялись местами")
	await drag(slot(10), slot(3))
	check(net.wslam.holders[0][0][3] == first and net.wslam.holders[0][0][9] == second, "Межстрочный перенос не сжимает другие строки")
	var before: Dictionary = net.wslam.holders.duplicate(true)
	await mouse(slot(3))
	await mouse(slot(3), 1)
	await mouse(slot(6))
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await mouse(slot(6), 0)
	await create_timer(0.3).timeout
	check(net.wslam.holders == before, "Escape отменяет перенос без изменения правил")
	await mouse(slot(3))
	await mouse(slot(3), 1)
	print("WS HOLD: ", root.gui_get_hovered_control(), " card=", table._cards[table._card_key(0, first)].get_global_rect(), " at=", slot(3), " drag=", table._cards[table._card_key(0, first)].dragging)
	check(table._cards[table._card_key(0, first)].dragging, "Удержание захватило карточку")
	paused = true
	await process_frame
	await process_frame
	check(not table._cards[table._card_key(0, first)].dragging, "Пауза отменяет захват")
	await mouse(slot(6), 0)
	paused = false
	await settle()
	check(net.wslam.holders == before, "Пауза не отправила перемещение")
	var spectator: Dictionary = net.view.duplicate(true)
	spectator.spectator = true
	table._on_state(spectator)
	await settle()
	await drag(slot(3), slot(6))
	check(net.wslam.holders == before and not table._am_storyteller(), "Зритель не переносит карточки рассказчика")
	# Второй настоящий экран, с темой до построения UI.
	app.queue_free()
	await settle()
	root.get_node("Prefs").theme_mode = "dark"
	await build_app()
	table._as = 2
	table._on_state(net.view)
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ws29/free-rows-dark.png")
	print("WS29: %d проверок, %d ошибок" % [checks, errors])
	app.queue_free()
	net.leave()
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
