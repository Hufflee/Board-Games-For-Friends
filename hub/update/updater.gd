extends Node
## Автообновление, часть 1 — загрузчик патчей (autoload `Updater`, стоит ПЕРВЫМ в project.godot).
##
## В `_init` подключает скачанные PCK-патчи из user://updates/ по порядку цепочки — раньше, чем
## загрузятся остальные autoload'ы, поэтому патч меняет и их скрипты. Сам этот файл патчем не
## обновить (он уже загружен из базы), поэтому здесь только подключение паков, откат и общие
## функции; скачивание и интерфейс — `update_client.gd` и `update_panel.gd` (их патчить можно).
##
## Откат:
## - новые патчи ставятся «на пробу»: если запуск с ними не дошёл до хаба (`confirm_boot`),
##   при следующем запуске они снимаются;
## - новая база (замена exe) — так же: старые файлы лежат рядом как `*.old`, и если новая версия
##   дважды не дошла до хаба, они возвращаются на место и запускается старый exe.
## Выключен в редакторе и Steam-сборке (feature `steam_store`). Проверка из редактора:
## env PW_UPDATER=1 (и PW_UPDATE_URL, PW_UPDATE_INSTALL_DIR — см. update_client.gd).

const DIR := "user://updates/"
const STATE := DIR + "state.json"
const BASE_TRIAL := DIR + "base_trial.json"

var base_version := ""  # версия самого exe (из project.godot базы)
var version := ""  # действующая версия с учётом патчей
var enabled := false
var loaded: Array[String] = []  # версии подключённых в этом запуске патчей
var rolled_back := ""  # что сняли при откате (для сообщения в хабе)
var _restore_exe := ""  # после отката базы — какой exe перезапустить


func _init() -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", "0"))
	version = base_version
	enabled = is_supported()
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	if not _check_base_trial():
		_cleanup_install_dir()
	_apply_patches()
	# Вся игра (хаб, «Что нового?», диагностика) берёт версию отсюда.
	ProjectSettings.set_setting("application/config/version", version)


func _ready() -> void:
	if _restore_exe != "":
		OS.create_process(_restore_exe, OS.get_cmdline_args())
		get_tree().quit()


## Апдейтер работает только в собранной не-Steam игре под Windows.
static func is_supported() -> bool:
	var force := OS.get_environment("PW_UPDATER")
	if force == "0" or OS.has_feature("steam_store") or OS.get_name() != "Windows":
		return false
	return force == "1" or not OS.has_feature("editor")


## Папка с exe, куда ставится новая база; "" — ставить некуда (запуск из редактора).
static func install_dir() -> String:
	var forced := OS.get_environment("PW_UPDATE_INSTALL_DIR")
	if forced != "":
		return forced
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir()
	return ""


## Сравнение версий «0.8.10» > «0.8.9»; хвосты вида «-lite» не учитываются.
static func compare(a: String, b: String) -> int:
	var pa := a.split("-")[0].split(".")
	var pb := b.split("-")[0].split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func write_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK


## Установленная цепочка патчей текущей базы: [{version, file, sha256, size}].
func chain() -> Array:
	var st := read_json(STATE)
	if str(st.get("base", "")) != base_version:
		return []
	return st.get("patches", [])


## Клиент докачал патчи: новая цепочка целиком, с индекса `trial_from` — пробные.
func save_chain(patches: Array, trial_from: int) -> bool:
	return write_json(STATE, {"base": base_version, "patches": patches, "trial_from": trial_from, "trial_started": false})


## Хаб открылся — пробные патчи и новая база прижились.
func confirm_boot() -> void:
	if not enabled:
		return
	var st := read_json(STATE)
	if int(st.get("trial_from", -1)) >= 0:
		st["trial_from"] = -1
		st["trial_started"] = false
		write_json(STATE, st)
	if FileAccess.file_exists(BASE_TRIAL):
		DirAccess.remove_absolute(BASE_TRIAL)


func _apply_patches() -> void:
	var st := read_json(STATE)
	if str(st.get("base", "")) != base_version:
		# Новая база (или первый запуск): патчи прошлой базы не годятся.
		_remove_patch_files(st.get("patches", []))
		write_json(STATE, {"base": base_version, "patches": [], "trial_from": -1, "trial_started": false})
		return
	var patches: Array = st.get("patches", [])
	var trial := int(st.get("trial_from", -1))
	if trial >= 0:
		if bool(st.get("trial_started", false)):
			# Прошлый запуск с пробными патчами не дошёл до хаба — снимаем их.
			var dropped := patches.slice(trial)
			if not dropped.is_empty():
				rolled_back = str(dropped[-1].get("version", ""))
			_remove_patch_files(dropped)
			patches = patches.slice(0, trial)
			st["trial_from"] = -1
			st["trial_started"] = false
			print("[update] откат пробных патчей до ", rolled_back)
		else:
			st["trial_started"] = true
		st["patches"] = patches
		write_json(STATE, st)
	var ok := 0
	for p: Dictionary in patches:
		var path := DIR + str(p.get("file", ""))
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() != int(p.get("size", -1)):
			break
		f.close()
		if not ProjectSettings.load_resource_pack(path, true):
			break
		version = str(p.get("version", version))
		loaded.append(version)
		ok += 1
	if ok < patches.size():
		# Цепочка оборвалась: хвост после сбойного патча бесполезен — убрать, клиент скачает заново.
		print("[update] патч не подключился: ", patches[ok].get("version", "?"))
		_remove_patch_files(patches.slice(ok))
		st["patches"] = patches.slice(0, ok)
		st["trial_from"] = -1
		write_json(STATE, st)


func _remove_patch_files(list: Array) -> void:
	for p: Variant in list:
		if p is Dictionary and str(p.get("file", "")) != "":
			DirAccess.remove_absolute(DIR + str(p["file"]))


## Проба новой базы. true — проба идёт, старые файлы (*.old) трогать нельзя.
func _check_base_trial() -> bool:
	var trial := read_json(BASE_TRIAL)
	if trial.is_empty():
		return false
	var dir := str(trial.get("dir", ""))
	if dir == "" or str(trial.get("to", "")) != base_version:
		# Запущена не новая версия (замена не удалась или уже откатили) — проба не нужна.
		DirAccess.remove_absolute(BASE_TRIAL)
		return false
	if not bool(trial.get("started", false)):
		trial["started"] = true
		write_json(BASE_TRIAL, trial)
		return true
	# Новая база уже запускалась и не дошла до хаба — возвращаем старые файлы.
	for name: Variant in trial.get("files", []):
		var dest := dir.path_join(str(name))
		if FileAccess.file_exists(dest + ".old"):
			DirAccess.remove_absolute(dest + ".bad")
			DirAccess.rename_absolute(dest, dest + ".bad")
			DirAccess.rename_absolute(dest + ".old", dest)
	DirAccess.remove_absolute(BASE_TRIAL)
	rolled_back = base_version
	_restore_exe = dir.path_join(OS.get_executable_path().get_file())
	print("[update] новая версия не запустилась, возвращаю ", trial.get("from", "?"))
	return true


## Убрать остатки прошлой замены exe (*.old, *.bad, недописанные *.new).
func _cleanup_install_dir() -> void:
	var dir := install_dir()
	if dir == "":
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".old") or f.ends_with(".bad") or f.ends_with(".new"):
			DirAccess.remove_absolute(dir.path_join(f))
