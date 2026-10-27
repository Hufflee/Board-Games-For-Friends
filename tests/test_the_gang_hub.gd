extends SceneTree
## Проверка присланной коробки The Gang в настоящем хабе; Dummy, отдельный APPDATA.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hub: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(4.0).timeout
	var count := 0
	for box in hub._room.boxes:
		if box.game.get("id") == "the_gang":
			count += 1
	var ok := count == 1
	var game_box: GDScript = load("res://hub/game_box.gd")
	for side in ["front", "back", "spine"]:
		ok = ok and game_box.cover_texture("the_gang", side) != null
	print("THE GANG HUB: box_count=", count, " assets_ok=", ok)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/shots/the_gang")
		root.get_texture().get_image().save_png("res://build/shots/the_gang/hub-box.png")
	hub.queue_free()
	await process_frame
	await root.get_node("Sfx").request_quit(0 if ok else 1)
