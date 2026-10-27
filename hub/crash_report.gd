extends CanvasLayer
## Отчёт о вылете: при запуске ставим отметку «игра запущена», при нормальном выходе снимаем.
## Если в прошлый раз игра закрылась аварийно (отметка осталась) — показываем окно с кнопками
## «Скопировать лог» и «Открыть папку с логами»: игрок сам отправляет лог разработчику.
## Diag сохраняет подробный журнал, стеки и доступные системные данные Windows в user://logs.
## Те же кнопки — в настройках (CrashReport.copy_log / open_folder). Создаёт Net.

const LOG_DIR := "user://logs"

var _crashed := false


func _ready() -> void:
	layer = 99
	_crashed = not Diag.previous_session.is_empty()
	if _crashed:
		_show.call_deferred()


## Лог прошлого запуска (самый свежий, кроме текущего godot.log); нет — текущий.
static func previous_log() -> String:
	if Diag.previous_session.has("log") and FileAccess.file_exists(str(Diag.previous_session.log)):
		return str(Diag.previous_session.log)
	var best := ""
	var best_t := -1
	var dir := DirAccess.open(LOG_DIR)
	if dir:
		for name in dir.get_files():
			if name.begins_with("godot") and name.ends_with(".log") and name != "godot.log":
				var t := FileAccess.get_modified_time(LOG_DIR + "/" + name)
				if t > best_t:
					best_t = t
					best = LOG_DIR + "/" + name
	return best if best != "" else LOG_DIR + "/godot.log"


## Скопировать единый отчёт нужного запуска: диагностика, Godot, событие Windows.
static func copy_log(path: String = "") -> bool:
	var selected_path := path if not path.is_empty() else str(Diag.session.get("log", ""))
	if not FileAccess.file_exists(selected_path):
		return false
	var text := Diag.report_text(selected_path)
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get() == text


static func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(LOG_DIR))


func _show() -> void:
	await get_tree().create_timer(1.0).timeout  # пусть сначала загрузится хаб
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = get_tree().root.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ConfirmPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1e1b2a")
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Предыдущий запуск не завершился штатно"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var text := Label.new()
	text.text = "Скопируйте лог и отправьте его разработчику\n(например, в личные сообщения), или откройте папку с логами и пришлите файл."
	text.add_theme_font_size_override("font_size", 15)
	text.modulate.a = 0.85
	col.add_child(text)
	var path := previous_log()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var copy := Button.new()
	copy.text = "Скопировать лог"
	copy.pressed.connect(func():
		copy.text = "Лог скопирован ✓" if copy_log(path) else "Лог не найден")
	row.add_child(copy)
	var folder := Button.new()
	folder.text = "Открыть папку с логами"
	folder.pressed.connect(open_folder)
	row.add_child(folder)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(root.queue_free)
	row.add_child(close)
	col.add_child(row)
	var file := Label.new()
	file.text = "Файл: " + path.get_file()
	file.add_theme_font_size_override("font_size", 12)
	file.modulate.a = 0.6
	col.add_child(file)
