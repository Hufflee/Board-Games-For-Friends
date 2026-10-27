extends "res://tests/test_fs_table_runtime.gd"
## Воспроизведение остановки UI после Мегатролль-бомбы: два штрафа подряд.

func click(button: Control) -> void:
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frames(3)
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames(2)
	print("CLICK: ", button.text, " old=", point, " rect=", button.get_global_rect())
	await mouse(point, true)
	await mouse(point, false)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Engine.time_scale = 3.0
	Engine.max_fps = 60
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	var g: FSRules = net.fours
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 1
	g.round_no = 15
	g.chars = [839, 842]
	g.phase = "death"
	g._death_queue = [0, 1]
	g._death_resume = "turn"
	g._after_stack = "turn"
	g._end_after_deaths = false
	g.hp = [0, 0]
	g.max_hp = [2, 2]
	g.coins = [29, 20]
	g.bank = 51
	g.items = [[FSData.item_entry(188, true), FSData.item_entry(652)], [FSData.item_entry(843), FSData.item_entry(233)]]
	g.hands = [[510, 632, 572, 521, 568, 574, 662, 513], [483, 484, 485, 486, 487, 488, 489, 490, 491]]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await frames(8)
	var pay := find_button("Принять штраф")
	var parent := pay.get_parent()
	for child in parent.get_children():
		if child is OptionButton:
			print("DEATH OPTION: ", child.get_selected_id(), " selected=", child.selected)
	pay.pressed.connect(func(): print("PAY PRESSED"))
	parent = pay.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(pay)
		parent = parent.get_parent()
	await frames(4)
	print("PAY RECT: ", pay.get_global_rect())
	await click(pay)
	await frames(8)
	check(g.coins[0] == 28, "Первый штраф действительно списан через кнопку")
	check(int(table._v.death_actor) == 1 and g.phase in ["death", "priority"], "Следующий штраф принадлежит второму игроку")
	# Основное действие следующего игрока разрешает окно ответов смерти.
	check(g.action(1, "end"), "Второй игрок разрешает ответы перед своим штрафом")
	net.fs_switch_seat(1)
	await frames(8)
	if find_button("Открыть мою руку") != null and find_button("Открыть мою руку").is_visible_in_tree():
		await click(find_button("Открыть мою руку"))
		await frames(4)
	await click(find_button("Принять штраф"))
	await frames(8)
	check(g.coins[1] == 19, "Второй штраф списан через кнопку")
	check(g._death_queue.is_empty() and g.current == 0, "После обоих штрафов передан ход, очередь смертей пуста")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-death-first.png")
	print("SIMULTANEOUS DEATH UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
