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
var phase_badge: PanelContainer
var nomination: Label
var controls: VBoxContainer
var event_label: Label
var personal: PanelContainer
var role_toggle: Button
var role_folded := false
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
## Выбор игроков щелчком по плашкам: "" — обычный список, "one" — один игрок, "pair" — два (Гадалка).
var pick_mode := ""
var picked: Array[int] = []
var request_summary: Label
## Пары (Гадалка, информация Прачки/Библиотекаря/Сыщика): левый и правый игрок, при нужде — роль.
var slot_row: VBoxContainer
var slot_left: OptionButton
var slot_right: OptionButton
var slot_role: OptionButton
var _slot_sync := false
var messages: RichTextLabel
var public_log: RichTextLabel
var log_window: PanelContainer
var grimoire: Control
var grimoire_text: RichTextLabel
var receiver: OptionButton
var shout_button: Button
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
var _message_seat := -2
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
	var leave := Style.button("Выйти" if Net.is_host() else "Выйти из пати", Style.SMALL)
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
	phase_badge = PanelContainer.new()
	phase_badge.size_flags_horizontal = SIZE_SHRINK_BEGIN
	title_row.add_child(phase_badge)
	phase_label = Style.label("", Style.BODY, Style.INK, true)
	phase_badge.add_child(phase_label)
	title_row.add_spacer(false)
	solo = OptionButton.new()
	solo.name = "SoloSeat"
	solo.add_theme_font_size_override("font_size", Style.SMALL)
	solo.item_selected.connect(func(index: int): Net.send_action("view_seat", {"seat": index - 1}))
	title_row.add_child(solo)
	nomination = Style.label("", Style.SMALL, Style.MUTED)
	nomination.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Строка события всегда в две строки высотой: иначе 1↔2 строки от чужого действия меняли высоту площади
	# и плашки мест подёргивались. Длиннее — многоточие, целиком в подсказке.
	nomination.max_lines_visible = 2
	nomination.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nomination.custom_minimum_size.y = 2 * (Style.SMALL + 7)
	nomination.mouse_filter = MOUSE_FILTER_PASS
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
	controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	square.add_child(controls)
	var choose := HBoxContainer.new()
	controls.add_child(choose)
	target = OptionButton.new()
	target.name = "PublicTarget"
	target.item_selected.connect(func(_i: int): _paint_picks())
	target.custom_minimum_size.x = 180
	target.size_flags_horizontal = SIZE_EXPAND_FILL
	choose.add_child(target)
	for operation: Array in [["nominate", "Номинировать"], ["slay", "Заявить выстрел"], ["evil_vote", "Предложить жертву"], ["hand", "Поднять руку"], ["cast_vote", "Голосую"], ["abstain", "Воздержаться"], ["end_speech", "Закончить речь"], ["show_victory", "Показать итоги"]]:
		var button := _action(operation[0], operation[1], choose)
		if operation[0] == "hand": button.name = "RaiseHand"
		if operation[0] == "cast_vote":
			button.add_theme_stylebox_override("normal", Style.box(Style.ACCENT))
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
	# Владелец 07.11: без общей прокрутки — сверху роль (сворачивается), снизу «Прошептать/Прокричать»,
	# всё место между ними — сообщения (новые снизу, старые уезжают вверх).
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	side_panel.add_child(side)
	role_toggle = Style.button("", Style.SMALL)
	role_toggle.name = "RoleToggle"
	role_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	role_toggle.clip_text = true
	role_toggle.tooltip_text = "Свернуть или развернуть карточку роли"
	role_toggle.pressed.connect(func():
		role_folded = not role_folded
		_sync_role_card())
	side.add_child(role_toggle)
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
		picked.clear()
		if pick_mode == "pair":
			_sync_slots()
			selected_option = request_indices[index]
		_paint_picks()
		request_confirm.disabled = _choice_sent)
	request_panel.add_child(request_options)
	# Два игрока — одной строкой, роль — второй: в 352 px три списка обрезали имена.
	slot_row = VBoxContainer.new()
	slot_row.name = "PairSlots"
	slot_row.add_theme_constant_override("separation", 8)
	request_panel.add_child(slot_row)
	var pair_line := HBoxContainer.new()
	pair_line.add_theme_constant_override("separation", 8)
	slot_row.add_child(pair_line)
	slot_left = OptionButton.new()
	slot_right = OptionButton.new()
	slot_role = OptionButton.new()
	for menu: OptionButton in [slot_left, slot_right, slot_role]:
		menu.size_flags_horizontal = SIZE_EXPAND_FILL
		menu.custom_minimum_size.x = 64
		menu.fit_to_longest_item = false
		menu.add_theme_font_size_override("font_size", Style.SMALL)
		menu.clip_text = true
		(slot_row if menu == slot_role else pair_line).add_child(menu)
	slot_left.item_selected.connect(func(_i: int): _slot_changed(0))
	slot_right.item_selected.connect(func(_i: int): _slot_changed(1))
	slot_role.item_selected.connect(func(_i: int): _slot_changed(2))
	request_summary = Style.label("", Style.SMALL)
	request_summary.name = "ChoiceSummary"
	request_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	request_panel.add_child(request_summary)
	request_confirm = Style.button("Подтвердить", Style.SMALL)
	request_confirm.name = "ConfirmChoice"
	request_confirm.pressed.connect(_confirm_choice)
	request_panel.add_child(request_confirm)
	messages = RichTextLabel.new()
	messages.name = "PrivateMessages"
	messages.bbcode_enabled = false
	messages.custom_minimum_size.y = 96
	messages.size_flags_vertical = SIZE_EXPAND_FILL
	messages.scroll_following = true
	messages.add_theme_font_size_override("normal_font_size", Style.SMALL)
	side.add_child(messages)
	receiver = OptionButton.new()
	receiver.name = "WhisperRecipient"
	side.add_child(receiver)
	private_text = LineEdit.new()
	private_text.name = "WhisperText"
	private_text.placeholder_text = "Личное сообщение…"
	private_text.max_length = 500
	private_text.keep_editing_on_text_submit = true
	private_text.text_submitted.connect(func(_text: String): _send_whisper())
	side.add_child(private_text)
	var talk := HBoxContainer.new()
	talk.name = "TalkButtons"
	talk.add_theme_constant_override("separation", 8)
	side.add_child(talk)
	var send := Style.button("Прошептать", Style.SMALL)
	send.name = "Whisper"
	send.size_flags_horizontal = SIZE_EXPAND_FILL
	send.pressed.connect(_send_whisper)
	talk.add_child(send)
	shout_button = Style.button("Прокричать", Style.SMALL)
	shout_button.name = "Shout"
	shout_button.size_flags_horizontal = SIZE_EXPAND_FILL
	shout_button.tooltip_text = "Всем сразу: сообщение увидят все в личных сообщениях (только днём)"
	shout_button.pressed.connect(_send_shout)
	talk.add_child(shout_button)
	log_window = _window("Журнал города")
	public_log = _text_window(log_window)
	# Гримуар — старая записная книга (bc_grimoire.gd): места слева, «Эта ночь» и записи справа.
	grimoire = preload("res://games/blood_on_the_clocktower/ui/bc_grimoire.gd").new()
	grimoire.name = "Grimoire"
	grimoire.z_index = 105
	add_child(grimoire)
	grimoire.hide()
	grimoire_text = grimoire.notes
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
	if kind in ["cast_vote", "abstain"]:
		arg["raised"] = kind == "cast_vote"
		kind = "cast_vote"
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
	_update_phase(phase)
	var text := "Роли других игроков скрыты. Обсуждайте, сомневайтесь и блефуйте."
	# Последнее публичное событие дня (выстрел, смерть, шёпот) видно без открытия журнала.
	var events: Array = view.get("log", [])
	if phase in ["discussion", "nominations", "defense", "dusk"] and not events.is_empty():
		text = str(events.back())
	var nominee := int(view.get("nominee", -1))
	var voter := int(view.get("next_voter", -1))
	if nominee >= 0:
		text = "Номинирован: %s" % people[nominee].name
		if phase == "voting": text += " · голосует %s · за: %d" % [_person(voter), int(view.get("vote_total", 0))]
	elif int(view.get("leader", -1)) >= 0:
		text = "На плахе: %s · %d голосов" % [_person(int(view.leader)), int(view.high_vote)]
	if phase == "game_over": text = "Победило %s" % ("добро" if view.get("winner") == "good" else "зло")
	# Таймер дня: кто говорит и сколько осталось.
	var timer: Dictionary = view.get("day_timer", {})
	if not timer.is_empty():
		var left := ceili(float(timer.get("left", 0.0)))
		var clock := "%d:%02d" % [floori(left / 60.0), left % 60]
		match str(timer.kind):
			"speech": text = "Говорит %s · %s" % [_person(int(timer.get("speaker", -1))), clock]
			"talk": text = "Общее обсуждение · %s" % clock
			"nominations": text += " · осталось %s" % clock
			"vote": text += " · на голос %s" % clock
	nomination.text = text
	nomination.tooltip_text = text
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
		refs.name_label.clip_text = true
		refs.name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		refs.name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# Ник — одна строка с многоточием, роль — своей строкой под ним (длинный ник её не вытесняет).
		refs.role.visible = role_of.has(seat)
		if role_of.has(seat):
			refs.role.text = _role_caption(role_of[seat])
			var known: Dictionary = role_of[seat]
			refs.role.add_theme_color_override("font_color", Style.EVIL if str(known.get("side", "")) == "evil" else Style.GOOD)
		# Плашка узкая (текст ~104 px): состояние — одной короткой строкой, рука — стрелкой у имени,
		# полное пояснение — в подсказке. «Мёртв» без пометки — последний голос уже потрачен.
		var vote: bool = bool(entry.alive) or bool(entry.dead_vote)
		refs.state.text = "Голосует" if seat == voter else ("Жив" if entry.alive else ("Мёртв · голос" if vote else "Мёртв"))
		# Значки не прячем, а делаем прозрачными: их глифы выше строки ника, и появление «↑»/«…»
		# от чужого действия меняло высоту плашки — она подпрыгивала на площади.
		refs.hand.modulate.a = 1.0 if bool(entry.hand) else 0.0
		# «…» — участник последнего дневного шёпота (виден факт разговора, не текст).
		var whispering: bool = view.get("last_whisper", []).has(seat)
		refs.whisper.modulate.a = 1.0 if whispering else 0.0
		refs.panel.tooltip_text = "%s%s\n%s%s%s" % [refs.name_label.text, (" (%s)" % refs.role.text) if refs.role.visible else "",
			"Жив" if entry.alive else ("Мёртв, остался последний голос" if vote else "Мёртв, голоса больше нет"),
			"\nРука поднята" if entry.hand else "", "\nСейчас шепчется" if whispering else ""]
		refs.panel.modulate = Color.WHITE if entry.alive or seat == voter else Color(0.7, 0.74, 0.8)
	_sync_evil_votes(phase)
	_fit_nicks(role_of)
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
	receiver.tooltip_text = "Текст видят собеседник и рассказчик." if bool(view.get("story_reads_whispers", false)) else "Текст видит только собеседник."
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
	shout_button.disabled = me < 0 or phase == "game_over" or (phase == "night" and not is_story)
	var current_role := str(view.get("role", ""))
	if current_role != role_key or role_name.text.is_empty():
		role_key = current_role
		role_icon.texture = Art.role(role_key)
		var card: Dictionary = Data.catalog().get(role_key, {})
		role_name.text = str(card.get("name", "Рассказчик" if is_story else "Зритель"))
		role_text.text = str(card.get("text", "Вы ведёте город и принимаете решения по правилам." if is_story else "Вам доступна только публичная информация."))
	_sync_role_card()
	var request: Dictionary = view.get("request", {})
	var token := str(request.get("token", ""))
	if token != request_token:
		request_token = token
		_choice_sent = false
		selected_option = -1
		request_search.text = ""
		request_data = request.get("options", []).duplicate(true)
		picked.clear()
		pick_mode = _pick_mode()
		request_title.text = str(request.get("title", ""))
		request_hint.text = str(request.get("hint", ""))
		request_hint.visible = not request_hint.text.is_empty()
		_filter_choices()
		request_confirm.disabled = true
	request_panel.visible = not token.is_empty()
	messages.visible = token.is_empty()
	messages.size_flags_vertical = SIZE_EXPAND_FILL if token.is_empty() else SIZE_FILL
	request_confirm.disabled = selected_option < 0 or _choice_sent
	_paint_picks()
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
	actions.nominate.visible = not is_story and alive and phase == "nominations" and not view.get("nominators", []).has(me)
	actions.slay.visible = not is_story and alive and day and view.edition == "tb" and not bool(people[me].get("slayer_shot", false))
	actions.evil_vote.visible = bool(view.get("evil_vote_open", false))
	actions.show_victory.visible = phase == "game_over" and Net.is_host() and not bool(view.get("victory_open", false))
	var can_raise: bool = me >= 0 and (alive or bool(people[me].dead_vote))
	actions.hand.visible = not is_story and can_raise and phase == "voting" and not view.get("counted", []).has(me)
	if me >= 0: actions.hand.text = "Опустить руку" if bool(people[me].hand) else "Поднять руку"
	var my_turn := me >= 0 and phase == "voting" and voter == me
	actions.cast_vote.visible = not is_story and my_turn
	actions.cast_vote.disabled = blocked or not can_raise
	actions.abstain.visible = actions.cast_vote.visible
	var speech: Dictionary = view.get("day_timer", {})
	actions.end_speech.visible = str(speech.get("kind", "")) == "speech" and (is_story or int(speech.get("speaker", -1)) == me)
	actions.artist.visible = not is_story and day and role_key == "artist"
	actions.savant.visible = not is_story and day and role_key == "savant"
	actions.gossip.visible = not is_story and alive and day and view.edition == "bmr"
	actions.juggle.visible = not is_story and alive and day and view.edition == "sv"
	_sync_targets(people, me, storyteller)
	actions.nominate.disabled = blocked or not target.visible
	_paint_picks()
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
	_hold_controls_height.call_deferred()

