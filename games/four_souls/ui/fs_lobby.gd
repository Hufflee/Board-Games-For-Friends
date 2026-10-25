extends Control
## Комната Four Souls: состав партии и единый переключатель DLC.
var app: Node
var _body: VBoxContainer
var _error: Label
func _ready() -> void:
	add_child(FSStyle.Backdrop.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 48; margin.offset_right = -340; margin.offset_top = 40; margin.offset_bottom = -40
	add_child(margin)
	var panel := FSStyle.panel(); margin.add_child(panel)
	var scroll := ScrollContainer.new(); panel.add_child(scroll)
	_body = FSStyle.vbox(16); _body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_body)
	var chat := K12ChatPanel.new(); chat.expanded = true; add_child(chat)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()
func _rebuild() -> void:
	FSStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty(): return
	_body.add_child(FSStyle.label("ISAAC · FOUR SOULS", FSStyle.H1, true))
	_body.add_child(FSStyle.label("2–8 игроков · первым соберите четыре души"))
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation",24); grid.add_theme_constant_override("v_separation",8)
	for member in data.members: grid.add_child(FSStyle.label(str(member.name)))
	_body.add_child(grid)
	if data.mode == "offline" and Net.is_host():
		var row := FSStyle.hbox()
		for delta in [-1,1]:
			var b := FSStyle.button("− Игрок" if delta < 0 else "+ Игрок")
			b.disabled = data.members.size() <= 2 if delta < 0 else data.members.size() >= 8
			b.pressed.connect(func(): Net.set_bots(Net.bots + delta))
			row.add_child(b)
		_body.add_child(row)
	var expanded := bool(data.settings.get("fs_dlc",false))
	var toggle := CheckBox.new(); toggle.text = "DLC · расширенный набор и комнаты"; toggle.button_pressed = expanded; toggle.disabled = not Net.is_host()
	toggle.toggled.connect(func(value): Net.set_setting("fs_dlc",value)); _body.add_child(toggle)
	var text := FSStyle.label("Базовый набор повторяет состав третьего мода. DLC добавляет расширенные карты из второго. Все карты на русском.",FSStyle.CAP)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _body.add_child(text)
	var info := FSStyle.label("Стол как в Tabletop Simulator: колоды, ресурсы и бой ведёт игра, сложные эффекты карт выполняют игроки через панель эффекта. Ботов нет.",FSStyle.CAP)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _body.add_child(info)
	if Net.is_host():
		var start := FSStyle.primary("Спуститься в подвал")
		start.pressed.connect(func(): _error.text = Net.start_game()); _body.add_child(start)
	else: _body.add_child(FSStyle.label("Ждём хоста…"))
	var row := FSStyle.hbox()
	for entry in [["Правила",app.show_rules],["Настройки",app.show_settings],["К выбору игры",app.back_to_hub]]:
		var b := FSStyle.button(entry[0],FSStyle.CAP); b.pressed.connect(entry[1]); row.add_child(b)
	_body.add_child(row); _error = FSStyle.label("",FSStyle.CAP); _body.add_child(_error)
