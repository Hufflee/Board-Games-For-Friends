extends SceneTree
## Four Souls: единый раннер тестов. Код выхода 1, если есть ошибки (известные баги из кейсов не считаются).
##   godot --headless --audio-driver Dummy --path . --script res://tests/fs/run.gd -- --group core,cards
## Группы: core (tests/fs/core), cards (tests/fs/cases), regress (tests/fs/regress), fuzz (фаззер),
##   legacy (старые tests/test_fs_*.gd отдельными процессами), ui (*_ui.gd, с окном), long (полная партия),
##   net (ENet: tools/run_fs_passive_network.py).
##   По умолчанию: core,cards,regress. Флаги: --filter <подстрока имени файла>, --games N, --seed N,
##   --steps N (фаззер), --no-regress-write (фаззер не пишет файлы). Логи — build/fs_tests/.
const FSCheck = preload("res://tests/fs/fs_check.gd")

const LOG_DIR := "res://build/fs_tests/"
const Cases = preload("res://tests/fs/fs_cases.gd")
const Fuzz = preload("res://tests/fs/fs_fuzz.gd")

var args := {}
var failed := false

func _initialize() -> void:
	_parse_args()
	Cases.trace = int(args.get("trace", 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var groups: PackedStringArray = str(args.get("group", "core,cards,regress")).split(",")
	var lines: Array[String] = []
	for group in groups:
		var started := Time.get_ticks_msec()
		var t := FSCheck.new()
		var notes: Array = []
		match group.strip_edges():
			"core": _run_core(t)
			"cards": _run_cases(t, "res://tests/fs/cases/", notes)
			"regress": _run_cases(t, "res://tests/fs/regress/", notes)
			"fuzz": notes.append(_run_fuzz(t))
			"legacy": _run_processes(t, _legacy_files(), notes)
			"ui": _run_processes(t, _files("res://tests/", "test_fs_", ".gd").filter(func(p: String) -> bool:
				return p.ends_with("_ui.gd") or p.contains("_ui_")), notes, false, 300)
			"long": _run_processes(t, ["res://tests/test_fs_full_game.gd"], notes, true, 900)
			"net": _run_net(t, notes)
			_: t.check(false, "Неизвестная группа " + group)
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		var line := "FS %-8s %5d проверок · %d ошибок · %.1f с" % [group, t.checks, t.errors.size(), seconds]
		lines.append(line)
		print(line)
		for e in t.errors.slice(0, 40):
			print("  ✗ " + e)
		if t.errors.size() > 40:
			print("  … ещё %d (полный список — %s%s.log)" % [t.errors.size() - 40, LOG_DIR, group])
		for n in notes:
			print("  · " + str(n))
		_write_log(group, line, t.errors, notes)
		failed = failed or not t.errors.is_empty()
	print("FS ИТОГ: " + ("ЕСТЬ ОШИБКИ" if failed else "всё зелёное"))
	quit(1 if failed else 0)

func _parse_args() -> void:
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var key := raw[i].trim_prefix("--")
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			args[key] = raw[i + 1]; i += 2
		else:
			args[key] = true; i += 1

func _filtered(path: String) -> bool:
	return not args.has("filter") or path.get_file().contains(str(args.filter))

func _files(dir: String, prefix: String, suffix: String) -> Array:
	var out: Array = []
	for name in DirAccess.get_files_at(dir):
		if name.begins_with(prefix) and name.ends_with(suffix) and _filtered(name):
			out.append(dir + name)
	out.sort()
	return out

func _legacy_files() -> Array:
	return _files("res://tests/", "test_fs_", ".gd").filter(func(p: String) -> bool:
		return not p.ends_with("_ui.gd") and not p.ends_with("full_game.gd") and not p.contains("_ui_") 			and not p.ends_with("table_runtime.gd"))

## core: файлы с func run(t: FSCheck) -> void.
func _run_core(t: FSCheck) -> void:
	for path in _files("res://tests/fs/core/", "", ".gd"):
		var script: GDScript = load(path)
		t.prefix = path.get_file().get_basename()
		if not t.check(script != null and script.can_instantiate(), "скрипт не загрузился (ошибка разбора)"):
			continue
		script.new().run(t)
	t.prefix = ""

func _run_cases(t: FSCheck, dir: String, notes: Array) -> void:
	for path in _files(dir, "", ".gd"):
		Cases.run_file(t, path, notes)

func _run_fuzz(t: FSCheck) -> String:
	var games := int(args.get("games", 100))
	var stats: Dictionary = Fuzz.run(t, games, int(args.get("seed", 1)), int(args.get("steps", 800)), not args.has("no-regress-write"))
	return "партий %d, до конца %d, действий %d, с нарушением %d, классов %d" % [stats.games, stats.finished, stats.steps, stats.failed, stats.classes.size()]

## Старые тесты — отдельными процессами: они сами вызывают quit() и печатают итог.
## UI-тесты (headless = false) открывают окно: ввод мыши в headless не доходит.
## Лог каждого — build/fs_tests/legacy/<имя>.log (UTF-8, через --log-file); зависший тест снимается по тайм-ауту.
func _run_processes(t: FSCheck, paths: Array, notes: Array, headless: bool = true, timeout_s: int = 120) -> void:
	var exe := OS.get_executable_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR + "legacy"))
	for path: String in paths:
		var log_path := ProjectSettings.globalize_path(LOG_DIR + "legacy/" + path.get_file().get_basename() + ".log")
		var arguments := ["--audio-driver", "Dummy", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "--script", path]
		if headless:
			arguments.push_front("--headless")
		# Свой чистый профиль на каждый тест: иначе снятый по тайм-ауту запуск оставляет окно
		# «Предыдущий запуск не завершился штатно», и оно перехватывает клики следующих UI-тестов.
		var profile := ProjectSettings.globalize_path(LOG_DIR + "profiles/" + path.get_file().get_basename())
		_remove_dir(profile)
		DirAccess.make_dir_recursive_absolute(profile)
		OS.set_environment("APPDATA", profile)
		var pid := OS.create_process(exe, arguments)
		var started := Time.get_ticks_msec()
		while OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_s * 1000:
			OS.delay_msec(100)
		var timed_out := OS.is_process_running(pid)
		if timed_out:
			OS.kill(pid)
		var code := -1 if timed_out else OS.get_process_exit_code(pid)
		var text := FileAccess.get_file_as_string(log_path)
		var summary := ("тайм-аут %d с" % timeout_s) if timed_out else _summary(text)
		t.check(code == 0, "%s — код выхода %d (%s)" % [path.get_file(), code, summary])
		if code == 0:
			notes.append("%s ✔ %s" % [path.get_file(), summary])

