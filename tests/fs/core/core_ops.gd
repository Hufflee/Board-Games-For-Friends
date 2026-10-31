extends RefCounted
## Таблица операций панели (fs_ops.gd) совпадает с тем, что исполняет сервер (match в fs_effects.gd).
const FSCheck = preload("res://tests/fs/fs_check.gd")
const Ops = preload("res://games/four_souls/logic/fs_ops.gd")

func run(t: FSCheck) -> void:
	var source := FileAccess.get_file_as_string("res://games/four_souls/logic/fs_effects.gd")
	var served := {}
	var regex := RegEx.create_from_string("(?m)^\\t\\t(\"\\w+\"(?:, \"\\w+\")*):")
	for found in regex.search_all(source):
		for name in found.get_string(1).split(", "):
			served[name.trim_prefix("\"").trim_suffix("\"")] = true
	var listed := {}
	for entry: Array in Ops.MAIN + Ops.EXTRA:
		t.check(not listed.has(entry[0]), "Операция %s в таблице один раз" % entry[0])
		listed[entry[0]] = true
		t.check(served.has(entry[0]), "Операция панели %s исполняется сервером" % entry[0])
		t.check(entry.size() == 3 and entry[2] is Dictionary, "У операции %s описаны поля" % entry[0])
	for name in served:
		t.check(listed.has(name), "Серверная операция %s есть в панели" % name)
