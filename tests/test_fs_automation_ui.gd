extends "res://tests/test_fs_table_runtime.gd"
## Реальные кнопки выбора, скрытая ручная панель автоматической карты и аварийная панель хоста720p.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.settings.fs_dlc = true
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	var s := Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [544]).item(1, 40, {"tapped": true}).coins(0, 0).build()
	s.ok(0, "loot", {"card": 544})
	s.close()
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(6)
	await click(find_button("Открыть мою руку"))
	await frames(8)
	check(find_button("Применить") == null, "У автоматической карты нет произвольных ручных операций")
	check(find_button("Эффект выполнен") == null, "Игрок не подтверждает уже выполняемый эффект")
	check(net.fours.coins[0] == 1, "544 выдал монету без ручной панели")
	await click(find_button("Выбрать цель / вариант"))
	await frames(5)
	var choice := find_button("Второй · G Fuel!")
	check(choice != null, "Чужой предмет доступен конкретной кнопкой")
	if choice != null:
		check(Rect2(Vector2.ZERO, root.size).encloses(choice.get_global_rect()), "Выбор помещается в1280×720")
		DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs_automation04/choice.png")
		await click(choice)
		await frames(8)
		check(not net.fours.items[1].filter(func(item): return int(item.id) == 40)[0].tapped, "Клик автоматически перезарядил выбранный предмет")
		check(net.fours.phase == "turn", "Карта завершилась без кнопки подтверждения")
	var host_panel: Script = load("res://hub/host_panel.gd")
	host_panel.toggle()
	await frames(8)
	var panel: Node = root.get_children().filter(func(node): return node.get_script() == host_panel)[0]
	check(panel.find_children("*", "Button", true, false).any(func(button): return button.text.contains("аварийные операции")), "Операции доступны внутри панели хоста")
	panel.queue_free()
	# Длинный список: у8мест и двух монстров Иерофант предлагает30вариантов.
	s = Scenario.new(Check.new()).players(8).dlc().current(0).character(0, 821).hand(0, [627]).monster(0, 423).monster(1, 427).build()
	s.ok(0, "loot", {"card": 627})
	s.close()
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Выбрать цель / вариант"))
	await frames(6)
	check(table._v.card_choices.size() == 30, "Иерофант показывает все0/1/2урона для8игроков и2монстров")
	var popup_panel: Control = table._popup.find_children("*", "PanelContainer", true, false)[0]
	check(Rect2(Vector2.ZERO, root.size).encloses(popup_panel.get_global_rect()), "Длинный выбор полностью помещается в1280×720")
	var scroller: ScrollContainer = table._popup.find_children("*", "ScrollContainer", true, false)[0]
	var last := find_button(str(table._v.card_choices.back()))
	scroller.ensure_control_visible(last)
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/large_choice.png")
	await click(last)
	await frames(8)
	check(not net.fours._next_hit_shields.is_empty(), "Нижний вариант в длинном списке реально нажимается")
	# Общая новая механика: атака игрока с яйцом доступна настоящей кнопкой.
	s = Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.hand(0, []).item(0, 100).monster(0, 423).monster(1, 427).room(-1).build()
	s.g._place_egg("player", 1, "white")
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	var player_attack := find_button("Атаковать игрока: Второй")
	check(player_attack != null and not player_attack.disabled, "Игрока с яйцом можно атаковать кнопкой стола")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/eggs.png")
	if player_attack != null:
		await click(player_attack)
		await frames(5)
		check(net.fours.stack.any(func(effect): return effect.kind == "player_attack"), "Настоящий клик объявил атаку игрока с яйцом")
	s = Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821).hand(0, [568]).room(-1).build()
	s.ok(0, "loot", {"card": 568})
	s.close()
	s.g.attack_left = 0
	s.g.attacked = true
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	var gold_attack := find_button("Атаковать верх колоды")
	check(gold_attack != null and not gold_attack.disabled, "Золотой ключ оставляет кнопку колоды доступной после обычной атаки")
	current_scene.back_to_hub()
	await scene_changed
	await frames(12)
	s = null
	print("FS AUTOMATION UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
