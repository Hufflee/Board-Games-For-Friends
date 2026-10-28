extends "res://tests/test_ws_guess_reentrancy28.gd"
## Узкие независимые границы host-Enter и снимок реальных chat/emote. Dummy/свой APPDATA.

func run() -> void:
	await process_frame
	root.size = Vector2i(1280,720)
	net = root.get_node("Net")
	role = "host"
	net.host_offline("word_slam")
	net.set_bots(3)
	check(net.start_game().is_empty(), "Старт независимой подготовленной WS")
	net.set_process(false)
	prepare()
	await build_app()
	table._as = 0
	table._on_state(net.view)
	await settle()
	var edit: LineEdit = table._guess_edit
	await click(edit)
	edit.text = "   "
	var before: int = net.wslam.guesses.size()
	await enter()
	check(net.wslam.guesses.size() == before and net.wslam.phase == "play", "Пробельный Enter не отправляет догадку")
	edit.text = "неверно"
	await enter()
	await enter()
	check(net.wslam.guesses.size() == before + 1 and edit.has_focus(), "Двойной Enter отправляет один непустой текст")
	edit.text = "арбуз"
	await enter()
	var scores: Array = net.wslam.scores.duplicate()
	var guesses: Array = net.wslam.guesses.duplicate(true)
	await enter()
	check(net.wslam.phase == "round_result" and table._guess_edit == null, "Верный Enter завершил фазу и удалил редактор")
	check(net.wslam.scores == scores and net.wslam.guesses == guesses, "Повторный Enter после верного не удваивает награду/догадки")
	table._send_guess()
	check(net.wslam.scores == scores, "Поздний callback с null editor безопасен")
	prepare()
	await settle()
	table._as = 0
	table._on_state(net.view)
	await settle()
	edit = table._guess_edit
	edit.text = "черновик до смены фазы"
	net.wslam._start_round()
	net._push_state()
	check(table._guess_edit == null, "Внешняя смена фазы убрала editor до старого callback")
	table._send_guess()
	check(net.wslam.guesses.is_empty(), "Поздний callback после смены фазы не отправляет старый черновик")
	# Настоящая доставка через Net.send_chat, не прямое создание bubble.
	net.send_chat("Проверка всплывающего сообщения WS", "chat")
	await create_timer(0.35).timeout
	var bubbles: Control
	for child in table.get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://hub/chat_bubbles.gd":
			bubbles = child
	check(bubbles != null and is_instance_valid(bubbles._current), "Net.send_chat создал настоящий пузырь WS")
	if bubbles != null and is_instance_valid(bubbles._current):
		var bubble_rect: Rect2 = bubbles._current.get_global_rect()
		var bar_rect: Rect2 = table._top_bar.get_global_rect()
		check(bubble_rect.position.y >= bar_rect.end.y, "Настоящий пузырь начинается не выше нижней границы TopBar")
		print("WS BUBBLE OBSERVATION ", JSON.stringify({"kind":"chat","bubble":str(bubble_rect),"bar":str(bar_rect),"bubble_z":bubbles.z_index,"bar_z":table._top_bar.z_index,"overlap":bubble_rect.intersects(bar_rect)}))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/batch28_word_slam/low-chat-bubble.png")
	net.send_chat("Согласен!", "emote")
	await create_timer(0.4).timeout
	check(is_instance_valid(bubbles._current), "Настоящая быстрая реплика также создала пузырь")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/batch28_word_slam/low-emote-bubble.png")
	print("WS LOW REVIEW: %d проверок, %d ошибок" % [checks, errors])
	app.queue_free()
	net.leave()
	await settle()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
