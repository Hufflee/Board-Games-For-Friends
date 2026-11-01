extends SceneTree
## Библиотека автора и отдельный кэш. Запускать только со свежим APPDATA в build/.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
var count := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	count += 1
	if not ok:
		errors += 1
		push_error(text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Проверке библиотеки нужен отдельный APPDATA внутри build/.")
		quit(1)
		return
	check(Library.list().is_empty(), "Новый профиль имеет пустую библиотеку")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/card_race.json"))
	var made := Library.create(data)
	check(made.error.is_empty(), "Игра создана")
	if not made.error.is_empty():
		quit(1)
		return
	var id := str(made.id)
	check(Library.uuid_valid(id) and made.definition.game_version == 1, "Создан UUID и первая версия")
	var copy := Library.load_game(id)
	check(copy.meta.title == data.meta.title and copy.id == id, "Игра читается по безопасному id")
	var note := FileAccess.open(Library.folder(id) + "/history/моя_заметка.txt", FileAccess.WRITE)
	note.store_string("Не снимок приложения")
	note.close()
	for revision in 12:
		copy.meta.title = "Редакция %d" % revision
		var saved := Library.save(id, copy)
		check(saved.error.is_empty(), "Изменение сохраняется")
		if saved.error.is_empty():
			copy = saved.definition
	check(copy.game_version == 13 and Library.load_game(id).game_version == 13, "Версия растёт при каждом сохранении")
	check(DirAccess.get_files_at(Library.folder(id) + "/history").size() == 11 and FileAccess.file_exists(Library.folder(id) + "/history/моя_заметка.txt"), "Хранятся десять снимков, посторонний файл не удалён")
	check(Library.list().size() == 1 and Library.list()[0].id == "custom:" + id, "Запись для хаба содержит custom:id")
	var hub: GDScript = load("res://hub/games.gd")
	check(hub.all().size() == hub.LIST.size() + 1 and hub.by_id("custom:" + id).custom, "Хаб объединяет встроенные игры с библиотекой")
	var foreign := Library.uuid()
	check(hub.by_id("custom:" + foreign).get("scene") == "res://games/custom/ui/main.tscn" and Library.list().size() == 1, "Маршрут игры друга доступен без коробки на полке")
	check(Library.folder("../escape").is_empty() and Library.load_game("../escape").is_empty(), "Выход из папки по UUID запрещён")
	check(not Library.save("../escape", copy).error.is_empty(), "Нельзя сохранить по опасному id")
	var package := Library.build_package(id)
	check(package.error.is_empty(), "Пакет авторской игры собран")
	if package.error.is_empty():
		var second := Library.build_package(id)
		check(second.error.is_empty() and second.hash == package.hash, "Хэш пакета стабилен без изменений")
		var cached := Library.cached(package.hash)
		check(cached.error.is_empty() and cached.definition.id == id, "Кэш проверяет ZIP и описание")
		var bytes := FileAccess.get_file_as_bytes(package.path)
		var received := Library.put_cache(package.hash, bytes)
		check(received.error.is_empty(), "Полученный пакет проверен")
		check(Library.list().size() == 1, "Кэш не добавляет игру в библиотеку автора")
		check(not Library.put_cache("0".repeat(64), bytes).error.is_empty(), "Неверный хэш входящих данных запрещён")
		Library.prune_cache(package.hash, 0)
		check(FileAccess.file_exists(package.path), "Активный пакет не удаляется при очистке")
		Library.prune_cache("", 0)
		check(not FileAccess.file_exists(package.path), "Неактивный кэш очищается по лимиту")
	# Повреждённая незавершённая запись восстанавливается из предыдущего снимка.
	var broken := FileAccess.open(Library.folder(id) + "/game.json", FileAccess.WRITE)
	broken.store_string("обрыв")
	broken.close()
	check(Library.load_game(id).game_version == 12, "Повреждённый game.json читает предыдущую .bak")
	check(Library.build_package(id).error.is_empty(), "Из восстановленного определения можно собрать пакет")
	var duplicated := Library.duplicate_game(id)
	check(duplicated.error.is_empty() and duplicated.id != id and duplicated.definition.game_version == 1, "Копия получает новый UUID и собственную версию")
	if duplicated.error.is_empty():
		check(Library.list().size() == 2 and Library.load_game(duplicated.id).meta.title.ends_with(" · копия"), "Копия появилась отдельной игрой")
		check(Library.trash_game(duplicated.id).is_empty() and Library.list().size() == 1, "Проект убран с полки в локальную корзину")
		check(not DirAccess.get_directories_at("user://custom_games_trash").is_empty() and not Library.load_game(id).is_empty(), "Корзина сохраняет файлы, исходный проект не затронут")
	check(not Library.trash_game("../escape").is_empty() and not Library.duplicate_game("../escape").error.is_empty(), "Операции библиотеки отвергают опасный ID")
	print("CUSTOM_LIBRARY: %d проверок, ошибок %d" % [count, errors])
	quit(1 if errors else 0)
