extends Node
## Автообновление, часть 2 — проверка, скачивание и установка (живёт в корне дерева как "UpdateClient").
##
## Манифест `latest.json` лежит в последнем GitHub-релизе (формат — tools/release/release.py):
##   {"format": 1, "version": "0.8.10", "page": "...",
##    "base": {"version": "0.8.9", "url": "...zip", "size": N, "sha256": "..."},
##    "patches": [{"version": "0.8.10", "url": "...pck", "size": N, "sha256": "..."}, ...]}
## - база манифеста новее нашего exe → качаем zip, сверяем SHA-256, кладём файлы рядом с exe
##   (старые → *.old), после перезапуска Updater следит, что новая версия запустилась;
## - база та же → докачиваем недостающий хвост цепочки патчей в user://updates/.
## Без сети/при ошибке молча остаётся в NONE/FAILED — играть это не мешает.
## Проверка локально: env PW_UPDATE_URL=http://127.0.0.1:8765/latest.json, PW_UPDATE_INSTALL_DIR=<папка>.

signal changed

const MANIFEST_URL := "https://github.com/Hufflee/Board-Games-For-Friends/releases/latest/download/latest.json"
const RELEASES_PAGE := "https://github.com/Hufflee/Board-Games-For-Friends/releases/latest"

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
			error = "Не удалось получить сведения об обновлениях."
			_set_state(State.FAILED)
		else:
			_set_state(State.NONE)  # автоматическая проверка без сети молчит
		return
	_manifest = m
	page = str(m.get("page", RELEASES_PAGE))
	_plan()


func _plan() -> void:
	_queue.clear()
	_keep.clear()
	kind = ""
	target = ""
	# Сравниваем действующую версию, включая уже загруженные PCK.
	# Другая контрольная сумма цепочки не повод предлагать ту же версию снова.
	var latest := str(_manifest.get("version", ""))
	if latest == "" or Updater.compare(latest, Updater.version) <= 0:
		_set_state(State.NONE)
		return
	var base: Dictionary = _manifest.get("base", {})
	var mb := str(base.get("version", ""))
	var patches: Array = _manifest.get("patches", [])
	if Updater.compare(mb, Updater.base_version) > 0:
		kind = "base"
		target = str(_manifest.get("version", mb))
		_queue = [_entry(base, "base-%s.zip" % mb)]
		var dir := Updater.install_dir()
		_set_state(State.AVAILABLE if dir != "" and _writable(dir) else State.MANUAL)
		return
	if mb != Updater.base_version:
		_set_state(State.NONE)
		return
	# Установленная цепочка должна совпадать с началом манифеста, иначе ставим заново.
	var have := Updater.chain()
	var same := have.size() <= patches.size()
	for i in have.size():
		if not same:
			break
		same = str(have[i].get("sha256", "")) == str(patches[i].get("sha256", ""))
	_keep = have if same else []
	_queue = []
	for i in range(_keep.size(), patches.size()):
		var p: Dictionary = patches[i]
		_queue.append(_entry(p, "patch-%s.pck" % str(p.get("version", i))))
	if _queue.is_empty():
		_set_state(State.NONE)
		return
	kind = "patch"
	target = str(_queue[-1]["version"])
	_set_state(State.AVAILABLE)


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
	_http.download_file = part
	if _http.request(str(q["url"]), ["User-Agent: PartyWorld-Updater"]) != OK:
		_fail("не удалось начать загрузку")
		return false
	var res: Array = await _await_request(30000)
	_http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		DirAccess.remove_absolute(part)
		_fail("загрузка прервалась (%s/%s)" % [res[0], res[1]])
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
	var list: Array = _keep.duplicate()
	for q: Dictionary in _queue:
		list.append({"version": q["version"], "file": q["file"], "sha256": q["sha256"], "size": q["size"]})
	if not Updater.save_chain(list, _keep.size()):
		return "не удалось записать список патчей"
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
	_http.download_file = ""
	if _http.request(url, ["User-Agent: PartyWorld-Updater", "Cache-Control: no-cache"]) != OK:
		return ""
	var res: Array = await _await_request(10000)
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("[update] манифест недоступен (%s/%s)" % [res[0], res[1]])
		return ""
	return (res[3] as PackedByteArray).get_string_from_utf8()


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
