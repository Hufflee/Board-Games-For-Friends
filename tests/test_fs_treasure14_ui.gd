extends "res://tests/test_fs_table_runtime.gd"
## Пакет14: обязательная атака видна на столе в720p.
const Batch := preload("res://tests/fs/core/core_automation_batch14.gd")
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
	var s = Batch.new()._game(Check.new(), 239)
	Batch.new()._activate(s)
	s.choose(0, "force_monster14", {"item": 1})
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(6)
	var end := find_button("Закончить ход")
	var blind := find_button("Атаковать верх колоды")
	check(end != null and end.disabled, "239 завершение хода выключено")
	check(blind != null and blind.disabled, "239 атака колоды выключена")
	check(s.g.get_view(0).forced_monster_slots == [1], "239 в состоянии указан выбранный монстр")
	check(end != null and Rect2(Vector2.ZERO, root.size).encloses(end.get_global_rect()), "Кнопки помещаются в720p")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/forced_monster.png")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS TREASURE14 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
