class_name CGLibrary
extends RefCounted
## Локальные исходники автора в user://custom_games. Кэш полученных игр хранится отдельно.

const Package := preload("res://games/custom/logic/cg_package.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const ROOT := "user://custom_games"
const CACHE := "user://custom_cache"
const CACHE_LIMIT := 1024 * 1024 * 1024
const SHAPES := {"square": Vector2(0.30, 0.30), "tall": Vector2(0.24, 0.32), "wide": Vector2(0.32, 0.24), "small": Vector2(0.18, 0.22)}
static var _list_cache: Array = []
static var _list_ready := false

static func invalidate() -> void:
	_list_ready = false

static func uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

static func uuid_valid(id: String) -> bool:
	if id.length() != 36:
		return false
	for index in id.length():
		if index in [8, 13, 18, 23]:
			if id[index] != "-":
				return false
		elif id[index] not in "0123456789abcdef":
			return false
	return true

static func folder(id: String) -> String:
	return ROOT + "/" + id if uuid_valid(id) else ""

static func read_definition(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Package.JSON_LIMIT:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not Definition.validate(parsed).errors.is_empty():
		return {}
	return parsed

static func load_game(id: String) -> Dictionary:
	var directory := folder(id)
	if directory.is_empty():
		return {}
	var data := read_definition(directory + "/game.json")
	if data.is_empty():
		data = read_definition(directory + "/game.json.bak")
	return data if data.get("id") == id else {}

static func create(definition: Dictionary) -> Dictionary:
	var id := uuid()
	var copy := definition.duplicate(true)
	copy.id = id
	copy.game_version = 0
	return save(id, copy)

static func save(id: String, definition: Dictionary) -> Dictionary:
	var directory := folder(id)
	if directory.is_empty() or definition.get("id") != id:
		return {"error": "Неверный идентификатор игры."}
	var check := Definition.validate(definition)
	if not check.errors.is_empty():
		return {"error": str(check.errors[0])}
	var old := load_game(id)
	var copy := definition.duplicate(true)
	copy.game_version = int(old.get("game_version", 0)) + 1
	var bytes := JSON.stringify(copy, "\t").to_utf8_buffer()
	if bytes.size() > Package.JSON_LIMIT:
		return {"error": "Описание игры больше 1 МБ."}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory + "/history")) != OK:
		return {"error": "Не удалось создать папку игры."}
	var path := directory + "/game.json"
	if not old.is_empty():
		var history_path := directory + "/history/%013d_%06d.json" % [int(Time.get_unix_time_from_system() * 1000), int(old.get("game_version", 0))]
		var history := FileAccess.open(history_path, FileAccess.WRITE)
		if history == null:
			return {"error": "Не удалось сохранить предыдущую версию."}
		history.store_string(JSON.stringify(old, "\t"))
		history.close()
	var error := _atomic_write(path, bytes)
	if error != OK:
		return {"error": "Не удалось записать игру: %s." % error_string(error)}
	var names: Array[String] = []
	for name_value: String in DirAccess.get_files_at(directory + "/history"):
		var parts := name_value.get_basename().split("_")
		if name_value.ends_with(".json") and parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			names.append(name_value)
	names.sort()
	while names.size() > 10:
		DirAccess.remove_absolute(directory + "/history/" + names[0])
		names.remove_at(0)
	invalidate()
	return {"error": "", "id": id, "definition": copy}

static func _atomic_write(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		error = DirAccess.rename_absolute(path, path + ".bak")
		if error != OK:
			return error
	error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK and FileAccess.file_exists(path + ".bak"):
		DirAccess.rename_absolute(path + ".bak", path)
	return error

static func list() -> Array:
	if _list_ready:
		return _list_cache.duplicate(true)
	var games: Array = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return games
	for id: String in DirAccess.get_directories_at(ROOT):
		if not uuid_valid(id):
			continue
		var definition := load_game(id)
		if definition.is_empty():
			continue
		var meta: Dictionary = definition.meta
		var seats: Array = meta.get("players", [2, 8])
		var box: Dictionary = definition.get("box", {})
		var template := str(box.get("template", "square"))
		games.append({"id": "custom:" + id, "uuid": id, "custom": true, "title": str(meta.title),
			"players": "%d–%d игроков" % [int(seats[0]), int(seats[1])], "time": str(meta.get("time", "")),
			"description": str(meta.get("description", "")), "scene": "res://games/custom/ui/main.tscn",
			"color": Color.from_string(str(meta.get("color", "#655080")), Color("655080")),
			"thickness": clampf(float(box.get("thickness", 0.06)), 0.04, 0.12), "box_size": SHAPES.get(template, SHAPES.square)})
	_list_cache = games
	_list_ready = true
	return games.duplicate(true)

static func files_for(id: String) -> Dictionary:
	var directory := folder(id)
	if directory.is_empty() or load_game(id).is_empty():
		return {}
	var definition := load_game(id)
	var references := {}
	_hashes_in(definition, references)
	var files := {"game.json": JSON.stringify(definition, "\t").to_utf8_buffer()}
	for sub: String in ["assets/img", "assets/fonts", "covers"]:
		if not DirAccess.dir_exists_absolute(directory + "/" + sub):
			continue
		for name_value: String in DirAccess.get_files_at(directory + "/" + sub):
			var path := sub + "/" + name_value
			if Package.path_valid(path) and (sub == "covers" or references.has(name_value.get_basename())):
				files[path] = FileAccess.get_file_as_bytes(directory + "/" + path)
	if FileAccess.file_exists(directory + "/thumb.png"):
		files["thumb.png"] = FileAccess.get_file_as_bytes(directory + "/thumb.png")
	return files

static func _hashes_in(value: Variant, found: Dictionary) -> void:
	if value is String and Package.hash_valid(value):
		found[value] = true
	elif value is Array:
		for item: Variant in value:
			_hashes_in(item, found)
	elif value is Dictionary:
		for key: String in value:
			if Package.hash_valid(key):
				found[key] = true
			_hashes_in(value[key], found)

static func build_package(id: String) -> Dictionary:
	var files := files_for(id)
	if files.is_empty():
		return {"error": "Игра не найдена."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE))
	var path := CACHE + "/outgoing.zip"
	var result := Package.write_zip(path, files)
	if not str(result.error).is_empty():
		return result
	var target := CACHE + "/" + str(result.hash) + ".zip"
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(path)
	else:
		var error := DirAccess.rename_absolute(path, target)
		if error != OK:
			return {"error": "Не удалось сохранить пакет в кэш."}
	result["path"] = target
	return result

