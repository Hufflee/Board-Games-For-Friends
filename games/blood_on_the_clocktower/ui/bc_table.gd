extends Control
## Постоянный стол: публичные места, собственная роль и адресные запросы. View не пересоздаёт сцену.
const Style := preload("res://games/blood_on_the_clocktower/ui/bc_style.gd")
const Data := preload("res://games/blood_on_the_clocktower/logic/bc_data.gd")
const Art := preload("res://games/blood_on_the_clocktower/ui/bc_art.gd")
var app: Control
var view: Dictionary = {}
var top: TopBar
var circle: Control
var seat_nodes: Dictionary = {}
var phase_label: Label
var nomination: Label
var event_label: Label
var personal: PanelContainer
var role_icon: TextureRect
var role_name: Label
var role_text: Label
var side_label: Label
var evil_votes_label: Label
var role_key := ""
var target: OptionButton
var solo: OptionButton
var actions: Dictionary = {}
var request_panel: VBoxContainer
var request_title: Label
var request_hint: Label
var request_options: ItemList
var request_confirm: Button
var request_search: LineEdit
var request_token := ""
var request_indices: Array[int] = []
var request_data: Array = []
var selected_option := -1
var messages: RichTextLabel
var public_log: RichTextLabel
var log_window: PanelContainer
var grimoire: PanelContainer
var grimoire_text: RichTextLabel
var receiver: OptionButton
var private_text: LineEdit
var statement: LineEdit
var guess_target: Array[OptionButton] = []
var guess_role: Array[OptionButton] = []
var juggle_window: PanelContainer
var preview: PanelContainer
var preview_icon: TextureRect
var preview_name: Label
var preview_text: Label
var _last_messages := ""
var _last_log := ""
var _last_grimoire := ""
var _choice_sent := false

