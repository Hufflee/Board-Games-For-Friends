class_name CGPackage
extends RefCounted
## Пакет игры — только JSON, изображения и шрифты. Предварительная проверка ZIP до распаковки.

const Definition := preload("res://games/custom/logic/cg_def.gd")
const LIMIT := 64 * 1024 * 1024
const JSON_LIMIT := 1024 * 1024
const FONT_LIMIT := 10 * 1024 * 1024
const FILE_LIMIT := 1000
const CHUNK := 48 * 1024
const COVER_NAMES := ["covers/front.png", "covers/back.png", "covers/spine.png", "covers/top.png", "thumb.png"]
const DIRECTORIES := ["assets/", "assets/img/", "assets/fonts/", "covers/"]

static func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func hash_valid(text: String) -> bool:
	if text.length() != 64:
		return false
	for c in text:
		if c not in "0123456789abcdef":
			return false
	return true

static func path_valid(path: String) -> bool:
	if path == "game.json" or path in COVER_NAMES:
		return true
	var parent := path.get_base_dir()
	var extension := path.get_extension()
	if parent == "assets/img" and extension in ["png", "jpg", "webp"] or parent == "assets/fonts" and extension in ["ttf", "otf"]:
		return hash_valid(path.get_file().get_basename())
	return false

static func migrate(definition: Dictionary) -> Dictionary:
	# Миграций пока нет; неизвестный формат не угадываем.
	return definition.duplicate(true) if definition.get("format") == 1 else {}

static func image_size(bytes: PackedByteArray, extension: String) -> Vector2i:
	if extension == "png" and bytes.size() >= 24 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
	if extension == "jpg" and bytes.size() >= 4 and bytes[0] == 255 and bytes[1] == 216:
		var at := 2
		while at + 4 <= bytes.size():
			if bytes[at] != 255:
				return Vector2i.ZERO
			var marker := bytes[at + 1]
			if marker == 255:
				at += 1
				continue
			if marker in [216, 217, 1] or marker >= 208 and marker <= 215:
				at += 2
				continue
			var length := int(bytes[at + 2]) * 256 + bytes[at + 3]
			if length < 2 or at + 2 + length > bytes.size():
				return Vector2i.ZERO
			if marker in [192, 193, 194] and length >= 7:
				return Vector2i(int(bytes[at + 7]) * 256 + bytes[at + 8], int(bytes[at + 5]) * 256 + bytes[at + 6])
			at += 2 + length
	if extension == "webp" and bytes.size() >= 30 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		var kind := bytes.slice(12, 16).get_string_from_ascii()
		if kind == "VP8X":
			return Vector2i(1 + _le24(bytes, 24), 1 + _le24(bytes, 27))
		if kind == "VP8 " and bytes[23] == 157 and bytes[24] == 1 and bytes[25] == 42:
			return Vector2i(bytes.decode_u16(26) & 16383, bytes.decode_u16(28) & 16383)
		if kind == "VP8L" and bytes[20] == 47:
			var bits := bytes.decode_u32(21)
			return Vector2i(1 + (bits & 16383), 1 + ((bits >> 14) & 16383))
	return Vector2i.ZERO

static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (int(bytes[at]) << 24) | (int(bytes[at + 1]) << 16) | (int(bytes[at + 2]) << 8) | int(bytes[at + 3])

static func _le24(bytes: PackedByteArray, at: int) -> int:
	return int(bytes[at]) | (int(bytes[at + 1]) << 8) | (int(bytes[at + 2]) << 16)

static func image_from_bytes(bytes: PackedByteArray, extension: String) -> Image:
	var dimensions := image_size(bytes, extension)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 2048 or dimensions.y > 2048:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match extension:
		"png": error = image.load_png_from_buffer(bytes)
		"jpg": error = image.load_jpg_from_buffer(bytes)
		"webp": error = image.load_webp_from_buffer(bytes)
	if error != OK or image.get_size() != dimensions:
		return null
	return image

static func validate_files(files: Dictionary) -> Dictionary:
	var total := 0
	if files.size() > FILE_LIMIT or not files.has("game.json"):
		return {"error": "В пакете нет game.json или слишком много файлов."}
	for path: Variant in files:
		if not path is String or not path_valid(path) or not files[path] is PackedByteArray:
			return {"error": "Недопустимый файл пакета."}
		var bytes: PackedByteArray = files[path]
		total += bytes.size()
		if total > LIMIT:
			return {"error": "Распакованная игра больше 64 МБ."}
		if path == "game.json":
			if bytes.size() > JSON_LIMIT:
				return {"error": "Описание игры больше 1 МБ."}
		elif path.get_extension() in ["ttf", "otf"]:
			if bytes.size() < 12 or bytes.size() > FONT_LIMIT or bytes.slice(0, 4) not in [PackedByteArray([0, 1, 0, 0]), "OTTO".to_ascii_buffer()]:
				return {"error": "Неверный шрифт или размер больше 10 МБ."}
		elif image_from_bytes(bytes, path.get_extension()) == null:
			return {"error": "Неверная картинка или размер больше 2048 px."}
		if path.begins_with("assets/") and sha(bytes) != path.get_file().get_basename():
			return {"error": "Хэш ассета не совпадает с именем."}
	var parser := JSON.new()
	if parser.parse((files["game.json"] as PackedByteArray).get_string_from_utf8()) != OK:
		return {"error": "Описание игры содержит ошибку JSON."}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"error": "Описание игры не является JSON-объектом."}
	var migrated := migrate(parsed)
	var validation := Definition.validate(migrated)
	if not validation.errors.is_empty():
		return {"error": str(validation.errors[0])}
	return {"error": "", "definition": migrated, "size": total}

