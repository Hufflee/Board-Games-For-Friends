extends SceneTree
## Экспорт/импорт игры файлом .pgame: экспорт сохранённой игры с картинкой, импорт новой игрой с новым id,
## описание и ассеты совпадают; испорченный файл и файл не-пакет отвергаются.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_custom_pgame.gd
const Library := preload("res://games/custom/logic/cg_library.gd")
const Assets := preload("res://editor/ed_assets.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный APPDATA.")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	data.meta.title = "Экспорт"
	var created := Library.create(data)
	check(str(created.error).is_empty(), "Игра создана")
	var id := str(created.id)
	var imported: Dictionary = Assets.import_image(id, ProjectSettings.globalize_path("res://games/poker/art/card_back.png"))
	var game := Library.load_game(id)
	if not game.has("assets"):
		game["assets"] = {}
	game.assets[imported.hash] = imported.asset
	game.elements.decks[0]["back"] = imported.hash
	check(str(Library.save(id, game).error).is_empty(), "Игра с картинкой сохранена")
	var out := ProjectSettings.globalize_path("user://export_test")
	var result := Library.export_game(id, out)
	check(str(result.error).is_empty() and str(result.path).ends_with(".pgame") and FileAccess.file_exists(str(result.path)), "Экспорт .pgame: %s" % str(result.get("error", "")))
	var before := Library.list().size()
	var back := Library.import_game(str(result.path))
	check(str(back.error).is_empty(), "Импорт: %s" % str(back.get("error", "")))
	check(Library.list().size() == before + 1 and str(back.id) != id, "Импорт — новая игра с новым id")
	var copy := Library.load_game(str(back.id))
	check(copy.meta.title == "Экспорт" and copy.elements.decks[0].back == imported.hash, "Описание совпадает")
	check(FileAccess.file_exists(Library.folder(str(back.id)) + "/" + str(imported.asset.path)), "Картинка рубашки на месте")
	# Испорченный файл и не пакет.
	var broken := FileAccess.open(ProjectSettings.globalize_path("user://broken.pgame"), FileAccess.WRITE)
	broken.store_string("это не игра")
	broken.close()
	check(not str(Library.import_game(ProjectSettings.globalize_path("user://broken.pgame")).error).is_empty(), "Испорченный файл отвергнут")
	var bytes := FileAccess.get_file_as_bytes(str(result.path))
	bytes[bytes.size() / 2] = bytes[bytes.size() / 2] ^ 0xFF
	var damaged := FileAccess.open(ProjectSettings.globalize_path("user://damaged.pgame"), FileAccess.WRITE)
	damaged.store_buffer(bytes)
	damaged.close()
	var damaged_result := Library.import_game(ProjectSettings.globalize_path("user://damaged.pgame"))
	check(not str(damaged_result.error).is_empty() or Library.load_game(str(damaged_result.get("id", ""))).is_empty() == false, "Повреждённый пакет: ошибка или проверенная игра")
	check(Library.list().size() <= before + 2, "Мусорные файлы не создают игр")
	print("CUSTOM PGAME: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
