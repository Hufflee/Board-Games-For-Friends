extends SceneTree
## Вставка коробки в заполненный ящик: лишнее уходит цепочкой в соседние, без потерь и дублей.
## Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_shelf_cascade30.gd
var checks := 0
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("SC30 ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var room: Node = load("res://hub/neon_room.gd").new()
	root.add_child(room)
	await create_timer(0.7).timeout
	var before: Array = room._shelf_ids()
	var total := 0
	for row: Array in before:
		total += row.size()
	var found := false
	for box: Node in room.boxes:
		if box.is_cups():
			continue
		for target: int in room._rows.size():
			if (room._rows[target] as Array).has(box):
				continue
			var trial: Array = (room._rows[target] as Array).duplicate()
			trial.insert(0, box)
			if not room._row_overflows(trial, target):
				continue
			room._pressed_box = box
			room._start_drag()
			var cascade: Array = room._cascade_rows(target, 0)
			if cascade.is_empty():
				room._finish_drag(false)
				continue
			found = true
			room._drag_to = Vector2i(target, 0)
			room._drag_cascade = cascade
			room._reflow(true)
			room._finish_drag(true)
			var after: Array = room._shelf_ids()
			var seen := {}
			var count := 0
			for row: Array in after:
				for id: String in row:
					seen[id] = true
					count += 1
			check(count == total and seen.size() == total, "все предметы на месте ровно по разу (%d)" % count)
			check((room._rows[target] as Array).has(box) and (room._rows[target] as Array).find(box) == 0, "коробка встала в заполненный ящик")
			var fit := true
			for cell: int in room._rows.size():
				fit = fit and not room._row_overflows(room._rows[cell], cell)
			check(fit, "после сдвига все ящики вмещают свои предметы")
			check(after != before, "раскладка изменилась и сохранена")
			var loaded := ShelfConfig.load_state(room._cabinet, room._shelf_ids(), room._shelf_sizes())
			check(loaded.ok, "сохранение загружается")
			break
		if found:
			break
	check(found, "нашёлся переполненный ящик для проверки")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/q30/cascade.png")
	print("CASCADE30 ", checks, "/", errors)
	room.queue_free()
	await process_frame
	quit(1 if errors else 0)
