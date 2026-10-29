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
	body = Style.column(16)
	margin.add_child(body)
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
	body.add_child(Style.label("За столом: " + " · ".join(names)))
	if host and Net.mode == "offline":
		var row := Style.row()
		for n: int in range(2, 7):
			var count := Style.button("%d игроков" % n)
			UISel.pick(count, people.size() == n)
			count.pressed.connect(func(): Net.set_bots(n - 1))
			row.add_child(count)
		body.add_child(row)
	var rings: Array = settings.get("tr_rings", ["Attribute", "Word", "Context"])
	body.add_child(Style.label("Кольца · выберите от одного до трёх"))
	var ring_row := Style.row()
	for category: String in ["Attribute", "Word", "Context"]:
		var b := Style.button(Style.category_name(category))
		UISel.pick(b, category in rings)
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
	body.add_child(ring_row)
	var role_row := Style.row()
	role_row.add_child(Style.label("Знающий:"))
	for seat: int in people.size():
		var b := Style.button(str(people[seat].name))
		UISel.pick(b, seat == int(settings.get("tr_knower", 0)))
		b.disabled = not host
		b.pressed.connect(func(): Net.set_setting("tr_knower", seat))
		role_row.add_child(b)
	body.add_child(role_row)
	var cooperative := Style.button("Кооператив" if people.size() != 2 else "Вдвоём · кооператив автоматически")
	cooperative.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UISel.pick(cooperative, bool(settings.get("tr_coop", false)) or people.size() == 2)
	cooperative.disabled = not host or people.size() == 2
	cooperative.pressed.connect(func(): Net.set_setting("tr_coop", not bool(settings.get("tr_coop", false))))
	body.add_child(cooperative)
	body.add_child(Style.label("Никаких уровней сложности: знающий выберет 1 из 3 правил каждого кольца.", 16, Style.muted()))
	var error := Style.label("", 16, Style.muted())
	if host:
		var start := Style.button("Начать партию")
		start.custom_minimum_size.x = 400
		start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		start.name = "StartGame"
		start.theme_type_variation = "SelectedButton"
		start.pressed.connect(func(): error.text = Net.start_game())
		body.add_child(start)
	else:
		body.add_child(Style.label("Ждём хоста…"))
	body.add_child(error)
	var leave := Style.button("К выбору игры")
	leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	body.add_child(leave)

