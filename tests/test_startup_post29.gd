extends SceneTree
## Узкая проверка первого трека хаба и надписи заставки. Запуск: --headless --audio-driver Dummy --script res://tests/test_startup_post29.gd
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	var prefs := root.get_node("Prefs")
	var audio_before := [prefs.muted, prefs.music_volume, prefs.sfx_volume]
	var sfx := root.get_node("Sfx")
	check(AudioServer.get_driver_name() == "Dummy", "Звук проверки выключен драйвером Dummy")
	check(not sfx._music_started and sfx._music.stream == null, "Свежий запуск ещё не выбирал музыку")
	var splash: Control = load("res://hub/boot/hufflesoft_splash.gd").new()
	root.add_child(splash)
	var label: Label = splash._word_vp.get_child(0)
	check(label.text == "huffleslop", "Видимая надпись заставки — huffleslop")
	check(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, splash.TEXT_PX).x <= splash._word_vp.size.x, "Новое слово помещается в текстовую область")
	splash.queue_free()
	await process_frame
	var hub: Control = load("res://hub/hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	# Синхронно сразу после _ready: старый порядок уже выбрал бы таверну.
	check(sfx._music.stream.resource_path == hub.MENU_MUSIC[0], "Самый первый stream — музыка хаба, без вступления таверны")
	check(sfx._playlist == hub.MENU_MUSIC, "Выбран плейлист хаба")
	check(sfx._music.playing and is_equal_approx(sfx._music.volume_db, -30.0), "Первый трек начинается плавно с -30 дБ")
	await create_timer(2.8).timeout
	check(sfx._music.stream.resource_path == hub.MENU_MUSIC[0], "После входа продолжает играть первый трек хаба")
	check(is_equal_approx(sfx._music.volume_db, sfx._track_db(hub.MENU_MUSIC[0])), "Плавный вход достигает штатного уровня трека")
	check(audio_before == [prefs.muted, prefs.music_volume, prefs.sfx_volume], "Настройки звука пользователя не изменены")
	print("STARTUP_POST29: проверок=", checks, " ошибок=", errors, " stream=", sfx._music.stream.resource_path, " db=", sfx._music.volume_db)
	current_scene = null
	hub.queue_free()
	await process_frame
	await sfx.request_quit(1 if errors else 0)
