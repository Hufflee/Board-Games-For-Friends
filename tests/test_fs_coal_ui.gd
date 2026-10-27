## Узкий сценарий 18 на настоящем столе: пять жестов TossDie, порог бонуса и фиксированный урон.
## Подготовленное состояние, не естественная партия и не визуальная проверка оформления.
## --headless --audio-driver Dummy --max-fps 60 --script res://tests/test_fs_coal_ui.gd.
extends "res://tests/test_fs_passive_events_ui.gd"

func seed_six(g: FSRules) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 101):
		rng.seed = seed_value
		if rng.randi_range(1, 6) == 6:
			g._rng.seed = seed_value
			return
	check(false, "Найден seed настоящего броска на шестёрку")

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
	g.items = [[FSData.item_entry(18)], []]
	g.hands = [[], []]
	g.hp = [5, 5]
	g.max_hp = [5, 5]
	g.attack = [1, 1]
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
	g.monsters = [{"id": 462, "hp": 100, "dc": 3, "at": 1}]
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	var hand_button := find_button("Открыть мою руку")
	if hand_button != null:
		await click(hand_button)
	# Проверяем путь после создания сцены: статический is TossDie загружает его до автозагрузок.
	check(is_instance_valid(table._die), "Стол создал кубик")
	if not is_instance_valid(table._die):
		await root.get_node("Sfx").request_quit(1)
		return
	check(table._die.get_script().resource_path == "res://hub/toss_die.gd", "Стол использует настоящий TossDie")
	var first_roll: int = g.roll_no
	# Следующий жест сначала разрешает предыдущий бросок по штатным окнам ответов.
	for gesture in range(1, 6):
		await ready_die()
		if errors:
			break
		check(table._die.draggable, "Кубик доступен перед жестом %d" % gesture)
		seed_six(g)
		await roll()
		await frames(8)
		check(g.roll_no == first_roll + gesture, "Жест %d создал ровно один бросок" % gesture)
		check(g.last_roll == 6, "Жест %d получил шестёрку от хоста" % gesture)
		check(int(g._turn_attack_rolls.get(0, 0)) == gesture - 1,
			"Перед следующим действием разрешено %d атак" % (gesture - 1))
		var expected_attack := 2 if gesture >= 4 else 1
		var expected_hp: int = [100, 99, 98, 97, 95][gesture - 1]
		check(g.attack[0] == expected_attack, "18: атака хоста после жеста %d" % gesture)
		check(table._v.players[0].attack == expected_attack, "18: атака в состоянии UI после жеста %d" % gesture)
		check(int(g.monsters[0].hp) == expected_hp, "18: третий урон равен 1, четвёртый равен 2")
		var health: Control = table.find_child("MonsterHealth0", true, false)
		check(health != null and health.current == expected_hp, "Сердечки отражают фактический урон")
		check(not table._die.draggable, "Полёт блокирует повторный захват")
		print("UI18 жест=", gesture, " разрешено=", g._turn_attack_rolls.get(0, 0),
			" ATK=", g.attack[0], " HP=", g.monsters[0].hp)
		if errors:
			break
	check(g.temporary_attack == [[0, 1]], "Четвёртая разрешённая атака не удваивает временный бонус")
	print("COAL UI: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