func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(name))
	DirAccess.remove_absolute(path)

## ENet: два настоящих процесса через tools/run_fs_passive_network.py (нужен python в PATH).
func _run_net(t: FSCheck, notes: Array) -> void:
	var output: Array = []
	var code := OS.execute("python", [ProjectSettings.globalize_path("res://tools/run_fs_passive_network.py")], output, true)
	var text := "".join(output)
	var log := FileAccess.open(LOG_DIR + "net.txt", FileAccess.WRITE)
	if log: log.store_string(text); log.close()
	t.check(code == 0, "ENet-приёмка — код выхода %d (лог %snet.txt)" % [code, LOG_DIR])
	if code == 0:
		notes.append("ENet: " + _summary(text))

func _summary(text: String) -> String:
	# Старые тесты печатают «ИМЯ: N проверок, M ошибок» (или «ошибок: M»).
	# Берём последнее совпадение: итог печатается в конце, выше бывают строки того же вида.
	var regex := RegEx.create_from_string("(?m)^[A-Z][A-Z0-9 _-]+: (\\d+) [^,\\n]+, \\D*?(\\d+)[^\\n]*$")
	var found := regex.search_all(text)
	if found.is_empty():
		return "без строки итога"
	var last: RegExMatch = found.back()
	return "%s проверок, %s ошибок" % [last.get_string(1), last.get_string(2)]

func _write_log(group: String, line: String, errors: Array[String], notes: Array) -> void:
	var file := FileAccess.open(LOG_DIR + group.strip_edges() + ".log", FileAccess.WRITE)
	if file == null:
		return
	file.store_line(line)
	for e in errors: file.store_line("✗ " + e)
	for n in notes: file.store_line("· " + str(n))
	file.close()