func _ready() -> void:
	theme = Style.theme()
	Art.backdrop(self)
	top = TopBar.make(self, "Кровь на часовой башне", Style.button, null, Style.INK, Style.font(true))
	for item: Array in [["Справочник", app.show_handbook], ["Настройки", app.show_settings], ["Журнал", _toggle_log]]:
		var button := Style.button(item[0], Style.SMALL)
		button.pressed.connect(item[1])
		top.actions.add_child(button)
	var leave := Style.button("Выйти", Style.SMALL)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	top.actions.add_child(leave)
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	body.offset_top = TopBar.HEIGHT + 16
	body.offset_left = 24
	body.offset_right = -24
	body.offset_bottom = -16
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	var square := VBoxContainer.new()
	square.size_flags_horizontal = SIZE_EXPAND_FILL
	square.add_theme_constant_override("separation", 8)
	body.add_child(square)
	var title_row := HBoxContainer.new()
	square.add_child(title_row)
	phase_label = Style.label("", Style.H1, Style.INK, true)
	phase_label.size_flags_horizontal = SIZE_EXPAND_FILL
	title_row.add_child(phase_label)
	solo = OptionButton.new()
	solo.name = "SoloSeat"
	solo.add_theme_font_size_override("font_size", Style.SMALL)
	solo.item_selected.connect(func(index: int): Net.send_action("view_seat", {"seat": index - 1}))
	title_row.add_child(solo)
	nomination = Style.label("", Style.SMALL, Style.MUTED)
	nomination.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	square.add_child(nomination)
	circle = Control.new()
	circle.name = "TownCircle"
	circle.custom_minimum_size = Vector2(480, 280)
	circle.size_flags_vertical = SIZE_EXPAND_FILL
	circle.resized.connect(_place_seats)
	square.add_child(circle)
	event_label = Style.label("", Style.BODY)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle.add_child(event_label)
	event_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	square.add_child(controls)
	var choose := HBoxContainer.new()
	controls.add_child(choose)
	target = OptionButton.new()
	target.name = "PublicTarget"
	target.custom_minimum_size.x = 180
	target.size_flags_horizontal = SIZE_EXPAND_FILL
	choose.add_child(target)
	for operation: Array in [["nominate", "Номинировать"], ["slay", "Заявить выстрел"], ["evil_vote", "Предложить жертву"], ["hand", "Поднять руку"], ["show_victory", "Показать итоги"]]:
		var button := _action(operation[0], operation[1], choose)
		if operation[0] == "hand": button.name = "RaiseHand"
		# Кнопка у всех: по правилам выстрел Истребителя можно заявить блефом, иначе кнопка выдавала бы роль.
		if operation[0] == "slay":
			button.tooltip_text = "Публично заявить выстрел Истребителя в выбранного игрока — один раз за партию.\nЕсли вы не Истребитель или цель не демон, все увидят «ничего не произошло»."
	var story := HBoxContainer.new()
	story.name = "StoryActions"
	controls.add_child(story)
	for operation: Array in [["begin_night", "Начать ночь"], ["open_nominations", "Номинации"], ["start_vote", "Начать голосование"], ["count_vote", "Следующий голос"], ["close_day", "Завершить день"]]:
		_action(operation[0], operation[1], story)
	var extras := HBoxContainer.new()
	controls.add_child(extras)
	for operation: Array in [["grimoire", "Гримуар"], ["tinker", "Смерть Лудильщика"], ["madness_execution", "Казнь за безумие"]]:
		_action(operation[0], operation[1], extras)
	var statements := HBoxContainer.new()
	statements.name = "Statements"
	controls.add_child(statements)
	statement = LineEdit.new()
	statement.name = "StatementText"
	statement.placeholder_text = "Вопрос Художника или публичная сплетня"
	statement.max_length = 500
	statement.size_flags_horizontal = SIZE_EXPAND_FILL
	statements.add_child(statement)
	for operation: Array in [["artist", "Вопрос"], ["gossip", "Сплетня"], ["savant", "Учёный"], ["juggle", "Жонглёр"]]:
		_action(operation[0], operation[1], statements)
	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size.x = 352
	side_panel.add_theme_stylebox_override("panel", Style.box())
	body.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(side_scroll)
	side_scroll.add_child(side)
	personal = PanelContainer.new()
	personal.name = "OwnRoleCard"
	personal.add_theme_stylebox_override("panel", Style.box(Style.INSET))
	side.add_child(personal)
	var card := HBoxContainer.new()
	personal.add_child(card)
	role_icon = TextureRect.new()
	role_icon.custom_minimum_size = Vector2(72, 72)
	role_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	role_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	role_icon.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(role_icon)
	var card_text := VBoxContainer.new()
	card_text.size_flags_horizontal = SIZE_EXPAND_FILL
	card.add_child(card_text)
	role_name = Style.label("", Style.BODY, Style.INK, true)
	role_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_text.add_child(role_name)
	# Команда игрока: цвет закреплён за смыслом (добро/зло).
	side_label = Style.label("", Style.SMALL)
	side_label.name = "OwnSide"
	card_text.add_child(side_label)
	role_text = Style.label("", Style.SMALL, Style.MUTED)
	role_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_text.custom_minimum_size.x = 200
	role_text.max_lines_visible = 3
	role_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_text.add_child(role_text)
	personal.mouse_entered.connect(_show_preview)
	personal.mouse_exited.connect(func(): preview.hide())
	# Домашнее правило: ночные голоса приспешников видят только злые; решает демон.
	evil_votes_label = Style.label("", Style.SMALL, Style.MUTED)
	evil_votes_label.name = "EvilVotes"
	evil_votes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evil_votes_label.visible = false
	side.add_child(evil_votes_label)
	request_panel = VBoxContainer.new()
	request_panel.name = "PrivateChoice"
	request_panel.size_flags_vertical = SIZE_EXPAND_FILL
	side.add_child(request_panel)
	request_title = Style.label("", Style.SMALL)
	request_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	request_panel.add_child(request_title)
	# Почему вариантов несколько: регистрации Шпиона/Отшельника, яд, Вортокс.
	request_hint = Style.label("", Style.SMALL, Style.MUTED)
	request_hint.name = "ChoiceHint"
	request_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	request_panel.add_child(request_hint)
	request_search = LineEdit.new()
	request_search.placeholder_text = "Найти вариант…"
	request_search.text_changed.connect(func(_text: String): _filter_choices())
	request_panel.add_child(request_search)
	request_options = ItemList.new()
	request_options.name = "ChoiceOptions"
	request_options.add_theme_font_size_override("font_size", Style.SMALL)
	request_options.custom_minimum_size.y = 100
	request_options.size_flags_vertical = SIZE_EXPAND_FILL
	request_options.item_selected.connect(func(index: int):
		selected_option = request_indices[index]
		request_confirm.disabled = false)
	request_panel.add_child(request_options)
	request_confirm = Style.button("Подтвердить", Style.SMALL)
	request_confirm.name = "ConfirmChoice"
	request_confirm.pressed.connect(_confirm_choice)
	request_panel.add_child(request_confirm)
	messages = RichTextLabel.new()
	messages.name = "PrivateMessages"
	messages.bbcode_enabled = false
	messages.custom_minimum_size.y = 96
	messages.size_flags_vertical = SIZE_EXPAND_FILL
	messages.add_theme_font_size_override("normal_font_size", Style.SMALL)
	side.add_child(messages)
	receiver = OptionButton.new()
	receiver.name = "WhisperRecipient"
	side.add_child(receiver)
	private_text = LineEdit.new()
	private_text.name = "WhisperText"
	private_text.placeholder_text = "Личное сообщение…"
	private_text.max_length = 500
	private_text.text_submitted.connect(func(_text: String): _send_whisper())
	side.add_child(private_text)
	var send := Style.button("Прошептать на ухо", Style.SMALL)
	send.pressed.connect(_send_whisper)
	side.add_child(send)
	log_window = _window("Журнал города")
	public_log = _text_window(log_window)
	grimoire = _window("Закрытый гримуар")
	grimoire_text = _text_window(grimoire)
	_build_juggle()
	_build_preview()
	Net.state_changed.connect(update_view)
	update_view(Net.view)

