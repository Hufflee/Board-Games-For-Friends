extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Реальный редактор лица: явная конверсия, перенос/угол/поворот, undo и привязка к строкам.

func _drag(start: Vector2, finish: Vector2) -> void:
	for down: bool in [true, false]:
		if not down:
			var motion := InputEventMouseMotion.new()
			motion.position = finish
			motion.global_position = finish
			motion.relative = finish - start
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			await frames(2)
		var event := InputEventMouseButton.new()
		event.position = start if down else finish
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)
	await frames(5)

func _screen(canvas: Control, point: Vector2) -> Vector2:
	return root.get_final_transform() * (canvas.global_position + canvas._origin() + point * canvas._factor())

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/editor_card_face/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("b75247"))
	image.fill_rect(Rect2i(8, 8, 24, 24), Color("65cfcc"))
	image.save_png(folder + "sample.png")
	for theme: String in ["dark", "light"]:
		prefs.set_value("theme_mode", theme)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		check(app.document.create("card_race"), "Создан исходный карточный пример")
		app._editing = true
		app._tab = 3
		app._deck = 0
		app._category = "decks"
		app._render()
		await frames(6)
		var original := JSON.stringify(app.document.data)
		await click(button("Редактор лица карты"))
		check(app._face_edit and JSON.stringify(app.document.data) == original, "Просмотр редактора не меняет прежний шаблон")
		await click(button("Создать слои из текущего вида"))
		check(app.document.data.elements.decks[0].face.layers.size() == 2 and app.document.issues().errors.is_empty(), "Явная конверсия создала фон и привязку числа")
		var canvas: Control = app.find_child("CardFaceCanvas", true, false)
		check(is_instance_valid(canvas) and canvas._face.find_children("*", "Label", true, false).any(func(label): return label.text == "1"), "Тот же renderer показывает значение первой карты")
		var fixed_before := JSON.stringify(app.document.data)
		await _drag(_screen(canvas, Vector2(472, 672)), _screen(canvas, Vector2(452, 652)))
		check(JSON.stringify(app.document.data) == fixed_before, "Закреплённый фон не двигается мышью")
		await click(button("+ Фигура"))
		canvas = app.find_child("CardFaceCanvas", true, false)
		var index: int = app._face_layer
		var rect: Rect2 = canvas._rect(index)
		var history: int = app.document.undo_stack.size()
		await _drag(_screen(canvas, rect.get_center()), _screen(canvas, rect.get_center() + Vector2(40, 24)))
		var moved: Rect2 = canvas._rect(index)
		check(moved.position.is_equal_approx(rect.position + Vector2(40, 24)), "Настоящий перенос изменяет прямоугольник слоя")
		check(app.document.undo_stack.size() == history + 1, "Перенос — одна команда undo")
		var anchor := moved.end
		await _drag(_screen(canvas, moved.position), _screen(canvas, moved.position - Vector2(24, 24)))
		var resized: Rect2 = canvas._rect(index)
		check(resized.end.is_equal_approx(anchor) and resized.size.is_equal_approx(moved.size + Vector2(24, 24)), "Верхний левый угол сохраняет противоположный угол")
		for corner: Vector2 in [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var opposite: Vector2 = canvas._point(resized, -corner, 0)
			var position: Vector2 = canvas._point(resized, corner, 0)
			var size_before := resized.size
			await _drag(_screen(canvas, position), _screen(canvas, position + corner * 12))
			resized = canvas._rect(index)
			check(canvas._point(resized, -corner, 0).is_equal_approx(opposite) and resized.size.is_equal_approx(size_before + Vector2(12, 12)), "Остальной угол сохраняет противоположную точку")
		var handle: Vector2 = canvas._point(resized, Vector2(0, -1), 0) + Vector2(0, -32)
		var target: Vector2 = resized.get_center() + (handle - resized.get_center()).rotated(PI / 2)
		await _drag(_screen(canvas, handle), _screen(canvas, target))
		check(is_equal_approx(float(app.document.data.elements.decks[0].face.layers[index].rotation), 90), "Настоящая ручка повернула слой на90°")
		await click(button("↶ Отмена"))
		check(is_zero_approx(float(app.document.data.elements.decks[0].face.layers[index].rotation)), "Undo отменяет поворот целиком")
		await click(button("↷ Повтор"))
		check(is_equal_approx(float(app.document.data.elements.decks[0].face.layers[index].rotation), 90), "Redo возвращает поворот")
		canvas = app.find_child("CardFaceCanvas", true, false)
		var rotated_anchor: Vector2 = canvas._point(resized, Vector2.ONE, 90)
		var rotated_corner: Vector2 = canvas._point(resized, -Vector2.ONE, 90)
		var before_rotated_size := resized.size
		await _drag(_screen(canvas, rotated_corner), _screen(canvas, rotated_corner + Vector2(-16, -16).rotated(PI / 2)))
		resized = canvas._rect(index)
		check(canvas._point(resized, Vector2.ONE, 90).is_equal_approx(rotated_anchor) and resized.size.is_equal_approx(before_rotated_size + Vector2(16, 16)), "Угол повёрнутого слоя сохраняет противоположную точку")
		var shape: OptionButton = app.find_child("CardFaceShape", true, false)
		shape.select(1)
		shape.item_selected.emit(1)
		await frames()
		check(app.document.data.elements.decks[0].face.layers[index].shape == "ellipse", "Слой может стать овалом")
		var snapshot := root.get_texture().get_image()
		var center_pixel := snapshot.get_pixelv(Vector2i(_screen(canvas, resized.get_center())))
		var corner_pixel := snapshot.get_pixelv(Vector2i(_screen(canvas, canvas._point(resized, Vector2(0.9, 0.9), 90))))
		check(Vector3(center_pixel.r, center_pixel.g, center_pixel.b).distance_to(Vector3(corner_pixel.r, corner_pixel.g, corner_pixel.b)) > 0.05, "Овал отрисован фигурой, а не сплошным прямоугольником")
		var sample: OptionButton = app.find_child("CardFaceSampleRow", true, false)
		sample.select(1)
		sample.item_selected.emit(1)
		await frames()
		check(canvas._face.find_children("*", "Label", true, false).any(func(label): return label.text == "2"), "Просмотр другой строки подставляет её число")
		await click(button("+ Текст"))
		var binding: OptionButton = app.find_child("CardFaceBinding", true, false)
		binding.select(1)
		binding.item_selected.emit(1)
		await frames()
		var layer: Dictionary = app.document.data.elements.decks[0].face.layers[app._face_layer]
		check(layer.field == "rank" and app.document.issues().errors.is_empty(), "Привязка нового слоя ссылается на колонку таблицы")
		await click(button("+ Рисунок"))
		var imported: Dictionary = load("res://editor/ed_assets.gd").import_image(str(app.document.data.id), folder + "sample.png")
		var copy: Dictionary = app.document.data.duplicate(true)
		copy.assets[imported.hash] = imported.asset
		var picture: Dictionary = copy.elements.decks[0].face.layers[app._face_layer]
		picture.asset = imported.hash
		picture.rect = [360, 560, 64, 48]
		app.document.replace(copy, "Тест несохранённого рисунка слоя")
		app._render()
		await frames(6)
		canvas = app.find_child("CardFaceCanvas", true, false)
		var textures: Array = canvas._face.find_children("*", "TextureRect", true, false)
		check(textures.any(func(item): return item.texture != null and item.texture.get_size() == Vector2(64, 48)), "Рисунок черновика отображается настоящей текстурой")
		check(textures.any(func(item): return item.texture != null and item.texture.get_image().get_pixel(0, 0).is_equal_approx(Color("b75247"))), "Предпросмотр показывает импортированные пиксели без подмены")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + theme + ".png")
		await click(button("К таблице карт"))
		check(not app._face_edit, "Можно вернуться к строкам колоды")
		check(await app._save(), "Шаблон лица сохраняется вместе с игрой")
		var saved: Dictionary = load("res://games/custom/logic/cg_library.gd").load_game(str(app.document.data.id))
		check(JSON.parse_string(JSON.stringify(saved.elements.decks[0].face.layers)) == JSON.parse_string(JSON.stringify(app.document.data.elements.decks[0].face.layers)), "Сохранение не теряет слои и привязки")
		app.queue_free()
		await frames(6)
	print("EDITOR CARD FACE UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
