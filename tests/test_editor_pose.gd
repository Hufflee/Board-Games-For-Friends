extends Node
## Настоящее нажатие кнопки положения в редакторе, отмена и сохранение.
var errors := 0

func check(ok: bool, message: String) -> void:
	print(message, ": ", ok)
	if not ok:
		errors += 1
		push_error(message)

func click(button: Button) -> void:
	await get_tree().process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	print("Кнопка ", button.get_global_rect(), " наведение ", get_viewport().gui_get_hovered_control())
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame

func _ready() -> void:
	var existed := FileAccess.file_exists(ShelfConfig.FILE)
	var original := FileAccess.get_file_as_bytes(ShelfConfig.FILE) if existed else PackedByteArray()
	var room := NeonRoom.new()
	add_child(room)
	await get_tree().create_timer(0.3).timeout
	var box: GameBox
	for candidate in room.boxes:
		if candidate.game.id == "wavelength":
			box = candidate
	var old: int = room._box_modes.wavelength
	room.open_shelf_editor()
	room._select_shelf_box(box)
	room.set_process(false)
	room.camera.global_position = box.global_position + Vector3(0, 0.1, 1.0)
	room.camera.look_at(box.global_position)
	room._update_pose_button()
	await get_tree().create_timer(0.2).timeout
	check(room._pose_button.visible, "Кнопка положения видна в редакторе")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/editor-pose.png")
	await click(room._pose_button)
	print("Поза до/после: ", old, "/", room._box_modes.wavelength)
	check(room._box_modes.wavelength == (old + 1) % 4, "Нажатие меняет положение")
	check(FileAccess.file_exists(ShelfConfig.FILE) == existed, "Черновик не создаёт сохранение")
	if existed:
		check(FileAccess.get_file_as_bytes(ShelfConfig.FILE) == original, "Черновик не меняет файл")
	room.finish_shelf_editor(false)
	check(room._box_modes.wavelength == old, "Отмена возвращает прежнее положение")
	room.open_shelf_editor()
	room._select_shelf_box(box)
	room.camera.global_position = box.global_position + Vector3(0, 0.1, 1.0)
	room.camera.look_at(box.global_position)
	room._update_pose_button()
	await get_tree().create_timer(0.2).timeout
	await click(room._pose_button)
	room.finish_shelf_editor(true)
	var stored := ConfigFile.new()
	check(stored.load(ShelfConfig.FILE) == OK, "Готово сохраняет шкаф")
	check(stored.get_value("cabinet", "poses", {}).get("wavelength") == (old + 1) % 4, "Новая поза записана")
	if existed:
		var file := FileAccess.open(ShelfConfig.FILE, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ShelfConfig.FILE))
	print("EDITOR POSE: ошибок ", errors)
	get_tree().quit(1 if errors else 0)
