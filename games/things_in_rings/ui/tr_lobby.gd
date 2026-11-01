extends Control
## Лобби без семантических ботов: местные места либо настоящие друзья.
const Style := preload("res://games/things_in_rings/ui/tr_style.gd")
var app: Node
var body: VBoxContainer

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	# Лобби по центру экрана на любом разрешении, в бумажной панели стола.
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "LobbyPanel"
	panel.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 32))
	panel.custom_minimum_size.x = 720
	center.add_child(panel)
	body = Style.column(16)
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
	body.add_child(Style.heading("THINGS IN RINGS · ЛОББИ"))
	var host: bool = Net.is_host()
	var settings: Dictionary = data.settings
	var people: Array = data.members
	if host and Net.mode == "offline":
		var row := Style.row()
		for n: int in range(2, 7):
			var count := _option("%d" % n)
			Style.pick(count, people.size() == n)
			count.pressed.connect(func(): Net.set_bots(n - 1))
			row.add_child(count)
		body.add_child(_group("Игроков", row))
	# Игроки и «Хочу вести»: свой переключатель у каждого, хост переключает и местных игроков.
	# Имя у хоста — выбор ведущего, если никто не вызвался.
	var wants: Array = settings.get("tr_want", [])
	var me: int = 1 if Net.mode == "offline" else multiplayer.get_unique_id()
	var knower_seat := int(settings.get("tr_knower", 0))
	var volunteers := PackedStringArray()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	var keys: Array[String] = []
	var local_count := 0
	for person: Dictionary in people:
		if str(person.get("kind", "")) == "local":
			keys.append("l%d" % local_count)
			local_count += 1
		else:
			keys.append("p%d" % int(person.get("peer", 0)))
	# Есть желающие — выбор хоста не действует и не подсвечивается.
	var anyone := keys.any(func(k: String) -> bool: return wants.has(k))
	local_count = 0
	for seat: int in people.size():
		var person: Dictionary = people[seat]
		var local_index := -1
		var mine: bool = int(person.get("peer", 0)) == me
		if str(person.get("kind", "")) == "local":
			local_index = local_count
			local_count += 1
			mine = host
		var wants_lead: bool = wants.has(keys[seat])
		if wants_lead:
			volunteers.append(str(person.name))
		grid.add_child(_player_chip(seat, str(person.name), wants_lead, mine, local_index, host, seat == knower_seat and not anyone))
	var lead_caption := "Игроки · ведущий: %s (выбор хоста)" % str(people[clampi(knower_seat, 0, people.size() - 1)].name)
	if volunteers.size() == 1:
		lead_caption = "Игроки · ведущий: %s (вызвался)" % volunteers[0]
	elif volunteers.size() > 1:
		lead_caption = "Игроки · ведущий — случайно из желающих: " + ", ".join(volunteers)
	body.add_child(_group(lead_caption, grid))
	# Режим: обычный по умолчанию, Blind Mind — одновременные слепые ходы.
	var blind: bool = str(settings.get("tr_mode", "classic")) == "blind"
	var mode_row := Style.row(8)
	for item: Array in [["classic", "Обычный"], ["blind", "Blind Mind"]]:
		var b := _option(item[1])
		b.name = "Mode_" + str(item[0])
		Style.pick(b, str(settings.get("tr_mode", "classic")) == item[0])
		b.disabled = not host
		var value: String = item[0]
		b.pressed.connect(func(): Net.set_setting("tr_mode", value))
		mode_row.add_child(b)
	var about := Style.label("Все искатели ставят по карточке одновременно и вслепую; ведущий сразу переносит их в верные области. В конце хода — открытие." if blind else "Искатели ходят по очереди, ведущий проверяет каждую карточку.", 12, Style.muted())
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_row.add_child(about)
	body.add_child(_group("Режим", mode_row))
	var rings: Array = settings.get("tr_rings", ["Attribute", "Word", "Context"])
	var ring_row := Style.row()
	for category: String in ["Attribute", "Word", "Context"]:
		var b := _option(Style.category_name(category))
		Style.pick(b, category in rings)
		b.disabled = not host
		b.pressed.connect(func():
			var selected: Array = rings.duplicate()
			if category in selected:
				if selected.size() > 1:
					selected.erase(category)
			else:
				selected.append(category)
			Net.set_setting("tr_rings", selected))
		ring_row.add_child(b)
	body.add_child(_group("Кольца · от одного до трёх", ring_row))
	# Кооператив и время на ход искателя — одной строкой: это второстепенные настройки.
	var extra := Style.row(8)
	var cooperative := Style.button("Кооператив")
	cooperative.tooltip_text = "Вдвоём — кооператив автоматически." if people.size() == 2 else "Общая победа: все искатели опустошают руки."
	Style.pick(cooperative, bool(settings.get("tr_coop", false)) or people.size() == 2)
	cooperative.disabled = not host or people.size() == 2
	cooperative.pressed.connect(func(): Net.set_setting("tr_coop", not bool(settings.get("tr_coop", false))))
	extra.add_child(cooperative)
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	extra.add_child(gap)
	var timer := int(settings.get("tr_timer", 0))
	var timer_title := Style.label("Время на ход:", 16, Style.muted())
	timer_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	extra.add_child(timer_title)
	for seconds: int in TurnClock.OPTIONS:
		var t := Style.button("∞" if seconds == 0 else "%d с" % seconds)
		t.name = "Timer%d" % seconds
		t.custom_minimum_size.x = 56
		t.tooltip_text = "Без ограничения" if seconds == 0 else "Не успел — ход пропущен (в Blind Mind — без карточки в этом ходу)"
		Style.pick(t, timer == seconds)
		t.disabled = not host
		t.pressed.connect(func(): Net.set_setting("tr_timer", seconds))
		extra.add_child(t)
	body.add_child(_group("Ещё", extra))
	body.add_child(_group("Порядок мест", SeatShuffle.settings_row(func(t, _z): return Style.button(t), func(t, _z): return Style.label(t, 16, Style.muted()))))
	var error := Style.label("", 16, Style.muted())
	error.visible = false
	body.add_child(error)
	# Низ панели: тихий выход слева, единственная главная кнопка — справа, в конце пути взгляда.
	var footer := Style.row(16)
	var leave := Style.button("К выбору игры")
	leave.theme_type_variation = "QuietButton"
	LeaveGuard.hold(leave, app.back_to_hub, "Выйти?")  # без wire: отступ перед кнопкой у края панели не нужен
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

