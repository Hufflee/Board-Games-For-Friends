extends "res://tests/test_fs_attack_modifiers_ui.gd"
## Реальный TossDie: спасение Всадника264 на4, затем настоящая награда на6, без преждевременной души.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func resolve_windows(g: FSRules) -> void:
	for i in 12:
		if g.phase != "priority":
			break
		g.tick(5.1)
	net._push_state()
	await frames(5)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Engine.time_scale = 3.0
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	net.set_process(false)
	var scenario := Scenario.new(Check.new()).players(2).dlc().current(0).character(0, 821) \
		.no_items(0).no_items(1).item(0, 16).monster(0, 264, {"hp": 1}).monster(1, 344) \
		.deck_top("treasure", [91]).build()
	var g: FSRules = scenario.g
	net.fours = g
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	var health: Control = table.find_child("MonsterHealth0", true, false)
	await click(health.get_parent().get_child(0))
	await click(find_button("Атаковать"))
	await ready_die()
	scenario.roll(4, [6])
	await roll()
	await wait_settled()
	await resolve_windows(g)
	check(g.phase == "battle_roll" and g.monsters[0].hp == 2, "После4 бой продолжается с полным здоровьем Всадника")
	check(g.monsters[0].dc == 4 and g.monsters[0].at == 2, "В UI-снимке усилены защита и атака")
	check(table._v.monsters[0].hp == 2 and table._v.players[0].souls == 0, "Сердца и души UI соответствуют спасению")
	check(find_button("Эффект выполнен") == null, "Спасение не открывает ложную награду смерти")
	check(g.items[0].any(func(item): return item.id == 91), "Награда за спасение — настоящее сокровище")
	await ready_die()
	await roll()
	await wait_settled()
	await resolve_windows(g)
	check(g.resolving.is_empty(), "Следующая6 выдала настоящую награду без ручной панели")
	check(find_button("Эффект выполнен") == null, "Ручное подтверждение обычной награды не требуется")
	check(g.souls[0] == 1, "Душа настоящей смерти начислена автоматически")
	print("HORSEMAN UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
