## Права TossDie: автор карты и назначенный бросающий различаются; пауза, полёт, повторный жест.
## Настоящие InputEvents, подготовленное состояние. --headless --audio-driver Dummy --max-fps 60 --script res://tests/test_fs_reroll_ui_owner.gd.
extends "res://tests/test_fs_attack_modifiers_ui.gd"

func select_seat(seat: int) -> void:
	net.fs_switch_seat(seat)
	await frames(8)
	var open: Button = find_button("Открыть мою руку")
	if open != null:
		await click(open)
	await frames(6)

func try_forbidden_grab(g: FSRules, label: String) -> void:
	var before: int = g.roll_no
	await mouse(table._die.center(), true)
	check(table._die.state != "dragging", label + ": реальный ввод не захватывает кубик")
	await mouse(table._die.center(), false)
	check(g.roll_no == before, label + ": бросок не отправлен")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Engine.time_scale = 3.0
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	var g: FSRules = net.fours
	g.current = 0
	g.chars = [839, 839]
	g.room = -1
	g.items = [[], []]
	g.hands = [[], [515]]
	g.character_ready = [true, true]
	g.hp = [20, 20]
	g.max_hp = [20, 20]
	g.attack = [1, 1]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	g.battle = 0
	g.battle_player = -1
	g.monsters = [{"id": 450, "hp": 20, "dc": 4, "at": 1}]
	check(g.action(0, "roll"), "Подготовлена настоящая атака0")
	g.stack.back().value = 6
	check(g.action(1, "loot", {"card": 515}), "Настоящий ответ Осколком1")
	g._resolve_top()
	check(g.action(1, "effect", {"op": "reroll", "target": 0}), "Переброс назначен игроку0")
	net.fs_switch_seat(1)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await select_seat(1)
	check(table._v.actor == 0 and table._v.resolving.owner == 1, "UI сохранил разные роли бросающего и автора")
	check(not table._die.draggable, "Автор чужого кубика не получает захват")
	await try_forbidden_grab(g, "Автор1 при запросе игроку0")
	check(find_button("Эффект выполнен") == null, "До переброса автор не завершает панель досрочно")
	await select_seat(0)
	await ready_die()
	check(table._die.draggable, "Назначенный владелец0 получает кубик")
	check(find_button("Эффект выполнен") == null, "Бросающий не получает завершение чужой панели")
	net.set_paused(true)
	await frames(6)
	check(not table._die.draggable, "Пауза выключает захват даже у назначенного владельца")
	await try_forbidden_grab(g, "Пауза")
	net.set_paused(false)
	await frames(6)
	await ready_die()
	seed_face(g, 4)
	var before: int = g.roll_no
	await roll()
	check(g.roll_no == before + 1 and g.phase == "priority", "Один настоящий жест создаёт один связанный переброс")
	check(table._die.state == "flying" and not table._die.draggable, "Полёт запрещает повторный захват")
	net._push_state()
	await frames(2)
	check(not table._die.draggable, "Обновление view не разрешает захват в полёте")
	await try_forbidden_grab(g, "Полёт после обновления view")
	await ready_die()
	await roll()
	check(g.roll_no == before + 1, "Повторный жест закрывает ответы, не создаёт второй бросок")
	check(g.phase == "effect" and g.resolving.owner == 1 and not g.resolving.has("reroll_request"),
		"Завершённый переброс вернул ручной эффект автору1")
	check(not table._die.draggable and find_button("Эффект выполнен") == null,
		"Игрок0 после возврата не получает чужие ручной бросок и завершение")
	await select_seat(1)
	check(find_button("Эффект выполнен") != null, "Автор1 получил настоящую кнопку завершения")
	check(table._die.draggable, "Обычный ручной бросок возвращённого эффекта доступен его автору")
	await click(find_button("Эффект выполнен"))
	g._finish_responses()
	check(g.discards.loot.count(515) == 1 and g.roll_no == before + 1,
		"Кнопка автора завершила карту один раз без дополнительного кубика")
	check(g.monsters[0].hp == 19 and g.paused_effects.is_empty(), "Исходная атака разрешилась, возвраты не потеряны")
	print("REROLL UI OWNER: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
