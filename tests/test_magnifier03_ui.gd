extends SceneTree
## Лупа: настоящий hover, соседний элемент в увеличении, отсутствие перехвата мыши и возврат настройки.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors += 1; push_error(message)

func frames() -> void:
	for index: int in 8: await process_frame
	await RenderingServer.frame_post_draw

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1); return
	root.size = Vector2i(1280, 720)
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/magnifier03/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for dark: bool in [false, true]:
		var scene := Control.new()
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(scene)
		var bg := ColorRect.new()
		bg.color = Color("171322") if dark else Color("e6e0ed")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(bg)
		var source := ColorRect.new()
		source.color = Color("c66053")
		source.position = Vector2(240, 180)
		source.size = Vector2(200, 240)
		scene.add_child(source)
		var neighbor := ColorRect.new()
		neighbor.color = Color("4777bc")
		neighbor.position = Vector2(440, 180)
		neighbor.size = Vector2(100, 240)
		scene.add_child(neighbor)
		prefs.set_value("card_preview_mode", "magnifier")
		await frames()
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_final_transform() * Vector2(430, 280)
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await frames()
		var original := root.get_texture().get_image()
		var original_left := original.get_pixel(445, 280)
		var original_right := original.get_pixel(560, 280)
		check(not (original_left.r > 0.6 and original_left.b < 0.45), "Исходный кадр не проходит проверку увеличенной красной карты")
		check(not (original_right.b > 0.6 and original_right.r < 0.4), "Исходный кадр не проходит проверку увеличенного соседа")
		check(preload("res://hub/card_magnifier.gd").offer(source), "Режим лупы заменяет просмотр")
		await frames()
		var lens: Node = prefs.get_node("CardMagnifier")
		check(lens.glass.visible and lens.glass.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Лупа видна и не перехватывает мышь")
		var screenshot := root.get_texture().get_image()
		var left := screenshot.get_pixel(445, 280)
		var right := screenshot.get_pixel(560, 280)
		check(left.r > 0.6 and left.b < 0.45, "Лупа расширяет красную карту на место исходного синего соседа")
		check(right.b > 0.6 and right.r < 0.4, "Сосед увеличен за пределами своей исходной рамки")
		screenshot.save_png(folder + ("dark.png" if dark else "light.png"))
		motion.position = root.get_final_transform() * Vector2(900, 600)
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await frames()
		check(not lens.glass.visible, "Уход с карты закрывает лупу")
		prefs.set_value("card_preview_mode", "card")
		check(not preload("res://hub/card_magnifier.gd").offer(source), "Режим крупной карты сохранён как альтернатива")
		scene.queue_free()
		await frames()
	print("MAGNIFIER03 UI: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
