extends SceneTree
## Проверка самостоятельного окна справочника реальным вводом Godot, снимок 1280×720.
## --audio-driver Dummy --path . --resolution 1280x720 --script res://tests/test_blood_on_the_clocktower_ui.gd.

const Handbook := preload("res://games/blood_on_the_clocktower/ui/bc_handbook.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("ОШИБКА: " + message)

func click(node: Control) -> void:
	var point := node.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var book := Handbook.new()
	root.add_child(book)
	await process_frame
	await process_frame
	await process_frame
	check(book._cards.get_child_count() == 22, "При открытии все роли первого сценария")
	await click(book._tabs["bmr"])
	check(book.edition == "bmr" and book._cards.get_child_count() == 25, "Кнопка второго сценария")
	await click(book._tabs["sv"])
	check(book.edition == "sv" and book._cards.get_child_count() == 25, "Кнопка третьего сценария")
	await click(book._search)
	for character in "отравлен":
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		Input.parse_input_event(key)
	await process_frame
	await process_frame
	check(book.query == "отравлен", "Поиск вводится с клавиатуры")
	check(book._cards.get_child_count() > 0 and book._cards.get_child_count() < 25, "Поиск фильтрует способности")
	await click(book._tabs["tb"])
	check(book.query.is_empty() and book._cards.get_child_count() == 22, "Смена сценария сбрасывает поиск")
	await process_frame
	await process_frame
	check(book._cards.columns == 2, "На 720p две колонки")
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for node: Control in [book._search, book._tabs["tb"], book._tabs["bmr"], book._tabs["sv"], book._scroll]:
		check(viewport.encloses(node.get_global_rect()), "Управление внутри окна: " + str(node.name))
	check(book._scroll.size.y > 300, "Список ролей имеет место для чтения")
	check(book._cards.get_child(0).size.x > 400, "Читаемая ширина карточки")
	var prefs := root.get_node_or_null("Prefs")
	if prefs != null:
		var previous: Variant = prefs.get("theme_mode")
		prefs.set("theme_mode", "light")
		await process_frame
		check(book.theme.get_color("font_color", "Label") == Color("f0e3cc"), "Глобальная светлая тема не меняет справочник")
		prefs.set("theme_mode", previous)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots/botc"))
	await RenderingServer.frame_post_draw
	var screen := root.get_texture().get_image()
	var saved := screen.save_png("res://build/shots/botc/handbook_1280x720.png")
	check(saved == OK, "Снимок справочника сохранён")
	var close: Button = book.find_child("Close", true, false)
	var observed := [false]
	book.closed.connect(func(): observed[0] = true)
	await click(close)
	check(observed[0], "Кнопка закрытия посылает сигнал")
	book.queue_free()
	await process_frame
	print("Clocktower UI: %d проверок, %d ошибок. Только справочник, не полный стол." % [checks, failures])
	quit(1 if failures > 0 else 0)
