extends SceneTree
## Настоящие столы 15 семейств, общий финал, реальные клики, темы и жизненный цикл музыкального плеера.
var checks := 0
var errors := 0
var net: Node
var sfx: Node
var app: Control
var table: Control
var screen: Control
var bar: Control
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("VICTORY ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1
func settle() -> void:
	await create_timer(0.18).timeout
func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	Input.parse_input_event(move)
	await process_frame
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await settle()
func shot(id: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/victory29/" + id + ".png")
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	sfx = root.get_node("Sfx")
	var prefs: Node = root.get_node("Prefs")
	DirAccess.make_dir_recursive_absolute("res://build/shots/victory29")
	var registry: Script = load("res://hub/games.gd")
	for id: String in ["king_of_12", "perudo", "wavelength", "dangerous_words", "hues_and_cues", "ready_set_bet", "word_slam", "tip_top", "tip_top_18", "not_a_hat", "gloom", "gloomier", "brodilka", "phantom_ink", "four_souls", "stillion", "the_gang"]:
		net.host_offline("gloom" if id == "gloomier" else id)
		if id in ["gloom", "gloomier"]:
			net.settings.gl_sets = "gm" if id == "gloomier" else "base"
		net.set_bots(9 if id == "the_gang" else 3)
		check(net.start_game() == "", id + ": запуск правил")
		net.set_process(false)
		var rules: Object = net._game_obj()
		for seat: int in rules.players.size():
			rules.players[seat].name = "Очень длинный ник участника номер %d" % seat
		rules.phase = "game_over"
		match id:
			"king_of_12", "perudo", "brodilka", "stillion", "four_souls":
				rules.winner = 1
			"wavelength", "phantom_ink":
				rules.winner = 0
			"word_slam", "dangerous_words":
				rules.winners = [0]
			"the_gang", "tip_top", "tip_top_18":
				rules.won = true
			"not_a_hat":
				pass
			"gloom", "gloomier":
				rules._finish_game()
			_:
				rules.winners = [1]
		net._push_state()
		app = load(registry.by_id(id).scene).instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		table = app.screen
		screen = table.get_node("VictoryScreen")
		bar = get_first_node_in_group("top_bar")
		check(screen.visible and screen.outcome.finished, id + ": общий экран на настоящем столе")
		var expected: Array = [1]
		if id in ["the_gang", "tip_top", "tip_top_18", "gloom", "gloomier", "not_a_hat"]:
			expected = range(rules.players.size())
		elif id in ["word_slam", "dangerous_words", "wavelength"]:
			expected = []
			for seat: int in rules.players.size():
				if int(rules.players[seat].get("team", -1)) == 0:
					expected.append(seat)
		elif id == "phantom_ink":
			expected = []
			for seat: int in rules.roles.size():
				if int(int(rules.roles[seat]) / 2) == 0:
					expected.append(seat)
		check(screen.outcome.winners == expected, id + ": корректные победившие места")
		check(screen._cards.size() == rules.players.size(), id + ": все игроки представлены")
		check(screen.global_position.y >= 48 and screen.z_index < bar.z_index, id + ": TopBar свободен")
		check(screen._buttons.get_global_rect().end.y <= 720, id + ": CTA в экране")
		for card: Control in screen._cards:
			var nick: Label = card.get_node("Nickname")
			check(nick.get_global_rect().end.y < screen._buttons.global_position.y, id + ": ник не пересекает CTA")
		if id == "the_gang":
			var winner_cards: Array[Control] = []
			for card: Control in screen._cards:
				if bool(card.get_meta("winner")):
					winner_cards.append(card)
			check(winner_cards.size() == 10, "TG10: десять победителей внутри одной звезды")
			var first_y := winner_cards[0].get_global_rect().get_center().y
			var previous_x := -INF
			var silhouette: PackedVector2Array = screen.star_polygon()
			for card: Control in winner_cards:
				var rect := card.get_global_rect()
				check(is_equal_approx(rect.get_center().y, first_y), "TG10: все победители в одной горизонтальной строке")
				check(rect.get_center().x > previous_x, "TG10: порядок победителей слева направо")
				previous_x = rect.get_center().x
				var local := Rect2(card.position, card.size).grow(2)
				for corner: Vector2 in [local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]:
					check(Geometry2D.is_point_in_polygon(corner, silhouette), "TG10: вся карточка с короной внутри звезды")
				check(rect.end.y < screen._buttons.global_position.y, "TG10: горизонтальный ряд не пересекает CTA")
		await shot(id + "-base")
		if id in ["the_gang", "word_slam", "not_a_hat", "stillion"]:
			for theme: String in ["dark", "light"]:
				prefs.theme_mode = theme
				prefs.changed.emit()
				await settle()
				app = current_scene
				table = app.screen
				screen = table.get_node("VictoryScreen")
				bar = get_first_node_in_group("top_bar")
				await shot(id + "-" + theme)
		await click(screen._buttons.get_node("ShowTable"))
		check(not screen._surface.visible and screen._return.visible, id + ": реальный клик показывает стол")
		if id in ["perudo", "stillion", "brodilka"]:
			var layer: Control = table.get("_overlay") if id == "perudo" else table.get("_over") if id == "stillion" else table.get_node("FinalResults")
			check(not layer.visible, id + ": известный старый финальный слой скрыт")
		if id == "not_a_hat":
			await shot("not_a_hat-open-table")
		await click(screen._return)
		check(screen._surface.visible and not screen._return.visible, id + ": реальный возврат к результатам")
		if id in ["perudo", "stillion", "brodilka"]:
			var layer: Control = table.get("_overlay") if id == "perudo" else table.get("_over") if id == "stillion" else table.get_node("FinalResults")
			check(layer.visible, id + ": старый слой восстановлен")
		if id == "the_gang":
			check(sfx._victory.playing and sfx._victory.stream.loop, "Музыка: реальный плеер запущен и loop=true")
			var playback: float = sfx._victory.get_playback_position()
			await create_timer(9.0).timeout
			check(sfx._victory.playing and sfx._victory.get_playback_position() > playback + 8.5, "Музыка играет после прежних 8.5 секунд")
			var old_player: AudioStreamPlayer = sfx._victory
			var before: float = old_player.get_playback_position()
			root.get_tree().scene_changed.emit()
			check(old_player.playing, "scene_changed той же игры сохраняет музыку")
			app.show_table()
			await settle()
			check(sfx._victory == old_player and old_player.playing and old_player.get_playback_position() >= before, "Пересоздание стола сохраняет музыкальный плеер/позицию")
			net.end_game()
			check(not old_player.playing, "В лобби музыка останавливается синхронно")
		app.queue_free()
		await process_frame
		net.leave()
		check(not is_instance_valid(sfx._victory) or not sfx._victory.playing, id + ": уход останавливает музыку")
		await settle()
	print("VICTORY UI ", checks, "/", errors)
	sfx.stop_audio()
	await process_frame
	quit(1 if errors else 0)
