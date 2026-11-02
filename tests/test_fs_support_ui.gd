extends "res://tests/test_fs_table_runtime.gd"
## Пометки ручных карт до розыгрыша, подсказка у просмотра, приватность рубашек и размер окна720p.
func _run() -> void:
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("four_souls")
	net.set_bots(1)
	net.settings.fs_dlc = true
	net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(net.fours)
	net.set_process(false)
	net.fours.current = 0
	net.fours.phase = "turn"
	net.fours.items[0] = [FSData.item_entry(13), FSData.item_entry(127), FSData.item_entry(121)]
	net.fours.skipped_turns[1] = 1
	net.fs_switch_seat(0)
	change_scene_to_file("res://games/four_souls/ui/main.tscn")
	await scene_changed
	await frames(20)
	table = current_scene.screen
	await click(find_button("Открыть мою руку"))
	await frames(5)
	var player_row: Node = table.find_child("Player1", true, false)
	check(player_row != null and player_row.find_children("*", "Label", true, false).any(func(label): return label.text == "Пропуск ходов: 1"), "Отложенный пропуск виден отдельной строкой игрока")
	var fan: Control
	for node: Node in table.find_children("*", "Control", true, false):
		if node.get_script() != null and node.get_script().resource_path == "res://hub/private_hand.gd" and node._cards.has("item:13"):
			fan = node
	check(fan != null, "Личная рука содержит ручной предмет")
	if fan != null:
		check(fan._cards["item:13"]._face.find_child("CardSupportBadge", true, false) != null, "Ручная карта помечена до розыгрыша")
		check(fan._cards["item:127"]._face.find_child("CardSupportBadge", true, false).text == "Ч", "Частичный эффект отличается от ручного")
		check(fan._cards["item:121"]._face.find_child("CardSupportBadge", true, false) == null, "Полностью автоматическая карта без ручной пометки")
	var container := Control.new()
	table.add_child(container)
	var hidden: Control = table._fan(container, [{"key": "hidden", "id": -1, "face_up": false}], "support-test", false)
	check(hidden.find_children("CardSupportBadge", "Label", true, false).is_empty(), "Рубашки не раскрывают сведения о закрытой карте")
	var revealed: Control = table._fan(container, [{"key": "revealed", "id": 7, "face_up": true}], "support-open", false)
	check(revealed._cards["revealed"]._face.texture == FSData.texture(7), "Лицо разрешённой открытой чужой карты действительно нарисовано")
	container.queue_free()
	for dark: bool in [true, false]:
		root.get_node("Prefs").theme_mode = "dark" if dark else "light"
		table._show_preview(727)
		await frames(4)
		var hint: Label = table._preview.find_child("CardSupportHint", true, false)
		check(hint != null and hint.text.contains("Атаковать верх колоды"), "Просмотр объясняет ручной выбор карты")
		check(Rect2(Vector2.ZERO, root.size).encloses(hint.get_global_rect()), "Подсказка полностью внутри1280×720")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots/fs02"))
		await process_frame
		root.get_texture().get_image().save_png("res://build/shots/fs02/support_%s.png" % ("dark" if dark else "light"))
		table._hide_preview()
	var dialog: VBoxContainer = table._card_dialog(727, "Просмотр", "", null, false)
	await frames(5)
	check(dialog.get_global_rect().size.y <= 696, "Инструкция и кнопки окна помещаются по высоте720p")
	print("CARD SUPPORT UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
