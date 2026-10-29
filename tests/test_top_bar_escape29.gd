extends SceneTree
## ESC-меню: настоящий клавиатурный/мышиный ввод, пауза и зритель; Dummy, отдельный APPDATA.
var checks := 0
var errors := 0
var scene: Control
var bar: Control
var game_button: Button
var edit: LineEdit
var hits := 0
var net: Node

class ClientPeer extends MultiplayerPeerExtension:
	func _is_server() -> bool:
		return false
	func _get_unique_id() -> int:
		return 2
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED
	func _poll() -> void:
		pass
	func _get_available_packet_count() -> int:
		return 0


func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	await create_timer(0.25).timeout

func key() -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await settle()

func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await settle()

func button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size.y = 32
	return b

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(2)
	check(net.start_game() == "", "Подготовлена настоящая локальная партия")
	net.set_process(false)
	scene = Control.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scene)
	current_scene = scene
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(background)
	var top_script: Script = load("res://hub/top_bar.gd")
	bar = top_script.make(scene, "Проверка меню", button, null, Color(0.9, 0.9, 0.85))
	bar.info.text = "Раунд 1 · ваш ход"
	for text: String in ["Правила", "Настройки", "Длинный журнал событий партии", "Ещё одна длинная кнопка", "Выйти из игры"]:
		var action_button := button(text, 14)
		action_button.pressed.connect(func(): hits += 10)
		bar.actions.add_child(action_button)
	game_button = button("Игровое действие", 16)
	game_button.position = Vector2(24, 620)
	game_button.pressed.connect(func(): hits += 1)
	scene.add_child(game_button)
	edit = LineEdit.new()
	edit.position = Vector2(24, 570)
	edit.size = Vector2(240, 36)
	scene.add_child(edit)
	await settle()
	check(not bar._drawer.is_visible_in_tree(), "Изначально все правые действия скрыты")
	check(bar.title.is_visible_in_tree() and bar.info.is_visible_in_tree() and bar.coin_dock.is_visible_in_tree(), "Название, ход и монетка остаются видимыми")
	await key()
	check(bar._menu_open and bar._drawer.is_visible_in_tree(), "Настоящий Escape раскрывает меню")
	await click(bar._esc_btn)
	check(not bar._menu_open and not bar._drawer.visible, "Квадрат esc скрывает меню")
	await click(bar._esc_btn)
	check(bar._menu_open, "Квадрат esc раскрывает меню")
	await click(bar.actions.get_child(0))
	check(hits == 10, "Кнопка меню выполняет действие настоящим вводом")
	hits = 0
	# Настоящее окно правил само обрабатывает Escape, не помечая его handled.
	var modal: Control = load("res://games/king_of_12/ui/rules_screen.gd").new()
	modal.z_index = 100
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.add_child(modal)
	await settle()
	await key()
	check(not is_instance_valid(modal), "Escape закрывает окно правил")
	check(bar._menu_open, "Закрытие модального окна не переключает меню")
	await key()
	check(not bar._menu_open, "Следующий Escape скрывает меню")
	await click(edit)
	edit.edit()
	await key()
	check(not edit.is_editing() and not bar._menu_open, "Первый Escape заканчивает редактирование LineEdit")
	await key()
	check(bar._menu_open, "Второй Escape открывает меню после LineEdit")
	await click(game_button)
	check(hits == 1, "Игровая кнопка вне панели сохраняет ввод")
	net.set_paused(true)
	await settle()
	edit.release_focus()
	game_button.release_focus()
	check(root.gui_get_focus_owner() == null, "На паузе действительно нет владельца фокуса")
	await key()
	check(not bar._menu_open, "Escape работает на паузе без фокуса")
	await click(game_button)
	check(hits == 1, "Игровая кнопка блокируется паузой")
	await click(bar._esc_btn)
	check(bar._menu_open, "Квадрат esc работает на паузе")
	check(bar._pause_btn.visible, "Хост видит кнопку продолжения")
	net.set_paused(false)
	net.view["spectator"] = true
	await settle()
	await click(bar._esc_btn)
	check(not bar._menu_open, "Зритель может нажать esc")
	await key()
	check(bar._menu_open, "Зритель раскрывает меню Escape")
	await click(game_button)
	check(hits == 1, "Зритель не получает игровые действия")
	check(not bar._spec_btn.visible, "Зритель не видит переход в зрители")
	# Mock прав клиента без сокетов; затем возвращаем настоящий offline peer.
	var old_peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	root.multiplayer.multiplayer_peer = ClientPeer.new()
	await settle()
	check(not bar._pause_btn.visible, "Клиент не видит хостовую кнопку паузы")
	root.multiplayer.multiplayer_peer = old_peer
	for width: int in [960, 1280]:
		root.size = Vector2i(width, 720)
		await settle()
		check(bar._drawer.get_global_rect().end.x <= width - 8, "Панель целиком внутри экрана с отступом")
		for c: Control in bar.actions.get_children():
			check(c.get_global_rect().position.x >= 0 and c.get_global_rect().end.x <= width, "Длинное действие помещается после resize")
	root.size = Vector2i(1280, 720)
	for dark: bool in [false, true]:
		background.color = Color(0.12, 0.14, 0.18) if dark else Color(0.83, 0.84, 0.80)
		var ink := Color(0.92, 0.91, 0.85) if dark else Color(0.15, 0.17, 0.21)
		bar.title.add_theme_color_override("font_color", Color(ink, 0.8))
		bar.info.add_theme_color_override("font_color", ink)
		scene.theme = ThemeDB.get_default_theme().duplicate()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.17, 0.21) if dark else Color(0.88, 0.87, 0.82)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		scene.theme.set_stylebox("normal", "Button", sb)
		scene.theme.set_color("font_color", "Button", Color(0.92, 0.91, 0.85) if dark else Color(0.15, 0.17, 0.21))
		await settle()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/esc_visual29/menu-%s.png" % ("dark" if dark else "light"))
	print("ESC29: %d проверок, %d ошибок" % [checks, errors])
	net.leave()
	scene.queue_free()
	await process_frame
	# Реальный стол: поздние контейнеры поля не должны перехватывать меню.
	var preferences: Node = root.get_node("Prefs")
	for mode: String in ["light", "dark"]:
		preferences.theme_mode = mode
		net.host_offline("the_gang")
		net.set_bots(9)
		check(net.start_game() == "", "Стол десяти мест для темы " + mode)
		var app: Control = load("res://games/the_gang/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		await settle()
		var table: Control = app.screen
		bar = table._top
		await click(bar._esc_btn)
		check(bar._menu_open, "Настоящий стол раскрывает меню мышью: " + mode)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/esc_visual29/gang-menu-%s.png" % mode)
		await click(app.find_child("Rules", true, false))
		var close: Control = app.find_child("CloseRules", true, false)
		check(close != null, "Кнопка правил получает ввод поверх поля: " + mode)
		if close != null:
			await click(close)
		await click(app.find_child("Settings", true, false))
		close = app.find_child("CloseSettings", true, false)
		check(close != null, "Кнопка настроек получает ввод поверх поля: " + mode)
		if close != null:
			await click(close)
		net.leave()
		app.queue_free()
		await process_frame
	print("ESC29 FINAL: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
