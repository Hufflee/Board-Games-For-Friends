## Узкие дополнительные условия оформления TG, без фишек/flip/полной партии.
extends "res://tests/test_the_gang_ui.gd"

func text_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := text_button(child, text)
		if found != null: return found
	return null

func _run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(2)
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(12)
	var games: Script = load("res://hub/games.gd")
	check(not str(games.by_id("the_gang").description).to_lower().contains("tts"), "Описание хаба без TTS")
	var reference := text_button(app, "Комбинации")
	check(reference != null, "Памятка доступна непосредственно из лобби")
	if reference != null: await click(reference)
	var image: TextureRect = app.find_child("PokerReferenceImage", true, false)
	check(image != null and image.texture != null, "Настоящий клик лобби открыл именованное изображение")
	if image != null:
		check(image.texture.resource_path == "res://hub/covers/poker combination.jpg", "Использована предоставленная памятка")
		var scroll: ScrollContainer = image.get_parent().get_parent()
		scroll.scroll_vertical = 9999
		await frames()
		check(scroll.scroll_vertical > 0, "Длинную памятку можно прокрутить")
	var close: Button = app.find_child("CloseRules", true, false)
	check(close != null and root.get_visible_rect().encloses(close.get_global_rect()), "Кнопка закрытия памятки помещается в720p")
	if close != null: await click(close)
	check(app.find_child("PokerReferenceImage", true, false) == null, "Памятка закрывается настоящей мышью")
	var style: Script = load("res://games/the_gang/ui/tg_style.gd")
	var theme: Theme = style.theme()
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		check(theme.get_stylebox(state, "SelectedButton").bg_color == style.GOLD, "Таймер сохраняет золотую заливку: " + state)
	check(net.start_game() == "", "Подготовлен стол без игрового хода")
	await frames(10)
	var table: Control = app.screen
	var before: Dictionary = net.view.duplicate(true)
	for mode: String in ["light", "dark"]:
		root.get_node("Prefs").theme_mode = mode
		root.get_node("Prefs").changed.emit()
		await frames()
		check(app.screen == table and net.view == before, "Общая тема не меняет стол и view: " + mode)
	print("TG DESIGN LOW: ", checks, " проверок, ", errors, " ошибок")
	net.leave()
	app.queue_free()
	await frames()
	await root.get_node("Sfx").request_quit(1 if errors else 0)
