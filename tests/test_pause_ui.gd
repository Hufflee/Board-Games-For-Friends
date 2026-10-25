extends SceneTree
## Регрессия общей паузы через GUI, без вызова сигнала pressed.
## Запуск: Godot --path . --script res://tests/test_pause_ui.gd
## GAMES=id,id ограничивает игры; PAUSE_THEME=light проверяет светлую тему.

var checks := 0
var errors := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("ПРОВЕРКА ", message, " = ", ok)
	if not ok:
		errors += 1
		push_error(message)

func settle() -> void:
	await create_timer(0.6).timeout

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	var hovered := root.gui_get_hovered_control()
	print("НАВЕДЕНИЕ ", hovered.get_path() if hovered else "нет", " скрипт=", hovered.get_script() if hovered else "нет")
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	var net = root.get_node("Net")
	# Окно отчёта прошлого неудачного теста не относится к проверяемому столу.
	for child: Node in net.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("crash_report.gd"):
			child.queue_free()
	await process_frame
	var prefs = root.get_node("Prefs")
	prefs.theme_mode = "light" if OS.get_environment("PAUSE_THEME") == "light" else "dark"
	prefs.window_mode = "windowed"
	prefs.resolution = "1280x720"
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.show()
	var pause = net.get_children().filter(func(n):
		return n.get_script() != null and n.get_script().resource_path.ends_with("pause_layer.gd"))[0]
	var registry = load("res://hub/games.gd")
	var games := OS.get_environment("GAMES").split(",", false)
	if games.is_empty():
		for game: Dictionary in registry.LIST:
			games.append(game.id)
	for game: String in games:
		net.leave()
		var entry: Dictionary = registry.LIST.filter(func(g): return g.id == game)[0]
		change_scene_to_file(entry.scene)
		await scene_changed
		await process_frame
		net.host_offline("gloom" if game == "gloomier" else game)
		if game in ["gloom", "gloomier"]:
			net.settings["gl_sets"] = "gm" if game == "gloomier" else "base"
		net.set_bots(3)
		check(net.start_game() == "", game + ": старт")
		net.set_process(false)
		await settle()
		net.set_paused(true)
		await settle()
		var buttons: Array = pause._panel.find_children("*", "Button", true, false)
		var go: Button = buttons.filter(func(b): return b.text == "Продолжить игру")[0]
		go.pressed.connect(func(): print("НАЖАТИЕ ПОЛУЧЕНО ", game))
		print("КНОПКА ", game, " ", go.get_global_rect())
		await click_at(go.get_global_rect().get_center())
		await settle()
		check(not net.paused and not pause._panel.visible, game + ": продолжение кликом GUI")
		# Повторная сборка стола создаёт поздний Control: z сам по себе не спасает ввод.
		var late_table := Control.new()
		current_scene.add_child(late_table)
		late_table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		net.set_paused(true)
		await settle()
		check(pause._root.get_index() > late_table.get_index(), game + ": оверлей после позднего стола")
		var service := Button.new()
		service.text = "Служебное окно"
		service.z_index = 100
		current_scene.add_child(service)
		service.position = Vector2(500, 300)
		service.size = Vector2(280, 48)
		service.set_meta("clicked", false)
		service.pressed.connect(func(): service.set_meta("clicked", true))
		pause._refresh()
		await click_at(service.get_global_rect().get_center())
		check(bool(service.get_meta("clicked")), game + ": служебное окно доступно поверх паузы")
		service.queue_free()
		await process_frame
		buttons = pause._panel.find_children("*", "Button", true, false)
		go = buttons.filter(func(b): return b.text == "Продолжить игру")[0]
		await click_at(go.get_global_rect().get_center())
		await settle()
		check(not net.paused, game + ": повторное продолжение после пересборки")
		late_table.queue_free()
		net.end_game()
		net.set_process(true)
	print("ПАУЗА: ", checks, " проверок, ", errors, " ошибок")
	net.leave()
	quit(1 if errors else 0)
