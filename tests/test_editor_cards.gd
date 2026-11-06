extends SceneTree
## Карты редактора: горизонтальные размеры, «Цвет карт», рамки, одиночная карта и точные ошибки с подсказками.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_cards.gd
const Document := preload("res://editor/ed_document.gd")
const Faces := preload("res://games/custom/logic/cg_faces.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Issues := preload("res://editor/ed_issues.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _has(report: Array, parts: Array) -> bool:
	for text: String in report:
		if parts.all(func(part: String): return text.contains(part)):
			return true
	return false

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	check(Definition.CARD_SIZES.size() == 12, "Двенадцать размеров карт")
	for index in [9, 10, 11]:
		var size: Vector2i = Definition.CARD_SIZES[index]
		check(size.x > size.y, "Размер %d — горизонтальный" % (index + 1))
	check(Definition.CARD_SIZES[9].x < Definition.CARD_SIZES[10].x and Definition.CARD_SIZES[10].x < Definition.CARD_SIZES[11].x, "Маленькая < стандарт < большая")

	var doc := Document.new()
	check(doc.create(), "Пустой проект создан")
	doc.add_deck()
	doc.add_deck(true)
	var single: Dictionary = doc.data.elements.decks[1]
	check(single.get("single", false) and single.rows.size() == 1 and single.zone == "table", "Одиночная карта: одна строка, лежит на столе")
	check(doc.issues().errors.is_empty(), "Колода и одиночная карта без ошибок: %s" % str(doc.issues().errors))
	check(doc.set_value(["elements", "decks", 0, "size"], 11, "Размер"), "Горизонтальный стандарт выбран")
	check(Faces.dimensions(doc.data.elements.decks[0])[0] > Faces.dimensions(doc.data.elements.decks[0])[1], "Холст лица горизонтальный")

	# Цвет карт: бумага простого вида и фон-слой.
	check(doc.set_value(["elements", "decks", 0, "color"], "#335577", "Цвет"), "Цвет карт задан")
	var deck: Dictionary = doc.data.elements.decks[0]
	check(Faces.fields(deck.rows[0], deck).paper == "#335577", "Простой вид получает цвет бумаги")
	var copy: Dictionary = doc.data.duplicate(true)
	copy.elements.decks[0]["face"] = {"layers": Faces.default_layers(copy.elements.decks[0])}
	copy.elements.decks[0].face.layers.append({"kind": "frame", "title": "Рамка", "rect": [24, 24, 300, 200], "color": "#30263f", "fill": "#aa3322", "border": 16, "radius": 24})
	check(doc.replace(copy, "Слои") and doc.issues().errors.is_empty(), "Рамка с заливкой — допустимый слой: %s" % str(doc.issues().errors))
	deck = doc.data.elements.decks[0]
	check(deck.face.layers[0].get("role") == "card", "Фон новых слоёв помечен как цвет карты")
	check(doc.set_value(["elements", "decks", 0, "color"], "#118844", "Цвет"), "Цвет карт сменён")
	deck = doc.data.elements.decks[0]
	var fields: Dictionary = Faces.fields(deck.rows[0], deck)
	check(fields.layers[0].color == "#118844", "Фон-слой красится цветом колоды")
	check(fields.layers.back().fill == "#aa3322", "Заливка внутри рамки своя")
	var legacy := {"kind": "fill", "title": "Фон", "rect": [0, 0, 10, 10], "color": "#ded7c8", "locked": true}
	check(Faces.is_card_background(legacy, 0) and not Faces.is_card_background(legacy, 1), "Старый закреплённый «Фон» внизу тоже считается цветом карты")
	check(not Definition.box_valid({"faces": {"front": [{"kind": "frame", "rect": [0, 0, 10, 10]}]}}), "Рамки только на картах, не на коробке")

	# Колонка-цвет: у каждой карты свой цвет внутри рамки.
	var elements = load("res://editor/ed_elements.gd").new(doc)
	check(elements.add_column(0, "масть", "color") == "", "Колонка-цвет добавлена")
	check(doc.data.elements.decks[0].rows[0]["масть"] == "#ffffff", "Новая ячейка цвета — белая")
	doc.set_value(["elements", "decks", 0, "rows", 0, "масть"], "#cc2244", "Цвет карты")
	var frame_index: int = doc.data.elements.decks[0].face.layers.size() - 1
	doc.set_value(["elements", "decks", 0, "face", "layers", frame_index, "fill_field"], "масть", "Цвет внутри")
	deck = doc.data.elements.decks[0]
	check(doc.issues().errors.is_empty(), "Привязка заливки к колонке-цвету допустима: %s" % str(doc.issues().errors))
	check(Faces.fields(deck.rows[0], deck).layers[frame_index].fill == "#cc2244", "Внутри рамки — цвет этой карты")
	check(elements.add_column(0, "имя", "text") == "", "Текстовая колонка добавлена")
	doc.set_value(["elements", "decks", 0, "face", "layers", frame_index, "color_field"], "имя", "Неверная привязка")
	check(_has(doc.issues().errors, ["«имя»", "не колонка-цвет"]), "Цвет из текстовой колонки — ошибка с названием колонки")
	doc.undo()
	doc.set_value(["elements", "decks", 0, "rows", 0, "имя"], "синий", "Текст")
	check(elements.change_column_type(0, doc.data.elements.decks[0].columns.size() - 1, "color") != "", "Текст «синий» не превращается в цвет молча")
	check(elements.change_column_type(0, doc.data.elements.decks[0].columns.size() - 2, "text") == "", "Цвет можно сделать текстом")
	check(str(doc.data.elements.decks[0].face.layers[frame_index].get("fill_field", "")) == "", "Смена типа снимает привязку цвета")
	doc.undo()

	# Неверные значения — сообщения с местом и подсказкой.
	check(doc.set_value(["elements", "decks", 0, "color"], "не цвет", "Цвет"), "Неверный цвет записан")
	var report: Array = doc.issues().errors
	check(_has(report, ["Колода «Новая колода»", "цвет"]), "Ошибка цвета называет колоду: %s" % str(report))
	doc.undo()
	copy = doc.data.duplicate(true)
	copy.elements.decks[0].face.layers.append({"kind": "text", "title": "Цена", "field": "price", "rect": [0, 0, 10, 10]})
	doc.replace(copy, "Слой без колонки")
	report = doc.issues().errors
	check(_has(report, ["Колода «Новая колода»", "слой «Цена»", "«price»"]), "Ошибка привязки называет колоду, слой и колонку: %s" % str(report))
	check(Issues.explain(str(report[0])).tab == 3, "Подсказка ведёт во вкладку «Элементы»")
	doc.undo()

	copy = doc.data.duplicate(true)
	copy.rules.chains.append({"event": {"type": "start"}, "blocks": [{"op": "set", "var": "", "value": 0}, {"op": "phase", "phase": "nope"}]})
	doc.replace(copy, "Пустая переменная")
	report = doc.issues().errors
	check(_has(report, ["цепочка №1", "«Установить переменную»", "не выбрана переменная"]), "Пустая переменная названа с цепочкой и блоком: %s" % str(report))
	check(_has(report, ["«Перейти к фазе»", "«nope»"]), "Неизвестная фаза названа")
	for text: String in report:
		var info: Dictionary = Issues.explain(text)
		check(info.tab == 2 and not str(info.hint).is_empty(), "У ошибки логики есть подсказка и вкладка «Логика»: " + text)
	check(Issues.place(str(report[0]), doc.data).chain == 0, "Переход из ошибки выбирает цепочку №1")
	check(Issues.place("Карта «Карта»: неверный цвет", doc.data).deck == 1, "Переход из ошибки выбирает карту по названию")
	check(Issues.explain("что-то совсем непонятное").tab == -1, "Неизвестная ошибка — общая подсказка без вкладки")

	print("EDITOR CARDS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
