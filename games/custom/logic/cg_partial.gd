extends RefCounted
## Одна незавершённая загрузка между запусками: ограниченный бинарный файл, окончательный SHA — только у полного ZIP.
const Package := preload("res://games/custom/logic/cg_package.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
const PATH := "user://custom_cache/receiving.part"
const MAGIC := "CGPART01"
const HEADER := 80

static func _matches(file: FileAccess, hash_value: String, total: int) -> bool:
	if file == null or file.get_length() < HEADER or file.get_length() > HEADER + Package.LIMIT:
		return false
	file.seek(0)
	return file.get_buffer(8).get_string_from_ascii() == MAGIC and file.get_buffer(64).get_string_from_ascii() == hash_value and file.get_64() == total

static func restore(hash_value: String, total: int) -> PackedByteArray:
	if not Package.hash_valid(hash_value) or total < 22 or total > Package.LIMIT or not FileAccess.file_exists(PATH):
		return PackedByteArray()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if not _matches(file, hash_value, total):
		return PackedByteArray()
	var count := file.get_length() - HEADER
	if count > total:
		return PackedByteArray()
	# После аварийного завершения последняя недописанная часть запрашивается заново целиком.
	if count < total:
		count = (count / Package.CHUNK) * Package.CHUNK
	file.seek(HEADER)
	var bytes := file.get_buffer(count)
	if bytes.size() != count or (count == total and Package.sha(bytes) != hash_value):
		return PackedByteArray()
	return bytes

static func save(hash_value: String, total: int, bytes: PackedByteArray, previous_size: int) -> bool:
	if not Package.hash_valid(hash_value) or total < 22 or total > Package.LIMIT or bytes.size() > total or previous_size < 0 or previous_size > bytes.size():
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Library.CACHE))
	var file: FileAccess
	if FileAccess.file_exists(PATH):
		file = FileAccess.open(PATH, FileAccess.READ_WRITE)
	var append := _matches(file, hash_value, total) and file.get_length() == HEADER + previous_size
	if not append:
		file = null
		Library.prune_cache(hash_value, Library.CACHE_LIMIT - total - HEADER)
		file = FileAccess.open(PATH, FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(MAGIC.to_ascii_buffer())
		file.store_buffer(hash_value.to_ascii_buffer())
		file.store_64(total)
		file.store_buffer(bytes)
	else:
		file.seek_end()
		file.store_buffer(bytes.slice(previous_size))
	file.flush()
	return file.get_error() == OK and file.get_length() == HEADER + bytes.size()

static func discard(hash_value: String, total: int) -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	var matches := _matches(file, hash_value, total)
	file = null
	if matches:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