func _action(kind: String, title: String, parent: Control) -> Button:
	var button := Style.button(title, Style.SMALL)
	button.name = "Action_" + kind
	button.pressed.connect(_send.bind(kind))
	parent.add_child(button)
	actions[kind] = button
	return button

func _send(kind: String) -> void:
	if kind == "grimoire":
		grimoire.visible = not grimoire.visible
		return
	if kind == "juggle":
		juggle_window.show()
		return
	var arg := {"revision": int(view.get("revision", -1))}
	if kind in ["nominate", "slay", "tinker", "madness_execution", "evil_vote"]:
		if target.selected < 0: return
		arg["target"] = target.get_selected_id()
	if kind == "hand":
		var me := int(view.get("you", -1))
		arg["raised"] = not bool(view.players[me].hand) if me >= 0 else false
	if kind == "count_vote":
		arg["voter"] = int(view.get("next_voter", -1))
	if kind in ["artist", "gossip"]: arg["text"] = statement.text
	Net.send_action(kind, arg)

func update_view(next: Dictionary) -> void:
	if next.is_empty() or not next.has("edition"): return
	view = next
	var people: Array = view.get("players", [])
	var me := int(view.get("you", -1))
	var storyteller := int(view.get("storyteller", -2))
	var is_story := me == storyteller
	var phase := str(view.get("phase", ""))
	var labels := {"setup": "Подготовка", "night": "Ночь", "discussion": "Обсуждение", "nominations": "Номинации", "defense": "Защита", "voting": "Голосование", "dusk": "Сумерки", "game_over": "Партия завершена"}
	phase_label.text = str(labels.get(phase, phase))
	top.info.text = "День %d · %s" % [int(view.get("day", 0)), phase_label.text]
	var text := "Роли других игроков скрыты. Обсуждайте, сомневайтесь и блефуйте."
	# Последнее публичное событие дня (выстрел, смерть, шёпот) видно без открытия журнала.
	var events: Array = view.get("log", [])
	if phase in ["discussion", "nominations", "defense", "dusk"] and not events.is_empty():
		text = str(events.back())
	var nominee := int(view.get("nominee", -1))
	if nominee >= 0:
		text = "Номинирован: %s" % people[nominee].name
		if phase == "voting": text += " · голосов: %d · далее: %s" % [int(view.get("vote_total", 0)), _person(int(view.get("next_voter", -1)))]
	elif int(view.get("leader", -1)) >= 0:
		text = "На плахе: %s · %d голосов" % [_person(int(view.leader)), int(view.high_vote)]
	if phase == "game_over": text = "Победило %s" % ("добро" if view.get("winner") == "good" else "зло")
	nomination.text = text
	event_label.text = str(view.get("event", {}).get("text", ""))
	_ensure_seats(people)
	# Роли рядом с никами: рассказчику — всегда (его гримуар), всем — после конца партии.
	var role_of: Dictionary = {}
	for known: Dictionary in view.get("grimoire", view.get("revealed", [])):
		role_of[int(known.seat)] = known
	for seat: int in seat_nodes:
		var entry: Dictionary = people[seat]
		var refs: Dictionary = seat_nodes[seat]
		refs.name_label.text = str(entry.name)
		# С ролью ник переносится внутри плашки прежней ширины: при 15 местах широкие плашки налезали друг на друга.
		refs.name_label.clip_text = not role_of.has(seat)
		refs.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if role_of.has(seat) else TextServer.AUTOWRAP_OFF
		refs.name_label.max_lines_visible = 2 if role_of.has(seat) else -1
		refs.name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if role_of.has(seat):
			# Ник и роль в скобках; длинная роль — с многоточием, целиком в подсказке.
			refs.name_label.text += "\n(%s)" % _role_caption(role_of[seat])
		# Плашка узкая (текст ~104 px): состояние — одной короткой строкой, рука — стрелкой у имени,
		# полное пояснение — в подсказке. «Мёртв» без пометки — последний голос уже потрачен.
		var vote: bool = bool(entry.alive) or bool(entry.dead_vote)
		refs.state.text = "Жив" if entry.alive else ("Мёртв · голос" if vote else "Мёртв")
		refs.hand.visible = bool(entry.hand)
		# «…» — участник последнего дневного шёпота (виден факт разговора, не текст).
		var whispering: bool = view.get("last_whisper", []).has(seat)
		refs.whisper.visible = whispering
		refs.panel.tooltip_text = "%s\n%s%s%s" % [refs.name_label.text.replace("\n", " "),
			"Жив" if entry.alive else ("Мёртв, остался последний голос" if vote else "Мёртв, голоса больше нет"),
			"\nРука поднята" if entry.hand else "", "\nСейчас шепчется" if whispering else ""]
		refs.panel.modulate = Color.WHITE if entry.alive else Color(0.7, 0.74, 0.8)
		refs.panel.add_theme_stylebox_override("panel", Style.box(Style.ACCENT if seat == nominee else Style.PANEL))
	_place_seats.call_deferred()
	solo.visible = bool(view.get("hotseat", false))
	if solo.item_count != people.size() + 1:
		solo.clear()
		solo.add_item("Соло: зритель")
		for i in people.size(): solo.add_item("Соло: %s%s" % [people[i].name, " · рассказчик" if i == storyteller else ""])
	if solo.visible: solo.select(me + 1)
	# Ночью игрок может шептать только рассказчику — остальных в списке нет.
	var listeners: Array[int] = []
	for i in people.size():
		if i == me: continue
		if phase == "night" and not is_story and i != storyteller: continue
		listeners.append(i)
	_sync_people(receiver, people, listeners)
	var my_side := str(view.get("side", ""))
	side_label.visible = not my_side.is_empty()
	side_label.text = "Команда добра" if my_side == "good" else "Команда зла"
	side_label.add_theme_color_override("font_color", Style.GOOD if my_side == "good" else Style.EVIL)
	evil_votes_label.visible = view.has("evil_votes") and phase == "night"
	if evil_votes_label.visible:
		var lines: Array[String] = []
		for vote: Dictionary in view.evil_votes:
			lines.append("%s → %s" % [_person(int(vote.from)), _person(int(vote.target))])
		evil_votes_label.text = "Голоса приспешников (видит только зло, решает демон): %s" % (
			"; ".join(lines) if not lines.is_empty() else "пока нет")
	var current_role := str(view.get("role", ""))
	if current_role != role_key or role_name.text.is_empty():
		role_key = current_role
		role_icon.texture = Art.role(role_key)
		var card: Dictionary = Data.catalog().get(role_key, {})
		role_name.text = str(card.get("name", "Рассказчик" if is_story else "Зритель"))
		role_text.text = str(card.get("text", "Вы ведёте город и принимаете решения по правилам." if is_story else "Вам доступна только публичная информация."))
	var request: Dictionary = view.get("request", {})
	var token := str(request.get("token", ""))
	if token != request_token:
		request_token = token
		_choice_sent = false
		selected_option = -1
		request_search.text = ""
		request_data = request.get("options", []).duplicate(true)
		request_title.text = str(request.get("title", ""))
		request_hint.text = str(request.get("hint", ""))
		request_hint.visible = not request_hint.text.is_empty()
		_filter_choices()
		request_confirm.disabled = true
	request_panel.visible = not token.is_empty()
	messages.visible = token.is_empty()
	messages.size_flags_vertical = SIZE_EXPAND_FILL if token.is_empty() else SIZE_FILL
	request_confirm.disabled = selected_option < 0 or _choice_sent
	_update_texts()
	var day := phase in ["discussion", "nominations"]
	var alive := me >= 0 and bool(people[me].alive)
	var blocked: bool = not view.get("event", {}).is_empty() or bool(view.get("game_paused", false))
	for kind: String in actions:
		actions[kind].disabled = blocked
	for kind: String in ["begin_night", "open_nominations", "start_vote", "count_vote", "close_day", "tinker", "madness_execution"]:
		actions[kind].visible = is_story
	actions.begin_night.visible = is_story and (phase in ["setup", "dusk"] or (phase == "night" and int(view.get("day", 0)) == 0))
	actions.open_nominations.visible = is_story and phase == "discussion"
	actions.start_vote.visible = is_story and phase == "defense"
	actions.count_vote.visible = is_story and phase == "voting"
	actions.close_day.visible = is_story and phase == "nominations"
	actions.tinker.visible = is_story and view.edition == "bmr"
	actions.madness_execution.visible = is_story and view.edition == "sv"
	actions.nominate.visible = not is_story and alive and phase == "nominations"
	actions.slay.visible = not is_story and alive and day and view.edition == "tb" and not bool(people[me].get("slayer_shot", false))
	actions.evil_vote.visible = bool(view.get("evil_vote_open", false))
	actions.show_victory.visible = phase == "game_over" and Net.is_host() and not bool(view.get("victory_open", false))
	actions.hand.visible = not is_story and me >= 0 and phase == "voting"
	if me >= 0: actions.hand.text = "Опустить руку" if bool(people[me].hand) else "Поднять руку"
	actions.artist.visible = not is_story and day and role_key == "artist"
	actions.savant.visible = not is_story and day and role_key == "savant"
	actions.gossip.visible = not is_story and alive and day and view.edition == "bmr"
	actions.juggle.visible = not is_story and alive and day and view.edition == "sv"
	_sync_targets(people, me, storyteller)
	statement.get_parent().visible = actions.artist.visible or actions.savant.visible or actions.gossip.visible or actions.juggle.visible
	statement.visible = actions.artist.visible or actions.gossip.visible
	if not view.has("grimoire") and not view.get("knowledge", {}).has("grimoire"): grimoire.hide()
	if me < 0:
		private_text.editable = false
		private_text.text = ""
		grimoire_text.text = ""
	# При смене тестового места закрытые окна очищаются вместе с собственным view.
	if not view.has("grimoire") and not view.get("knowledge", {}).has("grimoire"):
		grimoire_text.text = ""
	private_text.editable = me >= 0 and phase != "game_over"

