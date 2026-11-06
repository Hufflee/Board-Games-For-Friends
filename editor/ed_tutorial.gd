extends RefCounted
## Вкладка «Обучение»: уроки-пошаговки, которые проверяют сам проект. Шаг засчитан, когда в игре есть
## нужное (переменная, кнопка, цепочка), — неважно, сделал его автор руками или кнопкой «Сделать за меня».
## Урок «Игра про слова» собирает «Объясни слово»: ходящий видит случайное слово и объясняет, остальные угадывают.
## Экран вкладки — editor/ed_tutorial_ui.gd (здесь только данные: проверяется headless без автозагрузок).

const WORDS := "words"
## id шага, вкладка для «Показать где» (0 Коробка, 1 Интерфейс, 2 Логика, 3 Элементы), заголовок, как сделать руками.
const STEPS := [
	["title", 0, "Назовите игру", "Вкладка «Коробка» → поле «Название» справа. Например: «Объясни слово». Это имя будет на коробке в шкафу."],
	["dictionary", 3, "Подключите словарь", "Вкладка «Элементы» → галочка «Словарь · 1000 слов» слева сверху. Теперь в логике можно брать случайное слово."],
	["word", 2, "Переменная для слова", "Вкладка «Логика» → «Переменные и роли» → добавьте переменную, тип «Текст», общая. Видимость — «Никому»: слово будет показывать подсказка, только ходящему."],
	["score", 3, "Очки игроков", "Вкладка «Элементы» → «Ресурсы» → «+ Ресурс». Ресурс — это число у каждого игрока: здесь очки за угаданные слова."],
	["buttons", 1, "Кнопки «Угадали!» и «Другое слово»", "Вкладка «Интерфейс» → «+ Кнопка» два раза. Назовите их справа: «Угадали!» и «Другое слово». Кнопка запускает цепочку «Нажата кнопка» в логике."],
	["turn", 2, "Новое слово в начале хода", "Вкладка «Логика» → «+ Событие» → «Начало хода». Добавьте «Установить переменную»: переменная «Слово», значение — Текст → «Случайное слово». Затем «Показать подсказку»: кому — «Сейчас ходит», сообщение — «Текст из переменной» → «Слово»."],
	["guessed", 2, "Очко за угаданное слово", "«+ Событие» → «Нажата кнопка» (кнопка «Угадали!», нажимает тот, кто ходит). Внутрь: «Изменить переменную» (Очки, +1) и «Передать ход»."],
	["win", 2, "Как закончить игру", "Добавьте событие «Начало раунда» и в нём «Если / иначе»: номер раунда больше 3 → «Итоги по очкам» (Очки). Или «Победа» внутри цепочки «Угадали!», когда очков 5."],
	["check", -1, "Проверьте игру", "Нажмите «Проверить» сверху справа: редактор запустит партию за всех. Если что-то мешает — откройте «Ошибки», рядом с каждой есть подсказка «i»."],
]

## Готов ли шаг — по данным проекта.
static func done(step: String, data: Dictionary) -> bool:
	var rules: Dictionary = data.get("rules", {})
	match step:
		"title":
			var title := str(data.get("meta", {}).get("title", "")).strip_edges()
			return not title.is_empty() and title != "Новая игра"
		"dictionary":
			return rules.get("dictionary", "") == "shared"
		"word":
			return not _var(data, "text", "").is_empty()
		"score":
			return not _var(data, "number", "player").is_empty()
		"buttons":
			return _buttons(data).size() >= 2
		"turn":
			for chain: Dictionary in rules.get("chains", []):
				if chain.get("event", {}).get("type") == "turn_start" and _has(chain.blocks, func(block: Dictionary): return block.get("op") == "set" and _uses(block.get("value"), "dictionary_word")) and _has(chain.blocks, func(block: Dictionary): return block.get("op") == "hint"):
					return true
			return false
		"guessed":
			for chain: Dictionary in rules.get("chains", []):
				if chain.get("event", {}).get("type") == "button" and _has(chain.blocks, func(block: Dictionary): return block.get("op") == "change"):
					return true
			return false
		"win":
			for chain: Dictionary in rules.get("chains", []):
				if _has(chain.get("blocks", []), func(block: Dictionary): return block.get("op") in ["win", "finish"]):
					return true
			return false
		"check":
			return false
	return false

## Номер первого несделанного шага; последний («Проверьте игру») — когда сборка готова.
static func current(data: Dictionary, errors: Array) -> int:
	for index in STEPS.size() - 1:
		if not done(str(STEPS[index][0]), data):
			return index
	# Все шаги сборки готовы — остаётся проверка игрой (errors показываются на этом шаге).
	return STEPS.size() - 1

