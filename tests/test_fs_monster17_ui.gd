extends "res://tests/test_fs_table_runtime.gd"
## Ограниченная добавочная атака360: настоящие кнопки стола в720p.
const Batch := preload("res://tests/fs/core/core_automation_batch17.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _find_card17(node: Node, id: int) -> Button:
	if node is Button and int(node.get_meta("card_id", -1)) == id:
		return node
	for child in node.get_children():
		var found := _find_card17(child, id)
		if found != null:
			return found
	return null
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
	var s = Batch.new()._monster(Check.new(), 360)
	s.g.attack_left = 0
	s.g.attacked = true
	Batch.new()._trigger(s, "monster_death", {"seat": 0, "card": 360})
	s.choose(0, "extra_blind17")
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(8)
	await click(find_button("Открыть мою руку"))
	await frames(6)
	check(bool(table._v.blind_only17), "360 вид содержит ограниченную добавочную атаку")
	var blind := find_button("Атаковать верх колоды")
	check(blind != null and not blind.disabled, "360 разрешена атака колоды")
	var end := find_button("Закончить ход")
	check(end != null and not end.disabled, "360 необязательную атаку можно пропустить")
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/blind_extra17.png")
	await click(_find_card17(table, 360))
	await frames(5)
	var ordinary := find_button("Атаковать")
	check(ordinary != null and ordinary.disabled, "360 настоящий клик по монстру не разрешает обычную атаку")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS MONSTER17 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
