extends SceneTree
## Проверка автообновления на поддельном манифесте. Сам по себе не запускается: этапы гоняет
## драйвер `python tools/release/test_updater.py` (поднимает локальный HTTP-сервер, свой APPDATA,
## env PW_UPDATER=1). Этап — env UPD_STAGE; рабочая папка — env UPD_DIR.

# Клиент грузим в _run: preload тянул бы autoload Updater до его регистрации (rulebook).
var Client: GDScript

var _fails := 0
var _dir := OS.get_environment("UPD_DIR")
var _updater: Node
var _base_version := OS.get_environment("UPD_TEST_BASE")
var _v1 := OS.get_environment("UPD_TEST_PATCH1")
var _v2 := OS.get_environment("UPD_TEST_PATCH2")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("ПРОВАЛ: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_updater = root.get_node("Updater")
	Client = load("res://hub/update/update_client.gd")
	var stage := OS.get_environment("UPD_STAGE")
	print("== этап ", stage)
	match stage:
		"prep": _prep()
		"download": await _download()
		"verify": await _verify()
		"arm_rollback": _arm_rollback()
		"rollback": _rollback()
		"corrupt": await _corrupt()
		"base": await _base()
		_: check(false, "неизвестный этап " + stage)
	print("ИТОГ ", stage, ": ", "OK" if _fails == 0 else "%d ошибок" % _fails)
	quit(1 if _fails > 0 else 0)


## Два патча цепочки: первый добавляет _probe.txt = «one», второй меняет его на «two» и добавляет _probe2.txt.
func _prep() -> void:
	_pack("patch-%s.pck" % _v1, {"res://hub/update/_probe.txt": "one"})
	_pack("patch-%s.pck" % _v2, {"res://hub/update/_probe.txt": "two", "res://hub/update/_probe2.txt": "x"})


func _pack(name: String, files: Dictionary) -> void:
	var p := PCKPacker.new()
	check(p.pck_start(_dir.path_join(name)) == OK, "pck_start " + name)
	for res: String in files:
		var src := _dir.path_join(name + "." + res.get_file())
		var f := FileAccess.open(src, FileAccess.WRITE)
		f.store_string(files[res])
		f.close()
		p.add_file(res, src)
	check(p.flush() == OK, "flush " + name)


func _client() -> Node:
	return Client.call("get_or_create", self)


func _download() -> void:
	check(_updater.enabled, "апдейтер включён (PW_UPDATER=1)")
	check(_updater.loaded.is_empty(), "до загрузки патчей нет")
	var c := _client()
	await c.check()
	check(c.state == Client.State.AVAILABLE, "доступно обновление (состояние %d)" % c.state)
	check(c.kind == "patch" and c.target == _v2, "патч до %s, а не %s %s" % [_v2, c.kind, c.target])
	check(c._queue.size() == 2, "в очереди два патча")
	await c.start()
	check(c.state == Client.State.READY, "скачано и готово к перезапуску (%d %s)" % [c.state, c.error])
	var st: Dictionary = _updater.read_json(_updater.STATE)
	check((st.get("patches", []) as Array).size() == 2 and int(st.get("trial_from", -1)) == 0, "в state.json цепочка из 2, пробные с 0: %s" % st)


func _verify() -> void:
	check(_updater.loaded == [_v1, _v2], "подключены оба патча по порядку: %s" % [_updater.loaded])
	check(_updater.version == _v2, "Действующая версия последнего патча")
	check(str(ProjectSettings.get_setting("application/config/version")) == _v2, "версия в ProjectSettings подменена")
	check(_updater.base_version == _base_version, "базовая версия exe не изменилась")
	check(FileAccess.get_file_as_string("res://hub/update/_probe.txt") == "two", "второй патч перекрыл первый")
	check(FileAccess.file_exists("res://hub/update/_probe2.txt"), "файл из второго патча виден")
	var st: Dictionary = _updater.read_json(_updater.STATE)
	check(bool(st.get("trial_started", false)), "запуск пробный")
	_updater.confirm_boot()
	st = _updater.read_json(_updater.STATE)
	check(int(st.get("trial_from", 0)) == -1, "после confirm_boot проба снята")
	var c := _client()
	await c.check()
	check(not c._manifest.is_empty(), "манифест получен")
	check(c.state == Client.State.NONE, "после установки обновлений нет (%d)" % c.state)


## Имитация: второй патч поставлен на пробу, и запуск с ним упал до хаба.
func _arm_rollback() -> void:
	var st: Dictionary = _updater.read_json(_updater.STATE)
	st["trial_from"] = 1
	st["trial_started"] = true
	check(_updater.write_json(_updater.STATE, st), "state записан")


func _rollback() -> void:
	check(_updater.rolled_back == _v2, "снят пробный патч: «%s»" % _updater.rolled_back)
	check(_updater.loaded == [_v1], "остался только первый патч: %s" % [_updater.loaded])
	check(FileAccess.get_file_as_string("res://hub/update/_probe.txt") == "one", "содержимое — из первого патча")
	check(not FileAccess.file_exists(_updater.DIR + "patch-%s.pck" % _v2), "файл снятого патча удалён")


## Манифест с другой цепочкой и неверной суммой: качаем, сумма не сходится — ошибка, установленное не тронуто.
func _corrupt() -> void:
	var c := _client()
	await c.check()
	check(c.state == Client.State.AVAILABLE, "предложено (другая цепочка)")
	await c.start()
	check(c.state == Client.State.FAILED and c.error.contains("контрольная"), "ошибка контрольной суммы: %d %s" % [c.state, c.error])
	check(_updater.chain().size() == 1, "установленная цепочка не тронута")
	check(not FileAccess.file_exists(_updater.DIR + "patch-%s.pck.part" % _v2), "недокачанный файл убран")


## Новая база: zip с exe/dll ставится в PW_UPDATE_INSTALL_DIR, старые файлы → *.old; затем откат.
func _base() -> void:
	var inst: String = _updater.install_dir()
	check(inst != "", "папка установки задана")
	var c := _client()
	await c.check()
	check(c.state == Client.State.AVAILABLE and c.kind == "base" and c.target == "0.9.0", "предложена полная версия 0.9.0: %d %s %s" % [c.state, c.kind, c.target])
	await c.start()
	check(c.state == Client.State.READY, "база установлена (%d %s)" % [c.state, c.error])
	check(FileAccess.get_file_as_string(inst.path_join("PartyWorld.exe")) == "new exe", "exe заменён")
	check(FileAccess.get_file_as_string(inst.path_join("PartyWorld.exe.old")) == "old exe", "старый exe сохранён как .old")
	check(FileAccess.get_file_as_string(inst.path_join("steam_api64.dll")) == "new dll", "dll заменена")
	check(not FileAccess.file_exists(inst.path_join("PartyWorld.exe.new")), "временных .new не осталось")
	var trial: Dictionary = _updater.read_json(_updater.BASE_TRIAL)
	check(str(trial.get("to", "")) == "0.9.0" and not bool(trial.get("started", true)), "записана проба новой базы: %s" % trial)
	# Новая база дважды не дошла до хаба → файлы возвращаются.
	trial["to"] = _updater.base_version
	trial["started"] = true
	_updater.write_json(_updater.BASE_TRIAL, trial)
	check(_updater._check_base_trial(), "откат базы сработал")
	_updater._restore_exe = ""
	check(FileAccess.get_file_as_string(inst.path_join("PartyWorld.exe")) == "old exe", "после отката exe — старый")
	check(FileAccess.get_file_as_string(inst.path_join("PartyWorld.exe.bad")) == "new exe", "сбойный exe отложен как .bad")
	check(not FileAccess.file_exists(_updater.BASE_TRIAL), "проба базы снята")
	_updater._cleanup_install_dir()
	check(not FileAccess.file_exists(inst.path_join("PartyWorld.exe.bad")), "уборка удаляет .bad")
