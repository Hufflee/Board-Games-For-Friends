extends "res://tests/test_fs_table_runtime.gd"
## Подготовленный ответ Осколком кубика: настоящий жест владельца исходного броска.

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
	g.phase = "effect"
	g.resolving = {"kind": "loot", "card": 515, "owner": 1}
	g.stack = [{"kind": "roll", "owner": 0, "value": 3}]
	g._after_stack = "battle_roll"
	check(g.action(1, "effect", {"op": "reroll", "target": 0}), "Осколок просит исходного владельца бросить кубик")
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await frames(8)
	check(int(table._v.actor) == 0 and int(table._v.resolving.owner) == 1, "Эффект принадлежит другому игроку, бросает исходный владелец")
	check(table._die.draggable, "Кубик доступен правильному игроку")
	var before := g.roll_no
	await roll()
	check(g.roll_no == before + 1, "Жест создал ровно один результат переброса")
	check(g.phase == "priority", "После переброса открыто окно ответов")
	await ready_die()
	await frames(8)
	await roll()
	check(g.roll_no == before + 1, "Второй жест разрешает ответы без лишнего результата")
	check(g.phase == "effect" and int(g.resolving.owner) == 1 and not g.resolving.has("reroll_request"), "Эффект вернулся владельцу карты")
	check(g.stack[0].value == g.last_roll, "Исходный бросок заменён")
	# В headless нет отрисовки: игровые проверки и итог выполняются без ожидания кадра.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs-reroll-ui.png")
	print("FS REROLL UI: ", checks, " проверок, ", errors, " ошибок")
	net.leave()
	current_scene.queue_free()
	await frames(5)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
