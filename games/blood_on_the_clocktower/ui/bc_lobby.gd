extends Control
## Постоянное лобби; секретный редактор состава существует только у рассказчика.
const Style := preload("res://games/blood_on_the_clocktower/ui/bc_style.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const Setup := preload("res://games/blood_on_the_clocktower/logic/bc_setup.gd")
var app: Control
var edition: OptionButton
var teller: OptionButton
var roster: Label
var error: Label
var secret: VBoxContainer
var roles: ItemList
var bluffs: ItemList
var drunk: OptionButton
var lunatic: OptionButton
var delta: OptionButton
var start: Button
var role_ids: Array[String] = []
var bluff_ids: Array[String] = []
var draft_key := ""
var accepted_revision := -1
var updating := false

func _ready() -> void:
	theme = Style.theme()
	preload("res://games/blood_on_the_clocktower/ui/bc_art.gd").backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	margin.add_child(columns)
	var public := VBoxContainer.new()
	public.custom_minimum_size.x = 350
	public.size_flags_horizontal = SIZE_EXPAND_FILL
	public.add_theme_constant_override("separation", 16)
	columns.add_child(public)
	public.add_child(Style.label("Часовая башня", Style.H1, Style.INK, true))
	public.add_child(Style.label("Подготовка партии", Style.BODY, Style.MUTED))
	edition = OptionButton.new()
	for id: String in Data.EDITIONS:
		edition.add_item(Data.EDITIONS[id].name)
	edition.item_selected.connect(func(index: int):
		if not updating: Net.set_setting("bc_edition", Data.EDITIONS.keys()[index]))
	public.add_child(edition)
	public.add_child(Style.label("Рассказчик — отдельный участник", Style.SMALL))
	teller = OptionButton.new()
	teller.item_selected.connect(func(index: int):
		if not updating: Net.set_setting("bc_storyteller", index))
	public.add_child(teller)
	roster = Style.label("", Style.SMALL)
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Без растяжения по ширине перенос внутри прокрутки получал ширину 0 и ставил каждую букву на свою строку.
	roster.size_flags_horizontal = SIZE_EXPAND_FILL
	var roster_scroll := ScrollContainer.new()
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	roster_scroll.custom_minimum_size.y = 96
	public.add_child(roster_scroll)
	roster_scroll.add_child(roster)
	var local := HBoxContainer.new()
	local.name = "SoloSeats"
	for change: int in [-1, 1]:
		var button := Style.button("− Место" if change < 0 else "+ Место", Style.SMALL)
		button.pressed.connect(func(): Net.set_bots(clampi(Net.bots + change, 5, 15)))
		local.add_child(button)
	public.add_child(local)
	local.visible = Net.mode == "offline"
	var handbook := Style.button("Справочник")
	handbook.pressed.connect(app.show_handbook)
	public.add_child(handbook)
	start = Style.button("Начать партию")
	start.name = "StartGame"
	start.add_theme_stylebox_override("normal", Style.box(Style.ACCENT))
	start.pressed.connect(func(): error.text = Net.start_game())
	public.add_child(start)
	var leave := Style.button("К выбору игры", Style.SMALL)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться в хаб.", app.back_to_hub)
	public.add_child(leave)
	error = Style.label("", Style.SMALL, Style.MUTED)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	public.add_child(error)
	secret = VBoxContainer.new()
	secret.custom_minimum_size.x = 540
	secret.size_flags_horizontal = SIZE_EXPAND_FILL
	secret.add_theme_constant_override("separation", 8)
	var secret_scroll := ScrollContainer.new()
	secret_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	secret_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(secret_scroll)
	secret_scroll.add_child(secret)
	secret.add_child(Style.label("Закрытая подготовка рассказчика", Style.BODY))
	secret.add_child(Style.label("Состав перемешивается. Другие участники его не получают.", Style.SMALL, Style.MUTED))
	var lists := HBoxContainer.new()
	lists.custom_minimum_size.y = 280
	secret.add_child(lists)
	for title: String in ["Роли в мешке", "Три блефа демона"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		lists.add_child(col)
		col.add_child(Style.label(title, Style.SMALL))
		var list := ItemList.new()
		list.select_mode = ItemList.SELECT_MULTI
		list.size_flags_vertical = SIZE_EXPAND_FILL
		list.custom_minimum_size = Vector2(250, 200)
		list.add_theme_font_size_override("font_size", Style.SMALL)
		col.add_child(list)
		if title == "Роли в мешке": roles = list
		else: bluffs = list
	for title: String in ["Подставная роль Пьяницы", "Вид демона Лунатика", "Крёстный отец: число изгоев"]:
		var row := HBoxContainer.new()
		row.add_child(Style.label(title, Style.SMALL))
		var option := OptionButton.new()
		option.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(option)
		secret.add_child(row)
		if title.begins_with("Подставная"): drunk = option
		elif title.begins_with("Вид"): lunatic = option
		else: delta = option
		if option != delta:
			var shuffle := Style.button("Случайно", Style.SMALL)
			shuffle.tooltip_text = "Выбрать подставную роль случайно из допустимых"
			shuffle.pressed.connect(_random_fake.bind(option))
			row.add_child(shuffle)
	delta.add_item("−1")
	delta.add_item("+1")
	var buttons := HBoxContainer.new()
	secret.add_child(buttons)
	var suggest := Style.button("Случайный состав", Style.SMALL)
	suggest.pressed.connect(func(): _fill(Setup.suggest(str(Net.settings.bc_edition), Net.player_total() - 1)))
	buttons.add_child(suggest)
	var save := Style.button("Применить состав", Style.SMALL)
	save.pressed.connect(_save)
	buttons.add_child(save)
	Net.lobby_changed.connect(refresh)
	refresh()

func refresh() -> void:
	updating = true
	var members: Array = Net.lobby_view.get("members", [])
	var options: Dictionary = Net.lobby_view.get("settings", Net.settings)
	var id := str(options.get("bc_edition", "tb"))
	edition.select(Data.EDITIONS.keys().find(id))
	edition.disabled = not Net.is_host()
	teller.disabled = not Net.is_host()
	var names: Array[String] = []
	for member: Dictionary in members:
		names.append(str(member.get("name", "Игрок")))
	var joined := "\n".join(names)
	if teller.item_count != names.size() or roster.text != joined:
		teller.clear()
		for nick: String in names: teller.add_item(nick)
		roster.text = joined
	if teller.item_count > 0: teller.select(clampi(int(options.get("bc_storyteller", 0)), 0, teller.item_count - 1))
	start.visible = Net.is_host()
	start.disabled = names.size() - 1 < int(Data.EDITIONS[id].minimum) or names.size() > 16
	secret.visible = Net.bc_bridge.is_story_lobby()
	var packet: Dictionary = Net.bc_bridge.setup_view
	if secret.visible and not packet.is_empty():
		var key := str(packet.get("key", ""))
		var revision := int(packet.get("revision", -1))
		if key != draft_key or accepted_revision != revision:
			draft_key = key
			accepted_revision = revision
			_build_choices(id)
			_fill(packet.get("options", {}))
		error.text = str(packet.get("error", ""))
	elif not secret.visible:
		draft_key = ""
		roles.clear()
		bluffs.clear()
	updating = false

func _build_choices(id: String) -> void:
	roles.clear()
	bluffs.clear()
	drunk.clear()
	lunatic.clear()
	role_ids.clear()
	bluff_ids.clear()
	for entry: Dictionary in Data.handbook(id):
		role_ids.append(entry.id)
		roles.add_item("%s · %s" % [entry.name, Data.TYPES[entry.type]])
		if entry.side == "good":
			bluff_ids.append(entry.id)
			bluffs.add_item(entry.name)
		if entry.type == "townsfolk":
			drunk.add_item(entry.name)
			drunk.set_item_metadata(drunk.item_count - 1, entry.id)
		if entry.type == "demon":
			lunatic.add_item(entry.name)
			lunatic.set_item_metadata(lunatic.item_count - 1, entry.id)

func _fill(options: Dictionary) -> void:
	roles.deselect_all()
	bluffs.deselect_all()
	for id: String in options.get("bc_roles", []):
		if role_ids.has(id): roles.select(role_ids.find(id), false)
	for id: String in options.get("bc_bluffs", []):
		if bluff_ids.has(id): bluffs.select(bluff_ids.find(id), false)
	for pair: Array in [[drunk, "bc_drunk_role"], [lunatic, "bc_lunatic_role"]]:
		var menu: OptionButton = pair[0]
		for i in menu.item_count:
			if menu.get_item_metadata(i) == options.get(pair[1], ""): menu.select(i)
	delta.select(1 if int(options.get("bc_godfather_delta", 1)) == 1 else 0)

## Случайная подставная роль: Пьянице — горожанин вне мешка и блефов, Лунатику — любой демон сценария.
func _random_fake(menu: OptionButton) -> void:
	var taken: Array = []
	for index: int in roles.get_selected_items(): taken.append(role_ids[index])
	for index: int in bluffs.get_selected_items(): taken.append(bluff_ids[index])
	var allowed: Array[int] = []
	for i in menu.item_count:
		if menu == lunatic or not taken.has(menu.get_item_metadata(i)):
			allowed.append(i)
	if not allowed.is_empty():
		menu.select(allowed.pick_random())

func _save() -> void:
	var chosen: Array = []
	var absent: Array = []
	for index: int in roles.get_selected_items(): chosen.append(role_ids[index])
	for index: int in bluffs.get_selected_items(): absent.append(bluff_ids[index])
	Net.bc_configure({"bc_roles": chosen, "bc_bluffs": absent,
		"bc_drunk_role": drunk.get_selected_metadata(), "bc_lunatic_role": lunatic.get_selected_metadata(),
		"bc_godfather_delta": 1 if delta.selected == 1 else -1})
