extends SceneTree
## Чтение истории и настоящего преобразователя Markdown→BBCode; без изменения файлов.
var checks := 0
var errors := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
func headers(source: String) -> Array[String]:
	var out: Array[String] = []
	for line in source.split("\n"):
		if line.begins_with("## "):
			out.append(line.substr(3).strip_edges())
	return out
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await process_frame
	var source := FileAccess.get_file_as_string("res://hub/whats_new.md")
	var old := FileAccess.get_file_as_string("res://backups/hub28/whats_new.md")
	check(headers(source) == headers(old), "Все версии/даты и их порядок сохранены относительно backup")
	var ui: Control = load("res://hub/whats_new.gd").new()
	root.add_child(ui)
	await process_frame
	var text: RichTextLabel = ui.find_children("*", "RichTextLabel", true, false)[0]
	var parsed := text.get_parsed_text()
	for title in headers(source):
		check(parsed.contains(title), "Разметка показывает версию: " + title)
	check(not parsed.contains("<!--") and not parsed.contains("ПОРЯДОК — ПО ВАЖНОСТИ"), "Служебный комментарий не отображается")
	check(not parsed.contains("**") and parsed.contains("Большая бродилка"), "Жирный Markdown преобразован без сырых звёздочек")
	check(parsed.contains("Как их открыть — догадайтесь сами"), "Намёк о секрете сохранён без инструкции")
	ui.queue_free()
	await process_frame
	print("WHATS NEW LOW28: проверок=", checks, " ошибок=", errors)
	await root.get_node("Sfx").request_quit(1 if errors else 0)