func _ensure_seats(people: Array) -> void:
	if not seat_nodes.is_empty(): return
	for i in people.size():
		if bool(people[i].storyteller): continue
		var panel := PanelContainer.new()
		panel.name = "Seat_%d" % i
		panel.custom_minimum_size = Vector2(136, 68)
		panel.size = Vector2(136, 68)
		panel.mouse_filter = MOUSE_FILTER_STOP
		circle.add_child(panel)
		var col := VBoxContainer.new()
		col.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var row := HBoxContainer.new()
		row.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(row)
		var dot := ColorRect.new()
		dot.color = Net.color_of(int(people[i].color))
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = SIZE_SHRINK_CENTER
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var nick := Style.label(str(people[i].name), Style.SMALL)
		nick.custom_minimum_size.x = 80
		nick.size_flags_horizontal = SIZE_EXPAND_FILL
		nick.clip_text = true
		nick.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(nick)
		var whisper := Style.label("…", Style.SMALL, Style.MUTED)
		whisper.visible = false
		whisper.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(whisper)
		var hand := Style.label("↑", Style.SMALL)
		hand.visible = false
		hand.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(hand)
		var state := Style.label("", Style.SMALL, Style.MUTED)
		state.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(state)
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				for j in target.item_count:
					if target.get_item_id(j) == i: target.select(j))
		seat_nodes[i] = {"panel": panel, "name_label": nick, "state": state, "hand": hand, "whisper": whisper}
	_place_seats()

