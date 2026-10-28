extends SceneTree
## Настоящая заставка→хаб и локальный однократный показ версии. Dummy/свежий APPDATA.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for index in count:
		await process_frame

func snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/batch28_startup/%s.png" % name)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("application/config/version", "0.8.5")  # Проверяется историческое представление именно этой версии.
	await frames()
	root.size = Vector2i(1280, 720)
	var notice = load("res://hub/version_notice.gd")
	check(notice.pending(), "Свежий профиль ожидает представления0.8.5")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://hub/boot/boot.tscn", "Заставка является точкой запуска")
	check(not ProjectSettings.get_setting("application/boot_splash/show_image", true), "Штатная картинка Godot выключена")
	var boot: Control = load("res://hub/boot/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	await create_timer(1.95).timeout
	check(current_scene == boot, "До конца заставки хаб не открыт")
	await snap("logo")
	await create_timer(0.9).timeout
	await snap("burst")
	var deadline := Time.get_ticks_msec() + 18000
	while current_scene == boot and Time.get_ticks_msec() < deadline:
		await frames()
	check(current_scene != boot, "Заставка завершилась переходом в хаб")
	var hub: Control = current_scene
	check(hub.scene_file_path == "res://hub/hub.tscn", "Открыт настоящий хаб")
	var finished_ms := int(root.get_meta(&"startup_finished_msec", -1))
	check(finished_ms >= 0, "Сохранено время окончания заставки")
	while Time.get_ticks_msec() < finished_ms + 1950:
		check(hub.get_node_or_null("NewGameNotice") == null, "Новость не появляется раньше двух секунд")
		await create_timer(0.15).timeout
	deadline = Time.get_ticks_msec() + 6000
	while hub.get_node_or_null("NewGameNotice") == null and Time.get_ticks_msec() < deadline:
		await frames()
	check(hub.get_node_or_null("NewGameNotice") != null, "Появилась крупная надпись новой игры")
	check(Time.get_ticks_msec() >= finished_ms + 2000, "Выдержаны две секунды после окончания")
	check(str(hub._selected.get("id", "")) == "the_gang", "Выбрана именно коробка The Gang")
	check(not notice.pending(), "Версионный флаг сохранён после показа")
	await create_timer(0.65).timeout
	await snap("new-game")
	var banner: Control = hub.get_node_or_null("NewGameNotice")
	if banner:
		for label in banner.find_children("*", "Label", true, false):
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(label.get_global_rect()), "Надпись в пределах720p")
	current_scene = null
	hub.queue_free()
	await frames()
	check(change_scene_to_file("res://hub/hub.tscn") == OK, "Повторный вход в хаб")
	await create_timer(2.3).timeout
	check(current_scene.get_node_or_null("NewGameNotice") == null, "Возврат в хаб не повторяет новость")
	check(root.find_children("Boot", "Control", true, false).is_empty(), "Возврат не проигрывает заставку")
	var version: String = ProjectSettings.get_setting("application/config/version")
	ProjectSettings.set_setting("application/config/version", "0.8.6")
	check(not notice.pending(), "Новость привязана к нужной версии")
	ProjectSettings.set_setting("application/config/version", version)
	current_scene.queue_free()
	current_scene = null
	await frames()
	print("ЗАПУСК28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
