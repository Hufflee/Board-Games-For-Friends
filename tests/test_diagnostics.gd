extends SceneTree
## Диагностика: ошибки ядра со стеком, потокобезопасность, контекст без секретов, отчёты и Windows.
## Запуск с отдельным APPDATA: Godot --headless --audio-driver Dummy --path . --script res://tests/test_diagnostics.gd
## Две намеренные ошибки помечены «ОЖИДАЕМАЯ»; они проверяют сам перехват ошибок.

const WindowsInfo := preload("res://hub/windows_crash_info.gd")
const Sink := preload("res://hub/diagnostic_logger.gd")
var checks := 0
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error("ПРОВАЛ: " + message)
	else:
		print("ПРОВЕРКА: " + message)


func _expected_format_error() -> void:
	var bad: Variant = "ОЖИДАЕМАЯ: вместо числа"
	var _text: String = "%d" % bad


func _thread_error() -> void:
	push_error("ОЖИДАЕМАЯ: ошибка рабочего потока")


func _run() -> void:
	var diag = root.get_node("Diag")
	var net = root.get_node("Net")
	check(ProjectSettings.get_setting("debug/settings/gdscript/always_track_call_stacks"), "Стеки включены и для release")
	check(ProjectSettings.get_setting("application/run/flush_stdout_on_print"), "Стандартный журнал сбрасывается сразу")
	check(FileAccess.file_exists(diag.session.log), "Отдельный журнал создан до запуска игры")
	diag.mark("Проверка перед ошибкой", {"игра": "phantom_ink"})
	_expected_format_error()
	var worker := Thread.new()
	worker.start(_thread_error)
	worker.wait_to_finish()
	var text := FileAccess.get_file_as_string(diag.session.log)
	check(text.contains("number is required"), "Настоящая ошибка operator % попала в журнал")
	check(text.contains("_expected_format_error") and text.contains("test_diagnostics.gd"), "Сохранены функция и файл стека")
	check(text.contains("ОЖИДАЕМАЯ: ошибка рабочего потока"), "Перехвачена ошибка другого потока")
	check(text.contains("phantom_ink"), "Ошибка привязана к последней контрольной точке")
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(diag.FLAG))
	check(marker is Dictionary and marker.pid == OS.get_process_id(), "В маркере сохраняется PID именно текущего процесса")
	net.player_stats = PlayerStatsStore.new("user://diagnostic_test_stats.json")
	net.host_offline("phantom_ink")
	net.set_bots(3)
	check(net.start_game() == "", "Запуск настоящей партии проходит с диагностикой")
	diag._on_state({"game": "phantom_ink", "phase": "clue", "you": 1,
		"hand": ["ТАЙНА_РУКИ"], "api_key": "ТАЙНА_КЛЮЧА", "answer": "ТАЙНА_ОТВЕТА"})
	text = diag.report_text()
	check(text.contains("Получено состояние стола") and text.contains("clue"), "Текущий отчёт включает игру и фазу")
	check(not text.contains("ТАЙНА_"), "Карты, ответы и ключи не записываются в контекст")
	check(text.contains("Текущий запуск ещё не завершён"), "Текущий отчёт не выдаёт старое событие Windows за новое")
	var saved_previous: Dictionary = diag.previous_session
	var old_path := "user://logs/fixture-previous.log"
	var native_path := "user://logs/fixture-windows.json"
	var old_file := FileAccess.open(old_path, FileAccess.WRITE)
	old_file.store_string("СТАРЫЙ_СЕАНС")
	old_file.close()
	var native_file := FileAccess.open(native_path, FileAccess.WRITE)
	native_file.store_string('{"status":"found","events":[{"module":"test.dll","exception_code":"c0000005"}]}')
	native_file.close()
	diag.previous_session = {"pid": 1234, "log": old_path, "engine_log": "", "native_log": native_path}
	text = diag.report_text(old_path)
	check(text.contains("СТАРЫЙ_СЕАНС") and text.contains("test.dll") and text.contains("c0000005"), "Предыдущий журнал объединён со своим кодом исключения и модулем")
	check(not text.contains("Проверка перед ошибкой"), "Отчёт прошлого запуска не подмешивает текущую диагностику")
	if DisplayServer.get_name() != "headless" and OS.get_environment("DIAG_TEST_CLIPBOARD") == "1":
		var clipboard := DisplayServer.clipboard_get()
		var reporter = load("res://hub/crash_report.gd")
		check(reporter.copy_log(old_path) and DisplayServer.clipboard_get().contains("test.dll"), "Кнопка копирования передаёт системные сведения прошлого сеанса")
		check(reporter.copy_log() and DisplayServer.clipboard_get().contains("Текущий запуск ещё не завершён"), "Настройки копируют текущий сеанс даже с --log-file")
		DisplayServer.clipboard_set(clipboard)
	diag.previous_session = saved_previous
	var big_path := "user://logs/fixture-big.log"
	var big_file := FileAccess.open(big_path, FileAccess.WRITE)
	big_file.store_string("ЗАГОЛОВОК_ВЕРСИЯ\n" + "строка журнала\n".repeat(30000) + "КОНЕЦ_ЖУРНАЛА")
	big_file.close()
	text = diag.report_text(big_path)
	check(text.contains("ЗАГОЛОВОК_ВЕРСИЯ") and text.contains("КОНЕЦ_ЖУРНАЛА"), "Обрезка сохраняет заголовок и конец большого журнала")
	var limited_path := "user://logs/fixture-limited.log"
	var limited := Sink.new()
	limited.open(limited_path)
	limited.checkpoint("НАЧАЛО", "контекст")
	for i in 5:
		limited.checkpoint("x".repeat(600000), "контекст")
	limited.close()
	text = FileAccess.get_file_as_string(limited_path)
	check(text.contains("НАЧАЛО") and text.contains("Лимит журнала достигнут"), "Повторные сообщения не растят журнал бесконечно")
	var session := {"pid": 1234, "started": int(Time.get_unix_time_from_system()) - 10,
		"executable": "C:\\Игры\\Друг'а\\PartyWorld.exe"}
	var source := WindowsInfo.query_script(session, ProjectSettings.globalize_path("user://logs/query-test.json"))
	check(source.contains("Друг''а") and source.contains("$eventPid -ne $targetPid"), "PowerShell экранирует пути и проверяет PID")
	var fixture := FileAccess.open("res://build/crash_logging_tests/windows-query.ps1", FileAccess.WRITE)
	fixture.store_string(source)
	fixture.close()
	if OS.get_name() == "Windows":
		var native_result := ProjectSettings.globalize_path("user://logs/real-windows-query.json")
		if FileAccess.file_exists(native_result):
			DirAccess.remove_absolute(native_result)
		var process_id := WindowsInfo.start(session, native_result)
		check(process_id > 0, "Скрытое чтение системного журнала запускается")
		var deadline := Time.get_ticks_msec() + 15000
		while process_id > 0 and OS.is_process_running(process_id) and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		if process_id > 0 and OS.is_process_running(process_id):
			OS.kill(process_id)
		check(FileAccess.file_exists(native_result), "Системный запрос завершился и сохранил результат")
		if FileAccess.file_exists(native_result):
			var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(native_result))
			check(result is Dictionary and result.status in ["not_found", "unavailable"], "Отсутствие события не подменяется выдуманной причиной")
	net.leave()
	for path: String in [old_path, native_path, big_path, limited_path]:
		DirAccess.remove_absolute(path)
	print("ДИАГНОСТИКА: проверок=", checks, " ошибок=", errors)
	quit(1 if errors else 0)
