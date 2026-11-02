extends "res://tests/test_fs_headless_horseman_ui.gd"
## Настоящие атаки/жесты: фиксированная добыча и душа без панели, отдельный бросок награды и выбор Сердца.
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
	for id: int in [352, 345, 344]:
		var scenario := Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
			.hand(0, []).monster(0, id, {"hp": 1, "dc": 1}).monster(1, 427) \
			.deck_top("monster", [423]).build()
		var g: FSRules = scenario.g
		net.fours = g
		net.fs_switch_seat(0)
		# Каждая независимая партия получает новый стол, как при обычном запуске игры.
		change_scene_to_file("res://games/four_souls/ui/main.tscn")
		await scene_changed
		await frames(20)
		table = current_scene.screen
		print("AUTO REWARDS UI: карта%d" % id)
		var unlock := find_button("Открыть мою руку")
		if unlock != null:
			await click(unlock)
		var health: Control = table.find_child("MonsterHealth0", true, false)
		await click(health.get_parent().get_child(0))
		await click(find_button("Атаковать"))
		await ready_die()
		scenario.roll(5)
		await roll()
		await wait_settled()
		await resolve_windows(g)
		if id == 344:
			check(g.phase == "effect" and g.resolving.get("requires_reward_roll", false), "Бес просит отдельный бросок награды")
			check(find_button("Применить") == null and find_button("Эффект выполнен") == null, "Общая ручная панель для броска награды скрыта")
			check(g.hands[0].is_empty(), "Добыча ждёт броска награды")
			DirAccess.make_dir_recursive_absolute("res://build/shots/fs_rewards")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/shots/fs_rewards/reward_roll.png")
			await ready_die()
			scenario.roll(4)
			await roll()
			await wait_settled()
			await resolve_windows(g)
			check(g.hands[0].size() == 4, "Настоящий жест награды автоматически выдал4карты")
		else:
			check(g.resolving.is_empty() and find_button("Применить") == null, "Фиксированная награда не открывает ручную панель")
			check(g.coins[0] == 6 if id == 352 else g.hands[0].size() == 2 and g.souls[0] == 1, "Фиксированные ресурсы и душа выданы по карте")
		check(not g.monsters.any(func(monster): return monster.id == id), "Убитая карта снята после награды")
		check(g.phase == "turn", "После награды можно продолжать ход")
	var heart := Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.soul(1, 345).soul(1, 421).monster(0, 381, {"hp": 0}).build()
	net.fours = heart.g
	heart.g._continue_stack()
	heart.close()
	net.fs_switch_seat(0)
	await frames(6)
	check(find_button("Применить") == null, "У Сердца Мамы конкретный выбор вместо ручных чисел")
	await click(find_button("Побеждает: Второй"))
	check(heart.g.winner == 1 and heart.g.phase == "game_over", "Настоящий выбор завершил партию указанным победителем")
	print("AUTO REWARDS UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
