extends "res://tests/test_fs_table_runtime.gd"
## Оплата превращения повёрнутой Кости в физическую душу, 1280×720.
const Batch := preload("res://tests/fs/core/core_automation_batch25.gd")
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
	var batch := Batch.new()
	var s = batch._game(Check.new(), 843)
	s.g.items[0][1].tapped = true
	s.g.items[0][1].counters = 5
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	table._item_dialog(1)
	await frames(6)
	var paid := find_button("5 жетонов → стать душой")
	check(paid != null and not paid.disabled, "Платная способность доступна повёрнутому предмету")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/bone25.png")
	if paid != null:
		await click(paid)
	s.close()
	check(s.zone_of(843) == "soul:0", "Кнопка переместила Кость из предметов в души")
	check(s.g.items[0].size() == 1, "Исходная карта не осталась второй копией предмета")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS PACKET25 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)

