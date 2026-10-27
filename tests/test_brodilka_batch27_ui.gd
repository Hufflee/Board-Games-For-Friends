extends "res://tests/test_batch27_ui.gd"
## Настоящий стол Бродилки: открытие/закрытие подсказки мышью и выбор чужой карты.
func _run() -> void:
	var app := await start_game("brodilka")
	var table: Control = app.screen
	if table._cam_tween:
		table._cam_tween.kill()
	table._manual_until = Time.get_ticks_msec() + 60000
	var local_point: Vector2 = table.LABELS[0][0].get_center() * table._zoom
	table._map.position = table._board.size * 0.5 - local_point
	var at: Vector2 = table._board.global_position + table._board.size * 0.5
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await get_tree().create_timer(1.5).timeout
	check(not table._label_view.visible, "Наведение не открывает подпись поля")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	check(table._label_view.visible, "Нажатие на надпись открывает крупный просмотр")
	var chat: bool = table._top.chat.expanded
	await click(table._top._chat_btn)
	check(not table._label_view.visible, "Нажатие за пределами подписи закрывает просмотр")
	check(table._top.chat.expanded == chat, "Закрывающий клик не нажимает кнопку под ним")
	Net.brod.shop[0] = []
	Net.brod.shop[1] = [0, 1]
	Net.brod._ask(0, "steal", ["Второй"], "Кража", {seats = [1]})
	Net.brod.answer(0, 0)
	Net._push_state()
	await settle()
	check(table._dialog.visible and table._dialog.get_meta("kind") == "shop_pick", "Открыт выбор конкретной чужой карты")
	var images: Array = table._dialog.find_children("*", "TextureRect", true, false)
	check(images.size() == 2, "Обе карты доступны изображениями")
	await click(images[0])
	check(Net.brod.shop[0] == [0] and Net.brod.shop[1] == [1], "Нажатие забирает выбранную карту")
	await close_game(app)
	print("БРОДИЛКА27 UI: проверок=", checks, " ошибок=", errors)
	await Sfx.request_quit(1 if errors else 0)
