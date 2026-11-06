extends SceneTree
## Урок «Игра про слова»: шаги засчитываются по проекту, «Сделать за меня» даёт корректную игру
## в любом порядке, собранная игра играется: слово видит только ходящий, «Угадали!» даёт очко, игра заканчивается.
## Запуск: APPDATA=<папка в build> godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_tutorial.gd
const Document := preload("res://editor/ed_document.gd")
const Tutorial := preload("res://editor/ed_tutorial.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Rules := preload("res://games/custom/logic/cg_rules.gd")
var checks := 0
var errors := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _press(r: RefCounted, seat: int, id: String) -> bool:
	return r.act(seat, "button", {"id": id, "revision": r.state.revision})

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	var doc := Document.new()
	check(doc.create("blank"), "Пустой проект")
	check(Tutorial.current(doc.data, []) == 0, "Урок начинается с первого шага")
	for index in Tutorial.STEPS.size() - 1:
		var id := str(Tutorial.STEPS[index][0])
		check(not Tutorial.done(id, doc.data), "Шаг «%s» не засчитан заранее" % id)
		check(doc.replace(Tutorial.apply(id, doc.data), "Урок"), "Шаг «%s» выполнен" % id)
		check(Tutorial.done(id, doc.data), "Шаг «%s» засчитан" % id)
		check(doc.issues().errors.is_empty(), "После шага «%s» нет ошибок: %s" % [id, str(doc.issues().errors)])
	check(Tutorial.current(doc.data, []) == Tutorial.STEPS.size() - 1, "Остался шаг «Проверьте игру»")
	var again: Dictionary = Tutorial.apply("buttons", doc.data)
	check(Tutorial._buttons(again).size() == 2, "Повторное «Сделать за меня» не плодит кнопки")

	# Вразнобой: «Очко за угаданное» на пустом проекте само подтягивает переменные и кнопки.
	var jump := Document.new()
	jump.create("blank")
	jump.replace(Tutorial.apply("guessed", jump.data), "Сразу шаг 7")
	check(jump.issues().errors.is_empty(), "Шаг 7 на пустом проекте даёт корректную игру: %s" % str(jump.issues().errors))
	check(Tutorial.done("score", jump.data) and Tutorial.done("buttons", jump.data), "Нужные очки и кнопки созданы")

	# Партия собранной игры.
	var r := Rules.new()
	check(r.load_definition(doc.data).is_empty(), "Игра из урока загружается")
	check(r.new_game([{"name": "А", "team": 0}, {"name": "Б", "team": 1}, {"name": "В", "team": 0}], {"seed": 5}).is_empty(), "Партия на троих: %s" % r.last_error)
	var current := int(r.state.current)
	var word := str(r.get_var("word", 0))
	check(not word.is_empty(), "В начале хода выбрано слово")
	var mine: Array = r.get_view(current).hints
	var other: Array = r.get_view((current + 1) % 3).hints
	check(mine.has(word), "Ходящий видит слово подсказкой")
	check(not other.has(word), "Остальные слово не видят")
	check(not str(r.get_view((current + 1) % 3).vars).contains(word), "Слово не утекает через переменные")
	check(not _press(r, (current + 1) % 3, "guessed"), "Не ходящий не может нажать «Угадали!»")
	check(_press(r, current, "skip"), "«Другое слово» работает")
	check(int(r.state.current) == current, "Пропуск слова не передаёт ход")
	check(_press(r, current, "guessed"), "«Угадали!» нажато")
	check(int(r.get_var("score", current)) == 1, "Ходящий получил очко")
	check(int(r.state.current) != current, "Ход перешёл дальше")
	var guard := 0
	while r.phase != "game_over" and guard < 40:
		check(_press(r, int(r.state.current), "guessed"), "Ход %d: угадали" % guard)
		guard += 1
	check(r.phase == "game_over" and not r.state.winners.is_empty(), "После трёх кругов игра заканчивается итогами по очкам")

	print("EDITOR TUTORIAL: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors > 0 else 0)
