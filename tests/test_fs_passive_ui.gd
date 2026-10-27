extends "res://tests/test_fs_table_runtime.gd"
## Подготовленный стол: начальные состояния и обе способности смешанных предметов.
## Запуск с Dummy и отдельным APPDATA; это не новая полная партия.

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.phase = "turn"
	g.stack.clear()
	g.items[0].clear()
	var ids := [44, 50, 248, 503, 883, 22, 60, 199, 5, 202]
	for id in ids:
		g.items[0].append(FSData.item_entry(id))
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await frames(8)
	table._inventory(0)
	await frames(5)
	var scroll: ScrollContainer = table._popup.find_children("*", "ScrollContainer", true, false)[0]
	var groups: Control = scroll.get_child(0)
	check(groups.get_child_count() == ids.size(), "Все подготовленные предметы видны в инвентаре")
	for i in ids.size():
		var group := groups.get_child(i)
		var label: Label = group.get_child(1)
		var tap: Button = group.get_child(2)
		var paid: Button = group.get_child(3)
		if ids[i] in [44, 50, 248]:
			check(not tap.disabled and not paid.disabled, "Обе способности доступны: " + str(ids[i]))
		if ids[i] == 503:
			check(label.text.contains("Вечный"), "Клещ отображается вечным")
		if ids[i] == 883:
			check(tap.disabled and not paid.disabled, "Глюк доступен как условное срабатывание")
		if ids[i] in [22, 60, 199]:
			check(label.text.contains("Повёрнут") and tap.disabled, "Начальный поворот виден: " + str(ids[i]))
		if ids[i] in [5, 202]:
			check(label.text.ends_with(str(g.items[0][i].counters)), "Начальные жетоны видны: " + str(ids[i]))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/inventory.png")
	print("PASSIVE UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