## Группа настроек: подпись раздела и содержимое под ней.
func _group(title: String, content: Control) -> VBoxContainer:
	var group := Style.column(8)
	group.add_child(Style.section(title))
	group.add_child(content)
	return group

## Однотипные варианты одной ширины — ряд выглядит ровно.
func _option(text: String) -> Button:
	var b := Style.button(text)
	b.custom_minimum_size.x = 112
	b.clip_text = true
	return b

## Строка игрока: имя (у хоста — выбрать ведущим, если никто не вызвался) и переключатель «Хочу вести».
## Чужие переключатели видны всем, но нажать можно только свой (хост — ещё и местных).
func _player_chip(seat: int, player_name: String, wants_lead: bool, mine: bool, local_index: int, host: bool, chosen: bool) -> HBoxContainer:
	var chip := Style.row(8)
	chip.name = "Player%d" % seat
	var name_button := Style.button(player_name)
	name_button.name = "Knower%d" % seat
	name_button.custom_minimum_size.x = 160
	name_button.clip_text = true
	name_button.tooltip_text = "Ведущий, если никто не вызвался"
	Style.pick(name_button, chosen)
	name_button.disabled = not host
	name_button.pressed.connect(func(): Net.set_setting("tr_knower", seat))
	chip.add_child(name_button)
	var want := Style.button("Хочу вести" if not wants_lead else "Хочу вести ✓", 12)
	want.name = "Want%d" % seat
	want.custom_minimum_size.x = 120
	want.tooltip_text = "Хочу быть ведущим (знающим). Если желающих несколько — ведущий выбирается случайно."
	Style.pick(want, wants_lead)
	want.disabled = not mine
	want.pressed.connect(func(): Net.tr_toggle_want(local_index))
	chip.add_child(want)
	return chip
