extends Control
## Разовая проверка (07.11): дрожат ли карты без действий — серия кадров подряд (env CURSE=1 — проклятие 729 у себя).
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.host_offline("four_souls")
	Net.set_bots(3)
	Net.start_game()
	preload("res://tests/fs_test_setup.gd").finish(Net.fours)
	var g = Net.fours
	Net.set_process(false)
	if OS.get_environment("CURSE") == "1":
		g.curses[0].append(729)
		g.revision += 1
	if OS.get_environment("TOGGLE") == "1":
		g.current = 1
		g.hands[0] = [480, 497, 515, 509, 481]
		g.character_ready[0] = true
	Net.fs_switch_seat(0)
	var app = load("res://games/four_souls/ui/main.tscn").instantiate()
	add_child(app)
	await get_tree().create_timer(1.0).timeout
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text.to_lower() == "открыть мою руку":
			b.pressed.emit()
	await get_tree().create_timer(2.5).timeout
	var table: Node = get_tree().root.find_children("*", "Control", true, false).filter(func(n): return n.get("_fx_layer28") != null)[0]
	var rev0: int = int(table._v.revision)
	var count := [0]
	Net.state_changed.connect(func(_v): count[0] += 1)
	var tag := "c" if OS.get_environment("CURSE") == "1" else "n"
	if OS.get_environment("TOGGLE") == "1":
		tag = "t"
	for i in 4:
		if tag == "t":
			g.phase = "priority" if i % 2 == 0 else "turn"
			if i % 2 == 0:
				g.stack.append({"kind": "roll", "value": 3, "owner": 1})
			else:
				g.stack.clear()
			g.revision += 1
			Net._push_state()
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.13).timeout
		await _snap("shake_%s_%d" % [tag, i])
	var f := FileAccess.open(OS.get_environment("OUT") + "/shake_%s.txt" % tag, FileAccess.WRITE)
	f.store_line("обновлений состояния за ~0.5 с: %d, ревизия %d → %d, фаза %s ходит %d" % [count[0], rev0, int(table._v.revision), str(table._v.phase), int(table._v.current)])
	f.close()
	get_tree().quit()
