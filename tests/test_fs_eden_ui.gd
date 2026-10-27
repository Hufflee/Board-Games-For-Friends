extends "res://tests/test_fs_table_runtime.gd"
## Настоящий выбор Эдема в интерфейсе; кандидаты скрыты от остальных участников.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	net.set_process(false)
	var g: FSRules = net.fours
	var members: Array = g.players.duplicate(true)
	for seed_value in range(1, 101):
		g.new_game(members, false, seed_value)
		if g.phase == "starting_item":
			break
	check(g.phase == "starting_item", "Найден настоящий начальный выбор Эдема")
	var owner := g.actor()
	var options: Array = g.get_view(owner).starting_options
	check(options.size() == 3, "Доступны три кандидата")
	check(g.get_view(1 - owner).starting_options.is_empty(), "Другой участник не видит кандидатов")
	net.fs_switch_seat(owner)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	if find_button("Открыть мою руку") != null:
		await click(find_button("Открыть мою руку"))
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-eden.png")
	var chosen: int = options[0]
	var card_button: Button
	for button: Button in table.find_children("*", "Button", true, false):
		if int(button.get_meta("card_id", -1)) == chosen:
			card_button = button
			break
	check(card_button != null, "Предложенная карта представлена настоящей кнопкой")
	if card_button == null:
		quit(1)
		return
	var parent := card_button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(card_button)
		parent = parent.get_parent()
	await frames(3)
	await click(card_button)
	await frames(8)
	check(g.items[owner].any(func(item): return item.id == chosen and item.eternal), "Щелчок выбирает вечный стартовый предмет")
	if bool(table._v.get("starting_pending", false)):
		net.fs_switch_seat(g.current)
		await frames(8)
		if find_button("Открыть мою руку") != null:
			await click(find_button("Открыть мою руку"))
		await click(find_button("Начать первый ход"))
		await frames(8)
	check(g.phase in ["turn", "priority"] and not bool(table._v.get("starting_pending", false)), "Выбор завершён, партия началась")
	print("EDEN UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
