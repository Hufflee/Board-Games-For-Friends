extends SceneTree
## Настоящий стол, ввод мыши в TossDie и HP. Запуск без --headless, --script res://tests/test_fs_table_runtime.gd.
var checks := 0
var errors := 0
var table: Control
var net: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 4) -> void:
	for i in count:
		await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames(2)

func click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	await mouse(point, true)
	await mouse(point, false)

func find_button(text: String) -> Button:
	for node in table.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func roll() -> void:
	var die: Control = table._die
	await mouse(die.center(), true)
	check(die.state == "dragging", "Кубик захвачен настоящим событием мыши")
	var motion := InputEventMouseMotion.new()
	motion.position = die.center() + Vector2(-70, -20)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await frames(2)
	await mouse(motion.position, false)

func ready_die() -> void:
	for i in 900:
		await process_frame
		if table._die.state == "waiting":
			return
	check(false, "Кубик вернулся и разрешён следующий бросок")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(3)
	net.start_game()
	var g: FSRules = net.fours
	g.current = 0
	g.phase = "turn"
	g.stack.clear()
	g.monsters[0].hp = 3
	g.monsters[0].dc = 1
	g.attack[0] = 1
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await frames(12)
	for i in 4:
		var row := table.find_child("Player%d" % i, true, false)
		check(row != null, "Строка игрока %d присутствует" % i)
		var image: TextureRect = row.get_child(0).get_child(0)
		check(image.texture == FSData.texture(int(g.chars[i])), "Видна карта персонажа %d" % i)
		var health: Control = row.find_child("Health", true, false)
		check(health.current == g.hp[i], "HP игрока %d соответствует хосту" % i)
		check(row.get_global_rect().end.y < 500, "Персонаж %d виден над рукой в 720p" % i)
	DirAccess.make_dir_recursive_absolute("res://build/shots")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs-characters-1280x720.png")
	var health: Control = table.find_child("MonsterHealth0", true, false)
	await click(health.get_parent().get_child(0))
	await click(find_button("Атаковать"))
	await frames()
	check(table._die.state == "waiting", "Объявление атаки открывает кубик")
	await roll()
	check(g.roll_no == 1, "Один жест даёт один бросок")
	check(not table._die.draggable, "Полёт блокирует повторный захват сразу")
	# Ответ другого игрока перестраивает стол во время полёта.
	g.coins[1] += 1
	g.revision += 1
	net._push_state()
	await frames()
	check(not table._die.draggable, "Обновление сети не разблокирует летящий кубик")
	await mouse(table._die.center(), true)
	await mouse(table._die.center(), false)
	check(g.roll_no == 1, "Повторный клик во время полёта не бросает")
	check(g.monsters[0].hp == 3, "До закрытия ответов HP сохраняется по правилам")
	await ready_die()
	await roll()
	check(g.roll_no == 2, "После возврата разрешён ровно следующий бросок")
	check(g.monsters[0].hp == 2, "Успешная атака уменьшает настоящий HP монстра")
	health = table.find_child("MonsterHealth0", true, false)
	check(health.current == 2, "Сердечки монстра показывают новый HP")
	await ready_die()
	await roll()
	check(g.monsters[0].hp == 1, "Второе попадание снова уменьшает HP")
	health = table.find_child("MonsterHealth0", true, false)
	check(health.current == 1, "UI показывает HP после второго попадания")
	print("FS TABLE RUNTIME: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
