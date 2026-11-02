extends "res://tests/test_fs_karma_ui.gd"
## Настоящее нажатие ручного условия70/222 после10с: не активация, магазин без покупки и возврат в ход.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	net.set_process(false)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	for id: int in [70, 222]:
		root.get_node("Prefs").theme_mode = "dark" if id == 70 else "light"
		var scenario := Scenario.new(Check.new()).players(2).dlc().current(1).item(0, id).item(0, 237).shop(0, 243).build()
		var g: FSRules = scenario.g
		net.fours = g
		g.tick(11)
		table._turn_seen = g.current  # ход подменённой партии уже «виден»: иначе стол сам уведёт экран к ходящему
		net.fs_switch_seat(0)
		await frames(6)
		var unlock := find_button("Открыть мою руку")
		if unlock != null:
			await click(unlock)
		var index := -1
		for i in g.items[0].size():
			if int(g.items[0][i].id) == id:
				index = i
		table._item_dialog(index)
		await frames(4)
		check(find_button("Повернуть → эффект").disabled, "Новая активация после10с недоступна")
		var trigger := find_button("Срабатывание по условию")
		check(trigger != null and not trigger.disabled, "Ручное условие доступно после10с чужого хода")
		var coins: int = g.coins[0]
		await click(trigger)
		check(g.phase == "priority" and int(g.stack.back().card) == id, "Кнопка поставила свою физическую карту в стек")
		for i in 4:
			if g.phase != "priority":
				break
			g.tick(5.1)
		net._push_state()
		await frames(6)
		check(g.phase == "effect" and int(g.resolving.card) == id, "Условие дошло до ручной панели")
		check(g.coins[0] == coins, "Пассив237 не принял условие за активацию")
		await apply_to("discard_shop", 0)
		check(scenario.zone_of(243) == "discard:treasure", "Панель сбросила физический предмет магазина")
		await click(find_button("Эффект выполнен"))
		await frames(5)
		check(g.phase == "turn" and g.current == 1, "Завершение вернулось к исходному активному игроку")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs02")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs02/item_condition.png")
	print("ITEM TRIGGER UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
