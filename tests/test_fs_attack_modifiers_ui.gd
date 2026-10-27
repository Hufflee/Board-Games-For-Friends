## Настоящий стол и жесты TossDie: исходная грань, итог в журнале, защита и HP для34+36.
## Подготовленный бой; --headless --audio-driver Dummy --max-fps 60 --script res://tests/test_fs_attack_modifiers_ui.gd.
## Проверка API/текста без утверждений о внешнем виде и без полной естественной партии.
extends "res://tests/test_fs_passive_events_ui.gd"

func seed_face(g: FSRules, face: int) -> bool:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 101):
		rng.seed = seed_value
		if rng.randi_range(1, 6) == face:
			g._rng.seed = seed_value
			return true
	check(false, "Найден seed исходной грани%d" % face)
	return false

func wait_settled() -> bool:
	for i in 900:
		await process_frame
		if table._die.state == "settled":
			return true
	check(false, "Кубик дошёл до состояния settled")
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
	g.items = [[FSData.item_entry(34), FSData.item_entry(36)], []]
	g.hands = [[], []]
	g.hp = [20, 20]
	g.max_hp = [20, 20]
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
	# Тестовые HP/DC, обычный Сгусток без особых триггеров грани.
	g.monsters = [{"id": 450, "hp": 20, "dc": 4, "at": 1}]
	g.log.clear()
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	var hand_button := find_button("Открыть мою руку")
	if hand_button != null:
		await click(hand_button)
	check(is_instance_valid(table._die), "Стол создал кубик")
	if not is_instance_valid(table._die):
		await root.get_node("Sfx").request_quit(1)
		return
	check(table._die.get_script().resource_path == "res://hub/toss_die.gd", "Используется настоящий TossDie")
	check(table._v.monsters[0].dc == 3 and g.monsters[0].dc == 4, "UI получил эффективную защиту3 при исходной4")
	var start_roll: int = g.roll_no
	var raw_faces := [3, 2, 5, 2]
	for gesture in range(1, 5):
		await ready_die()
		if errors or not seed_face(g, raw_faces[gesture - 1]):
			break
		await roll()
		await frames(8)
		check(g.roll_no == start_roll + gesture, "Жест%d создал ровно один бросок" % gesture)
		check(int(g._turn_attack_rolls.get(0, 0)) == gesture - 1, "Разрешено%d предыдущих атак" % (gesture - 1))
		if not await wait_settled():
			break
		check(table._die._result == raw_faces[gesture - 1] and table._die._die.value == raw_faces[gesture - 1],
			"TossDie показывает исходную грань текущего ожидающего броска%d" % gesture)
		var expected_monster_hp := 20 if gesture == 1 else 19
		var expected_player_hp := 20 if gesture <= 2 else (19 if gesture == 3 else 18)
		check(int(g.monsters[0].hp) == expected_monster_hp and g.hp[0] == expected_player_hp,
			"Реальный урон после жеста%d соответствует модификаторам и запрету6" % gesture)
		var health: Control = table.find_child("MonsterHealth0", true, false)
		check(health != null and health.current == expected_monster_hp, "UI сердца монстра совпадают с хостом")
		print("UI34/36 жест=", gesture, " кубик=", table._die._die.value,
			" HPмонстра=", g.monsters[0].hp, " HPигрока=", g.hp[0])
		if errors:
			break
	if not errors:
		await click(find_button("Журнал"))
		await frames(5)
		var visible_log := ""
		for text: RichTextLabel in table.find_children("*", "RichTextLabel", true, false):
			if text.is_visible_in_tree():
				visible_log += text.text + "\n"
		check(visible_log.contains("3 +1 → 4 (итог)"), "Настоящее окно журнала различает исходную3 и итоговую4")
		check(visible_log.contains("5 +1 → 6 (итог)"), "Настоящее окно журнала показывает итоговую6 третьей атаки")
		check(g.hp[0] == 18 and int(g.monsters[0].hp) == 19, "Итоговая6 от36 промахнулась из-за34")
	print("ATTACK MODIFIERS UI: ", checks, " проверок, ", errors, " ошибок")
	await root.get_node("Sfx").request_quit(1 if errors else 0)
