extends Node
## Автообновление, часть 2 — проверка, скачивание и установка (живёт в корне дерева как "UpdateClient").
##
## Манифест `latest.json` лежит в последнем GitHub-релизе (формат — tools/release/release.py):
##   {"format": 1, "version": "0.8.10", "page": "...",
##    "base": {"version": "0.8.9", "url": "...zip", "size": N, "sha256": "..."},
##    "patches": [{"version": "0.8.10", "url": "...pck", "size": N, "sha256": "..."}, ...]}
## - установленная цепочка годна и совместима с линией манифеста → докачиваем недостающий хвост
##   патчей в user://updates/ (подробно — _plan: full / patch_from / lines);
## - иначе полная сборка новее нашего exe → качаем zip, сверяем SHA-256, кладём файлы рядом с exe
##   (старые → *.old), после перезапуска Updater следит, что новая версия запустилась.
## Без сети/при ошибке молча остаётся в NONE/FAILED — играть это не мешает.
## Проверка локально: env PW_UPDATE_URL=http://127.0.0.1:8765/latest.json, PW_UPDATE_INSTALL_DIR=<папка>.

signal changed

const MANIFEST_URL := "https://github.com/Hufflee/Board-Games-For-Friends/releases/latest/download/latest.json"
const RELEASES_PAGE := "https://github.com/Hufflee/Board-Games-For-Friends/releases/latest"
const SOCIAL_EXE := "BGSocial.exe"  # отдельное окно «Общение»; докачивается рядом с игрой, если его нет

enum State { IDLE, CHECKING, NONE, AVAILABLE, DOWNLOADING, INSTALLING, READY, FAILED, MANUAL }

var state := State.IDLE
var kind := ""  # "patch" | "base"
var target := ""  # версия, до которой обновимся
var total_bytes := 0
var done_bytes := 0
var error := ""
var page := RELEASES_PAGE
var _manifest := {}
var _queue: Array = []  # что качать: [{version, url, size, sha256, file}]
var _keep: Array = []  # уже установленная годная часть цепочки
var _http: HTTPRequest
var _current := 0  # размер скачанных файлов очереди до текущего
var _system_tls := false  # встроенные сертификаты Godot не подошли — работаем с хранилищем Windows
var _last_problem := ""  # причина последней сетевой неудачи (по-русски, для игрока и лога)


## Единственный клиент на весь запуск.
static func get_or_create(tree: SceneTree) -> Node:
	var c := tree.root.get_node_or_null("UpdateClient")
	if c == null:
		c = load("res://hub/update/update_client.gd").new()
		c.name = "UpdateClient"
		# Отложенно: зовут из _ready сцены, пока root ещё добавляет детей.
		tree.root.add_child.call_deferred(c)
	return c


func _init() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 0.0  # встроенный таймаут не годится — см. _await_request
	_http.use_threads = true
	add_child(_http)


func _ready() -> void:
	set_process(state == State.DOWNLOADING)  # в _init бесполезно: на ready _process включается сам


func progress() -> float:
	return clampf(float(done_bytes) / float(maxi(total_bytes, 1)), 0.0, 1.0)


## Тихая проверка один раз за запуск (звать после добавления в дерево — call_deferred).
func check(force: bool = false) -> void:
	if not Updater.enabled or state in [State.CHECKING, State.DOWNLOADING, State.INSTALLING, State.READY]:
		return
	if not force and state != State.IDLE:
		return
	if not is_inside_tree():
		await ready
	_set_state(State.CHECKING)
	var url := OS.get_environment("PW_UPDATE_URL")
	if url == "":
		url = MANIFEST_URL
	var body := await _get_text(url)
	var m: Variant = JSON.parse_string(body) if body != "" else null
	if not (m is Dictionary) or int(m.get("format", 0)) != 1:
		if force:
			error = _last_problem if _last_problem != "" else "сервер обновлений прислал не то, что ожидалось (возможно, страница-заглушка провайдера)"
			print("[update] проверка не удалась: ", error)
			_set_state(State.FAILED)
		else:
			_set_state(State.NONE)  # автоматическая проверка без сети молчит
		return
	_manifest = m
	page = str(m.get("page", RELEASES_PAGE))
	await _plan()


