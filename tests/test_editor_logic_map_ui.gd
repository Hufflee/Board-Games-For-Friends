extends SceneTree
## Оконная проверка обзора длинных цепочек, прокрутки и фильтра фаз; обе темы1280×720, Dummy.
var app: Control
var checks := 0
var errors := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 5) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw

func pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var folder := "res://build/shots/editor_logic_map/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for mode: String in ["dark", "light"]:
		root.get_node("Prefs").theme_mode = mode
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		app.document.create()
		var data: Dictionary = app.document.data.duplicate(true)
		data.rules.phases = ["play", "end"]
		data.rules.chains = []
		for chain_index in 4:
			var blocks: Array = []
			for block_index in 12:
				blocks.append({"id": "b%d_%d" % [chain_index, block_index], "op": "log", "text": "Сообщение"})
			blocks[0] = {"id": "branch%d" % chain_index, "op": "if", "condition": true,
				"then": [{"id": "nested%d" % chain_index, "op": "log", "text": "Вложенное сообщение"}], "else": []}
			data.rules.chains.append({"event": {"type": "phase_enter", "phase": "play" if chain_index < 3 else "end"}, "blocks": blocks})
		app.document.replace(data, "Тест длинных цепочек")
		app._editing = true
		app._tab = 2
		app._logic_chain = 0
		app._render()
		await frames(10)
		var minimap: Control = app.find_child("LogicMinimap", true, false)
		var scroll: ScrollContainer = app.find_child("LogicCanvasScroll", true, false)
		check(is_instance_valid(minimap) and minimap.is_visible_in_tree(), "Обзор виден")
		check(minimap.entries.size() == 56, "Обзор содержит четыре шапки и52блока, включая вложенные")
		check(scroll.get_v_scroll_bar().max_value > scroll.size.y * 3, "Сценарий действительно длиннее рабочего поля")
		var early_restore = load("res://editor/ed_logic.gd").new()
		early_restore.app = app
		early_restore._restore_scroll(scroll, 900)
		scroll.scroll_vertical = 240
		await frames()
		check(scroll.scroll_vertical == 240 and app._logic_scroll == 240, "Прокрутка в первые два кадра важнее отложенного восстановления")
		scroll.scroll_vertical = 0
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(minimap.get_global_rect()), "Обзор помещается в1280×720")
		var before := JSON.stringify(app.document.data)
		var bottom := minimap.global_position + Vector2(minimap.size.x / 2, minimap.size.y - 8)
		await pointer(bottom, true)
		await pointer(bottom, false)
		await frames()
		check(scroll.scroll_vertical > 1500, "Настоящий клик обзора перешёл к последним цепочкам")
		check(minimap.viewport_rect().end.y <= minimap.map_rect().end.y + 1, "Рамка видимой области остаётся в обзоре")
		var saved := scroll.scroll_vertical
		app._render()
		await frames(10)
		minimap = app.find_child("LogicMinimap", true, false)
		scroll = app.find_child("LogicCanvasScroll", true, false)
		check(absi(scroll.scroll_vertical - saved) <= 2, "Перестроение свойств сохраняет прокрутку логики")
		bottom = minimap.global_position + Vector2(minimap.size.x / 2, minimap.size.y - 8)
		await pointer(bottom, true)
		var motion := InputEventMouseMotion.new()
		motion.position = minimap.global_position + Vector2(minimap.size.x / 2, 8)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await process_frame
		await pointer(motion.position, false)
		await frames()
		check(scroll.scroll_vertical < 50, "Перетаскивание рамки вернуло начало цепочек")
		check(JSON.stringify(app.document.data) == before, "Навигация не меняет игру и историю документа")
		var phase_button: Button
		for node: Node in app.find_children("*", "Button", true, false):
			if node.text == "end":
				phase_button = node
		check(is_instance_valid(phase_button), "Фаза доступна в ленте")
		var point := phase_button.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames()
		minimap = app.find_child("LogicMinimap", true, false)
		check(minimap.entries.size() == 14, "Обзор учитывает фильтр фазы")
		check(app._logic_chain == 3, "Свойства и выбранная цепочка принадлежат видимой фазе")
		check(minimap.entries.filter(func(entry): return entry.get_meta("map_selected", false)).size() == 1, "Обзор выделяет ровно одно видимое событие")
		check(minimap.size.y >= 300, "Постоянные настройки фаз не вытесняют рабочее поле")
		var phase_tools: Button = app.find_child("LogicPhaseTools", true, false)
		point = phase_tools.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames()
		check(app._logic_phase_tools and app._logic_phase == "end", "Настройки фаз открываются отдельно от фильтра")
		phase_tools = app.find_child("LogicPhaseTools", true, false)
		point = phase_tools.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames()
		var zoom_out: Button = app.find_child("LogicZoomOut", true, false)
		point = zoom_out.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames(8)
		var canvas: Control = app.find_child("LogicZoomCanvas", true, false)
		check(is_equal_approx(app._logic_zoom, 0.9) and is_equal_approx(canvas.content.scale.x, 0.9), "Кнопка уменьшает настоящие цепочки до90%")
		minimap = app.find_child("LogicMinimap", true, false)
		check(minimap.entries.size() == 14 and minimap.content == canvas, "Обзор использует размеры масштабированного холста")
		var fold: Button = app.find_child("LogicFold3", true, false)
		point = fold.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames(8)
		minimap = app.find_child("LogicMinimap", true, false)
		check(app._logic_collapsed.has(3) and minimap.entries.size() == 1, "Свёрнутая цепочка оставляет в обзоре только шапку")
		fold = app.find_child("LogicFold3", true, false)
		point = fold.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames(8)
		minimap = app.find_child("LogicMinimap", true, false)
		check(not app._logic_collapsed.has(3) and minimap.entries.size() == 14, "Разворачивание возвращает все вложенные блоки")
		for step in 6:
			var zoom_in: Button = app.find_child("LogicZoomIn", true, false)
			point = zoom_in.get_global_rect().get_center()
			await pointer(point, true)
			await pointer(point, false)
			await frames(5)
		canvas = app.find_child("LogicZoomCanvas", true, false)
		check(is_equal_approx(app._logic_zoom, 1.5) and is_equal_approx(canvas.content.scale.x, 1.5), "Увеличение до150% сохраняет настоящий масштаб содержимого")
		var reset: Button = app.find_child("LogicZoomReset", true, false)
		point = reset.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames(8)
		check(is_equal_approx(app._logic_zoom, 1.0), "Кнопка процента возвращает100%")
		check(JSON.stringify(app.document.data) == before, "Масштаб и сворачивание не меняют правила игры")
		root.get_texture().get_image().save_png(folder + mode + ".png")
		data.rules.chains = [{"event": {"type": "start"}, "blocks": []}]
		app.document.replace(data, "Пустая цепочка")
		app._logic_phase = ""
		app._render()
		await frames()
		minimap = app.find_child("LogicMinimap", true, false)
		check(minimap.entries.size() == 1, "Пустая цепочка остаётся на мини-карте")
		data.rules.chains = []
		app.document.replace(data, "Без цепочек")
		for i in 4:
			app._render()
		await frames(8)
		minimap = app.find_child("LogicMinimap", true, false)
		scroll = app.find_child("LogicCanvasScroll", true, false)
		check(minimap.entries.is_empty(), "Быстрое перестроение пустого холста не оставляет старые ссылки")
		var area: Rect2 = minimap.map_rect()
		var visible: Rect2 = minimap.viewport_rect()
		check(absf(area.size.y - visible.size.y) <= 1 and scroll.scroll_vertical == 0, "Пустой холст целиком виден без прокрутки")
		# Следующий проект не должен наследовать скрывающий всё фильтр/ветвь прежнего.
		app._logic_phase = "old_phase"
		app._logic_path = ["rules", "chains", 0, "blocks", 0]
		app._logic_target = app._logic_path.duplicate()
		app._logic_scroll = 900
		app._editing = false
		app._render()
		await frames()
		var create_button: Button
		for node: Node in app.find_children("*", "Button", true, false):
			if node.text == "Новая игра" and node.is_visible_in_tree():
				create_button = node
		check(is_instance_valid(create_button), "Создание следующего проекта доступно")
		point = create_button.get_global_rect().get_center()
		await pointer(point, true)
		await pointer(point, false)
		await frames()
		check(app._editing and app._logic_phase.is_empty() and app._logic_path.is_empty() and app._logic_target.is_empty() and app._logic_scroll == 0, "Новый проект сбросил чужой фильтр/выбор/прокрутку")
		app.queue_free()
		await frames()
	print("EDITOR LOGIC MAP UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
