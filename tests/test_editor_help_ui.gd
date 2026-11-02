extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Первые подсказки, повторная справка, сохранение прочтения вне проекта; обе темы1280×720.

func _tap(control: BaseButton) -> void:
	check(is_instance_valid(control) and control.is_visible_in_tree(), "Справка доступна для клика")
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await frames()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/editor_help/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for theme: String in ["dark", "light"]:
		prefs.set_value("theme_mode", theme)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		app.document.create()
		app._editing = true
		var before := JSON.stringify(app.document.data)
		for tab in 4:
			app._tab = tab
			if tab == 0:
				app._message = "Сообщение восстановления проекта"
			app._render()
			await frames(6)
			if tab == 0:
				check(app._status.text.begins_with("Сообщение восстановления проекта"), "Первая подсказка не прячет важное сообщение проекта")
				app._message = ""
				app._status_text()
			check(not app._tab_tip.is_empty() if theme == "dark" else app._tab_tip.is_empty(), "Первое посещение показано однажды, вкладка%d" % tab)
			check(app.find_child("EditorHelpOverlay", true, false) == null, "Первая подсказка не блокирует холст")
			await _tap(app.find_child("EditorHelpButton", true, false))
			var overlay: Control = app.find_child("EditorHelpOverlay", true, false)
			check(is_instance_valid(overlay), "Подробная справка открыта нажатием")
			var panels := overlay.find_children("*", "PanelContainer", true, false)
			check(panels.size() == 1 and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panels[0].get_global_rect()), "Инструкция помещается в1280×720")
			if tab == 2:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder + theme + ".png")
			await click(button("Понятно"))
			check(not is_instance_valid(overlay) and app._tab_tip.is_empty(), "Закрытие справки отмечает подсказку прочитанной")
			check(JSON.stringify(app.document.data) == before, "Обучение не меняет проект и его undo")
		var help = load("res://editor/ed_help.gd").new()
		check(help.tip(0).is_empty() and help.tip(3).is_empty(), "Прочтение сохранено при повторной загрузке помощника")
		app.queue_free()
		await frames()
	print("EDITOR HELP UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