## Выбор пакета. Поля манифеста сверх формата 1 (старые клиенты их не читают):
##   "full": {version, url, size, sha256} — полная сборка, если патчами нельзя (по умолчанию — "base");
##   "patch_from": "0.9.1" — патчами обновляем, только если не нужно качать патчи этой версии и старше
##     (у старых установок полная сборка со сжатыми картами меньше, чем патч 0.9.1 на 435 МБ);
##   "lines": [{"base": "0.8.12", "patches": [...]}] — цепочки патчей для разных exe (по умолчанию —
##     одна: base + patches). После перехода на новую базу старые exe остаются на своей линии;
##   "social": {version, url, size, sha256} — BGSocial.exe: если его нет в папке игры, качается вместе
##     с патчами (в полной сборке он уже есть) или один, когда обновлять больше нечего.
## Патчи — только если установленная цепочка совпадает с началом линии по SHA-256, все её звенья
## подключены в этом запуске (Updater.loaded), файлы целы и действующая версия равна её концу.
func _plan() -> void:
	_queue.clear()
	_keep.clear()
	kind = ""
	target = ""
	# Сравниваем действующую версию, включая уже загруженные PCK.
	# Другая контрольная сумма цепочки не повод предлагать ту же версию снова.
	var latest := str(_manifest.get("version", ""))
	if latest == "" or Updater.compare(latest, Updater.version) <= 0:
		_queue = _social_entry()
		if not _queue.is_empty():
			kind = "social"
			target = "BGSocial"
			_set_state(State.AVAILABLE)
			return
		_set_state(State.NONE)
		return
	var base: Dictionary = _manifest.get("base", {})
	var full: Dictionary = _manifest.get("full", base)
	var lines: Array = _manifest.get("lines", [{"base": str(base.get("version", "")), "patches": _manifest.get("patches", [])}])
	var patch_from := str(_manifest.get("patch_from", ""))
	var have := await _intact_chain()
	# Сначала линия, с которой совпадает установленная цепочка; нет такой — ставим цепочку линии заново.
	for reinstall: bool in [false, true]:
		for line: Variant in lines:
			if line is Dictionary and _plan_line(line, have, patch_from, reinstall):
				kind = "patch"
				target = str(_queue[-1]["version"])
				_queue.append_array(_social_entry())
				_set_state(State.AVAILABLE)
				return
	_queue.clear()
	_keep.clear()
	var fv := str(full.get("version", ""))
	# Полная сборка новее нашего exe (если по действующей версии она не новее — следом придут патчи).
	if fv != "" and Updater.compare(fv, Updater.base_version) > 0:
		kind = "base"
		target = fv
		_queue = [_entry(full, "base-%s.zip" % fv)]
		var dir := Updater.install_dir()
		_set_state(State.AVAILABLE if dir != "" and _writable(dir) else State.MANUAL)
		return
	_set_state(State.NONE)


## BGSocial.exe к загрузке ([] — уже лежит рядом с игрой, в манифесте нет или ставить некуда).
func _social_entry() -> Array:
	var social: Dictionary = _manifest.get("social", {})
	var dir := Updater.install_dir()
	if social.is_empty() or dir == "" or FileAccess.file_exists(dir.path_join(SOCIAL_EXE)) or not _writable(dir):
		return []
	var e := _entry(social, SOCIAL_EXE + ".download")
	e["install"] = SOCIAL_EXE
	return [e]