func _update_phase(phase: String) -> void:
	var labels := {"setup": "Подготовка", "night": "Ночь", "discussion": "День",
		"nominations": "Номинации", "defense": "Номинации · защита", "voting": "Номинации · голосование",
		"dusk": "Сумерки", "game_over": "Партия завершена"}
	phase_label.text = str(labels.get(phase, phase))
	var fill: Color = {"night": Style.INSET, "discussion": Style.LINE, "dusk": Style.PANEL.lerp(Style.ACCENT, 0.5),
		"nominations": Style.ACCENT, "defense": Style.ACCENT, "voting": Style.ACCENT}.get(phase, Style.PANEL)
	var badge := Style.box(fill)
	badge.content_margin_top = 4
	badge.content_margin_bottom = 4
	phase_badge.add_theme_stylebox_override("panel", badge)
	top.info.text = "День %d" % int(view.get("day", 0)) if int(view.get("day", 0)) > 0 else phase_label.text

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
		# Голоса приспешников за эту жертву: квадратики цвета голосующих (видит только зло, ночью).
		var votes := HBoxContainer.new()
		votes.name = "EvilVotes"
		votes.add_theme_constant_override("separation", 2)
		votes.mouse_filter = MOUSE_FILTER_IGNORE
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
		row.add_child(votes)
		# Распорка: квадратики голосов стоят сразу за ником, значки «…»/«↑» — у правого края.
		var gap := Control.new()
		gap.size_flags_horizontal = SIZE_EXPAND_FILL
		gap.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(gap)
		var whisper := Style.label("…", Style.SMALL, Style.MUTED)
		whisper.modulate.a = 0.0
		whisper.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(whisper)
		var hand := Style.label("↑", Style.SMALL)
		hand.modulate.a = 0.0
		hand.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(hand)
		# Роль у рассказчика/в финале — своей строкой: длинный ник её больше не вытесняет.
		var role_line := Style.label("", Style.SMALL, Style.GOOD)
		role_line.name = "RoleLine"
		role_line.custom_minimum_size.x = 104
		role_line.clip_text = true
		role_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		role_line.mouse_filter = MOUSE_FILTER_IGNORE
		role_line.visible = false
		col.add_child(role_line)
		var state := Style.label("", Style.SMALL, Style.MUTED)
		state.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(state)
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_seat_clicked(i))
		seat_nodes[i] = {"panel": panel, "name_label": nick, "state": state, "hand": hand, "whisper": whisper, "votes": votes, "role": role_line}
	_place_seats()

