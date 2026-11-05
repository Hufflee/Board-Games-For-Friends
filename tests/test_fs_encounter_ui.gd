extends "res://tests/test_fs_table_runtime.gd"
## Короткий UI-проход пакета40: выбор слота босса и передача следующего броска другому месту.
const Batch := preload("res://tests/fs/core/core_automation_batch11.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.settings.fs_dlc = true
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(15)
	table = current_scene.screen
	var batch := Batch.new()
	var s = batch._game(Check.new())
	for id in [348, 395]:
		s._take(id); s.g.decks.monster.append(id)
	batch._event(s, 725)
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(6)
	await click(find_button("Открыть мою руку"))
	await frames(6)
	check(find_button("Применить") == null, "Событие не открывает произвольную панель")
	await click(find_button("Выбрать цель / вариант"))
	await frames(5)
	var choice := find_button(str(table._v.card_choices[0]))
	check(choice != null, "У Натиска боссов есть кнопка конкретного слота")
	if choice != null:
		check(Rect2(Vector2.ZERO, root.size).encloses(choice.get_global_rect()), "Название босса и слота помещается в720p")
		DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/shots/fs_automation04/boss_rush.png")
		await click(choice)
		await frames(6)
		check(net.fours.monsters.any(func(m): return int(m.id) == 395), "Клик автоматически разместил босса")
	s = batch._game(Check.new())
	batch._event(s, 734)
	s.roll(6); s.ok(0, "effect_roll"); s.close()
	net.fours = s.g
	net.fs_switch_seat(1)
	await frames(7)
	check(int(table._v.actor) == 1 and bool(table._v.card_roll_wait), "Следующий кубик принадлежит второму игроку")
	check(int(table._v.current) == 0, "Очередной бросок события не меняет активного игрока")
	current_scene.back_to_hub()
	await scene_changed
	await frames(10)
	s = null
	print("FS ENCOUNTER UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