func _place_seats() -> void:
	var count := seat_nodes.size()
	var keys: Array = seat_nodes.keys()
	var tallest := 0.0
	for key: int in keys:
		var panel: Control = seat_nodes[key].panel
		panel.size = Vector2(136, 0)
		panel.size = panel.get_combined_minimum_size()
		tallest = maxf(tallest, panel.size.y)
	# Места по периметру прямоугольника площади, по часовой стрелке от середины верха.
	# Владелец 06.11: плашки не наслаиваются — масштаб уменьшается, пока все места не встанут с зазором
	# (шаг меряем «в плашках»: по горизонтали — шириной, по вертикали — высотой).
	var scale := 1.0
	var span: Vector2
	var top: float
	var side: float
	var pitch: Vector2
	var across: float
	var down: float
	var total: float
	while true:
		var plate := Vector2(136, tallest) * scale
		span = Vector2(maxf(1.0, circle.size.x - plate.x), maxf(1.0, circle.size.y - plate.y))
		# Боковые колонки — между верхним и нижним рядами, чтобы угловые плашки не наезжали.
		top = plate.y + 8.0
		side = maxf(0.0, span.y - 2.0 * top)
		pitch = Vector2(plate.x + 8.0, top)
		across = span.x / pitch.x
		down = side / pitch.y
		total = 2.0 * (across + down)
		if total >= count or scale <= 0.5:
			break
		scale -= 0.05
	for i in count:
		var d := fposmod(total * i / maxi(1, count) + across / 2, total)
		var corner: Vector2
		if d < across: corner = Vector2(d * pitch.x, 0)
		elif d < across + down: corner = Vector2(span.x, top + (d - across) * pitch.y)
		elif d < 2 * across + down: corner = Vector2(span.x - (d - across - down) * pitch.x, span.y)
		else: corner = Vector2(0, top + side - (d - 2 * across - down) * pitch.y)
		var panel: Control = seat_nodes[keys[i]].panel
		panel.scale = Vector2(scale, scale)
		panel.position = corner + Vector2(0, (tallest - panel.size.y) * scale / 2)
	if event_label != null:
		event_label.position = circle.size / 2 - event_label.size / 2

