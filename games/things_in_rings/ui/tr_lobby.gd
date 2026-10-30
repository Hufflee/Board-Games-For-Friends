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
	body.add_child(Style.heading("THINGS IN RINGS · ЛОББИ"))
	var host: bool = Net.is_host()
	var settings: Dictionary = data.settings
	var people: Array = data.members
	var names := PackedStringArray()
	for person: Dictionary in people:
		names.append(str(person.name))
	body.add_child(_group("За столом", Style.label(" · ".join(names))))
	if host and Net.mode == "offline":
		var row := Style.row()
		for n: int in range(2, 7):
			var count := _option("%d" % n)
			Style.pick(count, people.size() == n)
			count.pressed.connect(func(): Net.set_bots(n - 1))
			row.add_child(count)
		body.add_child(_group("Игроков", row))
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
	var role_row := Style.row()
	for seat: int in people.size():
		var b := _option(str(people[seat].name))
		Style.pick(b, seat == int(settings.get("tr_knower", 0)))
		b.disabled = not host
		b.pressed.connect(func(): Net.set_setting("tr_knower", seat))
		role_row.add_child(b)
	body.add_child(_group("Знающий", role_row))
	var cooperative := Style.button("Кооператив" if people.size() != 2 else "Вдвоём · кооператив автоматически")
	cooperative.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Style.pick(cooperative, bool(settings.get("tr_coop", false)) or people.size() == 2)
	cooperative.disabled = not host or people.size() == 2
	cooperative.pressed.connect(func(): Net.set_setting("tr_coop", not bool(settings.get("tr_coop", false))))
	body.add_child(cooperative)
	body.add_child(Style.label("Никаких уровней сложности: знающий выберет 1 из 3 правил каждого кольца.", 16, Style.muted()))
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
