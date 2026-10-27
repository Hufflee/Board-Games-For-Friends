extends "res://tests/test_fs_table_runtime.gd"
## Настоящая ручная панель: временная атака и уход источника постоянного бонуса.
## Подготовленные состояния, локальный Net, Dummy/отдельный APPDATA; не полная партия.
var observations: Array = []

func click(button: Control) -> void:
	check(is_instance_valid(button), "Кнопка найдена перед нажатием")
	if not is_instance_valid(button):
		return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frames(3)
	await super.click(button)

func record(id: int, action: String, expected, actual) -> void:
	observations.append({"id": id, "name": FSData.title(id), "action": action,
		"expected": expected, "actual": actual, "matches": expected == actual, "category": "ui_lifecycle"})

func prepare(g: FSRules, id: int) -> void:
	g.current = 0
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": id, "owner": 0}
	g.items = [[FSData.item_entry(id)], []]
	g.attack = [1, 1]
	g.stack.clear()
	g.next_action = {}
	g._after_stack = "turn"
	g.temporary_attack.clear()
	g._refresh_passive_stats()
	g.revision += 1
	net.fs_switch_seat(0)
	await frames(10)
	if find_button("Открыть мою руку") != null:
		await click(find_button("Открыть мою руку"))
		await frames(8)

func operation(op: String, value: int, target: int = 0) -> void:
	var button := find_button("Применить")
	check(button != null, "Доступна кнопка применения")
	if button == null:
		return
	var choices: Array = []
	var numbers: Array = []
	for child in button.get_parent().get_children():
		if child is OptionButton:
			choices.append(child)
		if child is SpinBox:
			numbers.append(child)
	check(choices.size() == 2 and numbers.size() >= 2, "Поля цели, операции, количества и индекса доступны")
	var operations: Array = table.OPS + table.EXTRA_OPS
	var chosen := -1
	for i in operations.size():
		if operations[i][0] == op:
			chosen = i
	check(chosen >= 0, "Операция представлена в UI: " + op)
	if chosen < 0:
		return
	choices[0].select(target)
	choices[1].select(chosen)
	numbers[0].value = value
	numbers[1].value = 1
	await click(button)
	await frames(8)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 97, "owner": 0}
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await prepare(g, 97)
	await operation("temporary_attack", 1)
	record(97, "Ручной бонус до конца хода через UI и Net", 2, g.attack[0])
	await click(find_button("Эффект выполнен"))
	await frames(8)
	await click(find_button("Закончить ход"))
	await frames(8)
	record(97, "Снятие временной атаки после кнопки конца хода", 1, g.attack[0])
	for method in ["destroy", "give_item"]:
		await prepare(g, 16)
		await operation("attack", 1)
		record(16, "Постоянный бонус учтён, ручное повторение не добавляет второй", 2, table._v.players[0].attack)
		# Следующий подготовленный эффект уничтожает/передаёт предмет.
		# Ввод и изменение состояния выполняются настоящей панелью через Net.
		g.resolving = {"kind": "item", "card": 13, "owner": 0}
		g.revision += 1
		net._push_state()
		await frames(8)
		await operation(method, 1, 1 if method == "give_item" else 0)
		check(g.items[0].is_empty(), "Предмет действительно ушёл: " + method)
		record(16, "UI после ухода предмета: " + method, [1, 1] if method == "destroy" else [1, 2],
			[table._v.players[0].attack, table._v.players[1].attack])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-" + method + ".png")
	g.phase = "turn"
	g.resolving = {}
	g.current = 0
	g.bonuses = [694]
	g.claimed.clear()
	g.souls = [2, 0]
	g.soul_cards = [[], []]
	g.revision += 1
	net._push_state()
	await frames(8)
	table._bonus_dialog(694)
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-bonus.png")
	var recipient_button := find_button("Отдать душу · " + str(g.players[1].name))
	await click(recipient_button)
	await frames(8)
	record(694, "Выбор отстающего получателем души через настоящий UI", 1, g.souls[1])
	var mismatches := observations.filter(func(row): return not row.matches).size()
	var output := FileAccess.open("res://build/fs_passive_audit/followup/runtime_ui.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"observations": observations, "mismatches": mismatches, "setup_errors": errors}, "\t"))
	output.close()
	print("PASSIVE EVENTS UI: ", observations.size(), " наблюдений, расхождений ", mismatches,
		", проверок подготовки ", checks, ", ошибок подготовки ", errors)
	quit(2 if errors else (1 if mismatches else 0))
