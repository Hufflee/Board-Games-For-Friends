extends "res://tests/test_fs_table_runtime.gd"
## Ручные операции доступны из общей панели хоста и закрыты обычному протоколу.
const Batch := preload("res://tests/fs/core/core_automation_batch27.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _root_button(text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
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
	var batch := Batch.new()
	var s = batch._game(Check.new(), 71)
	s.operation_panel()
	net.fours = s.g
	table._turn_seen = 0
	net.fs_switch_seat(0)
	await frames(10)
	check(find_button("Применить") == null, "Ручной ввод скрыт с игрового стола")
	net.send_action("effect", {"op": "coins", "target": 0, "amount": 1})
	check(int(s.g.coins[0]) == 8, "Обычный канал действий не выполняет ручное исправление")
	var panel_button: Button = table.get("_top").get("_host_btn")
	check(panel_button != null and panel_button.visible, "Кнопка общей панели доступна хосту")
	if panel_button != null:
		await click(panel_button)
	await frames(8)
	var game_section := _root_button("▾  Игра")
	if game_section != null:
		await click(game_section)
	var section := _root_button("▸  Айзек · аварийные операции")
	check(section != null, "В общей панели есть раздел Айзека")
	if section != null:
		await click(section)
	await frames(8)
	var apply := _root_button("Применить исправление")
	check(apply != null, "Операция доступна в разделе хоста")
	if apply != null:
		for child in apply.get_parent().get_children():
			if child is OptionButton and child.item_count > 1 and child.get_item_text(1) == "Монеты ±":
				child.select(1)
				child.item_selected.emit(1)
				break
	DirAccess.make_dir_recursive_absolute("res://build/shots/fs_automation04")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/fs_automation04/host27.png")
	if apply != null:
		await click(apply)
	check(int(s.g.coins[0]) == 9, "Хост исправил монеты текущего эффекта")
	var done := _root_button("Завершить текущий эффект")
	if done != null:
		await click(done)
	check(s.g.phase == "turn", "Панель вернула партию в обычный ход")
	current_scene.back_to_hub()
	await scene_changed
	await frames(8)
	print("FS HOST27 UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
