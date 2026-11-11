extends SceneTree
## Служебный снимок главного меню: кубик-рубильник на телевизоре (включённые тумблеры) — build/shots/hub_fidget*.png.
## Запуск: APPDATA=<пустая папка> godot --audio-driver Dummy --resolution 1280x720 --path . --script res://tools/_chat_probe/hub_shot.gd


func _initialize() -> void:
	_run.call_deferred()


func _find_room(node: Node) -> Node:
	if node.has_method("_fidget_use"):
		return node
	for child: Node in node.get_children():
		var found := _find_room(child)
		if found != null:
			return found
	return null


func _run() -> void:
	change_scene_to_file("res://hub/hub.tscn")
	await create_timer(3.0).timeout
	var out := ProjectSettings.globalize_path("res://build/shots/")
	var room := _find_room(root)
	print("ROOM ", room != null)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "hub_fidget_off.png")
	if room != null:
		room._fidget_use("fidget_toggle0")
		room._fidget_use("fidget_toggle2")
		room._fidget_spin(1)
		var cube_at: Vector3 = (room._fidget.glow as Node3D).global_position
		var screen: Vector2 = room.camera.unproject_position(cube_at)
		print("CUBE_SCREEN ", screen, " prop=", room._room_prop_at(screen + Vector2(-20, 6)))
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(out + "hub_fidget_on.png")
		var crop := Rect2i(Vector2i(screen) - Vector2i(110, 80), Vector2i(220, 160)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var close := image.get_region(crop)
		close.resize(crop.size.x * 4, crop.size.y * 4, Image.INTERPOLATE_LANCZOS)
		close.save_png(out + "hub_fidget_zoom.png")
	if room != null:
		var ball: Node3D = room._ball
		var at: Vector2 = room.camera.unproject_position(ball.global_position)
		print("BALL_SCREEN ", at, " prop=", room._room_prop_at(at))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "hub_ball_rest.png")
		room._ball_asleep = false
		room._ball_v = Vector3(float(OS.get_environment("BVX")), 4.0, -2.5)
		var bounds_ok := true
		for tick in 80:
			await create_timer(0.1).timeout
			var p: Vector3 = ball.position
			var on_screen: Vector2 = room.camera.unproject_position(p)
			if not Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(on_screen):
				print("OUT tick=", tick, " ", p, " ", on_screen)
			bounds_ok = bounds_ok and Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(4).has_point(on_screen) and p.z >= -2.0 and p.z <= -0.9
			if tick == 5:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out + "hub_ball_fly.png")
		print("BALL_END ", ball.position, " asleep=", room._ball_asleep, " in_bounds=", bounds_ok)
		# тумбочка слева: мяч, брошенный в неё, отскакивает, а не оказывается внутри
		var inside_stand := false
		var leftmost := 9.0
		room.open_shelf_editor()
		room.set_shelf_camera_zoom(0.75)
		await create_timer(0.8).timeout
		for shot: Vector3 in [Vector3(-4.0, 1.0, -2.0), Vector3(-5.0, 0.2, -3.0), Vector3(-3.0, 3.0, -4.0)]:
			ball.position = Vector3(-0.6, 0.5, -1.3)
			room._ball_asleep = false
			room._ball_v = shot
			for tick in 50:
				await create_timer(0.08).timeout
				var q: Vector3 = ball.position
				leftmost = minf(leftmost, q.x)
				inside_stand = inside_stand or (absf(q.x + 1.7) < 0.2 and q.y < 0.48 and q.z < -1.55) or (q.x < -1.97 and q.y < 0.45)
		print("STAND_INSIDE ", inside_stand, " leftmost=", leftmost, " end=", ball.position)
		room.finish_shelf_editor(false)
		# камера приближается (редактор шкафа) — мяч обязан остаться в кадре
		for zoom: float in [1.6, 0.75, 1.0]:
			room.set_shelf_camera_zoom(zoom)
			await create_timer(1.2).timeout
			var seen: Vector2 = room.camera.unproject_position(ball.position)
			print("ZOOM ", zoom, " ball_on_screen=", Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(seen), " ", seen)
			if zoom == 1.6:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out + "hub_ball_zoom.png")
	quit()
