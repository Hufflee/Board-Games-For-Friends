extends Node
## Ранняя автозагрузка: версия/устройство, этапы запуска, ошибки со стеками и отчёт Windows.
## Хранит последние 10 сеансов в user://logs; отчёт копируется только по нажатию игрока.

const Sink := preload("res://hub/diagnostic_logger.gd")
const WindowsInfo := preload("res://hub/windows_crash_info.gd")
const FLAG := "user://running.flag"
const LOG_DIR := "user://logs"
const MAX_COPY := 200000
var previous_session: Dictionary = {}
var session: Dictionary = {}
var sink: Sink
var _net: Node
var _heartbeat := 0.0
var _scene := ""
var _phase := ""
var _state: Dictionary = {}
var _state_identity := ""
var _native_pid := -1
var _native_started_msec := 0
var _logger_registered := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	if FileAccess.file_exists(FLAG):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLAG))
		previous_session = old if old is Dictionary else {"legacy": true}
		var old_engine := str(previous_session.get("engine_log", LOG_DIR + "/godot.log"))
		if old_engine == LOG_DIR + "/godot.log" and old_engine == _engine_log():
			previous_session["engine_log"] = _previous_engine_log()
		elif old_engine == _engine_log():
			# --log-file отключает ротацию: этот файл уже перезаписан новым процессом.
			previous_session["engine_log"] = str(previous_session.get("engine_snapshot", ""))
		# Выбранный старый журнал больше не зависит от последующей ротации Godot.
		_snapshot_engine(previous_session)
		if FileAccess.file_exists(str(previous_session.get("engine_snapshot", ""))):
			previous_session["engine_log"] = previous_session.engine_snapshot
		elif not FileAccess.file_exists(str(previous_session.get("engine_log", ""))):
			previous_session["engine_log"] = ""
	var stamp := str(int(Time.get_unix_time_from_system())) + "-" + str(OS.get_process_id())
	session = {
		"pid": OS.get_process_id(), "started": int(Time.get_unix_time_from_system()),
		"process_started": int(Time.get_unix_time_from_system() - Time.get_ticks_msec() / 1000.0),
		"executable": OS.get_executable_path(), "log": LOG_DIR + "/session-" + stamp + ".log",
		"engine_log": _engine_log(), "native_log": LOG_DIR + "/session-" + stamp + "-windows.json"
	}
	session["engine_snapshot"] = str(session.log) + ".engine"
	sink = Sink.new()
	if sink.open(session.log):
		OS.add_logger(sink)
		_logger_registered = true
	mark("Запуск приложения", _environment())
	_snapshot_engine(session)
	if not previous_session.is_empty():
		mark("Предыдущий запуск не завершён штатно")
		if previous_session.has("native_log"):
			_native_pid = WindowsInfo.start(previous_session, ProjectSettings.globalize_path(previous_session.native_log))
			_native_started_msec = Time.get_ticks_msec()
			if _native_pid < 0:
				_native_status("unavailable", "Не удалось запустить чтение системного журнала Windows.")
				mark("Не удалось запустить чтение системного журнала Windows")
	_prune()


func _environment() -> Dictionary:
	return {
		"версия": ProjectSettings.get_setting("application/config/version", "?"),
		"Godot": Engine.get_version_info().string,
		"сборка": "debug" if OS.is_debug_build() else "release",
		"ОС": OS.get_name() + " " + OS.get_version(), "CPU": OS.get_processor_name(),
		"GPU": RenderingServer.get_video_adapter_name(),
		"версия_GPU_API": RenderingServer.get_video_adapter_api_version(),
		"драйвер_GPU": OS.get_video_adapter_driver_info(),
		"драйвер": RenderingServer.get_current_rendering_driver_name(),
		"рендер": RenderingServer.get_current_rendering_method(),
		"pid": OS.get_process_id()
	}


func attach_net(net: Node) -> void:
	_net = net
	net.state_changed.connect(_on_state)
	net.lobby_changed.connect(_on_lobby)
	net.game_started.connect(func(): mark("Сигнал начала партии"))
	net.game_ended.connect(func(): mark("Партия завершена"))
	net.session_closed.connect(func(_reason): mark("Соединение закрыто"))
	mark("Сеть инициализирована")


func _context() -> Dictionary:
	_sync_state_identity()
	var context := {"сцена": _scene}
	context.merge(_state)
	if is_instance_valid(_net) and _net.is_inside_tree():
		context.merge({
			"игра": _net.party_game, "сеть": _net.mode,
			"роль": "хост" if _net.is_host() else "клиент",
			"в_партии": _net.in_game, "участников": _net.lobby_view.get("members", []).size(),
			"партия": _net.game_id, "Steam_доступен": _net.steam_ok
		})
	return context


