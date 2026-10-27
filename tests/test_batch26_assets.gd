extends Control
## Визуальная проверка верхушек коробок и зачёркивания широких/узких букв.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var world := Node3D.new()
	add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 0.7, 1.1)
	camera.look_at(Vector3(0, 0, 0))
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-45, -20, 0)
	world.add_child(lamp)
	var index := 0
	for id in ["gloom", "gloomier"]:
		var game: Dictionary = HubGames.LIST.filter(func(entry): return entry.id == id)[0]
		var box := GameBox.new()
		box.setup(game, Vector3(0.2, 0.3, 0.3), Color.DIM_GRAY)
		box.position = Vector3(-0.18 + index * 0.36, 0, 0)
		world.add_child(box)
		var top: MeshInstance3D = box.get_node("Cover_top")
		check(top != null, "У коробки есть верхняя грань: " + id)
		check((top.transform.basis * Vector3.BACK).dot(Vector3.UP) > 0.99, "Крышка смотрит вверх")
		check(top.material_override.albedo_texture != null, "На крышке есть рисунок")
		index += 1
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/batch26-box-tops.png")
	world.queue_free()
	get_tree().root.theme = PIStyle.theme()
	var panel := PIStyle.panel()
	panel.position = Vector2(120, 120)
	panel.size = Vector2(700, 430)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	for letter in ["Л", "Ш", "У", "М", "Ы"]:
		var button := PIStyle.button("→ С" + letter + "  ✕", PIStyle.BODY)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 60
		button.disabled = true
		preload("res://games/phantom_ink/ui/pi_wrong_letter.gd").wire(button, 3)
		column.add_child(button)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/batch26-strikes.png")
	print("BATCH26 ASSETS: ", checks, " проверок, ", errors, " ошибок")
	get_tree().quit(1 if errors else 0)
