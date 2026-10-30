extends SceneTree
## The Gang: лобби и стол на 1280×720 — всё на экране без прокрутки, панели не на линиях фона.
## Кадры build/tg30/<имя>.png. Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_tg30.gd
var checks := 0
var errors := 0
var net: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	print("TG30 ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1

func _initialize() -> void:
	_run.call_deferred()

func shot(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tg30/" + name + ".png")

## Видимые панели не заходят на рамку фона (линии на 10 и 20 px от края) и не выходят за экран.
func check_geometry(app: Control, label: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	var frame := screen.grow(-22)
	var bad: Array[String] = []
	for node: Node in app.find_children("*", "PanelContainer", true, false):
		var panel := node as Control
		if not panel.is_visible_in_tree() or panel.get_global_rect().size.x < 4:
			continue
		var rect := panel.get_global_rect()
		if not frame.encloses(rect) and (rect.position.y > 60 or panel.name == "LobbyPanel"):
			bad.append("%s %s" % [panel.name, rect])
	check(bad.is_empty(), label + ": панели внутри рамки фона " + str(bad))
	# Кольцо сейфа (центр 0.72·w, 0.53·h, радиус до 230) и угловые веера — только там, где их не закрывают панели.
	var background: Node = app.screen.get_child(0)
	if bool(background.get("decor")):
		var dial := Rect2(Vector2(root.size) * Vector2(0.72, 0.53) - Vector2.ONE * 232, Vector2.ONE * 464)
		for node: Node in app.find_children("*", "PanelContainer", true, false):
			var panel := node as Control
			if panel.is_visible_in_tree():
				check(not panel.get_global_rect().intersects(dial) and not panel.get_global_rect().intersects(Rect2(0, 0, 104, 84)) and not panel.get_global_rect().intersects(Rect2(0, root.size.y - 84, 104, 84)), label + ": панель не на кольце/веерах")
	var scrolls := app.find_children("*", "ScrollContainer", true, false).filter(func(s: Node) -> bool:
		var sc := s as ScrollContainer
		return sc.is_visible_in_tree() and sc.get_v_scroll_bar().visible)
	check(scrolls.is_empty(), label + ": без вертикальной прокрутки")

## Своя фишка — игрушка: бросок с трением и отскоком внутри зоны карт, подброс; номинал не меняется.
func check_toy(app: Control) -> void:
	var me := int(net.view.seat)
	net.gang.action(me, "take", {"value": 2})
	net._push_state()
	await create_timer(0.4).timeout
	var table: Control = app.screen
	var toy: Control = table._toy
	check(toy != null and toy.toy and toy.value == 2, "своя фишка стала игрушкой")
	if toy == null:
		return
	var area: Control = toy.get_parent()
	var start := toy.global_position + toy.size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = start
	press.position = start
	toy._gui_input(press)
	for step: int in 4:
		var motion := InputEventMouseMotion.new()
		motion.global_position = start + Vector2(30 * (step + 1), -6 * (step + 1))
		toy._input(motion)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.global_position = start + Vector2(120, -24)
	toy._input(up)
	check(toy.velocity.length() > 50.0, "бросок даёт скорость")
	await create_timer(1.5).timeout
	var rect := Rect2(Vector2.ZERO, area.size)
	check(rect.encloses(Rect2(toy.position, toy.size)), "игрушка осталась в зоне карт")
	check(toy.velocity.length() < 40.0, "трение гасит скорость")
	toy.toss()
	await create_timer(0.3).timeout
	check(toy._lift > 0.1, "щелчок подбрасывает фишку")
	await shot("toy-toss")
	await create_timer(0.6).timeout
	check(toy._lift == 0.0 and int(net.gang.chips[me]) == 2 and toy.value == 2, "после игры номинал прежний")
	var kept: Vector2 = toy.position
	net._push_state()
	await create_timer(0.3).timeout
	check(table._toy != null and table._toy.position.is_equal_approx(kept), "место игрушки переживает перестройку стола")
	var zoom := root.get_texture().get_image()
	zoom.save_png("res://build/tg30/toy.png")

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	for bots: int in [2, 9]:
		net.host_offline("the_gang")
		net.set_bots(bots)
		var app: Control = load("res://games/the_gang/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await create_timer(0.5).timeout
		await shot("lobby-%d" % (bots + 1))
		check_geometry(app, "лобби %d" % (bots + 1))
		check(net.start_game().is_empty(), "партия %d" % (bots + 1))
		await create_timer(0.8).timeout
		await shot("table-%d" % (bots + 1))
		check_geometry(app, "стол %d" % (bots + 1))
		if bots == 2:
			await check_toy(app)
		net.leave()
		app.queue_free()
		await create_timer(0.3).timeout
	print("TG30 ", checks, "/", errors)
	quit(1 if errors else 0)
