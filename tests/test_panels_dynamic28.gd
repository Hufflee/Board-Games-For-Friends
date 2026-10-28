extends SceneTree
## Фактические панели: число игр, границы экрана, масштаб и выбранная игра.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var registry = load("res://hub/games.gd")
	var panels_type = load("res://hub/game_panels.gd")
	var previous := 2.0
	for count in [1, 3, 12, 18, 30]:
		root.size = Vector2i(1280, 720)
		var world := Node3D.new()
		root.add_child(world)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.current = true
		var panels = panels_type.new()
		world.add_child(panels)
		var games: Array = []
		for i in count:
			var game: Dictionary = registry.by_id("the_gang").duplicate(true)
			game.id = "test_%d" % i
			games.append(game)
		panels.setup(camera, games, Vector3(0, 0, -1))
		panels.open()
		await create_timer(0.06 * count + 1.4).timeout
		var scale_value: float = panels.get("_grid_scale")
		check(scale_value > 0 and scale_value <= previous, "Размер уменьшается при росте числа игр")
		previous = scale_value
		for item: Dictionary in panels.get("_items"):
			var node: Node3D = item.root
			var size: Vector2 = item.mesh.mesh.size
			for corner: Vector2 in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
				var point := camera.unproject_position(node.to_global(Vector3(corner.x * size.x / 2, corner.y * size.y / 2, 0)))
				check(Rect2(16, 32, 1248, 640).has_point(point), "Панель%d остаётся в экране: %s" % [count, point])
		if count == 18:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/batch28_hub/panels18.png")
		panels.select(0)
		await create_timer(0.8).timeout
		var selected: Node3D = panels.get("_items")[0].root
		check(selected.scale.x > 1.2, "Выбранная игра увеличена независимо от сетки")
		panels.deselect()
		var old_viewport: Vector2 = panels.get("_layout_viewport")
		root.size = Vector2i(1024, 768)
		await create_timer(0.8).timeout
		check(panels.get("_layout_viewport") == root.get_visible_rect().size and panels.get("_layout_viewport") != old_viewport, "Изменение размера пересчитывает сетку с учётом stretch")
		world.queue_free()
		await process_frame
	print("ПАНЕЛИ28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
