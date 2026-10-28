extends SceneTree
## Верхушки Ready Set Bet и Бродилки: текстура и реальная поверхность коробки в хабе.
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var box_type = load("res://hub/game_box.gd")
	var registry = load("res://hub/games.gd")
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.55, 0.7, 0.95)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -20, 0)
	world.add_child(light)
	var index := 0
	for id in ["ready_set_bet", "brodilka"]:
		var texture: Texture2D = box_type.cover_texture(id, "top")
		check(texture != null, "Текстура верхушки " + id)
		check(texture == box_type.cover_texture(id, "spine"), "Используется боковушка " + id)
		var box = box_type.new()
		box.setup(registry.by_id(id), Vector3(0.08, 0.3, 0.3), Color.DIM_GRAY)
		box.position = Vector3(-0.18 + 0.36 * index, 0, 0)
		world.add_child(box)
		var top: MeshInstance3D = box.get_node("Cover_top")
		check(top != null and top.material_override.albedo_texture == texture, "Верхняя грань отображает рисунок " + id)
		index += 1
	await create_timer(0.5).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/batch28_box_tops/tops.png")
	world.queue_free()
	await process_frame
	print("ВЕРХУШКИ28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
