extends "res://tests/test_fs_table_runtime.gd"
## Обычная комната с ценой здоровья. Настоящий клик и экран720p.
const Batch := preload("res://tests/fs/core/core_automation_batch24.gd")
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
	var s = batch._game(Check.new(), 71)
	batch._room24(s, 760)
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	for node in table.find_children("*", "Button", true, false):
		if int(node.get_meta("card_id", -1)) == 760:
			await click(node)
			break
	await frames(5)
	var pay := find_button("Заплатить 1 здоровье → получить 3¢")
	check(pay != null and not pay.disabled, "В карточке комнаты доступна её напечатанная цена")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/native_room24.png")
	if pay != null:
		await click(pay)
	s.close()
	check(s.g.hp[0] == 1 and s.g.coins[0] == 11, "Комната списала здоровье и выдала монеты")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS PACKET24 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
