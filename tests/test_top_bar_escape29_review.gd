extends "res://tests/test_top_bar_escape29.gd"
## Только непокрытый риск: смена направления tween/клики закрывающейся панели/disabled действия.
func fast_escape() -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280,720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(2)
	net.start_game()
	net.set_process(false)
	scene = Control.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scene)
	current_scene = scene
	bar = load("res://hub/top_bar.gd").make(scene,"Быстрые переключения",button,null,Color(0.9,0.9,0.85))
	var action := button("Разрешённое действие",16)
	action.pressed.connect(func(): hits += 1)
	bar.actions.add_child(action)
	var disabled := button("Запрещённое действие",16)
	disabled.disabled = true
	bar.actions.add_child(disabled)
	await settle()
	await fast_escape()
	await fast_escape()
	await fast_escape()
	await settle()
	check(bar._menu_open and bar._drawer.visible and is_equal_approx(bar._menu_amount, 1.0),"Три быстрых Escape завершаются одним открытым меню без старого hide callback")
	check(disabled.disabled,"Открытие не снимает игровой disabled")
	await click(action)
	check(hits == 1,"Открытая после разворотов панель принимает настоящий клик один раз")
	action.grab_focus()
	await fast_escape()
	check(not action.has_focus(),"Начало закрытия сразу освобождает фокус действия")
	check(action.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Во время закрытия игровая кнопка сразу не принимает мышь")
	await click(action)
	check(hits == 1,"Клик по прежней позиции во время закрытия не выполняет действие")
	await fast_escape()
	await fast_escape()
	await settle()
	check(not bar._menu_open and not bar._drawer.visible and is_zero_approx(bar._menu_amount),"Быстрое открытие/закрытие не оставляет видимый призрак панели")
	await fast_escape()
	await settle()
	check(disabled.disabled and action.mouse_filter == Control.MOUSE_FILTER_STOP,"Повторное открытие возвращает mouse_filter, сохранив disabled")
	print("ESC LOW29: проверок=",checks," ошибок=",errors)
	net.leave()
	scene.queue_free()
	await process_frame
	await root.get_node("Sfx").request_quit(1 if errors else 0)
