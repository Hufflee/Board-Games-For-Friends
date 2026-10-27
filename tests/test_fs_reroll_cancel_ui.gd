## Узкий UI осиротевшего переброса: реальный жест TossDie и ручные панели Бомбы/награды/Осколка.
## Подготовленный сервером ответ; переходы стека помогают _finish_responses, не естественная партия.
## --headless --audio-driver Dummy --max-fps 60 --script res://tests/test_fs_reroll_cancel_ui.gd.
extends "res://tests/test_fs_attack_modifiers_ui.gd"

func apply_operation(op: String, amount: int) -> bool:
	var apply := find_button("Применить")
	check(apply != null, "Видна настоящая кнопка применения " + op)
	if apply == null:
		return false
	var choices: Array = []
	var numbers: Array = []
	for child in apply.get_parent().get_children():
		if child is OptionButton:
			choices.append(child)
		elif child is SpinBox:
			numbers.append(child)
	check(choices.size() == 2 and numbers.size() >= 2, "Поля ручной панели доступны")
	if choices.size() != 2 or numbers.size() < 2:
		return false
	var operations: Array = table.OPS + table.EXTRA_OPS
	var selected := -1
	for i in operations.size():
		if operations[i][0] == op:
			selected = i
	check(selected >= 0, "Операция есть в настоящем списке: " + op)
	if selected < 0:
		return false
	choices[0].select(0)
	choices[1].select(selected)
	numbers[0].value = amount
	numbers[1].value = 1
	await click(apply)
	await frames(8)
	return true

func stop_if_errors() -> bool:
	if errors:
		print("REROLL CANCEL UI: ", checks, " проверок, ", errors, " ошибок")
		await root.get_node("Sfx").request_quit(1)
		return true
	return false

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
	g.items = [[FSData.item_entry(36)], [FSData.item_entry(165)]]
	g.hands = [[497], [515]]
	g.character_ready = [true, true]
	g.free_loot = 1
	g.hp = [20, 20]
	g.max_hp = [20, 20]
	g.attack = [1, 1]
	g.coins = [3, 3]
	g.bank = 94
	g.damage_shields = [0, 0]
	g.bonuses.clear()
	g.temporary_attack.clear()
	g._turn_attack_rolls.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g._death_queue.clear()
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	g.battle = 0
	g.battle_player = -1
	g.monsters = [{"id": 450, "hp": 1, "dc": 4, "at": 1}, {"id": 445, "hp": 20, "dc": 4, "at": 1}]
	g.decks.monster = [450]
	# Серверная подготовка ответа до сцены: настоящие action, сырая грань исходной атаки6.
	check(g.action(0, "roll", {}), "Подготовлена исходная атака")
	g.stack.back().value = 6
	check(g.action(1, "loot", {"card": 515}), "Осколок игрока1 отвечает на атаку")
	g._resolve_top()
	check(g.action(1, "effect", {"op": "reroll", "target": 0}), "Запрошен переброс владельцем0")
	if await stop_if_errors():
		return
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	var hand_button := find_button("Открыть мою руку")
	if hand_button != null:
		await click(hand_button)
	check(table._v.actor == 0 and table._v.resolving.owner == 1, "UI различает автора Осколка1 и бросающего0")
	print("ПЕРЕБРОС UI ДО ЖЕСТА: seat=", table._v.seat, " actor=", table._v.actor,
		" author=", table._v.resolving.owner, " phase=", table._v.phase,
		" state=", table._die.state, " draggable=", table._die.draggable,
		" request=", g.resolving.get("reroll_request", {}))
	if not table._die.draggable:
		# Не переводим кубик в waiting вручную: проверяем фактическую доступность владельцу.
		await mouse(table._die.center(), true)
		var captured: bool = table._die.state == "dragging"
		await mouse(table._die.center(), false)
		check(captured, "Назначенный игрок0 может захватить кубик для Осколка игрока1 настоящим InputEvent")
		await stop_if_errors()
		return
	await ready_die()
	if await stop_if_errors():
		return
	seed_face(g, 4)
	var before: int = g.roll_no
	await roll()
	await frames(8)
	check(g.roll_no == before + 1 and g.phase == "priority", "Настоящий жест создал ожидающий переброс")
	check(g.stack.back().kind == "effect_roll" and g.stack.back().value == 4, "В стеке настоящая исходная4 переброса")
	if await stop_if_errors():
		return
	# Ответ Бомбой подготовлен серверными action, его урон и завершение выполняет настоящая UI-панель.
	check(g.action(0, "loot", {"card": 497}), "Бомба отвечает до разрешения переброса")
	g._resolve_top()
	net._push_state()
	await frames(10)
	if not await apply_operation("monster_damage", 1):
		await stop_if_errors()
		return
	check(g.monsters[0].hp == 0, "UI-панель Бомбы убила цель атаки")
	await click(find_button("Эффект выполнен"))
	g._finish_responses()
	net._push_state()
	await frames(10)
	check(g.phase == "effect" and g.resolving.get("kind") == "reward", "Открылась ручная награда450")
	if await stop_if_errors():
		return
	# Напечатанная награда450 —4 монеты; выбранные поля и кнопка настоящей панели.
	if not await apply_operation("coins", 4):
		await stop_if_errors()
		return
	await click(find_button("Эффект выполнен"))
	g._finish_responses()
	net._push_state()
	await frames(10)
	check(g.coins == [7, 3] and g.bank == 90, "После UI-награды нет лишних2 от445 или3 от165")
	check(g.resolving.get("card") == 515 and int(g.resolving.get("owner", -1)) == 1,
		"Осколок вернулся правильному владельцу1")
	check(table._v.actor == 1 and table._v.resolving.owner == 1, "UI получил возврат способности игроку1")
	check(table._v.players[0].coins == 7 and table._v.players[1].coins == 3, "UI показывает правильные монеты")
	check(g._turn_attack_rolls.is_empty() and g.hp == [20, 20], "Призрачной атаки и боевого урона нет")
	if await stop_if_errors():
		return
	net.fs_switch_seat(1)
	await frames(10)
	hand_button = find_button("Открыть мою руку")
	if hand_button != null:
		await click(hand_button)
	await click(find_button("Эффект выполнен"))
	g._finish_responses()
	check(g.discards.loot.count(515) == 1 and g.discards.loot.count(497) == 1,
		"Настоящая кнопка владельца завершила Осколок, оба лута сброшены один раз")
	check(g.stack.is_empty() and g.paused_effects.is_empty(), "UI-сценарий не оставил зависших возвратов")
	print("REROLL CANCEL UI: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
