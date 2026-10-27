extends "res://tests/test_fs_passive_events_ui.gd"
## Настоящие кнопки обязательной атаки Засады и размещения Утопца после Пипа, 1280×720.

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
	g.phase = "turn"
	g.items = [[], []]
	g.hands = [[], []]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g.battle = -1
	g.monsters = [{"id": 450, "hp": 3, "dc": 4, "at": 1}, {"id": 451, "hp": 3, "dc": 4, "at": 1}]
	g.decks.monster = [450, 451]
	g._push({"kind": "event", "card": 715, "owner": 0}, "turn")
	g._finish_responses()
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	check(find_button("Закончить ход").disabled, "Конец хода закрыт до обязательных атак")
	var health: Control = table.find_child("MonsterHealth0", true, false)
	await click(health.get_parent().get_child(0))
	check(find_button("Атаковать").disabled, "Атака открытого монстра недоступна при Засаде")
	await click(find_button("Закрыть"))
	await click(find_button("Атаковать верх колоды"))
	await click(find_button(FSData.title(int(g.monsters[0].id))))
	check(int(table._v.forced_deck_attacks) == 1, "Выбор верхней атаки через UI уменьшил остаток до1")
	g.phase = "turn"
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g._after_stack = "turn"
	g.monsters = [{"id": 429, "hp": 0, "dc": 4, "at": 1}, {"id": 451, "hp": 3, "dc": 4, "at": 1}]
	g.battle = 0
	g.decks.monster = [450, 282, 451]
	g._continue_stack()
	g._finish_responses()
	net.fs_switch_seat(0)
	await frames(8)
	if find_button("Открыть мою руку") != null:
		await click(find_button("Открыть мою руку"))
	check(find_button("Применить") == null, "Награда ещё не доступна до размещения Утопца")
	var place := find_button("Выложить Утопца · ячейка 2")
	var scroll := place.get_parent()
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	check(scroll != null and scroll.get_global_rect().encloses(place.get_global_rect()), "Кнопка обязательного выбора видна без прокрутки при720p")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fs_passive_audit/followup/ui-peep-choice.png")
	await click(find_button("Выложить Утопца · ячейка 2"))
	check(int(g.monsters[1].id) == 282 and int(g.monsters[1].under.id) == 451, "Кнопка разместила Утопца поверх выбранного монстра")
	check(g.phase == "effect" and not g.resolving.has("spawn_card"), "Исходная награда осталась открыта")
	g.decks.treasure = [180]
	await operation("treasure", 1)
	check(g.items[0].size() == 1 and g.items[0][0].id == 180, "После размещения награда применена кнопкой")
	print("AMBUSH PEEP UI: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
