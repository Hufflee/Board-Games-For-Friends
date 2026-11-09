extends SceneTree
## Шкаф 08.11: свои ширина колонок и высота полок. Раскладка учитывает размер каждой ячейки,
## внутренние перегородки и полки в редакторе меняют только соседние ячейки, размеры видят друзья.
## godot --audio-driver Dummy --path . --script res://tests/test_shelf_cells.gd  (нужно окно: строится комната)
var checks := 0
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", message)


func _run() -> void:
	# --- правила
	var cfg := {"rows": 2, "cols": 2, "cups": 0, "width": 0.4, "height": 0.3, "col_widths": [0.25, 0.55], "row_heights": [0.2, 0.4]}
	var n := ShelfConfig.normalized(cfg)
	check(n.has("col_widths") and is_equal_approx(float(n.width), 0.4), "средняя ширина при своих колонках")
	check(is_equal_approx(ShelfConfig.cell_width(n, 1), 0.55) and is_equal_approx(ShelfConfig.cell_height(n, 2), 0.4), "размер ячейки по колонке и ряду")
	var tall := {"tall": Vector3(0.05, 0.33, 0.2)}
	var r := ShelfConfig.solve(n, [["tall"], [], [], []], tall, {"tall": 1}, 2)
	check(r.ok and (r.placements[2] as Array).has("tall") or (r.placements[3] as Array).has("tall"), "высокая коробка уходит в высокий нижний ряд")
	var wide := {"w1": Vector3(0.3, 0.15, 0.2)}
	var r2 := ShelfConfig.solve(n, [["w1"], [], [], []], wide, {"w1": 1}, 2)
	check(r2.ok and ((r2.placements[1] as Array).has("w1") or (r2.placements[3] as Array).has("w1")), "широкая коробка — в широкую колонку")
	var same := ShelfConfig.normalized({"rows": 1, "cols": 2, "cups": 0, "width": 0.4, "height": 0.3, "col_widths": [0.3, 0.3]})
	check(not same.has("col_widths") and is_equal_approx(float(same.width), 0.3), "одинаковые колонки — без списка")
	check(not ShelfConfig.normalized({"rows": 1, "cols": 2, "cups": 0, "width": 0.4, "height": 0.3, "col_widths": [0.3]}).has("col_widths"), "список не по числу колонок отброшен")
	var pub: Dictionary = load("res://hub/public_room.gd").clean({"config": n, "placements": [["perudo"], [], [], []], "poses": {}, "selected": "", "editor": false, "custom": {}})
	check(pub.get("config", {}).get("row_heights", []) == n.row_heights, "размеры полок уходят друзьям")
	# --- комната и редактор
	root.size = Vector2i(1280, 720)
	var room: Node = load("res://hub/neon_room.gd").new()
	root.add_child(room)
	await create_timer(0.8).timeout
	room.camera.current = true
	room.open_shelf_editor()
	await process_frame
	var base: Dictionary = room._cabinet.duplicate(true)
	if int(base.cols) < 2:
		base.cols = 2
		base.width = 0.5
		check(room.request_shelf_geometry(base) == "", "две колонки")
		await process_frame
	var cols: int = int(room._cabinet.cols)
	var rows: int = int(room._cabinet.rows)
	var before_full: float = ShelfConfig.full_width(room._cabinet)
	var edges: Array = room._shelf_edges()
	# перегородка одной ячейки: в верхнем ряду (ячейка 0 — слева вверху)
	var divider: Dictionary = edges.filter(func(e): return e.kind == "seg" and int(e.index) == 0)[0]
	var cells_before: Array = ShelfConfig.shelf_cells(room._cabinet).duplicate(true)
	room._begin_edge_drag(divider, divider.a)
	room._resize_shelf_edge((divider.a as Vector2) + Vector2(60, 0))
	await process_frame
	var cells_now: Array = ShelfConfig.shelf_cells(room._cabinet)
	var w0 := float(cells_now[0].w)
	var w1 := float(cells_now[1].w)
	check(w0 > w1 + 0.02, "перегородка верхнего ряда вправо: левая ячейка шире (%.3f / %.3f)" % [w0, w1])
	check(is_equal_approx(float(cells_now[2].w), float(cells_before[2].w)), "второй ряд не изменился — перегородка своя у ряда")
	check(absf(ShelfConfig.full_width(room._cabinet) - before_full) < 0.002, "ширина шкафа не изменилась")
	check(absf((float(room._row_info[1].right) - float(room._row_info[1].left)) - (w1 - 0.006)) < 0.003, "ячейки комнаты построены по своим ширинам")
	room._edge_drag = {}
	# убрать перегородку второго ряда: ячейки 2 и 3 → одна
	var count := ShelfConfig.cell_count(room._cabinet)
	var seg2: Dictionary = room._shelf_edges().filter(func(e): return e.kind == "seg" and int(e.index) == 2)[0]
	room._cells_right_click(((seg2.a as Vector2) + (seg2.b as Vector2)) * 0.5)
	await process_frame
	check(ShelfConfig.cell_count(room._cabinet) == count - 1, "правый клик по перегородке — ячеек на одну меньше")
	var placed := 0
	for row: Array in room._shelf_ids():
		placed += row.size()
	check(placed == room.boxes.size(), "все коробки остались на шкафу после объединения")
	# поставить перегородку обратно: правый клик в середине широкой ячейки
	var wide_cell: Dictionary = room._row_info[2]
	var mid := Vector3((float(wide_cell.left) + float(wide_cell.right)) * 0.5, float(wide_cell.floor) + float(wide_cell.height) * 0.5, room.BACK + room.CELL_D + 0.016)
	room._cells_right_click(room.camera.unproject_position(room._shelf_root.global_transform * mid))
	await process_frame
	check(ShelfConfig.cell_count(room._cabinet) == count, "правый клик внутри ячейки — перегородка вернулась")
	# кусок полки: объединить ячейку первого ряда с ячейкой под ней (одинаковая ширина)
	var explicit := ShelfConfig.with_cells(room._cabinet)
	var c0: Dictionary = explicit.cells[0]
	var below := -1
	for i in (explicit.cells as Array).size():
		var c: Dictionary = explicit.cells[i]
		if int(c.row) == 1 and absf(float(c.x) - float(c0.x)) < 0.004 and absf(float(c.w) - float(c0.w)) < 0.004:
			below = i
	if below < 0:
		var merged_v := ShelfConfig.merge_cells(room._cabinet, room._shelf_ids(), 0, 2)
		check(merged_v.is_empty(), "разная ширина — по вертикали не объединяются")
	var tall_cfg := ShelfConfig.merge_cells({"rows": 3, "cols": 2, "cups": 0, "width": 0.4, "height": 0.3}, [[], [], [], [], [], []], 0, 2)
	check(not tall_cfg.is_empty() and int(tall_cfg.config.cells[0].span) == 2 and (tall_cfg.config.cells as Array).size() == 5, "кусок полки убран: ячейка на два ряда")
	var back := ShelfConfig.split_cell(tall_cfg.config, tall_cfg.placements, 0, false, 1)
	check((back.config.cells as Array).size() == 6, "пунктир — полка вернулась")
	check(ShelfConfig.cells_valid(tall_cfg.config.cells, 3) and ShelfConfig.cells_valid(back.config.cells, 3), "ячейки покрывают шкаф без дыр")
	check(not ShelfConfig.cells_valid([{"row": 0, "span": 1, "x": 0.0, "w": 0.4}], 2), "неполный шкаф отвергнут")
	room._edge_drag = {}
	if rows >= 2:
		var taller: Dictionary = room._cabinet.duplicate(true)
		taller.height = 0.44
		taller.erase("row_heights")
		check(room.request_shelf_geometry(taller) == "", "полки выше — есть запас")
		await process_frame
		var level: Dictionary = room._shelf_edges().filter(func(e): return e.kind == "height" and int(e.index) == 1)[0]
		var h_before_bottom := ShelfConfig.row_height(room._cabinet, rows - 1)
		var h_before_top := ShelfConfig.row_height(room._cabinet, rows - 2)
		var full_h := ShelfConfig.full_height(room._cabinet)
		room._begin_edge_drag(level, level.a)
		# вниз: нижний ряд ниже, ряд над полкой выше (вверх может упереться в высокие коробки ряда выше)
		room._resize_shelf_edge((level.a as Vector2) + Vector2(0, 12))
		await process_frame
		var hb := ShelfConfig.row_height(room._cabinet, rows - 1)
		var ht := ShelfConfig.row_height(room._cabinet, rows - 2)
		check(hb < h_before_bottom - 0.005 and ht > h_before_top + 0.005, "полка вниз: нижний ряд ниже, верхний выше (%.3f→%.3f, %.3f→%.3f)" % [h_before_bottom, hb, h_before_top, ht])
		check(absf(ShelfConfig.full_height(room._cabinet) - full_h) < 0.002, "высота шкафа не изменилась")
		room._edge_drag = {}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/shelf_cells_editor.png")
	var snap: Dictionary = room.public_snapshot()
	check(snap.config.has("cells"), "снимок для друзей несёт ячейки")
	room.finish_shelf_editor(true)
	await process_frame
	check(room._cabinet.has("cells"), "сохранено после «Готово»")
	var loaded := ShelfConfig.load_state(room._cabinet, room._shelf_ids(), room._shelf_sizes())
	check(loaded.ok and loaded.config.has("cells"), "ячейки читаются из сохранения")
	print("ШКАФ: ЯЧЕЙКИ: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors > 0 else 0)