## Панель кнопок под площадью только растёт: кнопки появляются и прячутся от каждого действия,
## и без этого высота площади (а с ней плашки мест) менялась от чужих номинаций и рук.
func _hold_controls_height() -> void:
	var need := controls.get_combined_minimum_size().y
	if need > controls.custom_minimum_size.y:
		controls.custom_minimum_size.y = need

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
		# Игроков выбирают щелчком по плашке на площади; в списке остаются особые варианты («Не использовать»).
		if (pick_mode == "pair" and not _pair_of(option).is_empty()) or (pick_mode == "one" and int(option.get("target", -1)) >= 0): continue
		if not request_search.text.is_empty() and not text.to_lower().contains(request_search.text.to_lower()): continue
		request_indices.append(i)
		request_options.add_item(text)
		request_options.set_item_tooltip(request_options.item_count - 1, text)
	request_confirm.disabled = true
	request_options.visible = request_options.item_count > 0
	# Немного особых вариантов — список по их числу, а не на полпанели.
	request_options.custom_minimum_size.y = clampf(request_options.item_count * 30.0 + 20.0, 50.0, 100.0)
	request_options.size_flags_vertical = SIZE_EXPAND_FILL if request_options.item_count > 3 else SIZE_FILL
	request_search.visible = pick_mode.is_empty() and request_data.size() > 8
	_sync_slots()
	_paint_picks()