static func preflight(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 22 or bytes.size() > LIMIT:
		return {"error": "Размер ZIP должен быть не больше 64 МБ."}
	var end := -1
	for at in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(at) == 0x06054b50 and at + 22 + bytes.decode_u16(at + 20) == bytes.size():
			end = at
			break
	if end < 0:
		return {"error": "Не найден конец ZIP."}
	var count := bytes.decode_u16(end + 10)
	var at := int(bytes.decode_u32(end + 16))
	var directory_size := int(bytes.decode_u32(end + 12))
	if bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0 or bytes.decode_u16(end + 8) != count or count < 1 or count > FILE_LIMIT or at + directory_size != end:
		return {"error": "Многотомный ZIP, ZIP64 или неверный каталог не поддерживается."}
	var names := {}
	var total := 0
	for i in count:
		if at + 46 > end or bytes.decode_u32(at) != 0x02014b50:
			return {"error": "Повреждён каталог ZIP."}
		var flags := bytes.decode_u16(at + 8)
		var method := bytes.decode_u16(at + 10)
		var compressed := int(bytes.decode_u32(at + 20))
		var length := int(bytes.decode_u32(at + 24))
		var name_length := bytes.decode_u16(at + 28)
		var extra_length := bytes.decode_u16(at + 30)
		var comment_length := bytes.decode_u16(at + 32)
		var local := int(bytes.decode_u32(at + 42))
		if at + 46 + name_length + extra_length + comment_length > end:
			return {"error": "Длина записи ZIP выходит за каталог."}
		var name_bytes := bytes.slice(at + 46, at + 46 + name_length)
		for byte: int in name_bytes:
			if byte < 32 or byte > 126:
				return {"error": "Имя файла ZIP должно быть безопасным ASCII-путём."}
		var name_value := name_bytes.get_string_from_utf8()
		if name_bytes != name_value.to_utf8_buffer() or not (path_valid(name_value) or name_value in DIRECTORIES and length == 0) or names.has(name_value):
			return {"error": "Опасный путь или повтор файла в ZIP."}
		if flags & 1 or method not in [0, 8] or bytes.decode_u16(at + 34) != 0 or ((bytes.decode_u32(at + 38) >> 16) & 0xf000) == 0xa000:
			return {"error": "Шифрование, ссылки и этот метод сжатия не поддерживаются."}
		total += length
		if total > LIMIT or length > LIMIT or name_value == "game.json" and length > JSON_LIMIT or name_value.get_extension() in ["ttf", "otf"] and length > FONT_LIMIT:
			return {"error": "Заявленный распакованный размер превышает лимит."}
		if local + 30 > int(bytes.decode_u32(end + 16)) or bytes.decode_u32(local) != 0x04034b50:
			return {"error": "Повреждён локальный заголовок ZIP."}
		var local_name := bytes.decode_u16(local + 26)
		var start := local + 30 + local_name + bytes.decode_u16(local + 28)
		if start + compressed > int(bytes.decode_u32(end + 16)) or bytes.slice(local + 30, local + 30 + local_name) != name_bytes or bytes.decode_u16(local + 8) != method or bytes.decode_u16(local + 6) != flags:
			return {"error": "Локальный заголовок ZIP не совпадает с каталогом."}
		names[name_value] = length
		at += 46 + name_length + extra_length + comment_length
	if at != end or not names.has("game.json"):
		return {"error": "Неверный каталог или нет описания игры."}
	return {"error": "", "files": names, "size": total}

static func read_zip(path: String, expected_hash: String = "") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LIMIT:
		return {"error": "Не удалось открыть пакет или он больше 64 МБ."}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if not expected_hash.is_empty() and (not hash_valid(expected_hash) or sha(bytes) != expected_hash):
		return {"error": "Хэш пакета не совпал."}
	var checked := preflight(bytes)
	if not str(checked.error).is_empty():
		return checked
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"error": "Не удалось открыть ZIP."}
	var files := {}
	for name_value: String in checked.files:
		if name_value in DIRECTORIES:
			continue
		var data := zip.read_file(name_value)
		if data.size() != int(checked.files[name_value]):
			zip.close()
			return {"error": "Реальный размер файла ZIP не совпал."}
		files[name_value] = data
	zip.close()
	var result := validate_files(files)
	if str(result.error).is_empty():
		result["files"] = files
		result["hash"] = sha(bytes)
	return result

static func write_zip(path: String, files: Dictionary) -> Dictionary:
	var validation := validate_files(files)
	if not str(validation.error).is_empty():
		return validation
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return {"error": "Не удалось создать пакет."}
	var names: Array = files.keys()
	names.sort()
	for name_value: String in names:
		if zip.start_file(name_value, 420, 315532800) != OK or zip.write_file(files[name_value]) != OK or zip.close_file() != OK:
			zip.close()
			return {"error": "Ошибка записи пакета."}
	zip.close()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LIMIT:
		return {"error": "Пакет не помещается в 64 МБ."}
	var bytes := file.get_buffer(file.get_length())
	return {"error": "", "hash": sha(bytes), "size": bytes.size()}
