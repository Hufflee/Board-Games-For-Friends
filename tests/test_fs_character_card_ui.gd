extends "res://tests/test_fs_table_runtime.gd"
## Персонаж рядом со стартовым предметом:720p,превью и настоящая активация.
const Batch := preload("res://tests/fs/core/core_character_activation.gd")
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
	var s = Batch.new()._game(Check.new())
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(5)
	var fan = table._own_fan
	var character_key := "character:0"
	test_character(fan, character_key)
	var entry: Dictionary = fan.entries.filter(func(card): return bool(card.get("character", false)))[0]
	fan.chosen.emit(entry)
	await frames(5)
	var activate := find_button("Повернуть персонажа → ещё один розыгрыш добычи")
	check(activate != null and not activate.disabled, "Настоящая кнопка персонажа доступна")
	await click(activate)
	await frames(5)
	check(not s.g.character_ready[0], "Настоящий клик повернул персонажа на хосте")
	s.close()
	net._push_state()
	await frames(8)
	check(int(s.g._bonus_loot_plays[0]) == 1, "Персонаж дал один дополнительный розыгрыш")
	check(bool(table._collect_charge(table._v).get("c:0", false)), "Поворот персонажа виден в материале карты")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/character_card.png")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS CHARACTER UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
func test_character(fan: Control, key: String) -> void:
	check(key in fan.order, "В личной руке есть карта персонажа")
	var eternal: Array = fan.entries.filter(func(card): return bool(card.get("starting", false)))
	check(not eternal.is_empty(), "Стартовый предмет остаётся видимым")
	if not eternal.is_empty():
		check(fan.order.find(str(eternal[0].key)) == fan.order.find(key) + 1, "Персонаж непосредственно рядом со стартовым предметом")
