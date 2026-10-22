class_name K12ChatPanel
extends PanelContainer
## Чат партии: сворачиваемая панель с журналом и полем ввода. Enter — открыть и писать.
## «Быстрый чат» — реплики-реакции: раскрываются кнопкой прямо в панели (в углу экрана, ничего не перекрывают).

const REACTIONS := ["Думаю...", "Блефую!", "Кидаю кость!", "Хитро!", "Ой…", "Мне повезёт!", "Удивительно!", "Эй, вы ещё здесь?"]

var expanded := false:
	set(v):
		expanded = v
		_sync()

var corner_margin := Vector2(14, 14)  # отступ от правого нижнего угла родителя
var _log: RichTextLabel
var _input: LineEdit
var _body: VBoxContainer
var _toggle: Button
var _quick_btn: Button
var _quick: HFlowContainer
var quick_open := false
var _unread := 0


func _ready() -> void:
	add_theme_stylebox_override("panel", K12UI.box(Color(0.07, 0.05, 0.035, 0.9), 10, Color("8a6b45"), 1))
	var col := K12UI.vbox(4)
	add_child(col)
	# быстрые реплики: над кнопками, в пределах панели
	_quick = HFlowContainer.new()
	_quick.add_theme_constant_override("h_separation", 4)
	_quick.add_theme_constant_override("v_separation", 4)
	_quick.custom_minimum_size.x = 300
	for r in REACTIONS:
		var b := Button.new()
		b.text = r
		b.add_theme_font_size_override("font_size", 13)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			Net.send_chat(r, "emote")
			quick_open = false
			_sync())
		_quick.add_child(b)
	col.add_child(_quick)
	_toggle = K12UI.button("Чат", K12UI.CAP)
	_toggle.pressed.connect(func(): expanded = not expanded)
	var top := K12UI.hbox(4)
	_quick_btn = K12UI.button("Быстрый чат", K12UI.CAP)
	_quick_btn.tooltip_text = "Реплики одним нажатием"
	_quick_btn.pressed.connect(func():
		quick_open = not quick_open
		_sync())
	top.add_child(_quick_btn)
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_toggle)
	if Net.mode == "steam":
		# пригласить друзей Steam — из любого лобби и прямо за столом
		var inv := K12UI.button("+ Друзья", K12UI.CAP)
		inv.tooltip_text = "Пригласить друзей из Steam"
		inv.pressed.connect(Net.invite_friends)
		top.add_child(inv)
	col.add_child(top)
	_body = K12UI.vbox(4)
	col.add_child(_body)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(280, 150)
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_color_override("default_color", K12UI.CREAM)
	_body.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "Сообщение… (Enter — отправить)"
	_input.max_length = 200
	_input.add_theme_font_size_override("font_size", 13)
	_input.text_submitted.connect(_on_submit)
	_body.add_child(_input)
	for e in Net.chat_log:
		_append(e)
	Net.chat_received.connect(_on_chat)
	var parent := get_parent() as Control
	if parent:
		parent.resized.connect(_place)
	_sync()


func _on_submit(text: String) -> void:
	Net.send_chat(text)
	_input.clear()
	_input.release_focus()


func _on_chat(entry: Dictionary) -> void:
	_append(entry)
	if not expanded:
		_unread += 1
		_sync()
	if entry["kind"] == "emote":
		Sfx.babble(str(entry["text"]), str(entry.get("name", "")))  # реплика — «голосом»
	elif entry["kind"] != "system":
		Sfx.play("hover", -6, 0.1, 0.1)


func _append(entry: Dictionary) -> void:
	var text := str(entry["text"]).replace("[", "(").replace("]", ")")
	var who := str(entry.get("name", "")).replace("[", "(").replace("]", ")")
	if str(entry.get("color", "")) != "":
		who = "[color=#%s]%s[/color]" % [entry["color"], who]  # ник цветом игрока
	match entry["kind"]:
		"system":
			_log.append_text("[color=#a9c0b4][i]%s[/i][/color]\n" % text)
		"emote":
			_log.append_text("[b]%s[/b] [color=#e8c26a]%s[/color]\n" % [who, text])
		_:
			_log.append_text("[b]%s:[/b] %s\n" % [who, text])


func _sync() -> void:
	if _body == null:
		return
	_body.visible = expanded
	_quick.visible = quick_open
	_quick_btn.text = "Скрыть реплики" if quick_open else "Быстрый чат"
	if expanded:
		_unread = 0
	_toggle.text = ("Свернуть чат" if expanded else "Чат") + (" (%d)" % _unread if _unread > 0 else "")
	_place.call_deferred()


## Держим панель в правом нижнем углу и целиком внутри родителя.
func _place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var ms := get_combined_minimum_size()
	size = ms
	position = (parent.size - ms - corner_margin).max(Vector2.ZERO)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ENTER and not _input.has_focus():
		expanded = true
		_input.grab_focus()
		get_viewport().set_input_as_handled()


## Ряд кнопок быстрых реакций.
static func reactions_row() -> HBoxContainer:
	var row := K12UI.hbox(4)
	for r in REACTIONS:
		var b := K12UI.button(r, K12UI.CAP)
		b.pressed.connect(func(): Net.send_chat(r, "emote"))
		row.add_child(b)
	return row
