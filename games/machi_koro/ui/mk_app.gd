extends Control
## Меню/лобби Мачи Коро. Запуск: res://games/machi_koro/ui/main.tscn.

const Style := preload("res://games/machi_koro/ui/mk_style.gd")
const Table := preload("res://games/machi_koro/ui/mk_table.gd")
const Settings := preload("res://games/king_of_12/ui/settings_screen.gd")
const RULES := """[b]Цель[/b] — первым построить четыре достопримечательности, с «Плюс» — шесть. Начинаете с Пшеничного поля, Пекарни и трёх монет. Ратуша в «Плюс» уже построена и в число целей не входит.

[b]Бросок.[/b] Схватите кубик мышью, потяните и отпустите. С Вокзалом выбирайте один или два кубика. Радиовышка позволяет один переброс; Порт — добавить ровно 2 к результату 10 и выше. До окончания анимации эффекты не применяются.

[b]Доходы.[/b] Сначала красные предприятия получают деньги активного игрока, против часовой стрелки. Платится только имеющееся, недоплата списывается. Затем синие предприятия работают в любой ход, зелёные — только в свой; затем фиолетовые эффекты активного игрока. Все расчёты выполняет система. Балансы обновляются после поясняющей анимации.

[b]Выборы.[/b] Телецентр, Деловой центр и другие карты предлагают только допустимые цели. Выберите цель и подтвердите; система выполнит эффект. Добровольный эффект можно пропустить, обязательный — нельзя.

[b]Строительство.[/b] За ход можно купить одно предприятие, построить одну достопримечательность или отказаться. Выберите карту и нажмите кнопку строительства. Фиолетовые предприятия — не больше одного каждого вида. Резерв конечен.

[b]Достопримечательности.[/b] Торговый центр усиливает каждый подходящий магазин/общепит. Парк развлечений даёт ещё ход за дубль двух кубиков. Аэропорт приносит 10 монет при отказе от строительства. Ратуша даёт 1 монету, если после доходов у активного игрока ничего не осталось.

[b]«Шарп».[/b] Временно закрытая карта при следующем срабатывании открывается вместо эффекта. При передаче закрытие сохраняется. Монеты Венчурного фонда лежат отдельно от личного баланса.

[b]Рынок «10 видов».[/b] Карты выбранных наборов перемешаны в общую колоду. Открывается до десяти разных предприятий; одинаковые складываются. Когда тип заканчивается, рынок пополняется из оставшейся колоды.

[b]Один компьютер.[/b] Только местные игроки, без ботов. Все города открыты. Действия доступны за текущего игрока, любой город можно осмотреть нажатием имени. При сетевом отключении место сохраняется без автоматических решений за игрока."""
var screen: Control
var error_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_apply_theme()
	Net.game_started.connect(show_table)
	Net.game_ended.connect(show_lobby)
	Net.lobby_changed.connect(_lobby_changed)
	Net.session_closed.connect(show_menu)
	Net.party_game_changed.connect(_party_changed)
	Prefs.changed.connect(_prefs_changed)
	if Net.party_game == "machi_koro" and Net.in_game:
		show_table()
	elif Net.party_game == "machi_koro" and Net.in_session():
		show_lobby()
	elif Net.in_session():
		_go_hub()
	else:
		show_menu()

func _apply_theme() -> void:
	theme = Style.theme()
	get_tree().root.theme = theme

func _set_screen(node: Control) -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = node
	node.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(node)

func _center() -> VBoxContainer:
	var root := Control.new()
	var bg := preload("res://games/machi_koro/ui/mk_backdrop.gd").new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var col := Style.column(16)
	panel.add_child(col)
	_set_screen(root)
	return col

func show_menu(message: String = "") -> void:
	var col := _center()
	col.add_child(Style.heading("МАЧИ КОРО"))
	col.add_child(Style.label("ПОСТРОЙТЕ СВОЙ ГОРОД · 2–5 ИГРОКОВ", 14))
	col.add_child(RoomPanel.make("machi_koro", Style.button, Style.label))
	var local := Style.primary("Играть на одном компьютере")
	local.name = "LocalGame"
	local.pressed.connect(func():
		Net.host_offline("machi_koro")
		Net.set_bots(1))
	col.add_child(local)
	var rules := Style.button("Правила")
	rules.pressed.connect(show_rules)
	col.add_child(rules)
	var back := Style.button("К выбору игры")
	back.pressed.connect(_go_hub)
	col.add_child(back)
	if not message.is_empty():
		col.add_child(Style.label(message))

