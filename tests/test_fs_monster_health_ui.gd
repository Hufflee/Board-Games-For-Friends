extends "res://tests/test_fs_headless_horseman_ui.gd"
## HP-зависимая защита Маски420: HUD6, настоящий бросок5 промахивается, исходныйdc4 не меняется.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	Engine.time_scale = 3.0
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	net.set_process(false)
	var scenario := Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821) \
		.no_items(0).no_items(1).monster(0, 420, {"hp": 1}).monster(1, 344).build()
	var g: FSRules = scenario.g
	net.fours = g
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	check(table._v.monsters[0].dc == 6, "UI показывает защиту6 при1HP")
	var health: Control = table.find_child("MonsterHealth0", true, false)
	await click(health.get_parent().get_child(0))
	await click(find_button("Атаковать"))
	await ready_die()
	scenario.roll(5)
	await roll()
	await wait_settled()
	await resolve_windows(g)
	check(g.monsters[0].hp == 1 and g.hp[0] == 1, "Пятёрка не нанесла урон Маске, игрок получил ответный урон")
	check(table._v.monsters[0].dc == 6 and table._v.monsters[0].hp == 1, "HUD сохранил условную защиту и здоровье")
	check(g.monsters[0].dc == 4, "Базовая защита не залипла на6")
	for dark: bool in [true, false]:
		root.get_node("Prefs").theme_mode = "dark" if dark else "light"
		table._changed(table._v, false)
		await frames(5)
		DirAccess.make_dir_recursive_absolute("res://build/shots/fs02")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs02/mask_%s.png" % ("dark" if dark else "light"))
	print("MONSTER HEALTH UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