## Линия подходит: exe — её база или полная сборка одной из её версий; докачать надо хвост новее patch_from.
func _plan_line(line: Dictionary, have: Array, patch_from: String, reinstall: bool) -> bool:
	var patches: Array = line.get("patches", [])
	var start := -1
	if str(line.get("base", "")) == Updater.base_version:
		start = 0
	else:
		# Полная сборка новее базы линии: её содержимое = база + патчи до её версии.
		for i in patches.size():
			if Updater.compare(str(patches[i].get("version", "")), Updater.base_version) == 0:
				start = i + 1
	if start < 0:
		return false
	var tail: Array = patches.slice(start)
	var keep := 0
	while keep < have.size() and keep < tail.size() and str(have[keep].get("sha256", "")) == str(tail[keep].get("sha256", "")).to_lower():
		keep += 1
	if keep < have.size():
		if not reinstall:
			return false  # стоит чужая цепочка (другая линия или пересобранный патч)
		keep = 0
	var end: String = Updater.base_version if keep == 0 else str(have[keep - 1].get("version", ""))
	if patch_from != "" and Updater.compare(end, patch_from) < 0:
		return false  # пришлось бы качать старые тяжёлые патчи — полная сборка выгоднее
	if keep == tail.size():
		return false  # линия кончилась раньше манифеста — нечего докачивать
	_keep = have.slice(0, keep)
	for i in range(keep, tail.size()):
		var p: Dictionary = tail[i]
		_queue.append(_entry(p, "patch-%s.pck" % str(p.get("version", i))))
	return true


## Годное начало установленной цепочки: звено подключено в этом запуске (Updater.loaded — по порядку),
## файл на месте и его SHA-256 совпадает с записанной. Обрыв — дальше не считаем (докачаем заново).
## Если действующая версия не совпала с последним подключённым звеном, цепочке не верим вовсе.
func _intact_chain() -> Array:
	var have: Array = Updater.chain()
	var ok: Array = []
	for i in have.size():
		var p: Variant = have[i]
		if not (p is Dictionary) or i >= Updater.loaded.size() or Updater.loaded[i] != str(p.get("version", "")):
			break
		var sum: String = await _sha256(Updater.DIR + str(p.get("file", "")))
		if sum != str(p.get("sha256", "")).to_lower():
			break
		ok.append(p)
	# Действующая версия обязана быть версией последнего подключённого звена, иначе состояние неясно.
	var last: String = Updater.base_version if Updater.loaded.is_empty() else Updater.loaded[-1]
	if Updater.compare(last, Updater.version) != 0:
		return []
	return ok


func _entry(src: Dictionary, file: String) -> Dictionary:
	return {"version": str(src.get("version", "")), "url": str(src.get("url", "")), "size": int(src.get("size", 0)), "sha256": str(src.get("sha256", "")).to_lower(), "file": file}


## Кнопка «Обновить».
func start() -> void:
	if state == State.MANUAL:
		OS.shell_open(page)
		return
	if state != State.AVAILABLE and state != State.FAILED:
		return
	if _queue.is_empty():
		check(true)
		return
	total_bytes = 0
	for q: Dictionary in _queue:
		total_bytes += int(q["size"])
	done_bytes = 0
	_current = 0
	_set_state(State.DOWNLOADING)
	set_process(true)
	for q: Dictionary in _queue:
		var path := Updater.DIR + str(q["file"])
		if not await _download(q, path):
			set_process(false)
			return
		_current += int(q["size"])
	set_process(false)
	done_bytes = total_bytes
	_set_state(State.INSTALLING)
	await get_tree().process_frame
	var err := _install_base() if kind == "base" else _install_patches()
	if err == "":
		err = _install_social()
	if err != "":
		_fail(err)
		return
	_set_state(State.READY)


## Кнопка «Перезапустить».
func restart() -> void:
	if state != State.READY:
		return
	var exe := OS.get_executable_path()
	if kind == "base":
		exe = Updater.install_dir().path_join(exe.get_file())
	OS.create_process(exe, OS.get_cmdline_args())
	Sfx.request_quit()


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING:
		done_bytes = _current + maxi(_http.get_downloaded_bytes(), 0)
		changed.emit()


func _download(q: Dictionary, path: String) -> bool:
	var part := path + ".part"
	if FileAccess.file_exists(path):
		var have: String = await _sha256(path)
		if have == q["sha256"]:
			return true  # уже скачан раньше
	DirAccess.remove_absolute(part)
	var res: Array = await _request(str(q["url"]), ["User-Agent: PartyWorld-Updater"], 30000, part)
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		DirAccess.remove_absolute(part)
		_fail("загрузка прервалась: " + _describe(res))
		return false
	var sum: String = await _sha256(part)
	if sum != q["sha256"] or _file_size(part) != int(q["size"]):
		DirAccess.remove_absolute(part)
		_fail("файл повреждён — контрольная сумма не совпала")
		return false
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(part, path) != OK:
		_fail("не удалось сохранить файл")
		return false
	return true


