extends "res://tests/test_fs_table_runtime.gd"
## Один экран720p: способность комнаты, открытая добыча и настоящий бросокD8 мышью.
const Batch := preload("res://tests/fs/core/core_automation_batch20_treasures.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(15)
	table = current_scene.screen
	var s = Batch.new()._game(Check.new(), 12)
	s._take(19)
	var room := FSData.item_entry(19)
	room["room_item20"] = true
	s.g._extra_rooms20.append(room)
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(10)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	table._room_dialog20(0)
	await frames(5)
	var use := find_button("Применить способность комнаты")
	check(use != null and not use.disabled, "Активному доступна настоящая кнопка комнаты")
	await click(use)
	s.close()
	net._push_state()
	await frames(8)
	check(int(table._v.get("loot_top20", -1)) >= 0, "Способность комнаты открыла настоящий верх добычи")
	Batch.new()._activate(s)
	s.choose(0, "next_d8_20", {"target": 0})
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(8)
	net._push_state()
	await frames(8)
	check(table._die.max_face == 8 and table._die.draggable, "Для следующего броска показан доступныйD8")
	await roll()
	for frame in 900:
		await process_frame
		if table._die.state == "settled":
			break
	check(s.g._last_raw_die20 == 8 and s.g.last_roll == 6, "Жест мыши бросил8, правила получили6")
	check(table._die.max_face == 8, "Показ результата сохранил восьмигранный кубик")
	check(table._die._die.value == 8, "ОстановившийсяD8 действительно показывает8")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/packet20_d8_rooms.png")
	var normal: Control = load("res://hub/toss_die.gd").new()
	check(normal.max_face == 6, "Обычный общий кубик по умолчанию шестигранный")
	normal.free()
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS PACKET20 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
