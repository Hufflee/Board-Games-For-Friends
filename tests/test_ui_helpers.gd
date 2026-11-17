## Проверка общих текстовых функций. Запуск: --script res://tests/test_ui_helpers.gd.
extends SceneTree

const Contrast = preload("res://hub/ui_contrast.gd")
const Text = preload("res://hub/ui_text.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var numbers := [0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 112, -21]
	var forms := ["карт", "карта", "карты", "карты", "карт", "карт", "карт",
		"карт", "карта", "карты", "карт", "карта", "карт", "карт", "карта"]
	for i in numbers.size():
		var n: int = numbers[i]
		check(Text.plural(n, "карта", "карты", "карт") == "%d %s" % [n, forms[i]],
			"Склонение для %d" % n)
	check(Text.plural(1, "карту", "карты", "карт", false) == "карту", "Форма без числа")
	check(is_equal_approx(Contrast.ratio(Color.WHITE, Color.BLACK), 21.0), "Белый на чёрном")
	check(absf(Contrast.ratio(Color("c48a2c"), Color("eadcbc")) - 2.2) < 0.15, "Охра на кремовом")
	check(is_equal_approx(Contrast.ratio(Color(1, 1, 1, 0), Color.BLACK), 1.0), "Прозрачный текст")
	check(Contrast.pick(Color.BLACK, [Color("333333"), Color.WHITE]) == Color.WHITE, "Второй кандидат")
	check(Contrast.pick(Color.BLACK, [Color("333333"), Color("555555")]) == Color("555555"),
		"Лучший кандидат ниже порога")
	await _check_hover()
	print("Ошибок: %d" % _failures)
	quit(1 if _failures else 0)


func _check_hover() -> void:
	var title := Label.new()
	title.text = "Ник из двадцати четырёх букв"
	title.clip_text = true
	title.size.x = 30
	root.add_child(title)
	Text.full_on_hover(title)
	check(title.tooltip_text == title.text, "Подсказка показывает обрезанный ник")
	title.size.x = 600
	check(title.tooltip_text.is_empty(), "При достаточной ширине подсказки нет")
	title.size.x = 30
	title.text = "Новый длинный ник"
	await process_frame
	await process_frame
	check(title.tooltip_text == title.text, "После смены текста подсказка обновляется")
	title.queue_free()


func check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
