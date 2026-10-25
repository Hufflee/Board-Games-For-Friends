extends Node
## Реальные габариты Перудо и выбор Энди. Запуск: godot --path . res://tests/test_shelf_bounds.tscn
var checks := 0
var errors := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)


func _ready() -> void:
	var room := NeonRoom.new()
	add_child(room)
	room.set_process_input(false)
	room.set_process_unhandled_input(false)
	var cups: GameBox = room._cups
	var bounds := GameBox.geometry_bounds(cups)
	check(bounds.get_center().length() < 0.00001, "Центр геометрии Перудо совпадает с центром раскладки")
	check(bounds.size.is_equal_approx(cups.size), "Раскладка учитывает весь наклонённый стаканчик")
	var shape: CollisionShape3D = cups.find_children("*", "CollisionShape3D", true, false)[0]
	check((shape.shape as BoxShape3D).size.is_equal_approx(bounds.size), "Коллайдер охватывает реальные габариты")
	var brown: Node3D = cups.find_child("BrownCup", true, false)
	var brown_bounds := GameBox.geometry_bounds(brown, cups.global_transform.affine_inverse() * brown.global_transform)
	check(absf(brown_bounds.position.x + cups.size.x * 0.5) < 0.00001,
		"Левая грань коллайдера вплотную к коричневому стаканчику")
	for mode in 2:
		room._box_modes.perudo = mode
		var state := ShelfConfig.solve(room._cabinet, room._shelf_ids(), room._shelf_sizes(), room._box_modes)
		check(state.ok, "Поворот Перудо помещается после общей раскладки")
		if state.ok:
			room._apply_shelf_state(state)
		room._reflow(false)
		var cell := -1
		for i in room._rows.size():
			if room._rows[i].has(cups):
				cell = i
		var info: Dictionary = room._row_info[cell]
		var placed: AABB = cups.home * bounds
		check(placed.position.y >= float(info.floor) - 0.00001, "Перудо не проваливается в полку")
		check(placed.position.x >= float(info.left) - 0.00001 and placed.end.x <= float(info.right) + 0.00001,
			"Перудо внутри боковых стенок")
		for other: GameBox in room._rows[cell]:
			if other == cups:
				continue
			var neighbor: AABB = other.home * AABB(-other.size * 0.5, other.size)
			check(not placed.grow(-0.00001).intersects(neighbor), "Перудо не пересекает соседей: " + str(other.game.id))
	var andy: GameBox
	for box: GameBox in room.boxes:
		if str(box.game.id) == "shelf_andy":
			andy = box
	var surfaces := andy.find_children("*", "CollisionShape3D", true, false)
	check(not surfaces.is_empty(), "У Энди есть область выбора")
	for surface: CollisionShape3D in surfaces:
		check(surface.shape is ConcavePolygonShape3D, "Выбор Энди повторяет поверхность вместо широкого блока")
	await get_tree().physics_frame
	# Лучи через старый прямоугольник: силуэт выбирается, пустота рядом пропускает луч.
	var hits := 0
	var misses := 0
	for ix in 15:
		for iy in 12:
			var p := Vector3(-0.07 + ix * 0.01, -0.07 + iy * 0.012, 0.4)
			var query := PhysicsRayQueryParameters3D.create(andy.to_global(p), andy.to_global(p - Vector3(0, 0, 0.8)))
			var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider.get_meta("game_box", null) == andy:
				hits += 1
			else:
				misses += 1
	check(hits > 0 and misses > 0, "Луч выбирает силуэт Энди и пропускает пустые края")
	room._box_modes.perudo = 1
	room._reflow(false)
	var target := cups.global_position
	room.camera.global_position = target + Vector3(0.18, 0.22, 0.65)
	room.camera.look_at(target)
	room.set_process(false)
	get_window().size = Vector2i(1280, 720)
	await get_tree().create_timer(1.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "res://build/shots/shelf-bounds.png"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
		check(get_viewport().get_texture().get_image().save_png(path) == OK, "Скриншот сохранён")
		room.camera.global_position = andy.global_position + Vector3(0.15, 0.12, 0.55)
		room.camera.look_at(andy.global_position)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://build/shots/shelf-andy-bounds.png") == OK,
			"Скриншот Энди сохранён")
	print("SHELF BOUNDS: %d проверок, %d ошибок; лучи Энди %d/%d" % [checks, errors, hits, misses])
	get_tree().quit(0 if errors == 0 else 1)
