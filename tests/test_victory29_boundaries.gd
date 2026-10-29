extends SceneTree
## Адресные границы общего финала: поздний Steam-аватар из кеша, ESC/чат/правила поверх финала, уход удержанием.
var checks := 0
var errors := 0
var net: Node
var app: Control
var screen: Control
var bar: Control
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	print("VICTORY BOUNDARY ", "OK " if ok else "FAIL ", text)
	if not ok:
		errors += 1
func settle() -> void:
	await create_timer(0.2).timeout
func mouse(control: Control, down: bool) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame
func click(control: Control) -> void:
	await mouse(control, true)
	await mouse(control, false)
	await settle()
func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("the_gang")
	net.set_bots(3)
	check(net.start_game() == "", "Подготовлена партия")
	net.set_process(false)
	net.gang.phase = "game_over"
	net.gang.won = true
	net.gang.players[0].steam_id = 123456
	net._push_state()
	app = load("res://games/the_gang/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	screen = app.screen.get_node("VictoryScreen")
	bar = app.screen._top
	var card: Control = screen._cards[0]
	var avatar: TextureRect = card.get_node("Avatar")
	check(avatar.texture == null and card.get_node("Initials").visible, "Без Steam читаемые инициалы")
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("74a8c7"))
	var texture := ImageTexture.create_from_image(image)
	net._avatars[123456] = texture
	net.steam_ok = true
	screen._avatar_check_ms = 0
	await settle()
	check(avatar.texture == texture, "Поздно появившийся кешированный аватар заменяет fallback")
	check(not card.get_node("Initials").visible, "Инициалы скрыты после доставки аватара")
	net.steam_ok = false
	net._avatars.erase(123456)
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await settle()
	check(bar._menu_open, "ESC работает на финале")
	await click(bar._chat_btn)
	check(bar.chat.expanded, "Чат раскрывается поверх финала")
	await click(bar.chat._input)
	check(bar.chat._input.has_focus(), "Поле чата принимает мышь поверх финала")
	await click(bar._chat_btn)
	await click(app.find_child("Rules", true, false))
	var close: Control = app.find_child("CloseRules", true, false)
	check(close != null and close.is_visible_in_tree(), "Правила открываются поверх финала")
	if close != null:
		await click(close)
	check(app.find_child("CloseRules", true, false) == null, "Модальное окно закрывается реальным кликом")
	var player: AudioStreamPlayer = root.get_node("Sfx")._victory
	check(player.playing, "Музыка продолжает играть при просмотре правил/чата")
	var menu: Button = screen._buttons.get_node("VictoryMenu")
	await mouse(menu, true)
	await create_timer(1.15).timeout
	var release := InputEventMouseButton.new()
	release.position = Vector2(16, 16)
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await settle()
	check(not player.playing, "Удержание В меню немедленно останавливает музыку")
	check(not net.in_game, "Штатный маршрут приложения завершает партию")
	app = current_scene
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	print("VICTORY BOUNDARIES ", checks, "/", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
