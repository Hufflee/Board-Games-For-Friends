extends "res://tests/test_fs_table_runtime.gd"
## Реальное размещение Утопца вместо прежней ручной панели Пипа,720p.
const Batch := preload("res://tests/fs/core/core_automation_batch19.gd")
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
	var s = Batch.new()._monster(Check.new(), 429)
	Batch.new()._trigger(s, "monster_death", {"seat": 0, "card": 429})
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	check(table._v.card_automated, "429 эффект уже автоматический")
	check(not s.g.resolving.has("spawn_card"), "429 старый ручной режим не открыт")
	await click(find_button("Выбрать цель / вариант"))
	await frames(5)
	var pick := find_button("Слот монстров 2")
	check(pick != null and not pick.disabled, "429 доступна реальная кнопка слота")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/peep_slot19.png")
	await click(pick)
	await frames(5)
	check(FSData.card(int(s.g.monsters[1].id)).get("key", "") == "bloat", "429 настоящий клик размещает Утопца")
	check(not s.g._card_automation_active(), "429 выбор закончен автоматически")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS MONSTER19 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
