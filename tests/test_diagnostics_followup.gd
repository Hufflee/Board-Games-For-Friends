extends SceneTree
## Узкая проверка диагностики: переполнение, немедленная запись ошибок, приватность и смена партии.
## Godot --headless --audio-driver Dummy --path . --script res://tests/test_diagnostics_followup.gd

const Sink := preload("res://hub/diagnostic_logger.gd")
const WindowsInfo := preload("res://hub/windows_crash_info.gd")
var checks := 0
var errors := 0

class NetworkFixture extends Node:
	var party_game := "the_gang"
	var game_id := "old-match"
	var in_game := true
	var mode := "enet"
	var lobby_view := {"members": [1, 2, 3]}
	var view := {"game_id": "old-match"}
	var steam_ok := false

	func is_host() -> bool:
		return false


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error("ПРОВАЛ: " + message)


func _expected_error() -> void:
	push_error("ОЖИДАЕМАЯ_FOLLOWUP: ошибка после MAX_BYTES")


func _worker_error() -> void:
	push_error("ОЖИДАЕМАЯ_FOLLOWUP: ошибка потока после MAX_BYTES")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/client_switch_audit"))
	var diag: Node = root.get_node("Diag")
	var sink_script: Script = Sink
	var diagnostic_script: Script = load("res://hub/diagnostics.gd")
	if OS.get_environment("DIAG_BASELINE") == "1":
		sink_script = load("res://backups/client_diagnostics_2026-10-27/diagnostic_logger.gd")
		diagnostic_script = load("res://backups/client_diagnostics_2026-10-27/diagnostics.gd")
	var path := "user://logs/followup-limit.log"
	var logger: Logger = sink_script.new()
	check(logger.open(path), "Тестовый журнал открыт")
	logger.checkpoint("НАЧАЛО_FOLLOWUP", "начальный контекст")
	for i: int in 170:
		logger.checkpoint("заполнение_" + str(i) + "x".repeat(15900), "контекст")
	logger.checkpoint("ПОСЛЕДНИЙ_КОНТЕКСТ", "раунд=4; роль=клиент")
	OS.add_logger(logger)
	_expected_error()
	var thread := Thread.new()
	thread.start(_worker_error)
	thread.wait_to_finish()
	var report: String = diag.report_text(path)
	check(report.contains("ОЖИДАЕМАЯ_FOLLOWUP"), "Последняя ошибка сохранена после MAX_BYTES до close")
	check(report.contains("_expected_error") and report.contains("test_diagnostics_followup.gd"), "Стек ошибки сброшен до close")
	check(report.contains("раунд=4; роль=клиент"), "Ошибка содержит последний контекст после лимита")
	check(report.contains("_worker_error"), "Ошибка и стек рабочего потока сброшены после лимита")
	for i: int in 70:
		logger.checkpoint("после_ошибки_" + str(i) + "y".repeat(15900), "новый контекст")
	logger.checkpoint("КОНЕЦ_FOLLOWUP", "последняя фаза")
	report = diag.report_text(path)
	check(report.contains("НАЧАЛО_FOLLOWUP"), "Начало переполненного журнала сохранено")
	check(report.contains("КОНЕЦ_FOLLOWUP"), "Хвост продолжает обновляться после повторной ротации")
	check(report.contains("ОЖИДАЕМАЯ_FOLLOWUP"), "Шквал этапов не вытеснил последнюю ошибку")
	for i: int in 60:
		logger._log_error("синтетическая_ошибка", "fixture.gd", i, "ОШИБКА_" + str(i), "я".repeat(3000), false, 0, [])
	logger._log_error("последняя_ошибка", "fixture.gd", 60, "ПОСЛЕДНЯЯ_ОШИБКА_ПОСЛЕ_РОТАЦИИ", "описание", false, 0, [])
	report = diag.report_text(path)
	check(report.contains("ПОСЛЕДНЯЯ_ОШИБКА_ПОСЛЕ_РОТАЦИИ"), "Ограниченный журнал ошибок ротируется и сохраняет последнюю")
	check(FileAccess.get_file_as_bytes(path).size() <= Sink.MAX_BYTES, "Основной файл ограничен 2 МиБ")
	for suffix: String in [".tail", ".tail.previous", ".errors", ".errors.previous"]:
		var size := FileAccess.get_file_as_bytes(path + suffix).size() if FileAccess.file_exists(path + suffix) else 0
		check(size <= Sink.TAIL_BYTES, "Ограничен файл " + suffix)
	OS.remove_logger(logger)
	logger.close()
	# Отдельный объект без _ready не меняет реальную сеть; тестовый маркер ниже восстанавливаем.
	var fixture: Node = diagnostic_script.new()
	var net := NetworkFixture.new()
	root.add_child(net)
	fixture._net = net
	fixture.sink = Sink.new()
	fixture.sink.open("user://logs/followup-context.log")
	fixture._on_state({"game": "the_gang", "game_id": "old-match", "phase": "showdown", "round_no": 4})
	check(fixture._context().get("phase") == "showdown", "Старая фаза сначала действительно сохранена")
	net.party_game = "dangerous_words"
	var context: Dictionary = fixture._context()
	check(not context.has("phase") and not context.has("game"), "Смена игры до нового state убрала старую фазу и game")
	check(context.get("игра") == "dangerous_words", "Новая выбранная игра видна до state")
	fixture._on_state({"game": "the_gang", "game_id": "old-match", "phase": "showdown"})
	check(not fixture._context().has("phase"), "Поздний state другой игры не возвращает фазу")
	net.game_id = "new-match"
	fixture._on_state({"game": "dangerous_words", "game_id": "old-match", "phase": "old_phase"})
	check(not fixture._context().has("phase"), "Поздний state другой партии той же игры отвергнут")
	fixture._on_state({"game": "dangerous_words", "game_id": "new-match", "phase": "play", "round_no": 1})
	check(fixture._context().get("phase") == "play", "Подходящий новый state принят")
	check(fixture._context().get("партия") == "new-match", "Идентификатор партии не читается из старого net.view")
	net.in_game = false
	check(not fixture._context().has("phase"), "Выход в лобби очистил фазу")
	fixture._on_state({"game": "dangerous_words", "game_id": "new-match", "phase": "play"})
	check(not fixture._context().has("phase"), "State во время лобби не возвращает старую фазу")
	net.in_game = true
	fixture._on_state({"game": {"hand": "СЕКРЕТ_ИГРА"}, "phase": "old_phase"})
	check(not fixture._context().has("phase"), "Неверный тип game не допускает чужую фазу")
	fixture._on_state({"game": "dangerous_words", "game_id": ["СЕКРЕТ_ПАРТИЯ"], "phase": "old_phase"})
	check(not fixture._context().has("phase"), "Неверный тип game_id не допускает чужую фазу")
	fixture._on_state({"game": "dangerous_words", "game_id": "new-match", "phase": {"hand": "СЕКРЕТ_ВЛОЖЕННЫЙ"},
		"round_no": ["СЕКРЕТ_МАССИВ"], "hand": ["СЕКРЕТ_РУКА"], "api_key": "СЕКРЕТ_КЛЮЧ", "chat": "СЕКРЕТ_ЧАТ"})
	fixture.mark("Проверка фильтра", {"unknown": "СЕКРЕТ_НЕИЗВЕСТНЫЙ", "phase": {"api_key": "СЕКРЕТ_ДЕТАЛИ"}})
	var text := FileAccess.get_file_as_string("user://logs/followup-context.log")
	check(not text.contains("СЕКРЕТ_"), "Неизвестные и вложенные payload не попали в журнал")
	check(not FileAccess.get_file_as_string(diag.FLAG).contains("СЕКРЕТ_"), "Неизвестные payload не попали в JSON маркера")
	check(not fixture._context().has("phase") and not fixture._context().has("round_no"), "Неверные типы публичных полей отвергнуты")
	fixture.sink.close()
	fixture.free()
	net.free()
	diag._save_marker()
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(diag.FLAG))
	check(marker is Dictionary and marker.pid == OS.get_process_id(), "Маркер всё ещё принадлежит только этому процессу")
	if OS.get_environment("DIAG_BASELINE") != "1":
		_check_engine_archive(diag)
		var query := WindowsInfo.query_script({"pid": 1234, "started": 1793103896, "process_started": 1793103866,
			"last_seen": 1793103900, "executable": "C:\\Игры\\PartyWorld.exe"},
			ProjectSettings.globalize_path("res://build/client_switch_audit/windows-followup-result.json"))
		var file := FileAccess.open("res://build/client_switch_audit/medium-windows-query.ps1", FileAccess.WRITE)
		file.store_string(query)
		file.close()
		check(query.contains("FromUnixTimeSeconds(1793103866)"), "PID сопоставляется со стартом процесса, а не поздним _ready")
	if OS.get_environment("DIAG_BASELINE") != "1" and OS.get_name() == "Windows":
		await _check_timeout(diag)
	print("ДИАГНОСТИКА FOLLOWUP: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)


func _check_engine_archive(diag: Node) -> void:
	var source := "user://logs/followup-engine.log"
	var target := "user://logs/followup-engine.log.engine"
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string("СТАРЫЙ_ДВИЖОК\n")
	file.close()
	diag._snapshot_engine({"engine_log": source, "engine_snapshot": target})
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string("НОВЫЙ_ДВИЖОК\n")
	file.close()
	check(FileAccess.get_file_as_string(target).contains("СТАРЫЙ_ДВИЖОК"), "Снимок старого лога не зависит от перезаписи --log-file")
	var previous: Dictionary = diag.previous_session
	diag.previous_session = {"log": "user://logs/followup-context.log", "engine_log": target}
	var report: String = diag.report_text("user://logs/followup-context.log")
	check(report.contains("СТАРЫЙ_ДВИЖОК") and not report.contains("НОВЫЙ_ДВИЖОК"), "Старый отчёт не смешан с новым стандартным логом")
	diag.previous_session = previous
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string("x".repeat(400000))
	file.close()
	check(diag._read_tail(source).length() <= diag.MAX_COPY + 9000, "Одна огромная строка не обходит лимит копирования")


func _check_timeout(diag: Node) -> void:
	var powershell := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var child := OS.create_process(powershell, PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Start-Sleep -Seconds 30"
	]), false)
	check(child > 0, "Создан только собственный тестовый процесс системного запроса")
	if child <= 0:
		return
	var previous: Dictionary = diag.previous_session
	var native_path := "user://logs/followup-timeout.json"
	if FileAccess.file_exists(native_path):
		DirAccess.remove_absolute(native_path)
	diag.previous_session = {"native_log": native_path}
	diag._native_pid = child
	diag._native_started_msec = Time.get_ticks_msec() - 16000
	diag._process(0.0)
	await create_timer(0.2).timeout
	check(not OS.is_process_running(child), "Запрос остановлен по настенным часам при delta=0")
	var status: Variant = JSON.parse_string(FileAccess.get_file_as_string(native_path))
	check(status is Dictionary and status.status == "timeout", "Тайм-аут записан явно, причина аварии не выдумана")
	diag.previous_session = previous