## Как выбирать в текущем запросе: все игроки по одному — "one", пары игроков — "pair", иначе список.
func _pick_mode() -> String:
	var players := 0
	var pairs := 0
	for option: Variant in request_data:
		if not option is Dictionary: return ""
		if not _pair_of(option).is_empty(): pairs += 1
		elif int(option.get("target", -1)) >= 0: players += 1
	if pairs > 0: return "pair"
	if players > 0: return "one"
	return ""

## Пара игроков варианта: [левый, правый] из targets (Гадалка) или left/right (информация), иначе [].
func _pair_of(option: Variant) -> Array:
	if not option is Dictionary: return []
	if option.get("targets") is Array and option.targets.size() == 2: return [int(option.targets[0]), int(option.targets[1])]
	if option.has("left") and option.has("right"): return [int(option.left), int(option.right)]
	return []

func _same_pair(pair: Array, seats: Array) -> bool:
	return (pair[0] == seats[0] and pair[1] == seats[1]) or (pair[0] == seats[1] and pair[1] == seats[0])

## Номер варианта для выбранных игроков (пара — без учёта порядка) и роли, -1 — нет такого.
func _option_for(seats: Array[int], role: String = "") -> int:
	for i in request_data.size():
		var option: Variant = request_data[i]
		if not option is Dictionary: continue
		if seats.size() == 1 and int(option.get("target", -2)) == seats[0] and _pair_of(option).is_empty(): return i
		var pair := _pair_of(option)
		if seats.size() == 2 and not pair.is_empty() and _same_pair(pair, seats):
			if role.is_empty() or str(option.get("role", "")) == role: return i
	return -1

