## Узкое low-ревью каталога, без проверки игровых механик. Dummy/свой APPDATA.
extends "res://tests/test_card_pool.gd"

func button_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := button_text(child, text)
		if found != null: return found
	return null

func click(control: Control) -> void:
	check(control != null, "Цель мышиного клика существует")
	if control == null: return
	var at := control.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await settle()

func rules_catalog(app: Control, label: String) -> void:
	var previous: Dictionary = Net.view.duplicate(true)
	var rule_button := button_text(app, "Правила")
	check(rule_button != null, "Правила доступны из " + label)
	if rule_button == null: return
	await click(rule_button)
	await click(button_text(app, "Посмотреть пул карт"))
	var browser: Control = app.get_node_or_null("CardPool")
	check(browser != null, "Rules открыли каталог из " + label)
	if browser != null:
		await click(button_text(browser, "Закрыть"))
		check(not app.has_node("CardPool"), "Кнопка закрыла только каталог из " + label)
	await click(button_text(app, "Понятно"))
	check(Net.view == previous, "Rules/catalog не меняют Net.view: " + label)

func browse(app: Control, id: String, theme: String) -> void:
	var before: Dictionary = Net.view.duplicate(true)
	app.show_card_pool()
	await settle()
	var browser: Control = app.get_node("CardPool")
	check(browser.entries.size() == (85 if id == "brodilka" else 913), "Печатный объём85/913, не текущая колода")
	check(browser.entries.all(func(e: Dictionary) -> bool: return FileAccess.file_exists(e.path)), "Все исходные файлы изображений действительно существуют")
	var first: Control = browser._grid.get_child(0)
	var at := first.get_global_rect().get_center()
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await settle()
	check(browser._preview.texture != null, "Реальное наведение даёт preview")
	await click(first)
	await click(button_text(browser, "Повернуть карту"))
	check(is_equal_approx(browser._preview.rotation, PI), "Мышь поворачивает preview на180")
	await click(button_text(browser, "Повернуть карту"))
	check(is_zero_approx(browser._preview.rotation), "Второй поворот возвращает карту")
	browser._page = 999
	browser._render()
	await settle()
	check(browser._page == (7 if id == "brodilka" else 76) and browser._grid.get_child_count() == 1, "Последняя страница и остаток1 карты")
	check(browser._next.disabled and not browser._previous.disabled, "На последней странице нельзя выйти за границу")
	await click(browser._previous)
	check(browser._grid.get_child_count() == 12, "Возврат с последней страницы даёт12 изображений")
	browser._query.text = "   "
	browser._filter()
	check(browser._page == 0 and browser._filtered.size() == browser.entries.size(), "Пробельный поиск равен пустому и сбрасывает страницу")
	browser._query.text = "неттакойкарты_low_catalog"
	browser._filter()
	check(browser._grid.get_child_count() == 0 and browser._preview.texture == null and browser._previous.disabled and browser._next.disabled, "Нет результатов: пустой preview, обе стрелки выключены")
	browser._query.text = ""
	browser._filter()
	await settle()
	await click(browser._grid.get_child(0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/card_pool/low-%s-%s.png" % [id, theme])
	await click(browser._query)
	await escape()
	check(not app.has_node("CardPool"), "ESC закрывает каталог даже при фокусе поиска")
	if app.has_node("CardPool"):
		app.get_node("CardPool").queue_free()
		await settle()
	check(Net.view == before, "Пагинация/поиск/preview/rotation/ESC не меняют view и руки")

func _run() -> void:
	for id: String in ["brodilka", "four_souls"]:
		Net.leave()
		var app: Control = load("res://games/%s/ui/main.tscn" % id).instantiate()
		get_tree().root.add_child(app)
		get_tree().current_scene = app
		await settle()
		await click(button_text(app, "Пул карт"))
		check(app.has_node("CardPool"), "Меню открывает каталог мышью: " + id)
		if app.has_node("CardPool"): await click(button_text(app.get_node("CardPool"), "Закрыть"))
		Net.host_offline(id)
		Net.set_bots(1)
		await settle()
		await rules_catalog(app, id + " lobby")
		# Только подготовка настоящего стола для проверки доступа; игровые действия не выполняются.
		check(Net.start_game() == "", "Подготовлен UI-стол: " + id)
		Net.set_process(false)
		await settle()
		await rules_catalog(app, id + " table")
		for theme: String in ["light", "dark"]:
			Prefs.theme_mode = theme
			get_tree().root.theme = load("res://games/brodilka/ui/br_style.gd").theme() if id == "brodilka" else load("res://games/four_souls/ui/fs_style.gd").theme()
			await browse(app, id, theme)
		Net.leave()
		get_tree().current_scene = self
		app.queue_free()
		await settle()
	print("CARD POOL LOW REVIEW: ", checks, " проверок, ", errors, " ошибок")
	await Sfx.request_quit(1 if errors else 0)
