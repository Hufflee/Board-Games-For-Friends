extends Control
## Разовая проверка (07.11): стопка «СБРОС» из трёх карт — новая сверху, крупный просмотр и лупа показывают её;
## история сброса — просмотр поверх окна.
func _hover(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	Prefs.pointer_position = at if "pointer_position" in Prefs else at
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.host_offline("four_souls")
	Net.set_bots(3)
	Net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(Net.fours)
	Net.set_process(false)
	var g = Net.fours
	for i in 3:
		g.discards.loot.append(g.hands[0].pop_back())
	var newest: int = int(g.discards.loot.back())
	g.revision += 1
	Net.fs_switch_seat(0)
	var app = load("res://games/four_souls/ui/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(1.0).timeout
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.to_lower() == "открыть мою руку":
			b.pressed.emit()
	await get_tree().create_timer(1.5).timeout
	var table: Node = get_tree().root.find_children("*", "Control", true, false).filter(func(n): return n.get("_fx_layer28") != null)[0]
	var pile: Node = get_tree().root.find_child("PlayedPile", true, false)
	var top: Control = pile.find_children("*", "Button", true, false)[0]
	var f := FileAccess.open(OS.get_environment("OUT") + "/pile_hover.txt", FileAccess.WRITE)
	var at: Vector2 = top.get_global_rect().position + Vector2(20, 30)
	await _hover(at)
	await get_tree().create_timer(0.6).timeout
	f.store_line("просмотр: открыт %s, карта %s (нужна %d)" % [str(is_instance_valid(table._preview)), str(table._preview.texture == FSData.texture(newest)) if is_instance_valid(table._preview) else "-", newest])
	Prefs.card_preview_mode = "magnifier"
	var lens = preload("res://hub/card_magnifier.gd").ensure(Prefs)
	await _hover(at + Vector2(1, 1))
	var found: Dictionary = lens._card_at(at + Vector2(1, 1))
	f.store_line("лупа: верхняя новая карта %s" % str(found.get("tex") == FSData.texture(newest)))
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/pile_lens.png")
	Prefs.card_preview_mode = "card"
	table._played_history()
	await get_tree().process_frame
	await get_tree().process_frame
	var cell: Control = table._popup.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("card_id"))[0]
	await _hover(cell.get_global_rect().get_center())
	await get_tree().create_timer(0.6).timeout
	f.store_line("история: просмотр открыт %s, поверх окна %s" % [str(is_instance_valid(table._preview)), str(is_instance_valid(table._preview) and table._preview.z_index > table._popup.z_index)])
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/pile_history.png")
	f.close()
	get_tree().quit()
