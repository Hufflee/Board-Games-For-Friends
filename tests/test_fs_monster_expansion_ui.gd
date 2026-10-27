extends "res://tests/test_fs_passive_events_ui.gd"
## Бластоциста: расширение через настоящую ручную панель, сохранение награды и заполнение.
func _run() -> void:
	root.size = Vector2i(1280,720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.items = [[],[]]
	g.bonuses.clear()
	g.stack.clear()
	g.next_action = {}
	g.phase = "effect"
	g._after_stack = "battle_roll"
	g.resolving = {"kind":"reward","card":360,"owner":0,"slot":0}
	g.battle = 0
	g.monsters = [{"id":360,"hp":0,"dc":4,"at":1},{"id":450,"hp":3,"dc":4,"at":1}]
	g.decks.monster = [450,451,450,451]
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(30)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await operation("expand_monsters",2)
	check(g.monster_slots == 4 and g.phase == "effect", "UI расширил поле, сохранив награду")
	await operation("loot",1)
	await click(find_button("Эффект выполнен"))
	await frames(10)
	check(g.monsters.size() == 4, "UI показывает четыре заполненные ячейки")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-monster-expansion.png")
	print("EXPANSION UI: ",checks," проверок, ",errors," ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
