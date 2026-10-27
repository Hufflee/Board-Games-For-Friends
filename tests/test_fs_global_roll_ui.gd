extends "res://tests/test_fs_passive_events_ui.gd"
## Проклятый толстяк: настоящий бросок, приватная кнопка сброса и возврат эффекта.
func _run() -> void:
	root.size = Vector2i(1280,720)
	Engine.time_scale = 3.0
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.items = [[],[]]
	g.hands = [[475],[478,479]]
	g.hp = [5,5]
	g.max_hp = [5,5]
	g.bonuses.clear()
	g.stack.clear()
	g.next_action = {}
	g.phase = "effect"
	g._after_stack = "turn"
	g.resolving = {"kind":"item","card":13,"owner":1}
	g.monsters = [{"id":439,"hp":4,"dc":2,"at":1}]
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1,101):
		rng.seed = seed_value
		if rng.randi_range(1,6) == 5:
			g._rng.seed = seed_value
			break
	net.fs_switch_seat(1)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(30)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await ready_die()
	await roll()
	await ready_die()
	await roll()
	check(g.last_roll == 5 and g.phase == "forced_discard" and g.actor() == 1, "Два жеста дали5 и обязательный выбор владельца броска")
	await click(find_button("Сбросить №2: " + FSData.title(479)))
	check(g.hands[1] == [478] and g.phase == "effect" and g.resolving.owner == 1, "Кнопка сбросила выбранный лут и вернула исходную способность")
	check(find_button("Эффект выполнен") != null, "Ручная панель снова доступна после обязательного сброса")
	print("GLOBAL ROLL UI: ",checks," проверок, ",errors," ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