## Выпадающие списки пары: левый — все игроки из вариантов, правый — допустимые с левым, роль — для пары.
func _sync_slots() -> void:
	slot_row.visible = pick_mode == "pair" and not request_token.is_empty()
	if not slot_row.visible: return
	_slot_sync = true
	var everyone: Array[int] = []
	var partners: Array[int] = []
	var roles: Array[String] = []
	for option: Variant in request_data:
		var pair := _pair_of(option)
		if pair.is_empty(): continue
		for seat: int in pair:
			if not everyone.has(seat): everyone.append(seat)
		if not picked.is_empty() and pair.has(picked[0]):
			var other: int = pair[1] if pair[0] == picked[0] else pair[0]
			if not partners.has(other): partners.append(other)
		if picked.size() == 2 and _same_pair(pair, picked):
			var role := str(option.get("role", ""))
			if not role.is_empty() and not roles.has(role): roles.append(role)
	everyone.sort()
	partners.sort()
	_fill_slot(slot_left, "Первый игрок", everyone, picked[0] if not picked.is_empty() else -1)
	_fill_slot(slot_right, "Второй игрок", partners if not picked.is_empty() else everyone, picked[1] if picked.size() == 2 else -1)
	slot_right.disabled = picked.is_empty()
	var chosen_role := str(slot_role.get_item_metadata(slot_role.selected)) if slot_role.selected > 0 else ""
	slot_role.clear()
	slot_role.add_item("Роль")
	slot_role.set_item_metadata(0, "")
	for role: String in roles:
		slot_role.add_item(str(Data.catalog().get(role, {}).get("name", role)))
		slot_role.set_item_metadata(slot_role.item_count - 1, role)
	slot_role.visible = _pairs_have_roles()
	slot_role.disabled = roles.is_empty()
	if not roles.has(chosen_role): chosen_role = roles[0] if roles.size() == 1 else ""
	slot_role.select(maxi(0, roles.find(chosen_role) + 1) if not chosen_role.is_empty() else 0)
	_slot_sync = false
	var ready := picked.size() == 2 and (not slot_role.visible or not chosen_role.is_empty())
	selected_option = _option_for(picked, chosen_role) if ready else -1