func _install_patches() -> String:
	if kind != "patch":
		return ""
	var list: Array = _keep.duplicate()
	for q: Dictionary in _queue:
		if q.has("install"):
			continue
		list.append({"version": q["version"], "file": q["file"], "sha256": q["sha256"], "size": q["size"]})
	if not Updater.save_chain(list, _keep.size()):
		return "не удалось записать список патчей"
	return ""


## Скачанный BGSocial.exe — в папку игры (копией: user:// и папка игры могут быть на разных дисках).
func _install_social() -> String:
	for q: Dictionary in _queue:
		if not q.has("install"):
			continue
		var src := Updater.DIR + str(q["file"])
		var dest := Updater.install_dir().path_join(str(q["install"]))
		if not FileAccess.file_exists(dest) and DirAccess.copy_absolute(src, dest) != OK:
			return "не удалось положить %s в папку игры" % q["install"]
		DirAccess.remove_absolute(src)
	return ""


## Распаковать zip новой базы рядом с exe: сначала все файлы как *.new, затем подмена с *.old.
func _install_base() -> String:
	var zip_path := Updater.DIR + str(_queue[0]["file"])
	var dir := Updater.install_dir()
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "архив не открывается"
	var names: Array[String] = []
	for f in zip.get_files():
		if not f.ends_with("/"):
			names.append(f)
	var strip := _common_dir(names)
	var written: Array[String] = []
	for f in names:
		var rel := f.substr(strip.length())
		if rel.contains("/") or rel.contains(".."):
			continue  # в архиве базы только плоские файлы
		var out := FileAccess.open(dir.path_join(rel + ".new"), FileAccess.WRITE)
		if out == null:
			zip.close()
			_drop_new(dir, written)
			return "нет доступа к папке игры"
		out.store_buffer(zip.read_file(f))
		out.close()
		written.append(rel)
	zip.close()
	if not written.has(OS.get_executable_path().get_file()) and Updater.install_dir() == OS.get_executable_path().get_base_dir():
		_drop_new(dir, written)
		return "в архиве нет exe игры"
	# Подмена: работающий exe и dll в Windows переименовывать можно, перезаписывать — нет.
	var swapped: Array[String] = []
	for rel in written:
		var dest := dir.path_join(rel)
		DirAccess.remove_absolute(dest + ".old")
		if FileAccess.file_exists(dest) and DirAccess.rename_absolute(dest, dest + ".old") != OK:
			_unswap(dir, swapped)
			_drop_new(dir, written)
			return "файл игры занят: " + rel
		swapped.append(rel)
		if DirAccess.rename_absolute(dest + ".new", dest) != OK:
			_unswap(dir, swapped)
			_drop_new(dir, written)
			return "не удалось заменить " + rel
	DirAccess.remove_absolute(zip_path)
	Updater.write_json(Updater.BASE_TRIAL, {"dir": dir, "files": written, "from": Updater.version, "to": str(_queue[0]["version"]), "started": false})
	return ""


func _unswap(dir: String, swapped: Array[String]) -> void:
	for rel in swapped:
		var dest := dir.path_join(rel)
		if FileAccess.file_exists(dest + ".old"):
			if FileAccess.file_exists(dest):
				DirAccess.rename_absolute(dest, dest + ".new")
			DirAccess.rename_absolute(dest + ".old", dest)


func _drop_new(dir: String, written: Array[String]) -> void:
	for rel in written:
		DirAccess.remove_absolute(dir.path_join(rel + ".new"))


## Если все файлы архива лежат в одной папке — её префикс ("PartyWorld/").
func _common_dir(names: Array[String]) -> String:
	if names.is_empty() or not names[0].contains("/"):
		return ""
	var head := names[0].get_slice("/", 0) + "/"
	for n in names:
		if not n.begins_with(head):
			return ""
	return head


