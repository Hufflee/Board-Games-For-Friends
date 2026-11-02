class_name EDAssets
extends RefCounted
## Импорт только байтов картинки/шрифта. Нормализация до2048 px, SHA-имена, нарезка листа.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")

static func _read(path: String, limit: int) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > limit:
		return PackedByteArray()
	return file.get_buffer(file.get_length())

static func _store(id: String, bytes: PackedByteArray, extension: String, source: String) -> Dictionary:
	if Library.load_game(id).is_empty():
		return {"error": "Сначала сохраните проект игры."}
	var hash_value := Package.sha(bytes)
	var sub := "assets/fonts" if extension in ["ttf", "otf"] else "assets/img"
	var relative := sub + "/" + hash_value + "." + extension
	var directory := Library.folder(id)
	var existing := 0
	for child: String in ["assets/img", "assets/fonts", "covers"]:
		if not DirAccess.dir_exists_absolute(directory + "/" + child):
			continue
		for name_value: String in DirAccess.get_files_at(directory + "/" + child):
			var file := FileAccess.open(directory + "/" + child + "/" + name_value, FileAccess.READ)
			if file:
				existing += file.get_length()
	if not FileAccess.file_exists(directory + "/" + relative):
		if existing + bytes.size() > Package.LIMIT - Package.JSON_LIMIT:
			return {"error": "В игре недостаточно места: предел пакета 64 МБ."}
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory + "/" + sub))
		var error := Library._atomic_write(directory + "/" + relative, bytes)
		if error != OK:
			return {"error": "Не удалось сохранить ассет."}
	return {"error": "", "hash": hash_value, "asset": {"path": relative, "source": source}}

static func import_image(id: String, path: String, source: String = "") -> Dictionary:
	var extension := path.get_extension().to_lower()
	if extension == "jpeg":
		extension = "jpg"
	if extension not in ["png", "jpg", "webp"]:
		return {"error": "Поддерживаются PNG, JPG и WebP."}
	var bytes := _read(path, Package.LIMIT)
	var dimensions := Package.image_size(bytes, extension)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 32768 or dimensions.y > 32768 or dimensions.x * dimensions.y > 16 * 1024 * 1024:
		return {"error": "Изображение повреждено или больше 16 миллионов пикселей."}
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match extension:
		"png": error = image.load_png_from_buffer(bytes)
		"jpg": error = image.load_jpg_from_buffer(bytes)
		"webp": error = image.load_webp_from_buffer(bytes)
	if error != OK or image.get_size() != dimensions:
		return {"error": "Не удалось декодировать изображение."}
	var resized := false
	if maxi(dimensions.x, dimensions.y) > 2048:
		var scale_value := 2048.0 / maxi(dimensions.x, dimensions.y)
		image.resize(maxi(1, roundi(dimensions.x * scale_value)), maxi(1, roundi(dimensions.y * scale_value)), Image.INTERPOLATE_LANCZOS)
		resized = true
	var result := _store(id, image.save_webp_to_buffer(false), "webp", source)
	result["resized"] = resized
	result["dimensions"] = [image.get_width(), image.get_height()]
	if str(result.get("error", "")).is_empty():
		result.asset["name"] = path.get_file()
	return result

static func import_font(id: String, path: String, source: String = "") -> Dictionary:
	var extension := path.get_extension().to_lower()
	if extension not in ["ttf", "otf"]:
		return {"error": "Поддерживаются TTF и OTF."}
	var bytes := _read(path, Package.FONT_LIMIT)
	if bytes.size() < 12 or bytes.slice(0, 4) not in [PackedByteArray([0, 1, 0, 0]), "OTTO".to_ascii_buffer()]:
		return {"error": "Шрифт повреждён или больше 10 МБ."}
	var font := FontFile.new()
	font.data = bytes
	if font.get_glyph_index(16, 0x0410, 0) == 0 or font.get_glyph_index(16, 0x044f, 0) == 0:
		return {"error": "В шрифте не найдены русские буквы А/я."}
	var result := _store(id, bytes, extension, source)
	if str(result.get("error", "")).is_empty():
		result.asset["name"] = path.get_file()
	return result

static func grid(id: String, asset: Dictionary, columns: int, rows: int, count: int) -> Dictionary:
	if columns < 1 or columns > 30 or rows < 1 or rows > 30 or count < 1 or count > 300 or count > columns * rows:
		return {"error": "Укажите сетку 1–30 и число карт 1–300 внутри неё."}
	var path := str(asset.get("path", ""))
	if not Package.path_valid(path) or not path.begins_with("assets/img/"):
		return {"error": "Не найден импортированный лист карт."}
	var bytes := _read(Library.folder(id) + "/" + path, Package.LIMIT)
	var image := Package.image_from_bytes(bytes, path.get_extension())
	if image == null or image.get_width() < columns or image.get_height() < rows:
		return {"error": "Лист слишком маленький для этой сетки."}
	var cards: Array = []
	var assets := {}
	var cell := Vector2i(image.get_width() / columns, image.get_height() / rows)
	for index in count:
		var cropped := image.get_region(Rect2i(Vector2i(index % columns, index / columns) * cell, cell))
		var result := _store(id, cropped.save_webp_to_buffer(false), "webp", str(asset.get("source", "")))
		if not str(result.error).is_empty():
			return result
		assets[result.hash] = result.asset
		cards.append({"title": "Карта %d" % (index + 1), "art": result.hash, "copies": 1})
	return {"error": "", "assets": assets, "rows": cards}
