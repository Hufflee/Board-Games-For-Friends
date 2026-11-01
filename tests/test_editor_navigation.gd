extends SceneTree
## Настоящий переход ТВ→редактор→проверка партии→редактор. Запуск с окном1280×720/Dummy/отдельным APPDATA.

var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func wait_scene(path: String) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 8000:
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
		await create_timer(0.025).timeout
	check(false, "Ожидалась сцена «%s»" % path)
	return false

func mouse(at: Vector2, key: int) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = key
	event.pressed = true
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный APPDATA.")
		quit(1)
		return
	var hub: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(1.0).timeout
	var room: Node = hub._room
	check(room._tv_title.text == "РЕДАКТОР", "Телевизор подписан «Редактор»")
	var point := Vector2(-1, -1)
	for node: Node in room.find_children("*", "StaticBody3D", true, false):
		if node.get_meta("room_prop", "") != "tv":
			continue
		for offset: float in [-0.2, -0.1, 0.0, 0.1]:
			var screen: Vector2 = room.camera.unproject_position(node.global_position + Vector3(offset, 0, 0))
			if root.get_visible_rect().has_point(screen) and room._room_prop_at(screen) == "tv":
				point = screen
				break
	check(point.x >= 0, "У телевизора есть доступная точка клика")
	if point.x >= 0:
		await mouse(point, MOUSE_BUTTON_WHEEL_DOWN)
		check(room._tv_channel == 1 and room._tv_title.text == "PLAYER ONE", "Колесо над ТВ переключает канал")
		await mouse(point, MOUSE_BUTTON_LEFT)
	else:
		room._use_room_prop("tv")
	if not await wait_scene("res://editor/main.tscn"):
		root.get_node("Sfx").request_quit(1)
		return
	var editor: Control = current_scene
	check(not editor._editing, "ТВ открыл библиотеку редактора")
	check(editor.document.create("card_race"), "Создан проект для локальной проверки")
	editor._editing = true
	for kind: String in ["dice", "tokens", "resources"]:
		editor._category = kind
		editor._add_component()
	editor._render()
	var copy: Dictionary = editor.document.data.duplicate(true)
	var id := str(editor.document.data.id)
	var assets: GDScript = load("res://editor/ed_assets.gd")
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color("a7b9a8"))
	image.save_png("res://build/editor_stage4/nav_art.png")
	var art: Dictionary = assets.import_image(id, "res://build/editor_stage4/nav_art.png", "Свой тестовый рисунок")
	var font: Dictionary = assets.import_font(id, "res://hub/art/fonts/Exo2-Variable.ttf", "OFL")
	check(art.error.is_empty() and font.error.is_empty(), "Импортированы ассеты для настоящего стола")
	copy["assets"] = {art.hash: art.asset, font.hash: font.asset}
	for row: Dictionary in copy.elements.decks[0].rows:
		row["art"] = art.hash
	copy.elements.decks[0]["face"] = {"font": font.hash}
	copy.elements.decks[0]["back"] = art.hash
	copy.layout["custom"] = true
	copy.layout.screens[0].items[0]["rect"] = [80, 160, 288, 224]
	copy.layout.screens[0].items.append({"kind": "text", "id": "leader_hint", "text": "Только ведущему", "rect": [400, 160, 320, 40], "visible": ["role:leader"]})
	editor.document.replace(copy, "Свой стол для проверки")
	editor._play()
	if not await wait_scene("res://games/custom/ui/main.tscn"):
		root.get_node("Sfx").request_quit(1)
		return
	var net: Node = root.get_node("Net")
	check(net.party_game == "custom:" + id and net.mode == "offline", "Проверка открыла локальную игру автора")
	check(net.start_game().is_empty(), "Проверочная партия стартовала")
	await process_frame
	check(net.view.zones["hand@0"].size() == 3 and net.view.hotseat, "В партии настоящие приватные местные руки")
	check(net.view.zones.table.size() == 5, "Созданные в редакторе жетоны появились на столе")
	await process_frame
	var table: Control = current_scene._screen
	table._shown = true
	table._rebuild()
	await process_frame
	var shown: Control = table._cards[str(net.view.zones["hand@0"][0].id)]
	check(shown._face.art_texture != null and shown._face.custom_font != null, "Импортированный арт и шрифт появились на настоящей карте")
	check(net.view.zones.draw.back().get("back") == art.hash and not net.view.zones.draw.back().has("id"), "Закрытая карта передаёт свою рубашку без ID")
	check(table._field.get_children().any(func(child: Node): return child.get_meta("cg_back", "") == art.hash), "Настоящая карта получила импортированную рубашку")
	DirAccess.make_dir_recursive_absolute("res://build/shots/editor_stage4")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/editor_stage4/runtime_assets.png")
	check(is_equal_approx(table._zones.draw.get_global_rect().position.y, 160), "Координаты холста совпали с настоящим столом")
	check(table._field.find_children("*", "Label", true, false).any(func(label: Label): return label.text == "Только ведущему"), "Ведущий видит свой элемент раскладки")
	var resource := {"kind": "manual_resource", "id": "resource_1", "delta": 1, "revision": net.view.revision}
	net.send_action("manual_resource", resource)
	check(net.cg.get_var("resource_1", 0) == 1, "Созданным ресурсом можно управлять в партии")
	table._show_debug()
	await process_frame
	check(is_instance_valid(table._debug_window) and table._debug_text.text.contains("ПЕРЕМЕННЫЕ"), "Проверка автора открывает отладчик полного состояния")
	table._debug_step_back()
	check(net.cg.get_var("resource_1", 0) == 0, "Отладчик вернул ресурс до предыдущего действия")
	table._debug_window.hide()
	net.send_action("view_seat", {"seat": 1})
	await process_frame
	await process_frame
	check(not table._field.find_children("*", "Label", true, false).any(func(label: Label): return label.text == "Только ведущему"), "Игрок другой роли не видит элемент ведущего")
	current_scene.back_to_hub()
	if not await wait_scene("res://editor/main.tscn"):
		root.get_node("Sfx").request_quit(1)
		return
	editor = current_scene
	check(editor._editing and editor.document.data.id == id and not net.in_session(), "После проверки вернулся тот же проект")
	net.host_offline("the_mind")
	var old_game: String = net.party_game
	editor._play()
	check(net.party_game == old_game and editor._message.contains("пати"), "Проверка не закрывает существующий пати")
	net.leave()
	print("EDITOR_NAVIGATION: %d проверок, ошибок %d" % [count, errors])
	root.get_node("Sfx").request_quit(1 if errors else 0)
