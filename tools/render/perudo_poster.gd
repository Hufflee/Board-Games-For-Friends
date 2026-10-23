extends Node
## Постер «Перудо» для окошек игр: снимок 3D-набора стаканов из шкафа (GameBox) на прозрачном фоне.
## Запуск: godot --path . res://tools/render/perudo_poster.tscn  → hub/covers/perudo_poster.png
func _ready():
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 800)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c9c2e0")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_color = Color("b9a0ff")
	fill.light_energy = 0.6
	vp.add_child(fill)
	var g: Dictionary = HubGames.by_id("perudo")
	var box := GameBox.new()
	box.setup(g, Vector3.ONE, Color("c8262c"))
	vp.add_child(box)
	box.rotation = Vector3(0, 0.12, 0)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.position = Vector3(0, 0.25, 0.78)
	cam.look_at(Vector3(0, 0.075, 0))
	cam.current = true
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("res://hub/covers/perudo_poster.png")
	print("saved ", img.get_size())
	get_tree().quit()
