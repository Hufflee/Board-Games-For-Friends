extends "res://tests/test_fs_table_runtime.gd"
## Короткий UI пакета13: приватный просмотр173 через собственную кнопку.
const Batch := preload("res://tests/fs/core/core_automation_batch13.gd")
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
	var s = Batch.new()._game(Check.new(), 173)
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(6)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	table._item_dialog(1)
	await frames(5)
	var inspect := find_button("Посмотреть верхнее сокровище")
	check(inspect != null, "173есть кнопка собственного пассива")
	check(inspect != null and Rect2(Vector2.ZERO, root.size).encloses(inspect.get_global_rect()), "Кнопка просмотра помещается в720p")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/treasure_inspect.png")
	await click(inspect)
	await frames(6)
	check(s.g.peek.get("cards", []) == [s.g.decks.treasure.back()], "Клик открыл настоящий верх колоды")
	check(s.g.get_view(1).peek.is_empty(), "Другому месту верх не раскрыт")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS TREASURE13 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
