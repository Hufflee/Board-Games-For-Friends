extends "res://tests/test_fs_passive_events_ui.gd"
## Подготовленная Тишина: настоящий бросок после предыдущей6, HP в UI и ручной небоевой урон.

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
	g.phase = "battle_roll"
	g.battle = 0
	g.items = [[], []]
	g.hp = [5, 5]
	g.max_hp = [5, 5]
	g.attack = [3, 1]
	g.curses = [[], []]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g._death_queue.clear()
	g._after_stack = "battle_roll"
	g.monsters = [{"id": 281, "hp": 6, "dc": 1, "at": 1, "last_attack_roll": 6}]
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await roll()
	var first: int = g.last_roll
	await ready_die()
	await roll()
	check(g.hp[0] == 4 and g.monsters[0].hp == 6, "Любая выпавшая грань после6 — промах, игрок теряет1HP")
	check(int(g.monsters[0].last_attack_roll) == first, "История хранит разрешённый бросок, а не ещё ожидающий ответов")
	var health: Control = table.find_child("MonsterHealth0", true, false)
	check(health.current == 6, "UI оставил Тишине6HP после промаха")
	g.phase = "effect"
	g.stack.clear()
	g.next_action = {}
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	net.fs_switch_seat(0)
	await frames(6)
	if find_button("Открыть мою руку") != null:
		await click(find_button("Открыть мою руку"))
	await operation("monster_damage", 3)
	check(g.monsters[0].hp == 5, "Ручная панель применяет к Тишине только1 урон из3")
	health = table.find_child("MonsterHealth0", true, false)
	check(health.current == 5, "HP монстра в интерфейсе обновлены")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-hush.png")
	print("HUSH UI: ", checks, " проверок, ", errors, " ошибок; первый бросок=", first)
	quit(1 if errors else 0)
