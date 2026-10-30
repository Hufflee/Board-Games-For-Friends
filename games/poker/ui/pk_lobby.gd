extends Control
## «Покер»: лобби. Число мест (офлайн — с ботами) и режим: «Классика» / «Спортивный».
const Style := preload("res://games/poker/ui/pk_style.gd")
var app: Node
var body: VBoxContainer


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "LobbyPanel"
	panel.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 32, 18, Style.PINK))
	panel.custom_minimum_size.x = 720
	center.add_child(panel)
	body = Style.column(24)
	panel.add_child(body)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()
	var chat := K12ChatPanel.new()
	chat.expanded = false
	add_child(chat)


func _rebuild() -> void:
	Style.clear(body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		return
	body.add_child(Style.heading("ПОКЕР · ЛОББИ", 28, Style.PINK))
	var host: bool = Net.is_host()
	var settings: Dictionary = data.settings
	var people: Array = data.members
	var names := PackedStringArray()
	for person: Dictionary in people:
		names.append(str(person.name))
	body.add_child(_group("За столом", Style.label(" · ".join(names))))
	if host:
		var row := Style.row()
		var humans := people.size() - maxi(0, Net.bots)
		for n: int in range(2, 9):
			var count := _option("%d" % n, 64)
			Style.pick(count, people.size() == n)
			count.disabled = n < humans
			count.pressed.connect(func(): Net.set_bots(n - humans))
			row.add_child(count)
		body.add_child(_group("Мест за столом · свободные займут боты", row))
	var mode := str(settings.get("pk_mode", "classic"))
	var mode_row := Style.row()
	for item: Array in [["classic", "Классика"], ["sport", "Спортивный"]]:
		var b := _option(item[1], 200)
		Style.pick(b, mode == item[0])
		b.disabled = b.disabled or not host
		b.pressed.connect(func(): Net.set_setting("pk_mode", item[0]))
		mode_row.add_child(b)
	body.add_child(_group("Режим", mode_row))
	var count_now := people.size()
	var hint := "Раздачи без конца. Проиграли стек — садитесь заново со 100 BB." if mode == "classic" \
		else "Сессии по 14 раздач, очки за места. Победа — %d очков (2 × %d + 1)." % [count_now * 2 + 1, count_now]
	var hint_label := Style.label(hint, 16, Style.muted())
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	var error := Style.label("", 16, Style.BAD)
	error.visible = false
	body.add_child(error)
	var footer := Style.row(16)
	var leave := Style.button("К выбору игры")
	LeaveGuard.hold(leave, app.back_to_hub, "Выйти?")
	footer.add_child(leave)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	if host:
		var start := Style.button("Начать партию")
		start.custom_minimum_size.x = 240
		start.name = "StartGame"
		start.theme_type_variation = "SelectedButton"
		start.pressed.connect(func():
			error.text = Net.start_game()
			error.visible = not error.text.is_empty())
		footer.add_child(start)
	else:
		var waiting := Style.label("Ждём хоста…", 16, Style.muted())
		waiting.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		footer.add_child(waiting)
	body.add_child(footer)


func _group(title: String, content: Control) -> VBoxContainer:
	var group := Style.column(8)
	group.add_child(Style.section(title))
	group.add_child(content)
	return group


func _option(text: String, width: int = 112) -> Button:
	var b := Style.button(text)
	b.custom_minimum_size.x = width
	return b
