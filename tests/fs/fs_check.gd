extends RefCounted
## Четыре души, тесты: счётчик проверок для раннера tests/fs/run.gd.
## Каждая проверка с текстом на русском; ошибки копятся с префиксом текущего теста.

var checks := 0
var errors: Array[String] = []
var prefix := ""

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		errors.append((prefix + ": " if prefix != "" else "") + message)
	return ok

func equal(actual, expected, message: String) -> bool:
	return check(_same(actual, expected), "%s — ожидалось %s, получено %s" % [message, str(expected), str(actual)])

static func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return a == b