## Список целей — только когда видна кнопка, которой он нужен, и только допустимые для неё игроки.
func _sync_targets(people: Array, me: int, storyteller: int) -> void:
	var nominated: Array = view.get("nominated", [])
	var ids: Array[int] = []
	for i in people.size():
		if i == storyteller: continue
		var living := bool(people[i].alive)
		if actions.nominate.visible:
			# Мёртвых не номинируем (решение владельца), кроме «Дурной луны» — из-за Зомбуула.
			if not nominated.has(i) and (living or view.edition == "bmr"): ids.append(i)
		elif actions.slay.visible or actions.evil_vote.visible:
			if living and i != me: ids.append(i)
		elif actions.tinker.visible or actions.madness_execution.visible:
			ids.append(i)
	target.visible = not ids.is_empty()
	_sync_people(target, people, ids)

func _sync_people(menu: OptionButton, people: Array, ids: Array[int]) -> void:
	var expected: Array[String] = []
	for i: int in ids:
		expected.append(str(people[i].name))
	if menu.get_meta("names", []) == expected and menu.get_meta("ids", []) == ids: return
	var previous := menu.get_selected_id()
	menu.clear()
	for i in expected.size(): menu.add_item(expected[i], ids[i])
	for i in ids.size():
		if ids[i] == previous: menu.select(i)
	menu.set_meta("names", expected)
	menu.set_meta("ids", ids)