static func cache_path(hash_value: String) -> String:
	return CACHE + "/" + hash_value + ".zip" if Package.hash_valid(hash_value) else ""

static func cached(hash_value: String) -> Dictionary:
	var path := cache_path(hash_value)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"error": "Пакета пока нет в кэше."}
	var result := Package.read_zip(path, hash_value)
	if str(result.error).is_empty():
		_touch(hash_value)
	return result

static func put_cache(hash_value: String, bytes: PackedByteArray) -> Dictionary:
	if not Package.hash_valid(hash_value) or bytes.size() > Package.LIMIT or Package.sha(bytes) != hash_value:
		return {"error": "Неверный размер или хэш полученного пакета."}
	var preflight := Package.preflight(bytes)
	if not str(preflight.error).is_empty():
		return preflight
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE))
	var temporary := CACHE + "/receiving.zip"
	var error := _atomic_write(temporary, bytes)
	if error != OK:
		return {"error": "Не удалось записать полученный пакет."}
	var result := Package.read_zip(temporary, hash_value)
	if not str(result.error).is_empty():
		DirAccess.remove_absolute(temporary)
		return result
	var target := cache_path(hash_value)
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(temporary)
	else:
		error = DirAccess.rename_absolute(temporary, target)
		if error != OK:
			return {"error": "Не удалось поместить пакет в кэш."}
	if FileAccess.file_exists(temporary + ".bak"):
		DirAccess.remove_absolute(temporary + ".bak")
	_touch(hash_value)
	prune_cache(hash_value)
	return result

static func _touch(hash_value: String) -> void:
	var file := FileAccess.open(CACHE + "/" + hash_value + ".used", FileAccess.WRITE)
	if file:
		file.store_string(str(Time.get_unix_time_from_system()))

static func prune_cache(keep: String = "", limit: int = CACHE_LIMIT) -> void:
	var entries: Array = []
	var total := 0
	for name_value: String in DirAccess.get_files_at(CACHE):
		var hash_value := name_value.get_basename()
		if name_value.get_extension() != "zip" or not Package.hash_valid(hash_value):
			continue
		var file := FileAccess.open(CACHE + "/" + name_value, FileAccess.READ)
		if file == null:
			continue
		var length := file.get_length()
		file.close()
		total += length
		var used := CACHE + "/" + hash_value + ".used"
		var stamp := FileAccess.get_modified_time(used) if FileAccess.file_exists(used) else FileAccess.get_modified_time(CACHE + "/" + name_value)
		entries.append({"hash": hash_value, "size": length, "stamp": stamp})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return a.stamp < b.stamp)
	for entry: Dictionary in entries:
		if total <= limit:
			break
		if entry.hash == keep:
			continue
		DirAccess.remove_absolute(cache_path(entry.hash))
		DirAccess.remove_absolute(CACHE + "/" + str(entry.hash) + ".used")
		total -= int(entry.size)

static func cover_texture(id: String, face: String) -> Texture2D:
	if not uuid_valid(id) or face not in ["front", "back", "spine", "top"]:
		return null
	var path := folder(id) + "/covers/" + face + ".png"
	if not FileAccess.file_exists(path) and face == "back":
		path = folder(id) + "/covers/front.png"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Package.LIMIT:
		return null
	var image := Package.image_from_bytes(file.get_buffer(file.get_length()), "png")
	return ImageTexture.create_from_image(image) if image != null else null

static func duplicate_game(id: String) -> Dictionary:
	var source := load_game(id)
	if source.is_empty():
		return {"error": "Не найдена сохранённая версия игры."}
	var files := files_for(id)
	var checked := Package.validate_files(files)
	if not str(checked.get("error", "")).is_empty():
		return {"error": str(checked.error)}
	source.meta.title = str(source.meta.title).left(4000) + " · копия"
	var created := create(source)
	if not str(created.error).is_empty():
		return created
	for path: String in files:
		if path == "game.json":
			continue
		var destination := folder(str(created.id)) + "/" + path
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK or _atomic_write(destination, files[path]) != OK:
			trash_game(str(created.id))
			return {"error": "Не удалось скопировать ассеты игры."}
	invalidate()
	return created

static func trash_game(id: String) -> String:
	var source := folder(id)
	if source.is_empty() or not DirAccess.dir_exists_absolute(source):
		return "Игра не найдена."
	var trash := "user://custom_games_trash"
	if DirAccess.make_dir_recursive_absolute(trash) != OK:
		return "Не удалось создать корзину проектов."
	var destination := trash + "/" + id + "_" + str(Time.get_ticks_usec())
	var result := DirAccess.rename_absolute(source, destination)
	if result != OK:
		return "Не удалось переместить проект в корзину: %s." % error_string(result)
	invalidate()
	return ""