func _pairs_have_roles() -> bool:
	for option: Variant in request_data:
		if option is Dictionary and not _pair_of(option).is_empty() and not str(option.get("role", "")).is_empty(): return true
	return false

func _fill_slot(menu: OptionButton, title: String, seats: Array[int], chosen: int) -> void:
	menu.clear()
	menu.add_item(title, -1)
	for seat: int in seats: menu.add_item(_person(seat), seat)
	menu.select(maxi(0, seats.find(chosen) + 1) if chosen >= 0 else 0)

func _slot_changed(which: int) -> void:
	if _slot_sync or _choice_sent: return
	if which == 0:
		var seat := slot_left.get_selected_id()
		var keep := picked[1] if picked.size() == 2 else -1
		picked.clear()
		if seat >= 0:
			picked.append(seat)
			# Правый остаётся, если с новым левым такая пара есть.
			if keep >= 0 and keep != seat and _pair_exists(seat, keep): picked.append(keep)
	elif which == 2:
		pass
	elif which == 1:
		var seat := slot_right.get_selected_id()
		if picked.is_empty(): return
		picked.resize(1)
		if seat >= 0: picked.append(seat)
	_after_pick()

func _pair_exists(a: int, b: int) -> bool:
	for option: Variant in request_data:
		var pair := _pair_of(option)
		if not pair.is_empty() and _same_pair(pair, [a, b]): return true
	return false

## Общий хвост выбора: варианты списка сняты, кнопка и подпись обновлены.
func _after_pick() -> void:
	if pick_mode == "pair":
		_sync_slots()
	request_options.deselect_all()
	request_confirm.disabled = selected_option < 0 or _choice_sent
	_paint_picks()

