extends SceneTree
## Проверки границы пакетов: только данные, пути, хэши, заявленные размеры, безопасные картинки.

const Package := preload("res://games/custom/logic/cg_package.gd")
const OUT := "res://build/editor_package_tests"
var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var json := FileAccess.get_file_as_bytes("res://games/custom/examples/card_race.json")
	var image := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color("655080"))
	var png := image.save_png_to_buffer()
	var asset := "assets/img/" + Package.sha(png) + ".png"
	var files := {"game.json": json, asset: png, "covers/front.png": png}
	check(Package.validate_files(files).error.is_empty(), "Исходные JSON и PNG проходят проверку")
	var written := Package.write_zip(OUT + "/valid.zip", files)
	check(written.error.is_empty(), "Пакет записан")
	if written.error.is_empty():
		var read := Package.read_zip(OUT + "/valid.zip", written.hash)
		check(read.error.is_empty(), "Свой ZIP прошёл предварительную проверку: %s" % read.error)
		if read.error.is_empty():
			check(read.files == files, "Файлы совпадают после ZIP")
		check(not Package.read_zip(OUT + "/valid.zip", "0".repeat(64)).error.is_empty(), "Подмена хэша отклоняется")
	for path: String in ["../game.json", "/game.json", "C:/game.json", "assets/img/../evil.png", "assets\\img\\a.png", "game.gd", "game.tres", "game.tscn", "assets/fonts/test.ttf", "history/a.json", "game.json/evil", "GAME.JSON"]:
		check(not Package.path_valid(path), "Опасное имя отклоняется: %s" % path)
	var bad := files.duplicate()
	bad["game.gd"] = "quit()".to_utf8_buffer()
	check(not Package.validate_files(bad).error.is_empty(), "Исполняемый файл запрещён")
	bad = {"game.json": json, "assets/img/" + "0".repeat(64) + ".png": png}
	check(not Package.validate_files(bad).error.is_empty(), "Несовпадающий хэш ассета запрещён")
	bad = {"game.json": "[]".to_utf8_buffer()}
	check(not Package.validate_files(bad).error.is_empty(), "JSON-массив вместо игры запрещён")
	bad = {"game.json": " ".repeat(Package.JSON_LIMIT + 1).to_utf8_buffer()}
	check(not Package.validate_files(bad).error.is_empty(), "Большой JSON запрещён")
	var huge := png.duplicate()
	# Размер читается до декодирования/выделения пикселей.
	huge[16] = 127
	check(Package.image_from_bytes(huge, "png") == null, "Огромный заголовок PNG отклоняется до декодирования")
	check(Package.image_size(png, "png") == Vector2i(32, 24), "PNG-размер читается без декодирования")
	for extension: String in ["jpg", "webp"]:
		var bytes := image.save_jpg_to_buffer() if extension == "jpg" else image.save_webp_to_buffer()
		check(Package.image_size(bytes, extension) == Vector2i(32, 24), "Размер %s проверен" % extension)
		check(Package.image_from_bytes(bytes, extension) != null, "%s загружается из буфера" % extension)
	# Поддельный распакованный размер перехватывается до ZIPReader.read_file.
	var zip_bytes := FileAccess.get_file_as_bytes(OUT + "/valid.zip")
	for i in range(zip_bytes.size() - 46):
		if zip_bytes.decode_u32(i) == 0x02014b50:
			var bomb := zip_bytes.duplicate()
			bomb.encode_u32(i + 24, Package.LIMIT + 1)
			check(not Package.preflight(bomb).error.is_empty(), "ZIP-бомба по заявленному размеру отклоняется")
			var encrypted := zip_bytes.duplicate()
			encrypted.encode_u16(i + 8, 1)
			check(not Package.preflight(encrypted).error.is_empty(), "Зашифрованный ZIP отклоняется")
			var symlink := zip_bytes.duplicate()
			symlink.encode_u32(i + 38, 0xa1ff0000)
			check(not Package.preflight(symlink).error.is_empty(), "Символическая ссылка ZIP отклоняется")
			break
	var random := RandomNumberGenerator.new()
	random.seed = 17
	for length in range(0, 150):
		var garbage := PackedByteArray()
		garbage.resize(length)
		for i in length:
			garbage[i] = random.randi_range(0, 255)
		check(not Package.preflight(garbage).error.is_empty(), "Случайный мусор не принимается как ZIP")
	print("CUSTOM_PACKAGE: %d проверок, ошибок %d" % [count, errors])
	quit(1 if errors else 0)