## «Сделать за меня»: копия проекта с выполненным шагом. Существующее не ломает — только дополняет.
static func apply(step: String, source: Dictionary) -> Dictionary:
	var data: Dictionary = source.duplicate(true)
	var rules: Dictionary = data.rules
	if not rules.has("vars"):
		rules["vars"] = []
	if not rules.has("chains"):
		rules["chains"] = []
	match step:
		"title":
			data.meta.title = "Объясни слово"
		"dictionary":
			rules["dictionary"] = "shared"
		"word":
			if _var(data, "text", "").is_empty():
				rules.vars.append({"id": _free_id(rules.vars, "word"), "title": "Слово", "type": "text", "scope": "shared", "init": "", "visible": "none"})
		"score":
			if _var(data, "number", "player").is_empty():
				rules.vars.append({"id": _free_id(rules.vars, "score"), "title": "Очки", "type": "number", "scope": "player", "init": 0, "visible": "all"})
		"buttons":
			var items: Array = data.layout.screens[0].items
			var have := _buttons(data)
			for spec: Array in [["guessed", "Угадали!", 472], ["skip", "Другое слово", 712]]:
				if have.size() >= 2:
					break
				if have.has(spec[0]):
					continue
				items.append({"kind": "button", "id": spec[0], "action": spec[0], "title": spec[1], "visible": ["all"], "rect": [spec[2], 600, 216, 56]})
				have.append(spec[0])
		"turn":
			var word := _ensure(data, "word")
			data.rules.chains.append({"event": {"type": "turn_start", "by": "all"}, "blocks": _new_word(word)})
		"guessed":
			var score := _ensure(data, "score")
			var buttons := _ensure_buttons(data)
			data.rules.chains.append({"event": {"type": "button", "id": buttons[0], "by": "current"}, "blocks": [
				{"op": "change", "var": score, "value": 1, "player": {"op": "actor"}},
				{"op": "log", "text": "Слово угадано!"},
				{"op": "next"}]})
			if buttons.size() > 1 and not _button_chain(data, buttons[1]):
				data.rules.chains.append({"event": {"type": "button", "id": buttons[1], "by": "current"}, "blocks": _new_word(_ensure(data, "word"))})
		"win":
			var score := _ensure(data, "score")
			data.rules.chains.append({"event": {"type": "round_start", "by": "all"}, "blocks": [
				{"op": "if", "condition": {"op": "gt", "a": {"op": "round"}, "b": 3}, "then": [{"op": "finish", "var": score}]}]})
	return data

## Блоки «новое слово и подсказка ходящему».
static func _new_word(word: String) -> Array:
	return [{"op": "set", "var": word, "value": {"op": "dictionary_word"}, "player": {"op": "actor"}},
		{"op": "hint", "player": {"op": "current"}, "text": {"op": "var", "id": word, "player": {"op": "actor"}}}]

## Нужная переменная: найти подходящую или создать (вместе с предыдущими шагами, чтобы цепочка была корректной).
static func _ensure(data: Dictionary, kind: String) -> String:
	if kind == "word":
		data["rules"]["dictionary"] = "shared"
		if _var(data, "text", "").is_empty():
			data.merge(apply("word", data), true)
		return _var(data, "text", "")
	if _var(data, "number", "player").is_empty():
		data.merge(apply("score", data), true)
	return _var(data, "number", "player")

static func _ensure_buttons(data: Dictionary) -> Array:
	if _buttons(data).size() < 2:
		data.merge(apply("buttons", data), true)
	return _buttons(data)

static func _button_chain(data: Dictionary, id: String) -> bool:
	for chain: Dictionary in data.rules.get("chains", []):
		if chain.get("event", {}).get("type") == "button" and str(chain.event.get("id", "")) == id:
			return true
	return false

static func _var(data: Dictionary, type: String, scope: String) -> String:
	for entry: Dictionary in data.get("rules", {}).get("vars", []):
		if str(entry.get("type", "number")) == type and (scope.is_empty() or str(entry.get("scope", "shared")) == scope):
			return str(entry.id)
	return ""

static func _buttons(data: Dictionary) -> Array:
	var result: Array = []
	for screen: Dictionary in data.get("layout", {}).get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "button":
				result.append(str(item.get("action", item.get("id", ""))))
	return result

static func _free_id(entries: Array, base: String) -> String:
	var id := base
	var number := 2
	while entries.any(func(entry: Dictionary): return str(entry.get("id", "")) == id):
		id = "%s_%d" % [base, number]
		number += 1
	return id

## Есть ли блок, подходящий под условие, в цепочке (включая ветви и циклы).
static func _has(blocks: Variant, test: Callable) -> bool:
	if not blocks is Array:
		return false
	for block: Variant in blocks:
		if not block is Dictionary:
			continue
		if test.call(block):
			return true
		for nested: String in ["then", "else", "body"]:
			if _has(block.get(nested, []), test):
				return true
	return false

static func _uses(value: Variant, op: String) -> bool:
	if value is Dictionary:
		if value.get("op") == op:
			return true
		for entry: Variant in value.values():
			if _uses(entry, op):
				return true
	elif value is Array:
		for entry: Variant in value:
			if _uses(entry, op):
				return true
	return false