## Подпись роли у ника: настоящая роль, а для Пьяницы/Лунатика — ещё и та, которой он себя считает.
func _role_caption(known: Dictionary) -> String:
	var catalog: Dictionary = Data.catalog()
	var real := str(catalog.get(str(known.get("role", "")), {}).get("name", "?"))
	var shown := str(known.get("shown_role", known.get("role", "")))
	if shown != str(known.get("role", "")) and catalog.has(shown):
		return "%s · %s" % [real, catalog[shown].name]
	return real

func _person(index: int) -> String:
	var people: Array = view.get("players", [])
	return str(people[index].name) if index >= 0 and index < people.size() else "—"

func _filter_choices() -> void:
	request_options.clear()
	request_indices.clear()
	selected_option = -1
	for i in request_data.size():
		var option: Variant = request_data[i]
		var text := str(option.get("label", option.get("text", "Вариант %d" % (i + 1)))) if option is Dictionary else str(option)
		if not request_search.text.is_empty() and not text.to_lower().contains(request_search.text.to_lower()): continue
		request_indices.append(i)
		request_options.add_item(text)
		request_options.set_item_tooltip(request_options.item_count - 1, text)
	request_confirm.disabled = true

func _confirm_choice() -> void:
	if selected_option < 0 or _choice_sent: return
	_choice_sent = true
	request_confirm.disabled = true
	Net.send_action("private_reply", {"token": request_token, "index": selected_option})

func _update_texts() -> void:
	var text := "\n\n".join(view.get("messages", []))
	if text != _last_messages:
		_last_messages = text
		messages.text = text
		messages.scroll_to_line(maxi(0, messages.get_line_count() - 1))
	text = "\n\n".join(view.get("log", []))
	if text != _last_log:
		_last_log = text
		public_log.text = text
	var entries: Array = view.get("grimoire", view.get("knowledge", {}).get("grimoire", []))
	var lines: Array[String] = []
	for item: Dictionary in entries:
		lines.append("%s · %s · %s · %s\n%s" % [_person(int(item.seat)), str(Data.catalog().get(str(item.role), {}).get("name", item.role)), "добро" if item.side == "good" else "зло", "жив" if item.alive else "мёртв", "Здоров" if item.get("healthy", true) else "Способность нарушена"])
		lines.append(preload("res://games/blood_on_the_clocktower/ui/bc_status.gd").describe(item.get("status", {}), view.get("players", [])))
	text = "\n\n".join(lines)
	if text != _last_grimoire:
		_last_grimoire = text
		grimoire_text.text = text
	actions.grimoire.visible = not entries.is_empty()