func mark(stage: String, details: Dictionary = {}) -> void:
	if sink == null:
		return
	var context := _context()
	context.merge(_safe_details(details), true)
	sink.checkpoint(stage, JSON.stringify(context))
	session["stage"] = stage
	session["context"] = context
	_save_marker()
	print("[Диагностика] ", stage, " ", JSON.stringify(context))


func _on_lobby() -> void:
	mark("Обновлено лобби")


func _on_state(view: Dictionary) -> void:
	_sync_state_identity()
	if is_instance_valid(_net) and _net.is_inside_tree():
		if not _net.in_game:
			return
		if view.has("game") and (not view.game is String or view.game != _net.party_game):
			return
		if view.has("game_id") and (not view.game_id is String or view.game_id != _net.game_id):
			return
	# Только публичные индексы/фаза. Не сохраняем руки, ответы, ключи API и сообщения чата.
	var state := {}
	for key: String in ["game", "phase", "round_no", "turn_no", "current", "you", "spectator"]:
		if view.has(key) and _safe_public_value(key, view[key]):
			state[key] = view[key]
	var fingerprint := JSON.stringify(state)
	if fingerprint != _phase:
		_phase = fingerprint
		_state = state
		mark("Получено состояние стола", state)


func _sync_state_identity() -> void:
	if not is_instance_valid(_net) or not _net.is_inside_tree():
		return
	var identity := JSON.stringify([_net.party_game, _net.game_id, _net.in_game])
	if identity != _state_identity or not _net.in_game:
		_state.clear()
		_phase = ""
		_state_identity = identity


func _safe_public_value(key: String, value: Variant) -> bool:
	if key in ["round_no", "turn_no", "current", "you"]:
		return value is int
	if key == "spectator":
		return value is bool
	if key in ["game", "phase"]:
		return value is String and value.length() <= 64 and value.is_valid_identifier()
	return false


func _safe_details(details: Dictionary) -> Dictionary:
	var safe := {}
	for key: Variant in details:
		if not key is String:
			continue
		var value: Variant = details[key]
		if _safe_public_value(key, value):
			safe[key] = value
		elif key in ["целевая_сцена"] and value is String:
			if value.begins_with("res://") and value.length() <= 256:
				safe[key] = value
		elif key in ["версия", "Godot", "сборка", "ОС", "CPU", "GPU", "версия_GPU_API",
				"рендер", "драйвер", "эффект", "игра"]:
			if value is String and value.length() <= 256:
				safe[key] = value
		elif key in ["предыдущая_игра", "игра_команды", "игра_пакета", "партия_пакета", "ожидаемая_партия"]:
			if value is String and value.length() <= 128:
				safe[key] = value
		elif key in ["подписок", "поколение"] and value is int and value >= 0 and value <= 1000000:
			safe[key] = value
		elif key == "pid" and value is int:
			safe[key] = value
		elif key == "драйвер_GPU" and value is PackedStringArray:
			# Данные самого движка, а не произвольные контейнеры из сетевого состояния.
			safe[key] = Array(value).slice(0, 4)
	return safe


func _process(delta: float) -> void:
	_sync_state_identity()
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if is_instance_valid(scene) else ""
	if path != _scene:
		_scene = path
		mark("Сцена вошла в дерево")
	_heartbeat += delta
	if _heartbeat >= 5.0:
		_heartbeat = 0.0
		_snapshot_engine(session)
		_save_marker()
	if _native_pid > 0:
		if not OS.is_process_running(_native_pid):
			_native_pid = -1
			_native_status("unavailable", "Системный запрос завершился без файла результата.")
		elif Time.get_ticks_msec() - _native_started_msec > 15000:
			OS.kill(_native_pid)
			_native_pid = -1
			_native_status("timeout", "Чтение системного журнала Windows превысило 15 секунд.")
			mark("Чтение системного журнала Windows прервано по тайм-ауту")


func _native_status(status: String, note: String) -> void:
	var path := str(previous_session.get("native_log", ""))
	if path.is_empty() or FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"status": status, "note": note, "events": []}))
		file.flush()