## Щелчок по плашке: сначала — выбор в личном запросе, иначе — цель публичного действия и собеседник шёпота.
func _seat_clicked(seat: int) -> void:
	if not pick_mode.is_empty() and not request_token.is_empty() and not _choice_sent:
		if picked.has(seat):
			picked.erase(seat)
		elif pick_mode == "one" or picked.size() >= 2:
			if pick_mode == "pair": picked.pop_front()
			else: picked.clear()
			picked.append(seat)
		else:
			picked.append(seat)
		if pick_mode == "one":
			selected_option = _option_for(picked)
			# Недопустимую цель (не из вариантов запроса) не выделяем.
			if selected_option < 0: picked.clear()
		elif picked.size() == 2 and not _pair_exists(picked[0], picked[1]):
			picked.pop_front()
		_after_pick()
		Sfx.play("click", -8)
		return
	for menu: OptionButton in [target, receiver]:
		if not menu.visible and menu == target: continue
		for j in menu.item_count:
			if menu.get_item_id(j) == seat:
				menu.select(j)
	_paint_picks()

## Подсветка выбранных плашек и строка «вы выбрали …» над «Подтвердить».
func _paint_picks() -> void:
	var marked: Array[int] = picked.duplicate()
	if pick_mode.is_empty() and target.visible and target.selected >= 0:
		marked = [target.get_selected_id()]
	for seat: int in seat_nodes:
		var refs: Dictionary = seat_nodes[seat]
		var voting := seat == int(view.get("next_voter", -1))
		var fill := Style.ACCENT if seat == int(view.get("nominee", -1)) else Style.PANEL
		var box := Style.box(fill.lightened(0.12) if voting else fill)
		if voting or marked.has(seat):
			box.set_border_width_all(3)
			box.border_color = Style.INK if voting else Style.GOOD
		refs.panel.add_theme_stylebox_override("panel", box)
	if request_summary == null: return
	var names: Array[String] = []
	for seat: int in picked: names.append(_person(seat))
	if pick_mode == "pair":
		var fortune: bool = selected_option >= 0 and request_data[selected_option] is Dictionary and request_data[selected_option].has("targets")
		if selected_option >= 0:
			request_summary.text = ("Вы выбрали %s для проверки." % " и ".join(names)) if fortune else (
				"Будет показано: %s" % str(request_data[selected_option].get("label", "")))
		elif picked.size() == 2:
			request_summary.text = "Выберите роль в третьем списке." if slot_role.visible else "Такую пару выбрать нельзя — выберите других игроков."
		else:
			request_summary.text = "Выберите двух игроков в списках или щёлкните по их плашкам на площади." if picked.is_empty() else "Выбран %s — выберите второго игрока." % names[0]
	elif pick_mode == "one":
		request_summary.text = ("Вы выбрали: %s." % names[0]) if not picked.is_empty() else (
			"Щёлкните по плашке игрока на площади." if request_options.item_count == 0 else "Щёлкните по плашке игрока на площади или выберите вариант в списке.")
	request_summary.visible = not pick_mode.is_empty() and not request_token.is_empty()

## Ник занимает ровно ширину текста (но не больше места в плашке), чтобы квадратики голосов
## стояли прямо за ним и плашка не расширялась. С ролью в скобках — прежний перенос на всю ширину.
func _fit_nicks(role_of: Dictionary) -> void:
	for seat: int in seat_nodes:
		var refs: Dictionary = seat_nodes[seat]
		var nick: Label = refs.name_label
		if role_of.has(seat):
			nick.size_flags_horizontal = SIZE_EXPAND_FILL
			nick.custom_minimum_size.x = 80
			continue
		var font := nick.get_theme_font("font")
		var width := font.get_string_size(nick.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nick.get_theme_font_size("font_size")).x + 2
		var room := 80.0 - 11.0 * (refs.votes as HBoxContainer).get_child_count()
		nick.size_flags_horizontal = SIZE_FILL
		nick.custom_minimum_size.x = clampf(width, 24.0, maxf(24.0, room))

