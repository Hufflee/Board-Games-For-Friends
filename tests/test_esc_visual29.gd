extends "res://tests/test_top_bar_escape29.gd"
## Исправленная геометрия ESC по референсу владельца: настоящий стол Длины волны, клавиши и кадры.


func shot(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/esc_visual29/" + file_name + ".png")


func _run() -> void:
	await process_frame
	root.content_scale_size = Vector2i.ZERO
	net = root.get_node("Net")
	var prefs: Node = root.get_node("Prefs")
	for mode: String in ["light", "dark"]:
		root.size = Vector2i(1280, 720)
		prefs.theme_mode = mode
		net.host_offline("wavelength")
		net.set_bots(3)
		check(net.start_game() == "", "Подготовлен настоящий стол Длины волны: " + mode)
		net.set_process(false)
		var app: Control = load("res://games/wavelength/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		await settle()
		bar = app.screen._top
		var info_at: Vector2 = bar.info.global_position
		var coin_at: Vector2 = bar.coin_dock.global_position
		check(not bar._drawer.visible and bar._drawer.get_global_rect().end.y <= 0, "Скрытый ряд находится за верхним краем")
		check(is_equal_approx(bar._esc_btn.modulate.a, 0.2), "Клавиша Esc прозрачна на80%")
		await shot("wl-" + mode + "-closed")
		await key()
		await process_frame
		check(bar._menu_open and is_equal_approx(bar._menu_amount, 1.0), "Escape полностью выдвинул ряд")
		check(bar._drawer is HBoxContainer and bar.actions is HBoxContainer, "Все прежние действия остаются одним рядом")
		check(bar._drawer.get_global_rect().position.y >= 0 and bar._drawer.get_global_rect().end.y <= bar.size.y + 0.5, "Раскрытый ряд находится в прежней верхней полосе")
		check(bar._drawer.scale.is_equal_approx(Vector2.ONE), "Обычные кнопки Длины волны сохраняют прежний размер1280")
		check(is_equal_approx(bar._chat_btn.size.y, bar._left.size.y), "Кнопки сохраняют прежнюю высоту общей строки")
		check(bar._drawer.get_global_rect().end.x < bar._esc_btn.global_position.x, "Esc постоянно справа от последнего действия")
		check(bar.info.global_position.is_equal_approx(info_at) and bar.coin_dock.global_position.is_equal_approx(coin_at), "Название, фаза и монетка не сдвигаются")
		var action_y: float = bar._chat_btn.get_global_rect().get_center().y
		for action: Control in bar.actions.get_children():
			check(absf(action.get_global_rect().get_center().y - action_y) < 2.0, "Кнопка игры в той же строке: " + action.name)
		await shot("wl-" + mode + "-open")
		# Положение во время закрытия должно уйти вверх, без исчезновения на месте.
		var shown_y: float = bar._drawer.global_position.y
		bar.set_menu_open(false)
		bar._menu_tween.pause()
		bar._menu_tween.custom_step(0.08)
		check(bar._drawer.visible and bar._drawer.global_position.y < shown_y and bar._drawer.get_global_rect().end.y > 0, "Во время закрытия ряд плавно уезжает вверх")
		check(is_equal_approx(bar._drawer.modulate.a, 1.0), "Ряд не заменяет движение затуханием")
		bar._menu_tween.play()
		await settle()
		check(not bar._drawer.visible and bar._drawer.get_global_rect().end.y <= 0, "После закрытия весь ряд над экраном")
		if mode == "dark":
			root.size = Vector2i(1920, 1080)
			await settle()
			await key()
			check(bar._drawer.scale.is_equal_approx(Vector2.ONE), "Размеры исходных кнопок сохранены1920")
			await shot("wl-dark-open-1920")
		app.queue_free()
		await process_frame
		net.leave()
	print("ESC VISUAL29: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