func _send_whisper() -> void:
	if private_text.text.strip_edges().is_empty() or receiver.selected < 0: return
	Net.send_action("whisper", {"target": receiver.get_selected_id(), "text": private_text.text})
	private_text.clear()
	private_text.grab_focus()

func _window(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box())
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	panel.offset_left = 160
	panel.offset_right = -160
	panel.offset_top = 80
	panel.offset_bottom = -40
	panel.z_index = 105
	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	var label := Style.label(title, Style.H1, Style.INK, true)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(label)
	var close := Style.button("Закрыть", Style.SMALL)
	close.pressed.connect(func(): panel.hide())
	header.add_child(close)
	add_child(panel)
	panel.hide()
	return panel

func _text_window(window: PanelContainer) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.size_flags_vertical = SIZE_EXPAND_FILL
	window.get_node("Content").add_child(text)
	return text

func _toggle_log() -> void:
	log_window.visible = not log_window.visible

func _build_juggle() -> void:
	juggle_window = _window("Публичные предположения Жонглёра")
	var col := juggle_window.get_node("Content")
	for i in 5:
		var row := HBoxContainer.new()
		col.add_child(row)
		var who := OptionButton.new()
		who.custom_minimum_size.x = 220
		row.add_child(who)
		guess_target.append(who)
		var role := OptionButton.new()
		role.add_item("Не указывать", 0)
		for entry: Dictionary in Data.handbook("sv"):
			role.add_item(entry.name)
			role.set_item_metadata(role.item_count - 1, entry.id)
		row.add_child(role)
		guess_role.append(role)
	var send := Style.button("Огласить предположения")
	send.pressed.connect(func():
		var guesses: Array = []
		for i in 5:
			if guess_role[i].selected > 0:
				guesses.append({"target": guess_target[i].get_selected_id(), "role": guess_role[i].get_selected_metadata()})
		Net.send_action("juggle", {"revision": int(view.revision), "guesses": guesses})
		juggle_window.hide())
	col.add_child(send)
	juggle_window.visibility_changed.connect(func():
		if juggle_window.visible:
			# Жонглёр угадывает роли любых игроков круга (кроме рассказчика).
			var circle: Array[int] = []
			for i in view.get("players", []).size():
				if i != int(view.get("storyteller", -1)): circle.append(i)
			for menu: OptionButton in guess_target: _sync_people(menu, view.get("players", []), circle))

func _build_preview() -> void:
	preview = PanelContainer.new()
	preview.name = "RolePreview"
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", Style.box())
	preview.custom_minimum_size = Vector2(320, 360)
	preview.z_index = 110
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	preview.add_child(col)
	preview_icon = TextureRect.new()
	preview_icon.custom_minimum_size = Vector2(144, 144)
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(preview_icon)
	preview_name = Style.label("", Style.H1, Style.INK, true)
	preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(preview_name)
	preview_text = Style.label("", Style.BODY)
	preview_text.custom_minimum_size.x = 288
	preview_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(preview_text)
	add_child(preview)
	preview.hide()

func _show_preview() -> void:
	if role_key.is_empty() or Net.paused: return
	if preload("res://hub/card_magnifier.gd").offer(self): return
	preview_icon.texture = role_icon.texture
	preview_name.text = role_name.text
	preview_text.text = role_text.text
	preview.position = Vector2(maxf(16, personal.global_position.x - 336), maxf(56, personal.global_position.y))
	preview.show()
