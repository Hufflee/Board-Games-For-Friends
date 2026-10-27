extends "res://tests/test_fs_passive_events_ui.gd"
## Настоящие кнопки ручного урона/награды после срабатывания пассива другого игрока.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 1
	g.phase = "effect"
	g.items = [[FSData.item_entry(180)], []]
	g.hp = [2, 2]
	g.max_hp = [2, 2]
	g.bonuses.clear()
	g.stack.clear()
	g._death_queue.clear()
	g._after_stack = "turn"
	g.resolving = {"kind": "reward", "card": 387, "owner": 1, "slot": 0}
	g.battle = 0
	g.monsters[0].id = 387
	g.monsters[0].hp = 0
	g.monsters[0].death_pending = true
	net.fs_switch_seat(1)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await operation("damage", 3, 0)
	check(g.phase == "priority" and g.items[0][0].counters == 0, "Перед наградой ожидается пассив")
	check(find_button("Применить") != null and find_button("Эффект выполнен") != null, "Панель оставшейся награды не исчезла")
	var money: int = g.coins[1]
	await operation("coins", 6, 1)
	check(g.phase == "effect" and g.coins[1] == money + 6, "Кнопка продолжила награду после пассива")
	check(g.items[0][0].counters == 1, "Пассив другого игрока разрешён один раз")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-manual-resume.png")
	await operation("heal", 3, 0)
	await operation("damage", 1, 0)
	check(bool(table._v.effect_pending) and table._die.visible, "Перед ручным броском пассив не скрывает кубик")
	var before := g.roll_no
	await ready_die()
	await roll()
	check(g.roll_no == before + 1 and g.items[0][0].counters == 2, "Жест сначала разрешил пассив, затем создал один ручной бросок")
	await ready_die()
	await roll()
	check(g.roll_no == before + 1 and g.phase == "effect" and g.resolving.card == 387, "Закрытие ответов вернуло ту же награду без второго результата")
	print("MANUAL PASSIVE UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
