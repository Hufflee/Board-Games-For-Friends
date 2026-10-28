extends SceneTree
## Узкие границы startup. Dummy, собственный APPDATA; STARTUP_REVIEW_RESTART=1 — второй процесс.
var checks := 0
var errors := 0
var notice: GDScript
var clicks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func frames() -> void:
	for index in 3:
		await process_frame

func clear_scene() -> void:
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = null
	await frames()

func hub() -> Control:
	var node: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(node)
	current_scene = node
	await frames()
	return node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	ProjectSettings.set_setting("application/config/version", "0.8.5")  # Изолированный сценарий версионной новости.
	await frames()
	root.size = Vector2i(1280, 720)
	notice = load("res://hub/version_notice.gd")
	var prefs: Node = root.get_node("Prefs")
	var audio_before := [prefs.muted, prefs.music_volume, prefs.sfx_volume]
	check(AudioServer.get_driver_name() == "Dummy", "Драйвер звука Dummy")
	if OS.get_environment("STARTUP_REVIEW_RESTART") == "1":
		check(not notice.pending(), "Следующий процесс читает сохранённый флаг")
		check(not root.has_meta(&"startup_finished_msec"), "Метаданные Boot не переживают процесс")
		var boot: Control = load("res://hub/boot/boot.tscn").instantiate()
		root.add_child(boot)
		current_scene = boot
		await create_timer(8.2).timeout
		check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://hub/hub.tscn", "Второй процесс всё равно проходит заставку и открывает хаб")
		check(current_scene.get_node_or_null("NewGameNotice") == null, "После перезапуска новость не повторяется")
	else:
		check(notice.pending(), "Свежий независимый профиль")
		var node: Control = await hub()
		await create_timer(2.15).timeout
		check(node.get_node_or_null("NewGameNotice") == null and notice.pending(), "Прямой хаб без Boot не показывает и не помечает новость")
		await clear_scene()
		var version: String = ProjectSettings.get_setting("application/config/version")
		ProjectSettings.set_setting("application/config/version", "0.8.6")
		root.set_meta(&"startup_finished_msec", Time.get_ticks_msec() - 3000)
		node = await hub()
		await create_timer(0.1).timeout
		check(node.get_node_or_null("NewGameNotice") == null and not notice.pending(), "Иная версия исключает показ даже с Boot-метаданными")
		await clear_scene()
		ProjectSettings.set_setting("application/config/version", version)
		root.set_meta(&"startup_finished_msec", Time.get_ticks_msec())
		node = await hub()
		# Реальный запуск меню игры до истечения таймера представления.
		var target: Dictionary = load("res://hub/games.gd").by_id("wavelength")
		node._open_scene(target)
		await create_timer(2.2).timeout
		check(current_scene != node and current_scene.scene_file_path == target.scene, "Запуск игры доведён до настоящей сцены")
		check(root.find_children("NewGameNotice", "", true, false).is_empty(), "Отложенный callback старого хаба не добавляет баннер в игре")
		check(notice.pending(), "Отмена запуском игры не расходует флаг")
		await clear_scene()
		root.set_meta(&"startup_finished_msec", Time.get_ticks_msec())
		node = await hub()
		node._on_box_selected(target)
		await create_timer(2.15).timeout
		check(str(node._selected.get("id", "")) == "wavelength", "Представление не отнимает уже выбранную другую игру")
		check(node.get_node_or_null("NewGameNotice") == null and notice.pending(), "Выбор игрока отменяет показ без записи флага")
		await clear_scene()
		root.set_meta(&"startup_finished_msec", Time.get_ticks_msec())
		node = await hub()
		await clear_scene()
		await create_timer(2.1).timeout
		check(notice.pending(), "Удалённый хаб не расходует флаг и не вызывает старый callback")
		root.set_meta(&"startup_finished_msec", Time.get_ticks_msec())
		node = await hub()
		var button := Button.new()
		button.text = "Тест ввода под баннером"
		button.position = Vector2(400, 90)
		button.size = Vector2(480, 100)
		button.z_index = 109
		button.pressed.connect(func(): clicks += 1)
		node.add_child(button)
		var deadline := Time.get_ticks_msec() + 7000
		while node.get_node_or_null("NewGameNotice") == null and Time.get_ticks_msec() < deadline:
			await process_frame
		check(node.get_node_or_null("NewGameNotice") != null, "После отмен новая допустимая попытка показывает баннер")
		check(Time.get_ticks_msec() >= int(root.get_meta(&"startup_finished_msec")) + 2000, "Граница не менее двух секунд соблюдена")
		check(not notice.pending(), "Успешный показ сохраняет флаг")
		var point := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		await frames()
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.pressed = down
			Input.parse_input_event(event)
			await frames()
		check(clicks == 1, "Реальные нажатие/отпускание проходят через баннер к нижней кнопке")
		button.grab_focus()
		for down in [true, false]:
			var event := InputEventKey.new()
			event.keycode = KEY_SPACE
			event.pressed = down
			Input.parse_input_event(event)
			await frames()
		check(clicks == 2, "Баннер не отнимает клавиатурный фокус кнопки")
		await create_timer(4.2).timeout
		check(node.get_node_or_null("NewGameNotice") == null, "Баннер штатно удаляется по окончании")
	check([prefs.muted, prefs.music_volume, prefs.sfx_volume] == audio_before, "Заставка и показ не меняют громкости Prefs")
	await clear_scene()
	print("STARTUP_LOW: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
