extends "res://tests/test_fs_passive_events_ui.gd"
## Подготовленный возврат Тряпочника: настоящая награда, жест кубика и выбор завершения.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Engine.time_scale = 3.0
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.phase = "battle_roll"
	g.items = [[], []]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g._death_queue.clear()
	g._after_stack = "battle_roll"
	g.battle = 0
	g.monsters = [{"id": 358, "hp": 0, "dc": 3, "at": 1}, {"id": 450, "hp": 3, "dc": 4, "at": 1}]
	g.decks.monster = [451]
	g._continue_stack()
	g._finish_responses()
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	check(find_button("Эффект выполнен").disabled, "Кнопка не пропускает обязательный бросок")
	await operation("loot", 1)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 101):
		rng.seed = seed_value
		if rng.randi_range(1, 6) == 6:
			g._rng.seed = seed_value
			break
	await ready_die()
	await roll()
	await ready_die()
	await roll()
	check(int(g.resolving.get("reward_roll", -1)) == 6, "Настоящий жест разрешил подготовленную шестёрку")
	check(not find_button("Эффект выполнен").disabled, "После результата кнопка доступна")
	await click(find_button("Эффект выполнен"))
	await frames(8)
	check(g.monsters.any(func(monster): return int(monster.id) == 358), "Возвращённый Тряпочник сразу заполнил свободную ячейку")
	check(not g.discards.monster.has(358), "Копии Тряпочника в сбросе нет")
	print("RAGLING UI: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
