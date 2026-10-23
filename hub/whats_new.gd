extends Control
## Окно «Что нового?» в хабе: список изменений по версиям из hub/whats_new.md — только главное, по версиям (сверху — самое новое). Полный список правок — docs/PATCHNOTES.md.
## Файл попадает в сборку (include_filter в export_presets.cfg). Открывается кнопкой рядом с «Настройками».

const FILE := "res://hub/whats_new.md"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := HubStyle.panel(HubStyle.CYAN)
	center.add_child(panel)
	var col := HubStyle.vbox(16)
	panel.add_child(col)
	var head := HubStyle.hbox(16)
	var title := HubStyle.neon_label("Что нового?", 30, HubStyle.CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var ver := HubStyle.label("Сейчас: версия " + version(), 14, HubStyle.MUTED)
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ver)
	col.add_child(head)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = true
	text.custom_minimum_size = Vector2(760, 480)
	text.add_theme_font_override("normal_font", HubStyle.font("regular"))
	text.add_theme_font_override("bold_font", HubStyle.font("bold"))
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_color_override("default_color", HubStyle.TEXT)
	text.text = _bbcode(_read())
	col.add_child(text)
	var close := HubStyle.primary("Понятно", 16, 160)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	col.add_child(close)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


## Версия игры (application/config/version в project.godot).
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


func _read() -> String:
	var f := FileAccess.open(FILE, FileAccess.READ)
	return f.get_as_text() if f else "## Список изменений не найден"


## Простая разметка патчноута → BBCode: «## » версия, «### » раздел, «- » пункт, **жирный**; <!-- --> и «# » пропускаем.
func _bbcode(md: String) -> String:
	var out := PackedStringArray()
	var in_comment := false
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var first := true
	for raw in md.split("\n"):
		var line := raw.strip_edges()
		if in_comment:
			in_comment = not line.contains("-->")
			continue
		if line.begins_with("<!--"):
			in_comment = not line.contains("-->")
			continue
		line = line.replace("[", "[lb]")
		line = bold.sub(line, "[b]$1[/b]", true)
		if line.begins_with("### "):
			out.append("\n[color=#%s][b]%s[/b][/color]" % [HubStyle.YELLOW.to_html(false), line.substr(4)])
		elif line.begins_with("## "):
			out.append(("" if first else "\n\n") + "[font_size=22][color=#%s][b]%s[/b][/color][/font_size]" % [HubStyle.PINK.to_html(false), line.substr(3)])
			first = false
		elif line.begins_with("# ") or line == "":
			continue
		elif line.begins_with("- "):
			out.append("  •  " + line.substr(2))
		else:
			out.append(line)
	return "\n".join(out)
