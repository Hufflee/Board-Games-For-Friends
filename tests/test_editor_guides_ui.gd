extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Направляющие интерфейса: настоящие жесты, Alt, видимость и одна команда отмены.

func _screen(canvas: Control, point: Vector2) -> Vector2:
	return root.get_final_transform() * (canvas.global_position + canvas._origin() + point * canvas._factor())

func _press(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)

func _motion(start: Vector2, finish: Vector2, alt: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = finish
	event.global_position = finish
	event.relative = finish - start
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.alt_pressed = alt
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/editor_guides/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for theme: String in ["dark", "light"]:
		prefs.set_value("theme_mode", theme)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		check(app.document.create("card_race"), "Создан проект для направляющих")
		app.document.set_value(["layout", "screens", 0, "items"], [
			{"id": "a", "kind": "text", "text": "Перетаскиваемый элемент", "rect": [128, 160, 160, 80], "visible": ["all"]},
			{"id": "b", "kind": "text", "text": "Образец", "rect": [640, 328, 160, 80], "visible": ["all"]}], "Стенд")
		app._editing = true
		app._tab = 1
		app._render()
		await frames(6)
		var canvas: Control = app._layout_canvas
		var before := JSON.stringify(app.document.data)
		var history: int = app.document.undo_stack.size()
		var start := _screen(canvas, Vector2(200, 192))
		var finish := _screen(canvas, Vector2(544, 352))
		await _press(start, true)
		await _motion(start, finish)
		check(JSON.stringify(app.document.data) == before, "Во время жеста документ ещё не изменён")
		check(canvas._draft.position.is_equal_approx(Vector2(480, 328)) and canvas._guides.size() == 2, "Край и верх привязаны к соседу, две направляющие")
		root.get_texture().get_image().save_png(folder + theme + ".png")
		await _press(finish, false)
		check(canvas._guides.is_empty(), "После отпускания направляющие скрыты")
		check(app.document.data.layout.screens[0].items[0].rect == [480.0, 328.0, 160.0, 80.0], "Перенос записал итог привязки")
		check(app.document.undo_stack.size() == history + 1, "Один жест — одна отмена")
		app.document.undo()
		app._render()
		await frames()
		canvas = app._layout_canvas
		check(JSON.stringify(app.document.data) == before, "Отмена восстановила весь документ")
		start = _screen(canvas, Vector2(200, 192))
		finish = _screen(canvas, Vector2(544, 352))
		await _press(start, true)
		await _motion(start, finish, true)
		check(canvas._draft.position.is_equal_approx(Vector2(472, 320)) and canvas._guides.is_empty(), "Alt сохраняет сетку без умных привязок (%s, %s, жест:%s)" % [theme, canvas._draft, canvas._drag])
		await _press(finish, false)
		app.document.undo()
		app._render()
		await frames()
		canvas = app._layout_canvas
		start = _screen(canvas, Vector2(288, 240))
		finish = _screen(canvas, Vector2(632, 320))
		canvas.selection = 0
		await _press(start, true)
		await _motion(start, finish)
		check(canvas._draft.position.is_equal_approx(Vector2(128, 160)) and canvas._draft.size.is_equal_approx(Vector2(512, 168)), "Изменение размера привязывает конец, сохраняя начало (%s, %s, жест:%s)" % [theme, canvas._draft, canvas._drag])
		await _press(finish, false)
		check(app.document.data.layout.screens[0].items[0].rect == [128.0, 160.0, 512.0, 168.0], "Размер записан по направляющим")
		app.document.undo()
		app._render()
		await frames()
		before = JSON.stringify(app.document.data)
		await click(button("Направляющие"))
		canvas = app._layout_canvas
		check(not canvas.guides_enabled and JSON.stringify(app.document.data) == before, "Переключатель меняет только вид редактора")
		start = _screen(canvas, Vector2(200, 192))
		finish = _screen(canvas, Vector2(544, 352))
		await _press(start, true)
		await _motion(start, finish)
		check(canvas._draft.position.is_equal_approx(Vector2(472, 320)), "Отключённая привязка не притягивает к соседу")
		await _press(finish, false)
		canvas.guides_enabled = true
		canvas.perspective = "spectator"
		canvas.items[1].visible = ["role:hidden"]
		canvas.selection = 0
		canvas._guides.clear()
		var hidden_result: Rect2 = canvas._snap_guides(Rect2(472, 320, 160, 80), false)
		check(hidden_result.position.is_equal_approx(Vector2(480, 320)) and canvas._guides.size() == 1 and canvas._guides[0].axis == 0, "Невидимый сосед не притягивает верх; центр поля остаётся доступен")
		app.queue_free()
		await frames()
	print("EDITOR GUIDES UI: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
