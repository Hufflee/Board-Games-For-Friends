extends Control

const TextUI = preload("res://hub/ui_text.gd")
## «Покер»: лобби. Число мест (офлайн — с ботами) и режим: «Классика» / «Спортивный».
const Style := preload("res://games/poker/ui/pk_style.gd")
var app: Node
var body: VBoxContainer
var actions: VBoxContainer


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "LobbyPanel"
	panel.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, 24, 18, Style.PINK))
	add_child(panel)
	var layout := func():
		var width := minf(744.0, maxf(1.0, size.x - 32.0))
		var height := maxf(1.0, size.y - 48.0)
		panel.position = Vector2((size.x - width) * 0.5, 24.0)
		panel.size = Vector2(width, height)
	resized.connect(layout)
	layout.call()
	var outer := Style.column(12)
	panel.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.name = "LobbySettingsScroll"
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	body = Style.column(20)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	actions = Style.column(8)
	outer.add_child(actions)
	Net.lobby_changed.connect(_rebuild)
	_rebuild()
	var chat := K12ChatPanel.new()
	chat.expanded = false
	add_child(chat)


func _rebuild() -> void:
	Style.clear(body)
	Style.clear(actions)
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
	var roster := Style.label(" · ".join(names))
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_group("За столом", roster))
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
	var mode_row := HFlowContainer.new()
	for item: Array in [["classic", "Классика"], ["sport", "Спортивный"], ["cheat", "Cheat Poker"], ["cheat_experimental", "Cheat Poker (experimental)"]]:
		var b := _option(item[1], 0)
		Style.pick(b, mode == item[0])
		b.disabled = b.disabled or not host
		b.pressed.connect(func(): Net.set_setting("pk_mode", item[0]))
		mode_row.add_child(b)
	body.add_child(_group("Режим", mode_row))
	var count_now := people.size()
	var auto_target := count_now * 2 + 1
	var chosen := int(settings.get("pk_target", 0))
	var goal := chosen if chosen > 0 else auto_target
	var hint := "Раздачи без конца. Проиграли стек — садитесь заново со 100 BB."
	if mode != "classic":
		hint = "Сессии по %d раздач, очки за места; забрал за сессию все фишки — ещё +1. Победа — %s%s." % [
			PKRules.SESSION_HANDS, TextUI.plural(goal, "очко", "очка", "очков"), " (2 × %d + 1)" % count_now if chosen <= 0 else ""]
	if mode == "cheat":
		hint += " После префлопа, флопа и тёрна — по одной жульнической карте."
	if mode == "cheat_experimental":
		hint += " Карты можно играть во время торговли, даже в чужой ход. Эффект срабатывает сразу."
	var hint_label := Style.label(hint, 16, Style.muted())
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	if mode != "classic":
		# цель спортивного режима: «Авто» — 2N+1, либо своё число (его же меняет панель хоста в партии)
		var goal_row := Style.row()
		var auto := _option("Авто · %d" % auto_target, 140)
		auto.name = "TargetAuto"
		Style.pick(auto, chosen <= 0)
		auto.disabled = auto.disabled or not host
		auto.pressed.connect(func(): Net.set_setting("pk_target", 0))
		goal_row.add_child(auto)
		for step: int in [-1, 1]:
			var b := _option("−" if step < 0 else "+", 48)
			b.name = "TargetDown" if step < 0 else "TargetUp"
			b.disabled = b.disabled or not host or goal + step < 3 or goal + step > 99
			b.pressed.connect(func(): Net.set_setting("pk_target", clampi(goal + step, 3, 99)))
			goal_row.add_child(b)
			if step < 0:
				var value := Style.heading("%d" % goal, 20, Style.GOLD)
				value.name = "TargetValue"
				value.custom_minimum_size.x = 48
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				goal_row.add_child(value)
		body.add_child(_group("Победных очков до победы", goal_row))
	var open := bool(settings.get("pk_open", false))
	var open_row := Style.row()
	for item: Array in [[false, "Подсмотреть"], [true, "Открытые"]]:
		var b := _option(item[1], 200)
		b.name = "OpenCards" if item[0] else "HiddenCards"
		b.tooltip_text = "Свои карты всегда лицом вверх — спрятать нельзя (соперники их не видят)" if item[0] 			else "Свои карты лежат рубашкой — потяните край, чтобы подсмотреть"
		Style.pick(b, open == item[0])
		b.disabled = b.disabled or not host
		b.pressed.connect(func(): Net.set_setting("pk_open", item[0]))
		open_row.add_child(b)
	body.add_child(_group("Свои карты", open_row))
	body.add_child(TurnClock.settings_row(func(t, z): return Style.button(t, z), func(t, z): return Style.label(t, z)))
	body.add_child(SeatShuffle.settings_row(func(t, z): return Style.button(t, z), func(t, z): return Style.label(t, z)))
	var error := Style.label("", 16, Style.BAD)
	error.visible = false
	actions.add_child(error)
	var footer := Style.row(16)
	var leave := Style.button("К выбору игры")
	LeaveGuard.hold(leave, app.back_to_hub, "Выйти?")
	footer.add_child(leave)
	if host:
		var start := Style.button("Начать партию")
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	actions.add_child(footer)


func _group(title: String, content: Control) -> VBoxContainer:
	var group := Style.column(8)
	group.add_child(Style.section(title))
	group.add_child(content)
	return group


func _option(text: String, width: int = 112) -> Button:
	var b := Style.button(text)
	b.custom_minimum_size.x = width
	return b
