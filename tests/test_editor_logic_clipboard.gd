extends SceneTree
## Буфер цепочек/блоков: ветви, новыеID, ссылки, undo и безопасная вставка между проектами.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_editor_logic_clipboard.gd
const Document := preload("res://editor/ed_document.gd")
const Model := preload("res://editor/ed_logic_model.gd")
const Clipboard := preload("res://editor/ed_clipboard.gd")
var checks := 0
var errors := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _ids(blocks: Array) -> Array:
	var result: Array = []
	for block: Dictionary in blocks:
		result.append(str(block.get("id", "")))
		for branch: String in ["then", "else", "body"]:
			if block.get(branch) is Array:
				result.append_array(_ids(block[branch]))
	return result

func _payload(doc: RefCounted, kind: String, value: Dictionary) -> Dictionary:
	return Clipboard.decode(Clipboard.encode(doc, kind, value))

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	var doc := Document.new()
	check(doc.create(), "Создан отдельный проект")
	var model := Model.new(doc)
	model.add_event("start")
	var root_path: Array = ["rules", "chains", 0, "blocks"]
	var condition: Array = model.add_block("if", root_path)
	var repeat: Array = model.add_block("repeat", condition + ["then"])
	var log_path: Array = model.add_block("log", repeat + ["body"])
	model.add_block("set", root_path)
	doc.set_value(log_path + ["text"], {"op": "var", "id": "score", "player": {"op": "actor"}})
	var original: Dictionary = doc.data.rules.chains[0].duplicate(true)
	var chain_payload := _payload(doc, "chain", original)
	var before := JSON.stringify(doc.data)
	check(Clipboard.paste(doc, chain_payload, "chain", ["rules", "chains"]).is_empty(), "Вставлена вся цепочка")
	check(doc.data.rules.chains.size() == 2, "Вставка добавила событие")
	var pasted: Dictionary = doc.data.rules.chains[1]
	check(_ids(original.blocks).all(func(id): return id not in _ids(pasted.blocks)), "Каждый вложенный блок получил новый идентификатор")
	var new_ids := _ids(pasted.blocks)
	var unique_ids := {}
	for id: String in new_ids:
		unique_ids[id] = true
	check(new_ids.size() == 4 and new_ids.size() == unique_ids.size(), "Новые идентификаторы не совпадают друг с другом")
	check(pasted.blocks[0].then[0].body[0].text.id == "score", "Идентификатор переменной в выражении не переименован")
	check(doc.undo() and JSON.stringify(doc.data) == before, "Цепочка отменяется одной командой")
	check(doc.redo() and _ids(doc.data.rules.chains[1].blocks) == new_ids, "Повтор сохраняет идентификаторы вставки")
	var block_payload := _payload(doc, "block", original.blocks[0])
	var destination: Array = root_path + [0, "else"]
	check(Clipboard.paste(doc, block_payload, "block", destination).is_empty(), "Вставлен блок с вложенными ветвями в выбранную ветвь")
	check(doc.data.rules.chains[0].blocks[0].else.size() == 1, "Блок попал в ветвь, а не рядом с родителем")
	doc.set_value(destination + [0, "then", 0, "body", 0, "text"], "Другая надпись")
	check(doc.data.rules.chains[0].blocks[0].then[0].body[0].text is Dictionary, "Правка копии не меняет исходную ветвь")
	before = JSON.stringify(doc.data)
	check(not Clipboard.paste(doc, block_payload, "block", ["rules", "vars"]).is_empty(), "Блок не вставляется в таблицу переменных")
	check(JSON.stringify(doc.data) == before, "Неподходящий путь не меняет проект")
	var target := Document.new()
	check(target.create(), "Создан проект назначения")
	before = JSON.stringify(target.data)
	check(not Clipboard.paste(target, chain_payload, "chain", ["rules", "chains"]).is_empty(), "Отсутствующая переменная явно отклонена")
	check(JSON.stringify(target.data) == before, "Отказ не добавляет частичную цепочку")
	target.set_value(["rules", "vars"], doc.data.rules.vars.duplicate(true))
	check(Clipboard.paste(target, chain_payload, "chain", ["rules", "chains"]).is_empty(), "Совместимые ссылки допускают вставку между проектами")
	var bad_zone := _payload(doc, "block", {"op": "shuffle", "zone": {"op": "zone", "id": "нет_зоны"}})
	check(not Clipboard.paste(target, bad_zone, "block", root_path).is_empty(), "Неизвестная зона отклонена до вставки")
	var dictionary := _payload(doc, "block", {"op": "log", "text": {"op": "dictionary_word"}})
	for block: Dictionary in [
		{"op": "shuffle", "zone": "нет_зоны"},
		{"op": "draw", "from": "нет_зоны", "to": "table", "count": 1},
		{"op": "deal", "from": "draw", "to": "нет_зоны", "count": 1},
		{"op": "move", "card": {"op": "card"}, "to": "нет_зоны"},
		{"op": "collect", "to": "нет_зоны"},
		{"op": "ask_card", "player": {"op": "actor"}, "zone": "нет_зоны"},
		{"op": "each_card", "zone": "нет_зоны", "body": []},
		{"op": "log", "text": {"op": "count", "zone": "нет_зоны"}},
		{"op": "open", "card": {"op": "top", "zone": "нет_зоны"}},
		{"op": "shuffle", "zone": {"op": "literal", "value": "нет_зоны"}},
		{"op": "if", "condition": true, "then": [{"op": "shuffle", "zone": "нет_зоны"}]},
	]:
		before = JSON.stringify(target.data)
		var invalid_zone := _payload(doc, "block", block)
		check(not Clipboard.paste(target, invalid_zone, "block", root_path).is_empty(), "Строковая зона отклонена: " + str(block.op))
		check(JSON.stringify(target.data) == before, "Недостающая зона не оставляет частичной вставки")
	var valid_zone := _payload(doc, "block", {"op": "shuffle", "zone": "draw"})
	check(Clipboard.paste(target, valid_zone, "block", root_path).is_empty(), "Объявленная строковая зона допускает вставку")
	var event_zone := _payload(doc, "chain", {"event": {"type": "card", "zone": "нет_зоны"}, "blocks": []})
	before = JSON.stringify(target.data)
	check(not Clipboard.paste(target, event_zone, "chain", ["rules", "chains"]).is_empty(), "Отсутствующая зона шапки события отклонена")
	check(JSON.stringify(target.data) == before, "Отказ шапки события не меняет документ")
	var invalid_definition: Dictionary = target.data.duplicate(true)
	invalid_definition.rules.chains[0].blocks.append({"op": "move", "card": {"op": "card"}, "to": "нет_зоны"})
	check(not preload("res://games/custom/logic/cg_def.gd").validate(invalid_definition).errors.is_empty(), "Прямое определение игры также отклоняет отсутствующую строковую зону")
	var text_literal := _payload(doc, "block", {"op": "log", "text": {"op": "literal", "value": {"op": "zone", "id": "просто_текст"}}})
	check(Clipboard.paste(target, text_literal, "block", root_path).is_empty(), "Буквальный текст не становится ссылкой на зону")
	check(not Clipboard.paste(target, dictionary, "block", root_path).is_empty(), "Словарь сначала требуется подключить")
	target.set_value(["rules", "dictionary"], "shared")
	check(Clipboard.paste(target, dictionary, "block", root_path).is_empty(), "Подключённый словарь допускает вставку выражения")
	var invalid := _payload(doc, "block", {"op": "нет_операции"})
	before = JSON.stringify(target.data)
	check(not Clipboard.paste(target, invalid, "block", root_path).is_empty(), "Неизвестный исполняемый блок отклонён")
	check(JSON.stringify(target.data) == before, "Ошибка схемы не меняет документ")
	check(doc.issues().errors.is_empty() and target.issues().errors.is_empty(), "Оба документа остаются корректными")
	print("EDITOR LOGIC CLIPBOARD: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
