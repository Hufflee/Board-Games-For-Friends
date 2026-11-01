extends SceneTree
## Документ/undo/черновики/CSV/импорт ассетов. Только свежий APPDATA внутри build/.

const Document := preload("res://editor/ed_document.gd")
const Csv := preload("res://editor/ed_csv.gd")
const Assets := preload("res://editor/ed_assets.gd")
const Library := preload("res://games/custom/logic/cg_library.gd")
const Elements := preload("res://editor/ed_elements.gd")
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
		push_error("Нужен APPDATA внутри build/.")
		quit(1)
		return
	var doc := Document.new()
	check(doc.create(), "Создан пустой проект")
	check(doc.issues().errors.is_empty() and doc.data.rules.chains.is_empty(), "Песочница без логики корректна")
	var id := str(doc.data.id)
	check(not doc.set_value(["id"], "другой"), "Команда не меняет идентификатор")
	check(doc.set_value(["meta", "title"], "Первая правка"), "Команда правит поле")
	check(doc.dirty and doc.undo(), "Отмена доступна")
	check(doc.data.meta.title == "Новая игра" and doc.redo(), "Отмена восстановила данные")
	check(doc.data.meta.title == "Первая правка", "Повтор вернул правку")
	for i in 205:
		doc.set_value(["meta", "description"], str(i))
	check(doc.undo_stack.size() == 200 and doc.redo_stack.is_empty(), "История ограничена200 командами")
	doc.undo()
	check(doc.set_value(["meta", "title"], "Новая ветка") and doc.redo_stack.is_empty(), "Новая команда удаляет ветку повтора")
	var deck := doc.add_deck()
	check(deck == "deck_1" and doc.data.elements.decks.size() == 1, "Колода добавлена одной отменяемой командой")
	var elements := Elements.new(doc)
	check(elements.add_column(0, "Сила", "number").is_empty() and doc.data.elements.decks[0].rows[0]["Сила"] == 0, "Числовое свойство добавляется с числовым значением")
	check(elements.add_column(0, "Активна", "bool").is_empty() and doc.data.elements.decks[0].rows[0]["Активна"] == false, "Флаг карты хранится логическим значением")
	check(not elements.add_column(0, "Сила", "text").is_empty() and not elements.add_column(0, "copies", "number").is_empty(), "Дубликаты и зарезервированная колонка запрещены")
	check(elements.remove_column(0, 2) and not doc.data.elements.decks[0].rows[0].has("Активна") and doc.undo(), "Удаление свойства и значений отменяется")
	check(elements.remove_row(0, 0) and doc.data.elements.decks[0].rows.is_empty() and doc.undo(), "Удаление карты отменяется вместе со свойствами")
	check(elements.change_column_type(0, 1, "text").is_empty(), "Тип свойства меняется явно")
	doc.set_value(["elements", "decks", 0, "rows", 0, "Сила"], "12.5")
	check(elements.change_column_type(0, 1, "number").is_empty() and doc.data.elements.decks[0].rows[0]["Сила"] == 12.5, "Число из CSV преобразуется без потери значения")
	elements.change_column_type(0, 1, "text")
	doc.set_value(["elements", "decks", 0, "rows", 0, "Сила"], "много")
	var before_conversion: Dictionary = doc.data.duplicate(true)
	check(not elements.change_column_type(0, 1, "number").is_empty() and doc.data == before_conversion, "Неверная конверсия не затирает исходные ячейки")
	doc.undo()
	check(elements.change_column_type(0, 1, "number").is_empty(), "После отмены неверного текста число снова преобразуется")
	check(doc.save() and not doc.dirty and not doc.draft, "Полноценный проект сохранён")
	var stable := Library.load_game(id)
	doc.set_value(["rules", "chains"], [{"event": {"type": "start"}, "blocks": [{"op": "move"}]}])
	check(not doc.issues().errors.is_empty(), "Незавершённый блок имеет ошибки гнёзд")
	check(doc.save() and doc.draft and not doc.dirty, "Незавершённая работа сохранена черновиком")
	check(Library.load_game(id) == stable, "Черновик не портит последнюю корректную игру")
	var loaded := Document.new()
	check(loaded.open(id) and loaded.draft and not loaded.issues().errors.is_empty(), "Черновик восстановлен при открытии")
	check(not Library.files_for(id).has("draft.json"), "Черновик не попадает друзьям в пакет")
	doc.undo()
	check(doc.save() and not doc.draft and not FileAccess.file_exists(Library.folder(id) + "/draft.json"), "Исправленный проект заменяет черновик")
	var table := Csv.parse("Название;Текст;Копий\r\n\"Карта;А\";\"Первая\nВторая \"\"строка\"\"\";2\r\nБ;Кратко;1\r\n", ";")
	check(table.error.is_empty() and table.rows.size() == 2, "CSV читает кавычки и перенос внутри ячейки")
	if table.error.is_empty():
		check(table.rows[0]["Название"] == "Карта;А" and table.rows[0].copies == 2 and table.rows[0]["Текст"].contains("\"строка\""), "Содержимое CSV не искажено")
	for text: String in ["А,А\n1,2", "А,Б\n1", "А\n\"не закрыта", "Копий\n0", "Копий\n301"]:
		check(not Csv.parse(text).error.is_empty(), "Неверный CSV отклоняется")
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color("4c638c"))
	DirAccess.make_dir_recursive_absolute("res://build/editor_stage4")
	image.save_png("res://build/editor_stage4/sheet.png")
	var asset := Assets.import_image(id, "res://build/editor_stage4/sheet.png", "Свой тестовый рисунок")
	check(asset.error.is_empty() and not asset.resized, "Картинка импортирована по хэшу")
	if asset.error.is_empty():
		var grid := Assets.grid(id, asset.asset, 4, 2, 7)
		check(grid.error.is_empty() and grid.rows.size() == 7, "Лист4×2 нарезан в7 карт")
		check(Assets.import_image(id, "res://build/editor_stage4/sheet.png").hash == asset.hash, "Одинаковый ассет не дублируется")
		check(not Library.files_for(id).has(str(asset.asset.path)), "Незарегистрированный импорт не попадает в пакет")
		var with_asset := doc.data.duplicate(true)
		with_asset["assets"] = {asset.hash: asset.asset}
		doc.replace(with_asset, "Добавить ассет")
		check(doc.save() and Library.files_for(id).has(str(asset.asset.path)), "Зарегистрированный ассет входит в пакет")
	check(not Assets.import_image(id, "res://project.godot").error.is_empty(), "Скрипт/проект не импортируется как картинка")
	image.resize(3000, 16)
	image.save_png("res://build/editor_stage4/wide.png")
	var resized := Assets.import_image(id, "res://build/editor_stage4/wide.png")
	check(resized.error.is_empty() and resized.resized and resized.dimensions[0] == 2048, "Большая картинка уменьшена до2048")
	var font := Assets.import_font(id, "res://hub/art/fonts/Exo2-Variable.ttf", "Exo2/OFL")
	check(font.error.is_empty(), "Свободный кириллический шрифт импортирован через FontFile.data")
	if font.error.is_empty():
		var with_font := doc.data.duplicate(true)
		with_font.assets[font.hash] = font.asset
		doc.replace(with_font, "Добавить шрифт")
		check(doc.save() and Library.files_for(id).has(str(font.asset.path)), "Зарегистрированный шрифт включён в пакет")
	check(Library.build_package(id).error.is_empty(), "Импортированные данные проходят проверку пакета")
	var audit := Document.new()
	check(audit.create() and audit.issues().warnings.is_empty(), "Начальная раскладка не перекрывается")
	audit.set_value(["layout", "screens", 0, "items", 0, "rect"], [288, 400, 704, 192])
	check(not audit.issues().warnings.is_empty(), "Перекрывающиеся зоны дают предупреждение")
	audit.undo()
	check(audit.issues().warnings.is_empty(), "После undo проверка раскладки обновилась")
	audit.set_value(["layout", "screens"], ["повреждённый экран"])
	check(audit.save() and audit.draft, "Повреждённый промежуточный документ сохранён отдельно")
	var recovered := Document.new()
	check(recovered.open(str(audit.data.id)) and not recovered.draft and recovered.last_error.contains("Черновик"), "Неверная структура черновика не роняет редактор")
	for mutation: Array in [[["rules", "phases"], [42]], [["rules", "roles"], ["ведущий"]], [["meta", "phase_titles"], []], [["box", "faces"], {"front": [{"kind": "text", "rect": [0, "нет", 20, 20]}]}]]:
		var broken := recovered.data.duplicate(true)
		var target: Dictionary = broken
		for key: String in mutation[0].slice(0, mutation[0].size() - 1):
			target = target[key]
		target[mutation[0].back()] = mutation[1]
		var path := Library.folder(str(broken.id)) + "/draft.json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(broken))
		file.close()
		check(recovered.open(str(broken.id)) and not recovered.draft, "Повреждённые фазы/роли/метаданные/грани не передаются UI")
	print("EDITOR_DOCUMENT: %d проверок, ошибок %d" % [count, errors])
	quit(1 if errors else 0)
