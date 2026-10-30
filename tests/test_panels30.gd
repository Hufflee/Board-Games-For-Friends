extends SceneTree
## Окошки игр в кубе: крупнее, без наложений друг на друга и на края 1280×720. Кадр — build/q30/panels_<имя>.png.
## Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_panels30.gd
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print("P30 ", "OK " if ok else "FAIL ", message)
	if not ok:
		errors += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var label := OS.get_environment("SHOT")
	for dims: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = dims
		var hub: Node = load("res://hub/hub.gd").new()
		root.add_child(hub)
		await create_timer(0.8).timeout
		var room: Node = hub._room
		room.panels.open()
		await create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/q30/panels_%s_%d.png" % [label, dims.x])
		var rects: Array[Rect2] = []
		for item: Dictionary in room.panels._items:
			var mesh: MeshInstance3D = item.get("mesh")
			if mesh == null:
				continue
			var aabb: AABB = mesh.get_aabb()
			var tf := mesh.global_transform
			var r := Rect2(room.camera.unproject_position(tf * aabb.position), Vector2.ZERO)
			for k: int in 8:
				r = r.expand(room.camera.unproject_position(tf * aabb.get_endpoint(k)))
			rects.append(r)
		var screen := Rect2(Vector2.ZERO, Vector2(dims))
		var inside := true
		var apart := true
		for i: int in rects.size():
			inside = inside and screen.encloses(rects[i])
			for j: int in range(i + 1, rects.size()):
				apart = apart and not rects[i].grow(-2).intersects(rects[j].grow(-2))
		if not rects.is_empty():
			print("PANEL ", dims, " size ", rects[0].size, " scale ", room.panels._grid_scale)
		check(not rects.is_empty() and inside, "окошки внутри экрана %s" % dims)
		check(apart, "окошки не перекрываются %s" % dims)
		hub.queue_free()
		await create_timer(0.3).timeout
	print("PANELS30 ", checks, "/", errors)
	quit(1 if errors else 0)
