extends "res://tests/test_fs_table_runtime.gd"
## Пакет15: две способности248 и физическая цель-фамильяр в720p.
const Batch := preload("res://tests/fs/core/core_automation_batch15.gd")
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
	var s = Batch.new()._game(Check.new(), 248)
	Batch.new()._item(s, 1, 275)
	s.g.items[0][1].counters = 3
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(6)
	var attack := find_button("Атаковать: " + FSData.title(275) + " · " + s.g.name_of(1))
	check(attack != null and not attack.disabled, "275 доступна атака физического предмета")
	check(attack != null and Rect2(Vector2.ZERO, root.size).encloses(attack.get_global_rect()), "275 кнопка помещается в720p")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/familiar15.png")
	table._item_dialog(1)
	await frames(5)
	var kill := find_button("Сбросить 3 жетона → убить")
	check(kill != null and not kill.disabled, "248 отдельная платная способность доступна")
	check(find_button("Повернуть → эффект") != null, "248 поворот остаётся отдельной способностью")
	await click(kill)
	await frames(6)
	check(int(s.g.items[0][1].counters) == 0, "248 настоящий клик оплатил3жетона")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS PACKET15 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
