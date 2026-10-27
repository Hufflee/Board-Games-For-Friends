extends "res://tests/test_fs_passive_events_ui.gd"
## Гордыня: настоящие кнопки выбора цели и скрытых карт, затем продолжение броска.
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
	g.hands = [[475],[478,479,480]]
	g.hp = [5,5]
	g.max_hp = [5,5]
	g.attack = [1,1]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g.phase = "turn"
	g._after_stack = "turn"
	g.attacked = false
	g.monsters = [{"id":396,"hp":3,"dc":4,"at":1},{"id":450,"hp":3,"dc":4,"at":1}]
	g.action(0,"attack",{"slot":0})
	g._finish_responses()
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(30)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await click(find_button("Сбросить лут: " + str(g.players[1].name)))
	check(g.phase == "priority", "Кнопка цели открывает ответы")
	await ready_die()
	await roll()
	await frames(15)
	check(g.phase == "forced_discard" and g.actor() == 1, "Кубик не бросается, пока другой игрок выбирает карты")
	net.fs_switch_seat(1)
	await frames(15)
	await click(find_button("Открыть мою руку"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-pride-discard.png")
	await click(find_button("Сбросить №2: " + FSData.title(479)))
	check(g.hands[1] == [478,480] and g.discard_choice.remaining == 1, "Первая настоящая кнопка сбросила выбранную карту")
	await click(find_button("Сбросить №1: " + FSData.title(478)))
	check(g.hands[1] == [480] and g.roll_no == 1 and g.phase == "priority", "Вторая карта сброшена, отложенный бросок начался ровно раз")
	print("PRIDE UI: ",checks," проверок, ",errors," ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
