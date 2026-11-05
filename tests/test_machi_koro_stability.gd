extends SceneTree
## Коробка в настоящем шкафу и стабильные карты при сетевых снимках. Запуск с окном, Dummy.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ОШИБКА: " + message)

func frames() -> void:
	for i in 4:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/" + name + ".png")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var room: Node = load("res://hub/neon_room.gd").new()
	root.add_child(room)
	await frames()
	var found: Array = room.boxes.filter(func(box): return box.game.get("id") == "machi_koro")
	check(found.size() == 1, "одна настоящая коробка Мачи Коро в шкафу")
	check(room._shelf_ids().any(func(row): return row.has("machi_koro")), "коробка размещена в ячейке после загрузки прежних настроек")
	if found.size() == 1:
		check(load("res://hub/game_box.gd").cover_texture("machi_koro", "spine") != null, "корешок коробки загружен")
	await shot("mk_shelf_20261105")
	room.free()
	await frames()
	var net: Node = root.get_node("Net")
	net.host_offline("machi_koro")
	net.set_bots(1)
	net.set_setting("mk_plus", true)
	net.set_setting("mk_sharp", true)
	net.start_game()
	var app: Control = load("res://games/machi_koro/ui/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	var view: Dictionary = net.view.duplicate(true)
	view.you = 1
	view.current = 0
	view.hotseat = false
	view.phase = "build"
	view.event = {}
	view.revision += 1000
	for theme_name: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = theme_name
		app._prefs_changed()
		await frames()
		# Здесь управляем публичным клиентским снимком; локальный heartbeat не подменяет его hot-seat видом.
		net.state_changed.disconnect(app.screen._state)
		app.screen._state(view)
		await frames()
		var table: Control = app.screen
		var mine: Control = table.city_cards.get_child(0)
		var theirs: Control = table.landmark_cards.get_child(0)
		var market: Control = table.market_grid.get_child(0)
		var city_scroll: ScrollContainer = table.city_cards.get_parent()
		var market_scroll: ScrollContainer = table.market_grid.get_parent()
		city_scroll.scroll_horizontal = 120
		market_scroll.scroll_vertical = 100
		await frames()
		var position := mine.position
		var city_offset := city_scroll.scroll_horizontal
		var market_offset := market_scroll.scroll_vertical
		table._hover(mine, true)
		await create_timer(0.35).timeout
		var preview: Control = table.preview
		for update in 8:
			view = view.duplicate(true)
			view.revision += 1
			view.coins[0] += 1
			view.log.append("Чужое действие %d" % update)
			table._state(view)
			await frames()
		check(app.screen == table and table.city_cards.get_child(0) == mine and table.landmark_cards.get_child(0) == theirs, "чужие действия сохраняют стол и оба ряда: " + theme_name)
		check(table.market_grid.get_child(0) == market and mine.position.is_equal_approx(position), "карты не телепортируются: " + theme_name)
		check(city_scroll.scroll_horizontal == city_offset and market_scroll.scroll_vertical == market_offset, "обе прокрутки сохранены: " + theme_name)
		check(is_instance_valid(preview) and table.preview == preview, "крупный просмотр пережил чужие действия: " + theme_name)
		var id: String = market.id
		view.reserve[id] += 1
		view.revision += 1
		table._state(view)
		await frames()
		check(table.market_grid.get_child(0) == market and market.copies == view.reserve[id], "изменившееся количество обновлено на прежней карте: " + theme_name)
		await shot("mk_stable_" + theme_name)
	app.free()
	net.leave()
	await frames()
	print("MK_STABILITY: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
