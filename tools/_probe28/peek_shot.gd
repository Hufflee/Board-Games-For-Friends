extends Control
## Разовая проверка (07.11): окно просмотра верха колоды — карты видны целиком.
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.host_offline("four_souls")
	Net.set_bots(3)
	Net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(Net.fours)
	Net.set_process(false)
	var g = Net.fours
	g.current = 0
	g.phase = "turn"
	g._gain_item(0, 826, true)
	var slot: int = g.items[0].size() - 1
	g.action(0, "activate", {"item": slot})
	g._finish_responses()
	var choices: Array = g.get_view(0).card_choices
	for i in choices.size():
		if str(choices[i]).contains("Добыча"):
			g.action(0, "card_choice", {"index": i, "revision": g.revision})
			break
	g.revision += 1
	Net.fs_switch_seat(0)
	var app = load("res://games/four_souls/ui/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(1.0).timeout
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.to_lower() == "открыть мою руку":
			b.pressed.emit()
	await get_tree().create_timer(1.2).timeout
	var table: Node = get_tree().root.find_children("*", "Control", true, false).filter(func(n): return n.get("_fx_layer28") != null)[0]
	table._card_choice_dialog()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/peek_dialog.png")
	get_tree().quit()
