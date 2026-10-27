extends Logger
## Потокобезопасный журнал ошибок и контрольных точек. Без переменных стека и содержимого действий.
## После лимита сохраняет начало, ограниченный хвост и отдельные последние ошибки, сразу flush.

const MAX_BYTES := 2 * 1024 * 1024
const TAIL_BYTES := 128 * 1024
const BLOCK_CHARS := 16000
var _file: FileAccess
var _path := ""
var _mutex := Mutex.new()
var _context := ""
var _limited := false


func open(path: String) -> bool:
	_path = path
	_limited = false
	_file = FileAccess.open(path, FileAccess.WRITE)
	return _file != null


func checkpoint(message: String, context: String) -> void:
	_mutex.lock()
	_context = context
	_write_locked("ЭТАП: " + message + "\nКонтекст: " + context)
	_mutex.unlock()


func _write_locked(text: String, error: bool = false) -> void:
	if _file == null:
		return
	var bounded := text
	if bounded.length() > BLOCK_CHARS:
		var half := BLOCK_CHARS / 2
		bounded = bounded.left(half) + "\nЛимит журнала достигнут для сообщения; середина пропущена.\n"
		bounded += text.right(half)
	var block := "\n[" + Time.get_datetime_string_from_system(true) + " UTC; +"
	block += str(Time.get_ticks_msec()) + " мс] " + bounded + "\n"
	if not _limited and _file.get_position() + block.to_utf8_buffer().size() + 256 > MAX_BYTES:
		_file.store_line("Лимит журнала достигнут; продолжение в ограниченном хвосте.")
		_limited = true
	if _limited:
		_append_bounded(".tail", block)
	else:
		_file.store_string(block)
	_file.flush()
	# Обычные контрольные точки не вытесняют последние ошибки даже после переполнения хвоста.
	if error:
		_append_bounded(".errors", block)


func _append_bounded(suffix: String, block: String) -> void:
	var path := _path + suffix
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ
	var file := FileAccess.open(path, mode)
	if file == null:
		return
	if file.get_length() + block.to_utf8_buffer().size() > TAIL_BYTES:
		file.close()
		DirAccess.remove_absolute(path + ".previous")
		DirAccess.rename_absolute(path, path + ".previous")
		file = FileAccess.open(path, FileAccess.WRITE_READ)
		if file == null:
			return
	file.seek_end()
	file.store_string(block)
	file.flush()
	file.close()


func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		script_backtraces: Array[ScriptBacktrace]) -> void:
	# Ошибки ядра (в том числе operator %) иногда приходят без готового стека.
	# Захватываем только кадры вызовов; локальные переменные могут содержать ключи и тайные карты.
	var traces: Array[ScriptBacktrace] = script_backtraces
	if traces.is_empty():
		traces = Engine.capture_script_backtraces(false)
	var details := "ОШИБКА тип=" + str(error_type) + ": " + code + "\n" + rationale
	details += "\nИсточник: " + file + ":" + str(line) + " · " + function
	for trace: ScriptBacktrace in traces:
		details += "\n" + trace.format()
	_mutex.lock()
	_write_locked(details + "\nКонтекст: " + _context, true)
	_mutex.unlock()


func close() -> void:
	_mutex.lock()
	if _file:
		_file.flush()
		_file.close()
		_file = null
	_mutex.unlock()
