extends SceneTree
## «Покер»: интерфейс на 1280×720 с ботами. Лобби, мой ход (панель ставки: поле, ползунок, 2×/3×/4×),
## гора фишек от крупной ставки, вскрытие, итоги спортивной сессии. Кадры — build/shots/poker_*.png.
## Запуск: godot --path . --audio-driver Dummy --script res://tests/test_poker_ui.gd   (PK_THEME=light|dark)
var checks := 0
var errors := 0
var net: Node
var app: Control


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", text)


func settle(frames: int = 5) -> void:
	for _i: int in frames:
		await process_frame


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/poker_%s_%s.png" % [label, root.get_node("Prefs").theme_mode])


func table() -> Control:
	return app.screen


func find(node_name: String) -> Node:
	return table().find_child(node_name, true, false)


## Крутить хост, пока не наступит мой ход (боты ходят сами).
func wait_my_turn() -> bool:
	for _i: int in 600:
		if net.pkr.phase == "hand" and net.pkr.to_act == 0:
			await settle(3)
			return true
		net.pkr.tick(0.5)
		net._push_state()
		await process_frame
	return false


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var theme_name := OS.get_environment("PK_THEME")
	root.get_node("Prefs").theme_mode = theme_name if theme_name in ["light", "dark"] else "dark"
	net = root.get_node("Net")
	net.host_offline("poker")
	var seats_env := OS.get_environment("PK_SEATS")
	net.set_bots(int(seats_env) - 1 if seats_env.is_valid_int() else 3)
	net.set_setting("pk_mode", "sport")
	app = load("res://games/poker/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle(10)
	check(app.screen.find_child("LobbyPanel", true, false) != null, "лобби открыто")
	await shot("lobby")
	print("START: ", net.start_game())
	await settle(10)
	check(net.pkr != null and net.pkr.players.size() >= 2, "партия началась")
	check(await wait_my_turn(), "дождались своего хода")
	check(find("Raise") != null and find("RaiseSlider") != null and find("RaiseInput") != null, "панель ставки: кнопка, ползунок, поле")
	check(find("Mult2") != null and find("Mult3") != null and find("Mult4") != null, "кнопки 2× 3× 4×")
	var slider: HSlider = find("RaiseSlider")
	var mult: Button = find("Mult3")
	mult.pressed.emit()
	await settle()
	var base: int = maxi(net.pkr.current_bet, 2)
	check(int(slider.value) == clampi(base * 3, int(slider.min_value), int(slider.max_value)), "3× ставит ползунок (%d)" % slider.value)
	var edit: LineEdit = find("RaiseInput")
	edit.text = "37"
	edit.text_changed.emit("37")
	await settle()
	check(int(slider.value) == 37 and (find("Raise") as Button).text.ends_with("37"), "поле ввода двигает ползунок и кнопку")
	check(table().find_child("Mine0", true, false) != null, "мои карты на столе")
	await shot("my_turn")
	# крупная ставка — гора фишек
	(find("Raise") as Button).pressed.emit()
	await settle(4)
	check(net.pkr.bets[0] == 37 or net.pkr.totals[0] >= 37, "рейз до 37 принят")
	net.pkr.bets[2] = 150
	net.pkr.stacks[2] -= 150
	net.pkr.totals[2] += 150
	net._push_state()
	await settle(4)
	await shot("mountain")
	net.pkr.bets[2] = 0
	net.pkr.stacks[2] += 150
	net.pkr.totals[2] -= 150
	# вскрытие: доигрываем раздачу ботами до showdown
	for _i: int in 400:
		if net.pkr.phase == "showdown":
			break
		if net.pkr.phase == "hand" and net.pkr.to_act == 0:
			net.send_action("call", {})
		net.pkr.tick(0.5)
		net._push_state()
		await process_frame
	await settle(4)
	check(net.pkr.phase == "showdown", "раздача закончилась")
	await shot("showdown")
	# итоги сессии
	net.pkr.hand_no = 14
	net.pkr.time_left = 0.0
	net.pkr.tick(0.1)
	net._push_state()
	await settle(6)
	check(net.pkr.phase == "session_end", "после 14-й раздачи — итоги сессии")
	check(find("SessionOverlay") != null and (find("SessionOverlay") as Control).visible, "окно итогов сессии")
	await shot("session")
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)
