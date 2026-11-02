extends SceneTree
## Настоящие клики буфера цепочек/блоков, вставка в ветвь, undo/redo; обе темы1280×720.
const Clipboard := preload("res://editor/ed_clipboard.gd")
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

func frames(count: int = 4) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw

func button(text: String, side: String = "") -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		if node.text != text or not node.is_visible_in_tree():
			continue
		var x: float = node.get_global_rect().get_center().x
		if side == "left" and x >= 400 or side == "right" and x < 800 or side == "center" and (x < 400 or x >= 800):
			continue
		return node
	return null

func click(control: Button) -> void:
	check(is_instance_valid(control) and not control.disabled, "Кнопка доступна для настоящего клика")
	if not is_instance_valid(control) or control.disabled:
		return
	var caption := control.text
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames()
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var fired := [false]
	control.pressed.connect(func(): fired[0] = true, CONNECT_ONE_SHOT)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	check(bool(fired[0]), "Кнопка получила клик: " + caption)
	if not bool(fired[0]):
		var hovered := root.gui_get_hovered_control()
		print("UI ПРОМАХ: ", caption, " точка ", point, " рамка ", control.get_global_rect(), " наведение ", hovered.get_path() if is_instance_valid(hovered) else "нет", " курсор ", root.get_mouse_position())
		var path := "res://build/shots/input_miss_%d.png" % Time.get_ticks_msec()
		root.get_texture().get_image().save_png(path)
	await frames(6)

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var previous := DisplayServer.clipboard_get()
	var folder := "res://build/shots/editor_logic_clipboard/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for mode: String in ["dark", "light"]:
		root.get_node("Prefs").theme_mode = mode
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		app.document.create()
		var model: RefCounted = load("res://editor/ed_logic_model.gd").new(app.document)
		model.add_event("start")
		var block_path: Array = model.add_block("if", ["rules", "chains", 0, "blocks"])
		model.add_block("log", block_path + ["then"])
		app._editing = true
		app._logic_chain = 0
		app._render()
		await frames()
		await click(button("Логика"))
		# Поля свойств меняют документ без полного перестроения панели.
		app.document.set_value(["rules", "chains", 0, "blocks", 0, "then", 0, "text"], "Свежая правка")
		app._status_text()
		await click(button("Копировать", "left"))
		check(Clipboard.decode(DisplayServer.clipboard_get()).get("kind") == "chain", "Левая панель скопировала цепочку в системный буфер")
		check(Clipboard.decode(DisplayServer.clipboard_get()).data.blocks[0].then[0].text == "Свежая правка", "Копирование видит последнюю правку без перестроения панели")
		await click(button("Вставить", "left"))
		check(app.document.data.rules.chains.size() == 2 and app._logic_chain == 1, "Вставлена и выбрана новая цепочка")
		await click(app._undo_button)
		check(app.document.data.rules.chains.size() == 1 and app._logic_chain == 0, "Отмена цепочки выбирает существующее событие")
		check(not button("Копировать", "left").disabled, "После отмены цепочки буфер доступен без лишнего клика")
		await click(app._redo_button)
		check(app.document.data.rules.chains.size() == 2, "Повтор восстановил целую цепочку")
		await click(button("Если / иначе", "center"))
		await click(button("Копировать", "right"))
		check(Clipboard.decode(DisplayServer.clipboard_get()).get("kind") == "block", "Свойства скопировали именно выбранный блок")
		await click(button("+ В ветвь «Иначе»", "right"))
		await click(button("Вставить", "right"))
		var index: int = app._logic_chain
		check(app.document.data.rules.chains[index].blocks[0].else.size() == 1, "Клик вставил копию в выбранную пустую ветвь")
		check(app._logic_path == ["rules", "chains", index, "blocks", 0, "else", 0], "После вставки выбран новый вложенный блок")
		await click(app._undo_button)
		check(app.document.data.rules.chains[index].blocks[0].else.is_empty(), "Один клик отменил вставку блока")
		await click(app._redo_button)
		check(app.document.data.rules.chains[index].blocks[0].else.size() == 1, "Повтор восстановил вставку")
		await frames()
		root.get_texture().get_image().save_png(folder + mode + ".png")
		app.queue_free()
		await frames()
	DisplayServer.clipboard_set(previous)
	print("EDITOR LOGIC CLIPBOARD UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