func show_lobby() -> void:
	var col := _center()
	col.add_child(Style.heading("МАЧИ КОРО · ЛОББИ"))
	var members: Array = Net.lobby_view.get("members", [])
	var names := Style.row(16)
	for member: Dictionary in members:
		names.add_child(PlayerTag.make(member, members, 18, Style.ink()))
	col.add_child(names)
	if Net.mode == "offline" and Net.is_host():
		var row := Style.row()
		for change: int in [1, -1]:
			var button := Style.button("+ Игрок" if change > 0 else "− Игрок")
			button.disabled = members.size() >= 5 if change > 0 else members.size() <= 2
			button.pressed.connect(func(): Net.set_bots(Net.bots + change))
			row.add_child(button)
		col.add_child(row)
	for option: Array in [["mk_plus", "Дополнение «Плюс»"], ["mk_sharp", "Дополнение «Шарп»"], ["mk_limited", "Случайный рынок · 10 видов"]]:
		var toggle := CheckBox.new()
		toggle.text = option[1]
		toggle.button_pressed = bool(Net.lobby_view.get("settings", {}).get(option[0], false))
		toggle.disabled = not Net.is_host()
		var key: String = option[0]
		toggle.toggled.connect(func(on): Net.set_setting(key, on))
		col.add_child(toggle)
	col.add_child(SeatShuffle.settings_row(Style.button, Style.label))
	var refs := Style.row()
	for item: Array in [["Правила", show_rules], ["Настройки", show_settings]]:
		var button := Style.button(item[0])
		button.pressed.connect(item[1])
		refs.add_child(button)
	col.add_child(refs)
	if Net.is_host():
		var start := Style.primary("Начать партию")
		start.name = "StartGame"
		start.disabled = members.size() < 2 or members.size() > 5
		start.pressed.connect(func(): error_label.text = Net.start_game())
		col.add_child(start)
	else:
		col.add_child(Style.label("Ждём старта от хоста…"))
	var back := Style.button("К выбору игры")
	LeaveGuard.wire(back, "Выйти?", "Вернуться к выбору игры.", back_to_hub)
	col.add_child(back)
	error_label = Style.label("", 14)
	col.add_child(error_label)
	var chat := K12ChatPanel.new()
	screen.add_child(chat)

func show_table() -> void:
	var node := Table.new()
	node.app = self
	_set_screen(node)

func show_rules() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.1, 0.8)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.z_index = 110
	dim.add_to_group("pause_allowed")
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.offset_left = 96
	panel.offset_right = -96
	panel.offset_top = 72
	panel.offset_bottom = -48
	dim.add_child(panel)
	var col := Style.column(16)
	panel.add_child(col)
	col.add_child(Style.heading("ПРАВИЛА МАЧИ КОРО"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = RULES
	text.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(text)
	var close := Style.primary("Понятно")
	close.pressed.connect(dim.queue_free)
	col.add_child(close)

func show_settings() -> void:
	var node := Settings.new()
	node.make_panel = func(): return PanelContainer.new()
	node.make_title = Style.heading
	node.make_primary = Style.primary
	node.ink = Style.ink()
	add_child(node)

func back_to_hub() -> void:
	if Net.is_party() and Net.is_host():
		Net.return_to_party()
	else:
		Net.leave()
		_go_hub()

func _go_hub() -> void:
	get_tree().change_scene_to_file.call_deferred(HubGames.HUB_SCENE)

func _lobby_changed() -> void:
	if Net.party_game == "machi_koro" and not Net.in_game:
		show_lobby()

func _party_changed(id: String) -> void:
	if id != "machi_koro":
		_go_hub()

func _prefs_changed() -> void:
	_apply_theme()
	if is_instance_valid(screen) and screen.has_method("restyle"):
		screen.restyle()
	elif Net.in_session():
		show_lobby()
	else:
		show_menu()
