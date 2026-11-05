extends "res://tests/test_fs_table_runtime.gd"
## Дополнительные стороны Догмы: настоящее лицо и крупный просмотр в720p.
const Batch := preload("res://tests/fs/core/core_automation_batch16.gd")
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
	var s = Batch.new()._monster(Check.new(), 306)
	Batch.new()._trigger(s, "monster_death", {"seat": 0, "card": 306})
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(6)
	check(FSData.texture(913) != null and FSData.texture(914) != null, "Обе дополнительные стороны имеют собственные лица")
	check(table._v.monsters.any(func(monster): return int(monster.id) == 913), "Дополнительная карта видна в ряду")
	table._show_preview(913)
	await frames(6)
	check(is_instance_valid(table._preview), "Работает крупный просмотр дополнительной карты")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/harbingers16.png")
	table._hide_preview()
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS MONSTER16 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
