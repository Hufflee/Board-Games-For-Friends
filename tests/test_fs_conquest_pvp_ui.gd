extends "res://tests/test_fs_passive_events_ui.gd"
## Завоеватель: настоящая кнопка выбора игрока, жесты кубика и переход к чужому штрафу.

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
	g.items = [[], []]
	g.hands = [[], []]
	g.hp = [5, 2]
	g.max_hp = [5, 2]
	g.attack = [2, 1]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g._death_queue.clear()
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	g.battle = 0
	g.monsters = [{"id": 268, "hp": 0, "dc": 3, "at": 1}, {"id": 450, "hp": 3, "dc": 4, "at": 1}]
	g.decks.monster = [451]
	g._continue_stack()
	g._finish_responses()
	check(g.action(0, "effect_done"), "Завоеватель разрешил награду и оставил обязательную атаку")
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	check(find_button("Закончить ход").disabled, "До PvP нельзя завершить ход кнопкой")
	await click(find_button("Атаковать игрока: " + str(g.players[1].name)))
	check(g.phase == "priority", "Кнопка цели открывает окно ответов")
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 101):
		rng.seed = seed_value
		if rng.randi_range(1, 6) == 4:
			g._rng.seed = seed_value
			break
	await ready_die()
	await roll()
	await ready_die()
	await roll()
	check(g.last_roll == 4 and g.hp[1] == 0 and g.hp[0] == 5, "Грань4 настоящего броска попала по другому игроку")
	check(g.phase == "death" and g.actor() == 1 and g.battle_player == -1, "UI получил обычный штраф защищавшегося")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-conquest-pvp.png")
	print("CONQUEST PVP UI: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
