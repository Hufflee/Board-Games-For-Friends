extends SceneTree
## Собирает только локальный QA PCK: настоящий export-pack + тестовая главная сцена.
var failed := false

func _init() -> void:
	var base := OS.get_environment("WS_BASE_PACK")
	var destination := OS.get_environment("WS_QA_PACK")
	var settings_file := destination.get_base_dir().path_join("qa-project.binary")
	if not ProjectSettings.load_resource_pack(base, true):
		push_error("Не удалось смонтировать исходныйPCK")
		quit(1)
		return
	var original := FileAccess.open("res://project.binary", FileAccess.READ)
	if original == null or original.get_buffer(4).get_string_from_ascii() != "ECFG":
		push_error("Невалидный project.binary исходногоPCK")
		quit(1)
		return
	print("QA PREFLIGHT: исходный project.binary ECFG")
	var files := walk("res://")
	print("QA base files=", files.size())
	ProjectSettings.set_setting("application/run/main_scene", "res://tests/fixtures/ws_release_qa28.tscn")
	if ProjectSettings.save_custom(settings_file) != OK:
		quit(1)
		return
	var packer := PCKPacker.new()
	if packer.pck_start(destination) != OK:
		quit(1)
		return
	for path: String in files:
		if path != "res://project.binary":
			if packer.add_file(path, path) != OK:
				failed = true
	for path in ["tests/fixtures/ws_release_qa28.gd", "tests/fixtures/ws_release_qa28.tscn"]:
		if packer.add_file("res://" + path, OS.get_environment("WS_SOURCE_ROOT").path_join(path)) != OK:
			failed = true
	if packer.add_file("res://project.binary", settings_file) != OK:
		failed = true
	if packer.flush() != OK:
		failed = true
	print("QA PACK: ", destination, " failed=", failed)
	quit(1 if failed else 0)

func walk(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	directory.include_hidden = true
	for filename in directory.get_files():
		result.append(path.path_join(filename))
	for dirname in directory.get_directories():
		if dirname in ["build", "backups", ".git"]:
			continue
		result.append_array(walk(path.path_join(dirname)))
	return result
