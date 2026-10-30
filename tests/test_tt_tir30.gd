extends "res://tests/test_focus29_remaining.gd"
## Регрессия пакета30.10: геометрия вопроса/номера и реальная непрерывная отправка ответов.

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tt_tir30/" + label + ".png")

func run() -> void:
	await process_frame
	net = root.get_node("Net")
	root.content_scale_size = Vector2i.ZERO
	await start("tip_top")
	# Длинные крайности воспроизводили раздувание правой колонки за экран.
	net.tiptop.card = [["Как вы встретите Новый год на Северном полюсе?", "наименее праздничного", "наиболее праздничного"], ["Какой подарок вы выберете?", "самого обычного", "самого удивительного"]]
	net._push_state()
	table._theme_key = ""
	table._right_key = ""
	table._on_state(net.view)
	for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1024, 768)]:
		root.size = dims
		await settle()
		print("GEOM ", dims, " table=", table.size, " right=", table._right.get_global_rect(), " theme=", table._theme_panel.get_global_rect(), " edit=", entry().get_global_rect())
		await shot("tt-answer-%dx%d" % [dims.x, dims.y])
		check(Rect2(Vector2.ZERO, table.size).encloses(table._right.get_global_rect()), "Номер и ответ внутри экрана")
		var rich: RichTextLabel = table._theme_panel.find_children("*", "RichTextLabel", true, false)[0]
		check(rich.size.y > 24 and rich.size.x > 100, "Вопрос имеет видимую площадь")
	root.size = Vector2i(1280, 720)
	await settle()
	var other: Button
	for row: Node in table._players_box.get_children():
		if row.get_index() == table._as + 1:
			continue
		for button: Node in row.get_children():
			if button is Button and button.text == "за него":
				other = button
	entry().text = "Чужой черновик"
	await click(other)
	check(entry().has_focus(), "Горячее место получает фокус после кнопки за него")
	check(entry().text.is_empty(), "Черновик другого места не копируется")
	await common()
	await stop()
	await tt_themes()
	await tir_hand()
	print("TT TIR30: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)

func tt_themes() -> void:
	for adult: bool in [false, true]:
		root.get_node("Prefs").theme_mode = "dark" if adult else "light"
		net.host_offline("tip_top_18" if adult else "tip_top")
		net.set_bots(3)
		net.set_setting("tt_expert", adult)
		check(net.start_game().is_empty(), "Создан выбор темы")
		net.set_process(false)
		net.tiptop.card = [["Как вы встретите Новый год на Северном полюсе?", "наименее праздничного", "наиболее праздничного"], ["Что вы скажете космонавту перед полётом на другую планету?", "самого скучного", "самого невероятного"]]
		net._push_state()
		app = load("res://games/tip_top/ui/tt_app.gd").new()
		app.adult = adult
		root.add_child(app)
		current_scene = app
		await settle()
		table = app.screen
		for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768)]:
			root.size = dims
			await settle()
			for rich: RichTextLabel in table._theme_panel.find_children("*", "RichTextLabel", true, false):
				check(rich.size.y >= rich.get_content_height(), "Обе темы полностью видимы после resize")
			check(table._theme_panel.get_global_rect().end.y < table._track.position.y, "Выбор тем не перекрывает дорожку")
			await shot("tt-theme-%s-%dx%d" % ["adult" if adult else "base", dims.x, dims.y])
		var choices: Array[Node] = table._theme_panel.find_children("*", "Button", true, false)
		await click(choices[1])
		check(net.tiptop.phase == "answer" and entry() != null and entry().has_focus(), "Клик темы после resize открывает доступный ввод")
		root.size = Vector2i(1280, 720)
		await settle()
		await shot("tt-selected-%s-1280x720" % ["adult" if adult else "base"])
		for seat: int in net.tiptop.players.size():
			if seat != net.tiptop.captain:
				net.tiptop.answer(seat, "Ответ игрока %d" % seat)
		net._push_state()
		for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768)]:
			root.size = dims
			await create_timer(0.35).timeout
			for card: Control in table._cards.values():
				check(card.get_global_rect().position.y >= table._theme_panel.get_global_rect().end.y + 8, "Карты ответов не закрывают вопрос")
			check(Rect2(Vector2.ZERO, table.size).encloses(table._right.get_global_rect()), "Панель раскладки внутри окна")
			await shot("tt-order-%s-%dx%d" % ["adult" if adult else "base", dims.x, dims.y])
		await stop()

func tir_hand() -> void:
	game = "things_in_rings"
	for mode: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		net.host_offline(game)
		net.set_bots(2)
		net.set_setting("tr_knower", 0)
		check(net.start_game().is_empty(), "Создан стол колец")
		net.set_process(false)
		for category: String in net.tir.rings:
			net.tir.choose_rule(0, category, net.tir.rule_choices[category][0])
		net.tir.begin_clues(0)
		net._push_state()
		app = load("res://games/things_in_rings/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		table = app.screen
		for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1024, 768)]:
			root.size = dims
			await create_timer(0.3).timeout
			var hand: Control = table._hand
			for card: Control in hand._cards.values():
				var rect := card.get_global_rect()
				check(rect.position.y < table.size.y - 110 and rect.end.y < table.size.y + 24, "Рука видна почти целиком; снаружи небольшая кромка")
			await shot("tir-%s-%dx%d" % [mode, dims.x, dims.y])
		root.size = Vector2i(1280, 720)
		await settle()
		var hand: Control = table._hand
		var original: Array = hand.order.duplicate()
		var first: Control = hand._cards[original[0]]
		var old_y: float = first.position.y
		await motion(first.get_global_rect().get_center())
		await settle()
		check(first.position.y < old_y - 8, "Наведённая карта поднимается")
		check(table._picture.texture != null, "Мгновенный боковой просмотр сохранён")
		await drag_to(first, Vector2(hand.global_position.x + hand.size.x - 24, root.size.y - 36))
		var sorted_order: Array = hand.order.duplicate()
		check(sorted_order != original and sorted_order.back() == original[0], "Drag сортирует почти целиком видимую руку")
		net._push_state()
		await settle()
		hand = table._hand
		check(hand.order == sorted_order, "Сортировка переживает Net rebuild")
		var count: int = net.tir.board.size()
		await drag_to(hand._cards[sorted_order[0]], table._field.get_global_rect().get_center())
		check(net.tir.board.size() == count + 1, "Drag из поднятой руки размещает вещь на поле")
		await stop()

func motion(at: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	await process_frame

func drag_to(card: Control, target: Vector2) -> void:
	var origin := card.get_global_rect().get_center()
	await motion(origin)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = origin if down else target
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)
		if down:
			for i: int in range(1, 8):
				await motion(origin.lerp(target, float(i) / 7.0), true)
		await settle()

