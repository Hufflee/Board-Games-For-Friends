extends SceneTree
## Кадры Things in Rings: лобби (желающие вести, режим, таймер) и стол Blind Mind глазами искателя и ведущего,
## светлая и тёмная тема, 1280×720, плюс середина анимации открытия. Кадры — build/shots/tir_blind_*.png.
## Запуск (с окном, без звука): Godot --audio-driver Dummy --path . --script res://tests/test_tir_blind_ui.gd
var checks := 0
var errors := 0
var net: Node
var prefs: Node
var app: Control


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)


func settle(frames: int = 6) -> void:
	for _i: int in frames:
		await process_frame


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	root.get_texture().get_image().save_png("res://build/shots/tir_blind_" + label + ".png")


func set_theme(dark: bool) -> void:
	prefs.theme_mode = "dark" if dark else "light"
	root.theme = load("res://games/things_in_rings/ui/tr_style.gd").theme()
	app.theme = root.theme
	call_group("tr_backdrop", "queue_redraw")


func seat_view(seat: int) -> void:
	net.tr_view_seat = seat
	net._push_state()
	await settle()
	await create_timer(0.3).timeout


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	net = root.get_node("Net")
	prefs = root.get_node("Prefs")
	prefs.theme_mode = "light"
	net.host_offline("things_in_rings")
	net.set_bots(3)
	net.set_setting("tr_rings", ["Attribute", "Word", "Context"])
	net.set_setting("tr_mode", "blind")
	net.set_setting("tr_timer", 60)
	net.tr_toggle_want(0)
	net.tr_toggle_want(2)
	app = load("res://games/things_in_rings/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	await create_timer(0.3).timeout
	check(app.screen.find_child("Want1", true, false) != null, "В лобби есть переключатель «Хочу вести»")
	await shot("lobby_light")
	set_theme(true)
	app.show_lobby()
	await settle()
	await shot("lobby_dark")
	set_theme(false)
	check(net.start_game() == "", "Партия Blind Mind запущена")
	var tir: Object = net.tir
	check(tir.knower in [1, 3], "Ведущий — из желающих (местные 0 и 2 → места 1 и 3)")
	var k: int = tir.knower
	for category: String in tir.rings:
		tir.choose_rule(k, category, tir.rule_choices[category][0])
	tir.begin_clues(k)
	for mask: int in [0, 1, 3]:
		tir.clue(k, tir.hands[k][0], mask)
	check(tir.phase == "blind", "После подсказок — слепой ход")
	var seekers: Array = tir.blind_waiting()
	tir.blind_place(seekers[0], tir.hands[seekers[0]][0], 2)
	tir.blind_place(seekers[1], tir.hands[seekers[1]][0], 5)
	tir.blind_move(k, seekers[0], 6)
	tir.revision += 1
	await seat_view(seekers[0])
	check(app.screen.find_child("BlindCard%d" % tir.blind_cards[seekers[0]].card, true, false) != null, "Искатель видит свою скрытую карточку")
	check(app.screen.find_child("BlindCard%d" % tir.blind_cards[seekers[1]].card, true, false) == null, "Чужая карточка искателю не видна")
	await shot("player_light")
	await seat_view(k)
	check(app.screen.find_child("BlindDone", true, false) != null, "У ведущего кнопка «Завершить проверку»")
	var field: Control = app.screen.find_child("RingField", true, false)
	await shot("knower_light")
	set_theme(true)
	app.show_table()
	await settle()
	await create_timer(0.3).timeout
	await shot("knower_dark")
	await seat_view(seekers[2])
	await shot("waiting_dark")
	tir.blind_place(seekers[2], tir.hands[seekers[2]][0], 0)
	tir.revision += 1
	await seat_view(seekers[0])
	await shot("player_dark")
	tir.blind_done(k)
	tir.revision += 1
	net._push_state()
	await create_timer(0.4 + 0.75).timeout
	await shot("reveal_dark")
	await create_timer(4.5).timeout
	await shot("after_reveal_dark")
	set_theme(false)
	print("TIR BLIND UI: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
