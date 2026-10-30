extends SceneTree
## Ведущий на экране победы Things in Rings: отдельно от победителей, лайк через хост, без повторов.
## Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_leader30.gd
var checks := 0
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("L30 ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var net: Node = root.get_node("Net")
	var result: GDScript = load("res://hub/victory_result.gd")
	net.host_offline("things_in_rings")
	net.set_bots(3)
	check(net.start_game() == "", "партия подготовлена")
	net.set_process(false)
	var rules: Object = net._game_obj()
	rules.coop = false
	rules.knower = 2
	rules.winners = [0]
	rules.phase = "game_over"
	net._push_state()
	var outcome: Dictionary = result.resolve("things_in_rings", net.view)
	check(outcome.leader == 2 and outcome.winners == [0] and not outcome.others.has(2), "знающий — ведущий, не победитель и не проигравший")
	rules.coop = true
	net._push_state()
	check(result.resolve("things_in_rings", net.view).leader == -1, "в кооперативе ведущего отдельно нет")
	rules.coop = false
	net._push_state()
	var app: Control = load("res://games/things_in_rings/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await create_timer(0.8).timeout
	var screen: Control = app.find_child("VictoryScreen", true, false)
	check(screen != null and screen.visible, "экран победы показан")
	var leader: Control = screen.find_child("Leader2", true, false) if screen else null
	check(leader != null, "карточка ведущего есть")
	net._host_victory_like(1, 2)
	check((net.victory_likes.seats as Array).is_empty(), "ведущий не лайкает сам себя")
	net._host_victory_like(1, 1)
	net._host_victory_like(1, 1)
	check(net.victory_likes.seats == [1], "лайк засчитан один раз")
	net._host_victory_like(1, 3)
	check(net.victory_likes.seats == [1, 3], "второй игрок лайкает")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/leader30/tir-leader.png")
	var button: Control = screen.find_child("LeaderLike", true, false) if screen else null
	check(button != null and not Rect2(Vector2.ZERO, Vector2(root.size)).intersection(button.get_global_rect()).has_area() == false, "кнопка лайка на экране")
	if leader and screen:
		var star := Rect2()
		for point: Vector2 in screen.star_polygon():
			star = Rect2(point, Vector2.ZERO) if not star.has_area() and star.position == Vector2.ZERO else star.expand(point)
		check(not star.intersects(Rect2(leader.position + Vector2(43, 28), Vector2(64, 64))), "аватар ведущего вне звезды")
	print("LEADER30 ", checks, "/", errors)
	quit(1 if errors else 0)