func _save_marker() -> void:
	if session.is_empty():
		return
	session["last_seen"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(FLAG + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(session))
		file.flush()
		file.close()
		DirAccess.rename_absolute(FLAG + ".tmp", FLAG)


func _exit_tree() -> void:
	_snapshot_engine(session)
	if sink:
		sink.checkpoint("Штатное завершение приложения", JSON.stringify(_context()))
		if _logger_registered:
			OS.remove_logger(sink)
		sink.close()
	if _native_pid > 0 and OS.is_process_running(_native_pid):
		OS.kill(_native_pid)
	DirAccess.remove_absolute(FLAG)


func _prune() -> void:
	var files := []
	for name: String in DirAccess.get_files_at(LOG_DIR):
		if name.begins_with("session-") and name.ends_with(".log"):
			files.append(name)
	files.sort()
	var remaining := files.size()
	for name: String in files:
		if remaining <= 10:
			break
		var path := LOG_DIR + "/" + name
		if path == str(previous_session.get("log", "")) or path == str(session.log):
			continue
		DirAccess.remove_absolute(path)
		for suffix: String in [".tail", ".tail.previous", ".errors", ".errors.previous", ".engine"]:
			DirAccess.remove_absolute(path + suffix)
		DirAccess.remove_absolute(path.trim_suffix(".log") + "-windows.json")
		remaining -= 1


func _engine_log() -> String:
	var args := OS.get_cmdline_args()
	var index := args.find("--log-file")
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	# Godot 4.7 может удалить обработанный --log-file из args. Старый файл по умолчанию
	# тогда не является журналом этого процесса: не подмешиваем его в новый отчёт.
	var path: String = ProjectSettings.get_setting("debug/file_logging/log_path", LOG_DIR + "/godot.log")
	var process_started := int(Time.get_unix_time_from_system() - Time.get_ticks_msec() / 1000.0)
	if FileAccess.file_exists(path) and FileAccess.get_modified_time(path) >= process_started:
		return path
	return ""


func _snapshot_engine(selected: Dictionary) -> void:
	var source := str(selected.get("engine_log", ""))
	var target := str(selected.get("engine_snapshot", ""))
	if target.is_empty() or source == target or not FileAccess.file_exists(source):
		return
	var text := _read_tail(source)
	var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.flush()
		file.close()
		DirAccess.rename_absolute(target + ".tmp", target)


func _previous_engine_log() -> String:
	var best := ""
	var modified := -1
	for name: String in DirAccess.get_files_at(LOG_DIR):
		if name.begins_with("godot") and name.ends_with(".log") and name != "godot.log":
			var path := LOG_DIR + "/" + name
			var time := FileAccess.get_modified_time(path)
			if time > modified:
				modified = time
				best = path
	return best


func report_text(path: String = "") -> String:
	var selected := session
	if not path.is_empty() and not previous_session.is_empty() and (
		path == str(previous_session.get("log", "")) or path == str(previous_session.get("engine_log", ""))
	):
		selected = previous_session
	elif not path.is_empty() and path != str(session.get("engine_log", "")) and path != str(session.log):
		return _diagnostic_text(path)
	var result := "Отчёт PartyWorld · сеанс PID " + str(selected.get("pid", "неизвестен"))
	result += "\n\n=== Диагностика ===\n" + _diagnostic_text(str(selected.get("log", "")))
	result += "\n\n=== Журнал Godot ===\n" + _read_tail(str(selected.get("engine_log", "")))
	result += "\n\n=== Windows: аварийное завершение ===\n"
	var native_path := str(selected.get("native_log", ""))
	if not native_path.is_empty() and FileAccess.file_exists(native_path):
		result += _read_tail(native_path)
	elif selected == session:
		result += "Текущий запуск ещё не завершён. Событие Windows проверяется после следующего запуска."
	else:
		result += "Системные данные пока недоступны (чтение ещё идёт или событие Windows отсутствует)."
	return result


func _diagnostic_text(path: String) -> String:
	var result := _read_tail(path)
	for suffix: String in [".tail.previous", ".tail", ".errors.previous", ".errors"]:
		if FileAccess.file_exists(path + suffix):
			result += "\n\n=== Продолжение " + suffix + " ===\n" + _read_tail(path + suffix)
	return result


func _read_tail(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return "Журнал отсутствует."
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Не удалось прочитать журнал."
	var length := file.get_length()
	var prefix := "Файл: " + path.get_file() + "\n"
	if length > MAX_COPY:
		var head := file.get_buffer(8192)
		# Одна огромная строка тоже не должна обходить ограничение размера отчёта.
		while not head.is_empty() and head[head.size() - 1] != 10:
			head.resize(head.size() - 1)
		prefix += head.get_string_from_utf8()
		file.seek(length - MAX_COPY)
		# Пропускаем байты неполной строки до декодирования UTF-8.
		while file.get_position() < length and file.get_8() != 10:
			pass
		prefix += "Середина большого журнала пропущена; начало и последние сообщения сохранены.\n"
	return prefix + file.get_buffer(mini(MAX_COPY, length - file.get_position())).get_string_from_utf8()
