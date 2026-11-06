extends "res://tests/test_fs_table_runtime.gd"
## Оплата второй способности на повёрнутом предмете, 1280×720.
const Batch := preload("res://tests/fs/core/core_automation_batch21.gd")
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
	var s = Batch.new()._game(Check.new(), 44)
	s.g.items[0][1].tapped = true
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	table._item_dialog(1)
	await frames(6)
	var paid := find_button("Заплатить 7¢ и перезарядить")
	check(paid != null and not paid.disabled, "Платная способность доступна повёрнутому предмету")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/battery21.png")
	if paid != null:
		await click(paid)
	s.close()
	check(s.g.coins[0] == 1, "Кнопка списала на хосте ровно7¢")
	check(not bool(s.g.items[0][1].tapped), "Аккумулятор перезаряжен собственной способностью")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS PACKET21 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
