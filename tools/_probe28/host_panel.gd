extends Control
## Разовая проверка (07.11): «Панель хоста» — раздел Айзека, список не складывается от чужого действия.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.host_offline("four_souls")
	Net.set_bots(3)
	Net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(Net.fours)
	Net.set_process(false)
	Net.fs_switch_seat(0)
	var app = load("res://games/four_souls/ui/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(1.0).timeout
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.to_lower() == "открыть мою руку":
			b.pressed.emit()
	await get_tree().create_timer(0.8).timeout
	HostPanel.toggle()
	await get_tree().create_timer(0.5).timeout
	var panel: HostPanel = get_tree().root.find_children("*", "HostPanel", true, false)[0] if not get_tree().root.find_children("*", "HostPanel", true, false).is_empty() else null
	for n in get_tree().root.get_children():
		if n is HostPanel: panel = n
	panel._open_sections["fs_effects"] = true
	panel._rebuild()
	await get_tree().create_timer(0.4).timeout
	var f := FileAccess.open(OS.get_environment("OUT") + "/host_panel.txt", FileAccess.WRITE)
	var lists: Array = panel._panel.find_children("*", "OptionButton", true, false)
	f.store_line("списков в панели: %d" % lists.size())
	var rescue: OptionButton = null
	for l in lists:
		if l.item_count > 0 and str(l.get_item_text(0)).begins_with("Снять зависание"): rescue = l
	f.store_line("список аварийных действий: %s, пунктов %d" % [str(rescue != null), rescue.item_count if rescue else 0])
	rescue.show_popup()
	await get_tree().process_frame
	Net.fours.coins[1] += 1
	Net.fours.bank -= 1
	Net.fours.revision += 1
	Net._push_state()
	await get_tree().create_timer(0.3).timeout
	f.store_line("после чужого действия список открыт: %s, тот же узел: %s" % [str(is_instance_valid(rescue) and rescue.get_popup().visible), str(is_instance_valid(rescue))])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/host_panel.png")
	rescue.get_popup().hide()
	await get_tree().create_timer(0.3).timeout
	f.store_line("после закрытия панель обновилась: %s" % str(not is_instance_valid(rescue) or not rescue.is_inside_tree()))
	f.close()
	get_tree().quit()