func _writable(dir: String) -> bool:
	var probe := dir.path_join(".pw_update_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _get_text(url: String) -> String:
	_last_problem = ""
	var res: Array = await _request(url, ["User-Agent: PartyWorld-Updater", "Cache-Control: no-cache"], 10000, "")
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_last_problem = _describe(res)
		print("[update] манифест недоступен (%s/%s): %s" % [res[0], res[1], _last_problem])
		return ""
	return (res[3] as PackedByteArray).get_string_from_utf8()


## Запрос с запасным путём: если соединение не удалось (часто — антивирус подменяет HTTPS-сертификаты,
## которым Godot не доверяет, хотя браузер работает), повторяем с сертификатами из хранилища Windows.
## Удачный запасной путь запоминается до конца запуска (и для скачивания патчей).
func _request(url: String, headers: PackedStringArray, stall_ms: int, file: String) -> Array:
	var res: Array = await _request_once(url, headers, stall_ms, file)
	if res[0] in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_TIMEOUT] or _system_tls:
		return res
	var tls := _system_tls_options()
	if tls == null:
		return res
	print("[update] повтор с сертификатами Windows после: ", _describe(res))
	_http.set_tls_options(tls)
	var again: Array = await _request_once(url, headers, stall_ms, file)
	if again[0] == HTTPRequest.RESULT_SUCCESS:
		_system_tls = true
		return again
	_http.set_tls_options(TLSOptions.client())
	return again


func _request_once(url: String, headers: PackedStringArray, stall_ms: int, file: String) -> Array:
	_http.download_file = file
	var err := _http.request(url, headers)
	if err != OK:
		_http.download_file = ""
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	var res: Array = await _await_request(stall_ms)
	_http.download_file = ""
	return res


func _system_tls_options() -> TLSOptions:
	var pem := OS.get_system_ca_certificates()
	if pem.is_empty():
		return null
	var cert := X509Certificate.new()
	if cert.load_from_string(pem) != OK:
		return null
	return TLSOptions.client(cert)


## Понятная причина сетевой неудачи — её видно в настройках и в логе.
static func _describe(res: Array) -> String:
	match int(res[0]):
		HTTPRequest.RESULT_SUCCESS:
			return "GitHub ответил кодом %d" % int(res[1])
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "не найден адрес GitHub — нет интернета или DNS не отвечает"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "нет соединения с GitHub — сеть, VPN или провайдер не пускают к серверу файлов"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "не удалось защищённое соединение — проверьте дату и время на компьютере и HTTPS-проверку в антивирусе"
		HTTPRequest.RESULT_TIMEOUT:
			return "GitHub не отвечает больше 10 секунд — медленная сеть или сервер файлов недоступен"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "слишком много перенаправлений"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "GitHub не прислал ответ"
	return "ошибка сети %d/%d" % [int(res[0]), int(res[1])]


## Дождаться конца запроса; если stall_ms не приходит ни байта — отменить (RESULT_TIMEOUT).
## Свой сторож вместо HTTPRequest.timeout: в Godot 4.7.2 после load_resource_pack встроенный
## таймаут срабатывает сразу (проверено), а патчи подключены почти всегда.
func _await_request(stall_ms: int) -> Array:
	var box: Array = []
	var cb := func(r: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		box.append([r, code, headers, body])
	_http.request_completed.connect(cb, CONNECT_ONE_SHOT)
	var last := -1
	var since := Time.get_ticks_msec()
	while box.is_empty():
		await get_tree().process_frame
		var got := _http.get_downloaded_bytes()
		if got != last:
			last = got
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since > stall_ms:
			_http.cancel_request()
			_http.request_completed.disconnect(cb)
			return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	return box[0]


## SHA-256 файла кусками по 4 МБ, кадр за кадром — большой zip не подвешивает хаб.
func _sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(4 << 20))
		await get_tree().process_frame
	f.close()  # иначе файл держится открытым до сборки корутины и не переименовывается
	return ctx.finish().hex_encode()


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


func _fail(msg: String) -> void:
	error = msg
	print("[update] ошибка: ", msg)
	_set_state(State.FAILED)


func _set_state(s: State) -> void:
	state = s
	changed.emit()
