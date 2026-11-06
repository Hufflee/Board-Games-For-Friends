extends "res://tests/test_fs_passive_events_ui.gd"
## Карма сама вызывает владельца после10с: настоящий розыгрыш чужой души и ручные кнопки двух наград.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func apply_to(opcode: String, target: int, index: int = 0, amount: int = 1) -> void:
	var button := find_button("Применить")
	check(button != null and not button.disabled, "Панель разрешает применение выбранной операции")
	if button == null:
		return
	var choices: Array = []
	var numbers: Array = []
	for child in button.get_parent().get_children():
		if child is OptionButton:
			choices.append(child)
		elif child is SpinBox:
			numbers.append(child)
	var operations: Array = table.OPS + table.EXTRA_OPS
	for i in operations.size():
		if operations[i][0] == opcode:
			choices[1].select(i)
			choices[1].item_selected.emit(i)
	choices[0].select(target)
	numbers[0].value = amount
	numbers[1].value = index + 1
	# Появившееся поле индекса меняет высоту панели; сначала дождаться новой раскладки.
	await frames(3)
	var before: int = table._v.revision
	var fired := [false]
	button.pressed.connect(func(): fired[0] = true, CONNECT_ONE_SHOT)
	await click(button)
	await frames(6)
	check(bool(fired[0]), "Кнопка получила настоящий клик: " + opcode)
	check(int(table._v.revision) > before, "Операция выполнена кнопкой: " + opcode)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(2)
	net.start_game()
	net.set_process(false)
	var scenario := Scenario.new(Check.new()).players(3).dlc().current(1).item(0, 8) \
		.hand(1, [475]).shop(0, 91).shop(1, 229).build()
	var g: FSRules = scenario.g
	net.fours = g
	g.tick(11.0)
	net.fs_switch_seat(1)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	var fan: Control
	for node: Control in table.find_children("*", "Control", true, false):
		if node.get_script() != null and node.get_script().resource_path == "res://hub/private_hand.gd" and node.movable:
			fan = node
	check(fan != null, "Рука активного игрока найдена")
	if fan == null:
		await root.get_node("Sfx").request_quit(1)
		return
	await click(fan._cards["loot:475"])
	await click(find_button("Сыграть лут"))
	for i in 12:
		if g.phase != "priority":
			break
		g.tick(5.1)
	net._push_state()
	await frames(5)
	check(g.resolving.get("card", -1) == 8 and g.actor() == 0, "Чужая душа автоматически открыла Карму первому игроку")
	net.fs_switch_seat(0)
	await frames(5)
	await click(find_button("Открыть мою руку"))
	for dark: bool in [true, false]:
		root.get_node("Prefs").theme_mode = "dark" if dark else "light"
		table._changed(table._v, false)
		await frames(5)
		DirAccess.make_dir_recursive_absolute("res://build/shots/fs02")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs02/karma_%s.png" % ("dark" if dark else "light"))
	var coins: Array = g.coins.duplicate()
	await apply_to("take_shop", 1, 0)
	await apply_to("loot", 1)
	await apply_to("take_shop", 2, 1)
	await apply_to("loot", 2)
	check(g.items[1].any(func(item): return item.id == 91), "Первый адресат получил выбранную карту")
	check(g.items[2].any(func(item): return item.id == 229), "Второй адресат получил другую карту")
	check(g.coins == coins, "Карма не потратила монеты игроков")
	await click(find_button("Эффект выполнен"))
	await frames(5)
	check(g.phase == "turn" and g.souls[1] == 1, "Выбор завершён, исходная душа сохранена")
	print("KARMA UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
