extends SceneTree
## Пакет29.10: принятие приглашения справа; финальное раскрытие всех подарков, без раскрытия в партии.
## Запуск с --audio-driver Dummy, отдельным APPDATA; графические кадры в build/batch29_small.

var checks := 0
var errors := 0
var net: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func shot(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/batch29_small/" + file_name + ".png")


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/batch29_small"))
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.set_process(false)
	var invite = load("res://hub/steam_invite.gd").new()
	root.add_child(invite)
	invite._build_toast("Проверка приглашения", 12345)
	await create_timer(0.1).timeout
	var accept: Button
	var decline: Button
	for control: Node in invite.find_children("*", "Button", true, false):
		if control.text == "Принять":
			accept = control
		elif control.text == "Отклонить":
			decline = control
	check(accept != null and decline != null, "Обе кнопки приглашения доступны")
	check(decline.global_position.x < accept.global_position.x, "Отказ слева, принятие справа")
	check(accept.get_parent() == decline.get_parent(), "Оба варианта в прежнем ряду")
	await shot("invite")
	await click(decline)
	await process_frame
	check(not is_instance_valid(invite), "Настоящий клик отказа закрывает приглашение")
	for mode: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		for each: int in [1, 2]:
			net.host_offline("not_a_hat")
			net.set_bots(3)
			check(net.start_game() == "", "Подготовлена партия Это не шляпа")
			var rules = net.nothat
			rules.new_game(rules.players, each, 291029)
			rules.start_play()
			var steps := 0
			while steps < 100:
				steps += 1
				if rules.phase == "give":
					rules.give(rules.giver, int(rules.card.g))
				elif rules.phase == "respond":
					rules.respond(rules.receiver, false)
				elif rules.phase == "reveal":
					if rules.penalties[int(rules.reveal.loser)].size() >= rules.MAX_PENALTY:
						break
					rules.advance()
			check(rules.phase == "reveal", "Штатными действиями получен последний штраф")
			for seat: int in rules.players.size():
				var view: Dictionary = rules.get_view(seat, false)
				for hand: Array in view.hands:
					for card: Dictionary in hand:
						check(int(card.g) == -1, "До конца партии чужие и свои закрытые подарки не раскрыты")
			net._push_state()
			var app: Control = load("res://games/not_a_hat/ui/main.tscn").instantiate()
			root.add_child(app)
			current_scene = app
			await create_timer(0.1).timeout
			var table: Control = app.screen
			rules.advance()
			net._push_state()
			check(rules.phase == "game_over", "Штатный advance закончил партию")
			for player: int in table._hand_cards:
				for card: Control in table._hand_cards[player]:
					check(card._flip.busy, "Финальное лицо открывается общей анимацией переворота")
			for seat: int in rules.players.size():
				var view: Dictionary = rules.get_view(seat, false)
				for player: int in rules.hands.size():
					check(view.hands[player] == rules.hands[player], "Каждое место получило все финальные лица и направления")
			await create_timer(0.6).timeout
			for player: int in table._hand_cards:
				var cards: Array = table._hand_cards[player]
				for index: int in cards.size():
					check(cards[index].gift == int(rules.hands[player][index].g), "Настоящий стол раскрыл подарок игрока")
			await shot("hat-end-" + mode + "-" + str(each))
			app.queue_free()
			await process_frame
			net.leave()
	print("BATCH29 SMALL: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
