extends "res://tests/test_fs_karma_ui.gd"
## Липкий пятак: настоящий розыгрыш и передача через панель720p при обеих общих настройках темы.
## Сам Айзек остаётся тёмным по решению владельца25.10.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	net.set_process(false)
	var scenario := Scenario.new(Check.new()).players(2).dlc().current(0).hand(0, [506]).build()
	var g: FSRules = scenario.g
	net.fours = g
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	var fan: Control
	for node: Control in table.find_children("*", "Control", true, false):
		if node.get_script() != null and node.get_script().resource_path == "res://hub/private_hand.gd" and node.movable:
			fan = node
	check(fan != null, "Личная рука найдена")
	if fan == null:
		await root.get_node("Sfx").request_quit(1)
		return
	await click(fan._cards["loot:506"])
	await click(find_button("Сыграть лут"))
	for i in 12:
		if g.phase != "priority":
			break
		g.tick(5.1)
	net._push_state()
	await frames(5)
	check(g.phase == "effect" and g.resolving.card == 506, "Особая монета открыла ручной текст вместо немедленного начисления")
	for dark: bool in [true, false]:
		root.get_node("Prefs").theme_mode = "dark" if dark else "light"
		table._changed(table._v, false)
		await frames(5)
		var labels: Array = table.find_children("*", "Label", true, false)
		check(labels.any(func(label): return label.text.contains("Передать разыгранную карту лута")), "У особой монеты видна ручная инструкция")
		DirAccess.make_dir_recursive_absolute("res://build/shots/fs02")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs02/coin_choices_%s.png" % ("dark" if dark else "light"))
	await apply_to("self_give", 1)
	check(g.hands[1].has(506), "Получатель получил физическую карту через кнопку")
	await click(find_button("Эффект выполнен"))
	await frames(5)
	check(g.phase == "turn" and g.hands[1].has(506) and not g.discards.loot.has(506), "Завершение сохранило подаренную карту в руке")
	print("COIN CHOICES UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
