extends Control
## Лобби: распределение ролей духов и медиумов.
var app: Node
var _body: VBoxContainer
var _error: Label
func _ready() -> void:
	add_child(PIStyle.Backdrop.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 48
	margin.offset_top = 32
	margin.offset_right = -340
	margin.offset_bottom = -32
	add_child(margin)
	var panel := PIStyle.panel()
	margin.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	_body = PIStyle.vbox(16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()
func _rebuild() -> void:
	PIStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		return
	_body.add_child(PIStyle.label("ПРИЗРАЧНЫЕ ЧЕРНИЛА", PIStyle.H1, true))
	var help := PIStyle.label("Две команды. В каждой — один дух и хотя бы один медиум.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(help)
	var members: Array = data.members
	var roles: Array = data.settings.get("pi_roles", [])
	if roles.size() != members.size():
		roles = PIData.default_roles(members.size())
	var grid := GridContainer.new()
	grid.columns = 4 if members.size() > 4 else 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	for i in members.size():
		var name_label := PIStyle.label(str(members[i].name))
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 80
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var select := OptionButton.new()
		for role in PIData.ROLES:
			select.add_item(role)
		select.select(int(roles[i]))
		select.disabled = not Net.is_host()
		select.item_selected.connect(func(value: int):
			var updated: Array = roles.duplicate()
			updated[i] = value
			Net.set_setting("pi_roles", updated))
		grid.add_child(select)
	if data.mode == "offline" and Net.is_host():
		var row := PIStyle.hbox()
		for delta in [-1, 1]:
			var b := PIStyle.button("− Игрок" if delta < 0 else "+ Игрок")
			b.disabled = members.size() <= 4 if delta < 0 else members.size() >= 8
			b.pressed.connect(func(): Net.set_bots(Net.bots + delta))
			row.add_child(b)
		_body.add_child(row)
		var privacy := PIStyle.label("Передавайте экран по очереди. Пока дух смотрит предмет, медиумы должны отвернуться.", PIStyle.CAP)
		privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(privacy)
	if Net.is_host():
		var start := PIStyle.primary("Начать сеанс")
		start.pressed.connect(func(): _error.text = Net.start_game())
		_body.add_child(start)
	else:
		_body.add_child(PIStyle.label("Ждём начала сеанса…"))
	var row := PIStyle.hbox()
	for entry in [["Правила", app.show_rules], ["Настройки", app.show_settings], ["К выбору игры", app.back_to_hub]]:
		var b := PIStyle.button(entry[0], PIStyle.CAP)
		b.pressed.connect(entry[1])
		row.add_child(b)
	_body.add_child(row)
	_error = PIStyle.label("", PIStyle.CAP)
	_body.add_child(_error)
