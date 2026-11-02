extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Комментарии цепочек: редактирование одной командой, fold/undo/буфер, сохранение и неизменность правил.
const Definition := preload("res://games/custom/logic/cg_def.gd")
const Rules := preload("res://games/custom/logic/cg_rules.gd")
const Document := preload("res://editor/ed_document.gd")

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var folder := "res://build/shots/editor_comments/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for theme: String in ["dark", "light"]:
		root.get_node("Prefs").set_value("theme_mode", theme)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		check(app.document.create("card_race"), "Создан проект с цепочками")
		app._editing = true
		app._tab = 2
		app._logic_chain = 0
		app._logic_path = []
		app._render()
		await frames(6)
		var initial: Dictionary = app.document.data.duplicate(true)
		var edit: TextEdit = app.find_child("LogicCommentEditor", true, false)
		check(is_instance_valid(edit) and button("Сохранить комментарий").disabled, "У события есть пустой редактор без лишней команды сохранения")
		var history: int = app.document.undo_stack.size()
		var message := "Подготовка: раздать каждому игроку стартовую руку.\nПроверить скрытость карт соперника."
		edit.text = message
		edit.text_changed.emit()
		check(JSON.stringify(app.document.data) == JSON.stringify(initial), "Набор текста не меняет правила до сохранения")
		await click(button("Сохранить комментарий"))
		check(app.document.data.rules.chains[0].comment == message and app.document.undo_stack.size() == history + 1, "Комментарий записан одной командой")
		var note: Control = app.find_child("LogicComment0", true, false)
		check(is_instance_valid(note) and note.is_visible_in_tree(), "На холсте появилась заметка события")
		var fold: Button = app.find_child("LogicFold0", true, false)
		await click(fold)
		check(app.find_child("LogicComment0", true, false) != null, "Свёрнутая цепочка сохраняет комментарий")
		root.get_texture().get_image().save_png(folder + theme + ".png")
		app.document.undo()
		app._render()
		await frames()
		check(not app.document.data.rules.chains[0].has("comment"), "Отмена удалила новое поле комментария")
		app.document.redo()
		app._render()
		await frames()
		check(app.document.data.rules.chains[0].comment == message, "Повтор вернул комментарий")
		check(app.document.save(), "Проект с заметкой сохранён")
		var restored := Document.new()
		check(restored.open(str(app.document.data.id)) and restored.data.rules.chains[0].comment == message, "Повторное открытие сохраняет заметку")
		var encoded := Clipboard.encode(app.document, "chain", app.document.data.rules.chains[0])
		var decoded := Clipboard.decode(encoded)
		check(not decoded.is_empty() and Clipboard.paste(restored, decoded, "chain", ["rules", "chains"]).is_empty() and restored.data.rules.chains.back().comment == message, "Буфер переносит комментарий вместе с цепочкой")
		var base := Rules.new()
		var annotated := Rules.new()
		var players: Array = [{"name": "А"}, {"name": "Б"}]
		check(base.load_definition(initial).is_empty() and annotated.load_definition(app.document.data).is_empty(), "Оба варианта правил загружены")
		check(base.new_game(players, {"seed": 97}).is_empty() and annotated.new_game(players, {"seed": 97}).is_empty() and JSON.stringify(base.state) == JSON.stringify(annotated.state), "Комментарий не меняет исполнение и начальный RNG")
		var invalid: Dictionary = initial.duplicate(true)
		invalid.rules.chains[0]["comment"] = {"op": "next"}
		check(not Definition.validate(invalid).errors.is_empty(), "Исполняемый объект не принимается как комментарий")
		edit = app.find_child("LogicCommentEditor", true, false)
		edit.text = "я".repeat(4097)
		edit.text_changed.emit()
		check(button("Сохранить комментарий").disabled, "Лимит текста не позволяет записать лишнее")
		edit.text = ""
		edit.text_changed.emit()
		await click(button("Сохранить комментарий"))
		check(not app.document.data.rules.chains[0].has("comment") and app.find_child("LogicComment0", true, false) == null, "Очистка удаляет заметку и поле из данных")
		app.queue_free()
		await frames()
	print("EDITOR COMMENTS UI: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
