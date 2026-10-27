extends "res://tests/test_fs_passive_events_ui.gd"
## Выбор игрока и уничтожение его карты души через настоящую ручную панель.

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
	g.stack.clear()
	g.bonuses.clear()
	g.resolving = {"kind": "reward", "card": 389, "owner": 0}
	g.souls = [0, 2]
	g.soul_cards = [[], [{"id": 454, "value": 2}]]
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await operation("destroy_soul", 1, 1)
	check(g.souls[1] == 0 and g.soul_cards[1].is_empty(), "Кнопка убрала всю двухочковую карту души")
	check(g.discards.monster.has(454), "Карта находится в правильном сбросе")
	check(table._v.players[1].souls == 0 and table._v.players[1].souls_cards.is_empty(), "UI видит согласованные счётчик и карты")
	print("DESTROY SOUL UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