## Голоса приспешников квадратиками их цвета у ника жертвы (только у зла и только ночью).
func _sync_evil_votes(phase: String) -> void:
	var by_target: Dictionary = {}
	if phase == "night":
		for vote: Dictionary in view.get("evil_votes", []):
			var list: Array = by_target.get(int(vote.target), [])
			list.append(int(vote.from))
			by_target[int(vote.target)] = list
	var people: Array = view.get("players", [])
	for seat: int in seat_nodes:
		var box: HBoxContainer = seat_nodes[seat].votes
		var voters: Array = by_target.get(seat, [])
		var key := str(voters)
		if str(box.get_meta("voters", "[]")) == key: continue
		box.set_meta("voters", key)
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()
		for voter: int in voters:
			var square := ColorRect.new()
			square.custom_minimum_size = Vector2(9, 9)
			square.size_flags_vertical = SIZE_SHRINK_CENTER
			square.mouse_filter = MOUSE_FILTER_IGNORE
			square.color = Net.color_of(int(people[voter].color)) if voter < people.size() else Style.EVIL
			box.add_child(square)
		var names: Array[String] = []
		for voter: int in voters: names.append(_person(voter))
		box.tooltip_text = "" if voters.is_empty() else "Голос приспешников: %s" % ", ".join(names)

func _confirm_choice() -> void:
	if selected_option < 0 or _choice_sent: return
	_choice_sent = true
	request_confirm.disabled = true
	Net.send_action("private_reply", {"token": request_token, "index": selected_option})

func _update_texts() -> void:
	var text := "\n\n".join(view.get("messages", []))
	var seat := int(view.get("you", -1))
	if text != _last_messages or seat != _message_seat:
		if seat == _message_seat and not _last_messages.is_empty() and text.begins_with(_last_messages + "\n\n"):
			messages.add_text(text.substr(_last_messages.length()))
		else:
			var scroll := messages.get_v_scroll_bar()
			var previous := scroll.value
			var follow := seat != _message_seat or previous >= scroll.max_value - scroll.page - 1.0
			messages.clear()
			messages.add_text(text)
			messages.get_content_height()
			scroll.value = scroll.max_value - scroll.page if follow else previous
		_last_messages = text
		_message_seat = seat
	text = "\n\n".join(view.get("log", []))
	if text != _last_log:
		_last_log = text
		public_log.text = text
	var entries: Array = view.get("grimoire", view.get("knowledge", {}).get("grimoire", []))
	var lines: Array[String] = []
	# Рассказчику: кто ещё не ходил этой ночью (Шпиону очередь не приходит).
	var queue: Array = view.get("night_queue", [])
	if view.has("night_queue"):
		var now: Array[String] = []
		var later: Array[String] = []
		for item: Dictionary in queue:
			var who := "%s (%s)" % [_person(int(item.seat)), str(Data.catalog().get(str(item.role), {}).get("name", item.role))]
			if bool(item.get("now", false)): now.append(who)
			else: later.append(who)
		lines.append("— Эта ночь —\nСейчас выбирает: %s\nЕщё не ходили: %s" % [
			", ".join(now) if not now.is_empty() else "—", ", ".join(later) if not later.is_empty() else "все сходили"])
	grimoire.set_entries(entries, view.get("players", []), int(view.get("day", 0)), str(view.get("phase", "")) == "night")
	var acted: Array = view.get("story_log", [])
	if not acted.is_empty():
		lines.append("— Действия игроков —\n" + "\n".join(acted.slice(maxi(0, acted.size() - 40))))
	text = "\n\n".join(lines)
	if text.is_empty() and not entries.is_empty() and view.has("grimoire"):
		text = "Пока тихо. Здесь появятся ночная очередь и всё, что выбирают игроки."
	if text != _last_grimoire:
		_last_grimoire = text
		grimoire_text.text = text
	actions.grimoire.visible = not entries.is_empty()

## Крик — общий чат в той же панели сообщений.
func _send_shout() -> void:
	if private_text.text.strip_edges().is_empty(): return
	Net.send_action("shout", {"text": private_text.text})
	private_text.clear()
	private_text.grab_focus()

## Карточка роли свёрнута — остаётся одна строка-кнопка с ролью и командой.
func _sync_role_card() -> void:
	var side_text := side_label.text if side_label.visible else ""
	role_toggle.text = ("▸ " if role_folded else "▾ ") + role_name.text + (" · " + side_text if not side_text.is_empty() else "")
	personal.visible = not role_folded

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
