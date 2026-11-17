extends SceneTree
## Выбор пакета обновления (патчи или полная сборка) на локальных манифестах: переходном и финальном.
## Сам не запускается — его гоняет `python tools/release/test_update_select.py` (готовит манифесты
## через release.py, поддельные PCK, старые клиенты из git, свой APPDATA). Рабочая папка — env UPD_DIR.
## Для каждого сценария и клиента печатает строку «ВЫБОР|сценарий|клиент|манифест|что|файлы».

var _fails := 0
var _dir := OS.get_environment("UPD_DIR")
var _updater: Node
var _files: Dictionary = {}  # версия патча старой линии → {file, sha256, size}
var _clients: Dictionary = {}  # имя → GDScript


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("ПРОВАЛ: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_updater = root.get_node("Updater")
	var fakes: Variant = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("fakes.json")))
	_files = fakes
	_clients["новый"] = load("res://hub/update/update_client.gd")
	for name: String in ["старый 0.8.12", "старый 0.9.0.2+"]:
		var s := GDScript.new()
		s.source_code = FileAccess.get_file_as_string(_dir.path_join("client_%s.gd" % name.get_slice(" ", 1).trim_suffix("+")))
		check(s.reload() == OK, "компиляция клиента " + name)
		_clients[name] = s
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("scenarios.json")))
	for sc: Dictionary in plan:
		await _scenario(sc)
	print("ИТОГ выбор пакета: ", "OK" if _fails == 0 else "%d ошибок" % _fails)
	quit(1 if _fails > 0 else 0)


## Установка как у игрока: exe, цепочка в state.json, файлы патчей, что подключилось в этом запуске.
func _install(sc: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path(_updater.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var chain: Array = []
	for v: String in sc["chain"]:
		var info: Dictionary = _files[v]
		chain.append({"version": v, "file": "patch-%s.pck" % v, "sha256": info["sha256"], "size": info["size"]})
		var data := FileAccess.get_file_as_bytes(_dir.path_join(str(info["file"])))
		if v in sc.get("corrupt", []):
			data[data.size() - 1] = data[data.size() - 1] ^ 0xff  # тот же размер, другое содержимое
		if not v in sc.get("missing", []):
			var f := FileAccess.open(dir.path_join("patch-%s.pck" % v), FileAccess.WRITE)
			f.store_buffer(data)
			f.close()
	_updater.write_json(_updater.STATE, {"base": sc["exe"], "patches": chain, "trial_from": -1, "trial_started": false})
	_updater.base_version = sc["exe"]
	var loaded: Array[String] = []
	loaded.assign(sc.get("loaded", sc["chain"]))
	_updater.loaded = loaded
	_updater.version = loaded[-1] if not loaded.is_empty() else str(sc["exe"])
	# BGSocial.exe в папке игры (PW_UPDATE_INSTALL_DIR): по умолчанию есть.
	var social := _dir.path_join("BGSocial.exe")
	if sc.get("social", true):
		FileAccess.open(social, FileAccess.WRITE).store_string("installed social")
	else:
		DirAccess.remove_absolute(social)


func _scenario(sc: Dictionary) -> void:
	for client: String in sc["clients"]:
		for mname: String in sc["expect"][client]:
			_install(sc)
			var c: Node = _clients[client].new()
			root.add_child(c)
			c.set("_manifest", JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join(mname + ".json"))))
			await c.call("_plan")
			var files: Array = []
			for q: Dictionary in c.get("_queue"):
				files.append(str(q["url"]).get_file())
			var kind: String = c.get("kind") if c.get("state") != 2 else "нет"  # State.NONE == 2
			var got := "%s:%s" % [kind, ",".join(files)]
			print("ВЫБОР|%s|%s|%s|%s|%s" % [sc["name"], client, mname, kind, ",".join(files)])
			var want: String = sc["expect"][client][mname]
			check(got == want, "%s / %s / %s: ждали «%s», получили «%s»" % [sc["name"], client, mname, want, got])
			if kind == "social":
				# Установка: скачанный файл копируется в папку игры.
				var q: Dictionary = c.get("_queue")[0]
				FileAccess.open(_updater.DIR + str(q["file"]), FileAccess.WRITE).store_string("downloaded social")
				check(c.call("_install_social") == "", "BGSocial.exe установлен")
				check(FileAccess.get_file_as_string(_dir.path_join("BGSocial.exe")) == "downloaded social", "BGSocial.exe в папке игры")
			c.queue_free()
			await process_frame
