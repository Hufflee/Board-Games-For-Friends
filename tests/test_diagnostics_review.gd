## Независимые проверки low: последние ошибки/flush/контекст/приватность/маркер.
## Только свежий изолированный APPDATA, --headless --audio-driver Dummy.
extends SceneTree

var checks := 0
var errors := 0
var logger: Logger

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error("LOW_DIAG ПРОВАЛ: " + message)

func _initialize() -> void:
	_run.call_deferred()

func worker(index: int) -> void:
	var private_local := "LOW_PRIVATE_LOCAL_NEVER_PRINT"
	for i in 12:
		logger._log_error("low_worker", "independent_fixture", i, "LOW_WORKER_" + str(index), "ж".repeat(700), false, 0, [])
	# Локальная переменная намеренно не включается в текст ошибки.
	assert(private_local.length() > 0)

func _run() -> void:
	var diag: Node = root.get_node("Diag")
	var net: Node = root.get_node("Net")
	net.set_process(false)
	logger = load("res://hub/diagnostic_logger.gd").new()
	var path := "user://logs/low-independent.log"
	check(logger.open(path), "Открыт отдельный журнал")
	logger.checkpoint("LOW_BEGIN", "начало")
	for i in 155:
		logger.checkpoint("LOW_FILL_" + str(i) + "a".repeat(15900), "наполнение")
	check(FileAccess.file_exists(path + ".tail"), "MAX действительно превышен до ошибок")
	var workers: Array[Thread] = []
	for i in 4:
		var thread := Thread.new()
		thread.start(worker.bind(i))
		workers.append(thread)
	for thread in workers: thread.wait_to_finish()
	# Читаем открытый журнал с другого FileAccess, не вызывая close/flush в тесте.
	var text: String = diag.report_text(path)
	for i in 4:
		check(text.contains("LOW_WORKER_" + str(i)), "Каждый из4 workers сбросил ошибки до close")
	check(not text.contains("LOW_PRIVATE_LOCAL_NEVER_PRINT"), "Локальные переменные worker не записаны в стек")
	for i in 35:
		logger.checkpoint("LOW_NOISE_" + str(i) + "b".repeat(15900), "шум")
	text = diag.report_text(path)
	check(text.contains("LOW_WORKER_"), "Шум этапов не вытеснил отдельный error-журнал")
	for i in 90:
		logger._log_error("rotation", "independent_fixture", i, "LOW_ERROR_" + str(i), "я".repeat(2400), false, 0, [])
	logger._log_error("last", "independent_fixture", 999, "LOW_FINAL_ERROR_ЮНИКОД", "последняя", false, 0, [])
	text = diag.report_text(path)
	check(text.contains("LOW_BEGIN") and text.contains("LOW_FINAL_ERROR_ЮНИКОД"), "Начало и последняя Unicode-ошибка сохранены после ротаций")
	check(FileAccess.file_exists(path + ".errors.previous"), "Error-журнал действительно ротировался")
	check(FileAccess.get_file_as_bytes(path).size() <= 2097152, "Основной файл не более2МиБ")
	for suffix in [".tail", ".tail.previous", ".errors", ".errors.previous"]:
		check(FileAccess.get_file_as_bytes(path + suffix).size() <= 131072, "Ограничен независимый спутник " + suffix)
	logger.close()
	# Настоящая Diag и Net, только синтетическое состояние в памяти, без партии и транспорта.
	net.party_game = "wavelength"
	net.game_id = "low-A"
	net.in_game = true
	diag._on_state({"game": "wavelength", "game_id": "low-A", "phase": "guess", "turn_no": 2})
	check(diag._context().get("phase") == "guess", "Установлен валидный старый контекст")
	net.game_id = "low-B"
	check(not diag._context().has("phase"), "Samegame новый match очищает старую фазу до нового view")
	diag._on_state({"game": "wavelength", "game_id": "low-A", "phase": "reveal"})
	check(not diag._context().has("phase"), "Поздний предыдущий match не восстановил контекст")
	net.party_game = "hues_and_cues"
	diag._on_state({"game": "wavelength", "game_id": "low-B", "phase": "guess"})
	check(not diag._context().has("phase"), "Чужая игра не восстановила фазу")
	diag._on_state({"game": "hues_and_cues", "game_id": "low-B", "phase": "pick", "round_no": 1,
		"hand": ["LOW_PRIVATE_HAND"], "answer": "LOW_PRIVATE_ANSWER", "chat": "LOW_PRIVATE_CHAT"})
	diag.mark("LOW_PRIVATE_FILTER_TEST", {"payload": {"api_key": "LOW_PRIVATE_KEY"}, "phase": ["LOW_PRIVATE_PHASE"]})
	text = diag.report_text()
	var marker := FileAccess.get_file_as_string(diag.FLAG)
	for sentinel in ["LOW_PRIVATE_HAND", "LOW_PRIVATE_ANSWER", "LOW_PRIVATE_CHAT", "LOW_PRIVATE_KEY", "LOW_PRIVATE_PHASE"]:
		check(not text.contains(sentinel) and not marker.contains(sentinel), "Приватный sentinel не записан в report/marker")
	var parsed: Variant = JSON.parse_string(marker)
	check(parsed is Dictionary and parsed.pid == OS.get_process_id() and parsed.context.phase == "pick", "Атомарный JSON marker: свой PID и последняя валидная фаза")
	check(not FileAccess.file_exists(diag.FLAG + ".tmp"), "После атомарного rename нет остатка tmp")
	net.in_game = false
	check(not diag._context().has("phase"), "Лобби убирает фазу независимо от delta")
	diag.mark("LOW_END")
	print("LOW DIAGNOSTICS REVIEW: checks=", checks, " errors=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
