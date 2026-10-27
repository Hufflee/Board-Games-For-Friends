extends Control
## Главное меню.

var app: Node
var message := ""

var _status: Label
var _name: LineEdit
var _code: LineEdit


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := K12UI.vbox(10)
	col.custom_minimum_size.x = 560
	center.add_child(col)

	col.add_child(K12UI.title("Дюжина короля", 56))
	col.add_child(K12UI.label("настольная игра для 2–8 игроков", K12UI.BODY, K12UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	if not Prefs.tutorial_seen:
		col.add_child(K12UI.label("Впервые за столом? Начните с «Обучения» — это партия с подсказками.", K12UI.CAP, K12UI.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
	if not Net.last_join.is_empty():
		var back := K12UI.button("Вернуться в партию", K12UI.BODY)
		back.pressed.connect(Net.rejoin)
		col.add_child(back)

	var name_row := K12UI.hbox()
	name_row.add_child(K12UI.label("Ваше имя:", K12UI.BODY))
	_name = LineEdit.new()
	_name.text = Net.my_name
	_name.max_length = 24
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(t): Net.my_name = t if t.strip_edges() != "" else "Игрок")
	name_row.add_child(_name)
	col.add_child(name_row)

	var steam_box := K12UI.panel()
	var sv := K12UI.vbox(10)
	steam_box.add_child(sv)
	col.add_child(steam_box)
	sv.add_child(K12UI.label("Игра через Steam", K12UI.BODY, K12UI.GOLD))
	var st := "Steam подключён: %s" % Net.my_name if Net.steam_ok else Net.steam_error
	var st_label := K12UI.label(st, K12UI.CAP, K12UI.GREEN if Net.steam_ok else K12UI.MUTED)
	st_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(st_label)
	var host_btn := K12UI.primary("Создать игру и пригласить друзей")
	host_btn.disabled = not Net.steam_ok
	host_btn.pressed.connect(Net.host_steam)
	if Net.steam_ok:
		host_btn.theme_type_variation = "SelectedButton"  # главное действие экрана — золотом
	sv.add_child(host_btn)
	var join_row := K12UI.hbox()
	_code = LineEdit.new()
	_code.placeholder_text = "код лобби"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_code)
	var join_btn := K12UI.button("Войти по коду", K12UI.BODY)
	join_btn.disabled = not Net.steam_ok
	join_btn.pressed.connect(func(): Net.join_steam(int(_code.text.strip_edges())))
	join_row.add_child(join_btn)
	sv.add_child(join_row)

	var test_box := K12UI.panel()
	var tv := K12UI.vbox(10)
	test_box.add_child(tv)
	col.add_child(test_box)
	tv.add_child(K12UI.label("Без Steam", K12UI.BODY, K12UI.GOLD))
	var bots_btn := K12UI.primary("Играть с ботами")
	bots_btn.pressed.connect(Net.host_offline)
	if not Net.steam_ok:
		bots_btn.theme_type_variation = "SelectedButton"
	tv.add_child(bots_btn)

	var bottom := K12UI.hbox(10)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	var tut := K12UI.button("Обучение", K12UI.BODY, 190)
	tut.pressed.connect(func(): app.start_tutorial())
	bottom.add_child(tut)
	var rules_btn := K12UI.button("Правила", K12UI.BODY, 190)
	rules_btn.pressed.connect(func(): app.show_rules())
	bottom.add_child(rules_btn)
	var stats_btn := K12UI.button("Статистика", K12UI.BODY, 190)
	stats_btn.pressed.connect(func(): app.show_stats())
	bottom.add_child(stats_btn)
	col.add_child(bottom)
	var bottom2 := K12UI.hbox(10)
	bottom2.alignment = BoxContainer.ALIGNMENT_CENTER
	var set_btn := K12UI.button("Настройки", K12UI.BODY, 190)
	set_btn.pressed.connect(func(): app.show_settings())
	bottom2.add_child(set_btn)
	var hub_btn := K12UI.button("← К выбору игры", K12UI.BODY, 190)
	hub_btn.pressed.connect(func(): app.back_to_hub())
	bottom2.add_child(hub_btn)
	var quit_btn := K12UI.button("Выйти из игры", K12UI.CAP, 190)
	quit_btn.theme_type_variation = "QuietButton"  # опасное действие — приглушено
	quit_btn.pressed.connect(func(): Sfx.request_quit())
	bottom2.add_child(quit_btn)
	col.add_child(bottom2)

	_status = K12UI.label(message, K12UI.BODY, K12UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	Net.status_changed.connect(_on_status)


func _on_status(text: String) -> void:
	_status.text = text
