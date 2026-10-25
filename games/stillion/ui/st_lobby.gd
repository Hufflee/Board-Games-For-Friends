extends Control
## Лобби «Стиллиона»: игроки (2–8), боты на одном компьютере, ключ jev для проверки ответов, старт, чат.

var app: Node
var _body: VBoxContainer
var _error: Label


func _ready() -> void:
	var bg := STStyle.Backdrop.new()
	bg.image = "bg_circus_approved.png"
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -300  # справа — чат
	add_child(center)
	var card := STStyle.panel(24)
	card.custom_minimum_size = Vector2(640, 0)
	center.add_child(card)
	_body = STStyle.vbox(12)
	card.add_child(_body)
	var chat := K12ChatPanel.new()
	chat.expanded = true
	STStyle.restyle_chat(chat)
	add_child(chat)
	add_child(STStyle.FilmFX.new())
	Net.lobby_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	STStyle.clear(_body)
	var data: Dictionary = Net.lobby_view
	if data.is_empty():
		_body.add_child(STStyle.label("Подключение…"))
		return
	var host := Net.is_host()
	var s: Dictionary = data["settings"]
	var head := STStyle.hbox(16)
	var t := STStyle.title("Стиллион")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var back: Button
	if Net.is_party() and host:
		back = STStyle.button("← К выбору игры", STStyle.CAP)
		back.pressed.connect(func(): app.back_to_hub())
	elif Net.is_party():
		back = STStyle.button("Покинуть пати", STStyle.CAP)
		LeaveGuard.wire(back, "Покинуть пати?", "Вы выйдете из игры и из пати.", func(): app.leave_party())
	else:
		back = STStyle.button("Выйти в меню", STStyle.CAP)
		back.pressed.connect(func(): app.back_to_menu())
	back.theme_type_variation = "QuietButton"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_body.add_child(head)
	var members: Array = data["members"]
	_body.add_child(STStyle.label("ИГРОКИ · от 2 до 8", STStyle.CAP, STStyle.muted(), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for m in members:
		grid.add_child(PlayerTag.make(m, members, STStyle.BODY, STStyle.ink(), "  · хост" if m["kind"] == "host" else ""))
	_body.add_child(grid)
	var bots := bool(s.get("st_bots", false))
	if data["mode"] == "offline" and host:
		var lrow := STStyle.hbox(8)
		var add := STStyle.button("+ Игрок", STStyle.CAP)
		add.disabled = members.size() >= 8
		add.pressed.connect(func(): Net.set_bots(Net.bots + 1))
		lrow.add_child(add)
		var rem := STStyle.button("− Игрок", STStyle.CAP)
		rem.disabled = Net.bots == 0
		rem.pressed.connect(func(): Net.set_bots(Net.bots - 1))
		lrow.add_child(rem)
		var bot_btn := STStyle.button("Добавленные — боты", STStyle.CAP)
		UISel.pick(bot_btn, bots)
		bot_btn.tooltip_text = "Выключено — за одним компьютером по очереди печатают живые игроки.\nВключено — добавленные места занимают боты."
		bot_btn.pressed.connect(func(): Net.set_setting("st_bots", not bots))
		lrow.add_child(bot_btn)
		_body.add_child(lrow)
	if data["mode"] == "offline":
		var tl := STStyle.label("Пушка целится в игрока — он садится к клавиатуре и печатает ответ." if not bots else "Вы против ботов: пушка будет целиться и в них.", STStyle.CAP, STStyle.muted())
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tl)
	# настройки партии (меняет хост)
	_body.add_child(STStyle.label("НАСТРОЙКИ ПАРТИИ", STStyle.CAP, STStyle.muted(), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	_choice_row("Жизни", "st_lives", int(s.get("st_lives", STRules.MAX_LIVES)), [1, 2, 3, 4, 5], host)
	_choice_row("Шкала", "st_meter", int(s.get("st_meter", STRules.METER_MAX)), [10, 15, 20, 30], host,
		"Сколько очков ответов нужно набрать, чтобы вернуть жизнь.")
	var casual := bool(s.get("st_casual", false))
	_choice_row("Редкость", "st_casual", casual, [false, true], host,
		"Знатоки — редкость ответа как в списке.\nОбычные игроки — ответ ценится на ступень выше: умник засчитывается как эрудит,\nшкольник — как умник, менее очевидная половина общеизвестных — как школьник.",
		["Знатоки", "Обычные игроки"])
	# проверка ответов
	_body.add_child(STStyle.label("ПРОВЕРКА ОТВЕТОВ", STStyle.CAP, STStyle.muted(), HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	var jev_on := STJev.available()
	var st := STStyle.label("Jev подключён: незнакомые ответы проверит нейросеть." if jev_on else "Только по встроенным спискам ответов. Чтобы принимать любые верные ответы, подключите Jev.", STStyle.CAP, STStyle.GREEN if jev_on else STStyle.muted())
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(st)
	if host:
		var krow := STStyle.hbox(8)
		var key := LineEdit.new()
		key.secret = true
		key.placeholder_text = "Ключ Typesafe API (Jev)"
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.tooltip_text = "Ключ хранится только на этом компьютере (user://stillion.cfg) и нужен только ведущему."
		krow.add_child(key)
		var save := STStyle.button("Сохранить", STStyle.CAP)
		save.pressed.connect(func():
			STJev.save_key(key.text)
			key.text = ""
			_rebuild())
		krow.add_child(save)
		_body.add_child(krow)
	var start_row := STStyle.hbox(12)
	if host:
		var start := STStyle.primary("Зарядить пушку!", STStyle.BODY, 240)
		start.pressed.connect(func():
			var err: String = Net.start_game()
			if err != "":
				_error.text = err)
		start_row.add_child(start)
	else:
		start_row.add_child(STStyle.label("Ждём, когда хост начнёт игру…", STStyle.BODY, STStyle.muted()))
	_body.add_child(start_row)
	_error = STStyle.label("", STStyle.CAP, STStyle.RED)
	_body.add_child(_error)


## Строка выбора настройки: подпись и кнопки значений (выбранное — заливкой); не хосту — только просмотр.
func _choice_row(caption: String, key: String, current, values: Array, host: bool, tip := "", names: Array = []) -> void:
	var row := STStyle.hbox(8)
	var cap := STStyle.label(caption, STStyle.CAP, Color(0, 0, 0, 0), HORIZONTAL_ALIGNMENT_LEFT, "bold")
	cap.custom_minimum_size.x = 96
	cap.tooltip_text = tip
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(cap)
	for i in values.size():
		var v = values[i]
		var b := STStyle.button(str(names[i]) if i < names.size() else str(v), STStyle.CAP, 44)
		UISel.pick(b, v == current)
		b.tooltip_text = tip
		b.disabled = b.disabled or not host
		b.pressed.connect(func(): Net.set_setting(key, v))
		row.add_child(b)
	_body.add_child(row)
