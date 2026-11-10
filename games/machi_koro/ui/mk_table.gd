extends Control
## Открытый 2D-стол Мачи Коро: рынок, города, выборы и поясняющая анимация очереди хоста.

const Style := preload("res://games/machi_koro/ui/mk_style.gd")
const Card := preload("res://games/machi_koro/ui/mk_card.gd")
const Data := preload("res://games/machi_koro/logic/mk_data.gd")
var app: Node
var view: Dictionary = {}
var catalog: Dictionary = Data.catalog()
var top: TopBar
var market_panel: PanelContainer
var side: PanelContainer
var city_panel: PanelContainer
var landmark_panel: PanelContainer
var market_grid: GridContainer
var controls: HBoxContainer
var city_cards: HBoxContainer
var landmark_cards: HBoxContainer
var city_title: Label
var landmark_title: Label
var side_col: VBoxContainer
var market_title: Label
var bg: Control
var fx: Control
var dice_nodes: Array = []
var dice_count := 1
var seen_throw := -1
var seen_turn := -1
var inspect_seat := 0
var selected := ""
var preview: Control
var preview_token := 0
var choice_panel: PanelContainer
var choice_index := -1
var event_elapsed := 0.0
var event_id := -1
var event_remaining := 0.0
var last_phase := ""
var last_revision := -1
var local_throw_serial := -1
var local_throw_velocity := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg = preload("res://games/machi_koro/ui/mk_backdrop.gd").new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	top = TopBar.make(self, "Мачи Коро", Style.button, null, Style.ink(), Style.HEAD)
	for item: Array in [["Правила", app.show_rules], ["Настройки", app.show_settings]]:
		var button := Style.button(item[0], 14)
		button.pressed.connect(item[1])
		top.actions.add_child(button)
	top.actions.add_child(ThemeToggle.new())
	var leave := Style.button("Выйти", 14)
	LeaveGuard.wire(leave, "Выйти из партии?", "Вернуться к выбору игры.", app.back_to_hub)
	top.actions.add_child(leave)
	market_panel = PanelContainer.new()
	var market_style := Style.box()
	market_style.bg_color.a = 0.18
	market_style.border_color.a = 0.12
	market_style.shadow_color.a = 0.0
	market_panel.add_theme_stylebox_override("panel", market_style)
	add_child(market_panel)
	var body := Style.column(8)
	market_panel.add_child(body)
	market_title = Style.heading("Рынок")
	body.add_child(market_title)
	controls = Style.row()
	controls.custom_minimum_size.y = 46
	body.add_child(controls)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(scroll)
	market_grid = GridContainer.new()
	market_grid.columns = 6
	market_grid.add_theme_constant_override("h_separation", 8)
	market_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(market_grid)
	side = PanelContainer.new()
	add_child(side)
	side_col = Style.column(8)
	side.add_child(side_col)
	city_panel = PanelContainer.new()
	add_child(city_panel)
	var own := Style.column()
	city_panel.add_child(own)
	city_title = Style.heading("Мой город", 18)
	city_title.clip_text = true
	city_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	own.add_child(city_title)
	var city_scroll := ScrollContainer.new()
	city_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	city_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	own.add_child(city_scroll)
	city_cards = Style.row()
	city_scroll.add_child(city_cards)
	landmark_panel = PanelContainer.new()
	add_child(landmark_panel)
	var landmarks := Style.column()
	landmark_panel.add_child(landmarks)
	landmark_title = Style.heading("Достопримечательности", 18)
	landmark_title.clip_text = true
	landmark_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	landmarks.add_child(landmark_title)
	var landmark_scroll := ScrollContainer.new()
	landmark_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	landmark_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	landmarks.add_child(landmark_scroll)
	landmark_cards = Style.row()
	landmark_scroll.add_child(landmark_cards)
	for i in 2:
		var die := TossDie.new()
		die.z_index = 20
		add_child(die)
		dice_nodes.append(die)
		die.finished.connect(_dice_finished)
		if i == 0:
			die.thrown.connect(_thrown)
			die.stalled.connect(_dice_stalled)
	fx = Control.new()
	fx.mouse_filter = MOUSE_FILTER_IGNORE
	fx.z_index = 60
	fx.draw.connect(_draw_effect)
	add_child(fx)
	for panel: PanelContainer in [market_panel, side, city_panel, landmark_panel]:
		panel.minimum_size_changed.connect(_layout.call_deferred)
	resized.connect(_layout)
	Net.state_changed.connect(_state)
	if not Net.view.is_empty():
		_state(Net.view)
	_layout()

func _layout() -> void:
	var width := maxf(size.x, 1280)
	var height := maxf(size.y, 720)
	var main_width := width - 312
	market_panel.position = Vector2(16, TopBar.HEIGHT + 16)
	market_panel.size = Vector2(main_width, height - TopBar.HEIGHT - 288)
	side.position = Vector2(width - 280, TopBar.HEIGHT + 16)
	side.size = Vector2(264, height - TopBar.HEIGHT - 32)
	market_grid.columns = maxi(1, int((main_width - 48) / 140))
	var own_width := floorf((main_width - 16) * 0.55)
	city_panel.position = Vector2(16, height - 256)
	city_panel.size = Vector2(own_width, 240)
	landmark_panel.position = Vector2(32 + own_width, height - 256)
	landmark_panel.size = Vector2(main_width - own_width - 16, 240)
	for i in dice_nodes.size():
		var die: TossDie = dice_nodes[i]
		die.area = Rect2(16, TopBar.HEIGHT + 8, main_width, height - 256)
		die.home = Vector2(main_width - 112 + i * 72, TopBar.HEIGHT + 56)
		if die.state in ["idle", "waiting"]:
			die.position = die.home - die.size * 0.5
	if is_instance_valid(choice_panel):
		choice_panel.position = Vector2(64, 160)
		choice_panel.size = Vector2(minf(624, main_width - 80), minf(400, height - 200))

func _state(data: Dictionary) -> void:
	if data.get("game", "machi_koro") != "machi_koro":
		return
	view = data
	if int(data.get("revision", -1)) == last_revision and last_phase == str(data.phase):
		_sync_dice()
		_refresh_controls()
		return
	last_revision = int(data.revision)
	var next_event: int = int(data.get("event", {}).get("id", -1))
	if next_event != event_id:
		event_id = next_event
		event_elapsed = 0.0
		event_remaining = float(data.get("event_left", 0.0))
	if seen_turn != int(data.turn_no):
		seen_turn = int(data.turn_no)
		inspect_seat = int(data.current) if data.get("hotseat", false) else maxi(0, int(data.you))
		selected = ""
		if not data.built[int(data.current)].has("station"):
			dice_count = 1
	_refresh()
	_sync_dice()
	last_phase = str(view.phase)
	queue_redraw()

func _can_act() -> bool:
	return not view.is_empty() and not Net.paused and not bool(view.get("spectator", false)) and int(view.you) == int(view.current)

func _send(kind: String, data: Dictionary = {}) -> void:
	if not _can_act():
		return
	data.revision = int(view.revision)
	Net.send_action(kind, data)

func _refresh() -> void:
	top.info.text = "Раунд %d · Ход: %s" % [view.round_no, str(view.players[int(view.current)].name)]
	market_title.text = "Рынок · в колоде %d" % int(view.deck_count) if view.limited else "Рынок"
	var market_entries: Array = []
	for id: String in view.reserve:
		market_entries.append({"key": id, "id": id, "copies": int(view.reserve[id])})
	_sync_cards(market_grid, market_entries)
	Style.clear(side_col)
	side_col.add_child(Style.heading("Города", 18))
	for s in view.players.size():
		var button := Style.button("%s · %d мон." % [str(view.players[s].name), int(view.coins[s])], 18)
		button.icon = PlayerTag.dot(Net.color_of(int(view.players[s].get("color", s))), 18)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if s == int(view.current):
			button.add_theme_stylebox_override("normal", Style.box(Style.ACCENT.darkened(0.5) if Style.dark() else Color("d3e6de"), 10))
		TurnNameGlow.apply(button, s == int(view.current))
		var seat: int = s
		button.pressed.connect(func():
			inspect_seat = seat
			_refresh_city())
		side_col.add_child(button)
	if not view.event.is_empty():
		var effect := Style.label(str(view.event.text) + "\n" + str(view.event.get("detail", "")), 14)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_col.add_child(effect)
	side_col.add_child(Style.heading("Журнал", 18))
	var journal := RichTextLabel.new()
	journal.text = "\n\n".join(view.log)
	journal.scroll_following = true
	journal.size_flags_vertical = SIZE_EXPAND_FILL
	journal.add_theme_font_size_override("normal_font_size", 14)
	side_col.add_child(journal)
	_refresh_city()
	_refresh_controls()
	_refresh_choice()
	_layout()
	_settle_layout()

func _settle_layout() -> void:
	# ScrollContainer уточняет минимум после первого прохода контейнеров.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree():
		_layout()

func _card(id: String) -> Control:
	var card := Card.new()
	card.id = id
	card.active = str(view.get("event", {}).get("card", "")) == id
	card.hover.connect(_hover)
	return card

func _refresh_city() -> void:
	if _two_cities():
		var mine := int(view.you)
		var active := int(view.current)
		city_title.text = "Ваш город · %s · %d мон." % [view.players[mine].name, int(view.coins[mine])]
		landmark_title.text = "Ходит %s · %d мон." % [view.players[active].name, int(view.coins[active])]
		city_panel.set_meta("shown_seat", mine)
		landmark_panel.set_meta("shown_seat", active)
		# В чужой ход в своём городе только предприятия: достопримечательности не нужны (просьба владельца 06.11).
		_sync_cards(city_cards, _city_entries(mine))
		_sync_cards(landmark_cards, _city_entries(active) + _landmark_entries(active))
	else:
		city_title.text = "Город: %s" % str(view.players[inspect_seat].name)
		landmark_title.text = "Достопримечательности"
		city_panel.set_meta("shown_seat", inspect_seat)
		landmark_panel.set_meta("shown_seat", inspect_seat)
		_sync_cards(city_cards, _city_entries(inspect_seat))
		_sync_cards(landmark_cards, _landmark_entries(inspect_seat))
	_layout.call_deferred()

func _two_cities() -> bool:
	return not view.is_empty() and not bool(view.get("hotseat", false)) and int(view.you) >= 0 and int(view.you) != int(view.current)

func _city_entries(seat: int) -> Array:
	var groups := {}
	for instance: Dictionary in view.cities[seat]:
		var key := "%s/%s/%d" % [instance.id, str(instance.closed), int(instance.fund)]
		if not groups.has(key):
			groups[key] = {"id": instance.id, "closed": instance.closed, "count": 0, "fund": instance.fund}
		groups[key].count += 1
	var entries: Array = []
	for key: String in groups:
		var entry: Dictionary = groups[key]
		entries.append({"key": "%d/%s" % [seat, key], "id": entry.id, "closed": entry.closed, "copies": entry.count, "compact": true, "interactive": false, "fund": entry.fund})
	return entries

func _landmark_entries(seat: int) -> Array:
	var entries: Array = []
	for id: String in Data.landmarks(bool(view.plus)):
		entries.append({"key": "%d/%s" % [seat, id], "id": id, "compact": true, "narrow": true, "built": view.built[seat].has(id), "interactive": seat == int(view.current) and _can_act()})
	return entries

## Ключи сохраняют узлы, hover и прокрутку при чужих действиях и повторных view.
func _sync_cards(row: Container, entries: Array) -> void:
	var existing := {}
	for child: Node in row.get_children():
		existing[str(child.get_meta("card_key", ""))] = child
	var keep: Array = []
	for entry: Dictionary in entries:
		var key: String = entry.key
		var card: Control = existing.get(key)
		var fresh := not is_instance_valid(card)
		if fresh:
			card = _card(str(entry.id))
			card.set_meta("card_key", key)
			card.selected.connect(_select)
		card.copies = int(entry.get("copies", 1))
		card.closed = bool(entry.get("closed", false))
		card.built = bool(entry.get("built", false))
		card.compact = bool(entry.get("compact", false))
		card.narrow = bool(entry.get("narrow", false))
		card.interactive = bool(entry.get("interactive", true))
		card.active = str(view.get("event", {}).get("card", "")) == str(entry.id)
		card.fund = int(entry.get("fund", 0))
		if fresh:
			row.add_child(card)
		else:
			card.update_state()
		if card.get_index() != keep.size():
			row.move_child(card, keep.size())
		keep.append(card)
	for child: Node in row.get_children():
		if not keep.has(child):
			row.remove_child(child)
			child.queue_free()

func _select(id: String) -> void:
	selected = id
	Sfx.play("click", -12)
	_refresh_controls()

func _refresh_controls() -> void:
	Style.clear(controls)
	var message := "Ждём %s…" % str(view.players[int(view.current)].name)
	var acting := _can_act()
	match str(view.phase):
		"roll":
			message = TossDie.roll_hint()
			if acting and view.built[int(view.current)].has("station"):
				for n in [1, 2]:
					var button := Style.button("%d кубик%s" % [n, "" if n == 1 else "а"], 14)
					UISel.pick(button, dice_count == n)
					button.pressed.connect(func():
						dice_count = n
						_refresh_controls()
						_sync_dice())
					controls.add_child(button)
		"trawler":
			message = "Траулеры: бросьте два кубика"
		"reroll":
			message = "Радиовышка: оставить результат?"
			if acting:
				_action_button("Оставить", "keep")
				_action_button("Перебросить", "reroll", {}, false)
		"harbor":
			message = "Порт · результат %d" % int(view.result)
			if acting:
				_action_button("Добавить 2", "harbor", {"add": true})
				_action_button("Оставить", "harbor", {"add": false}, false)
		"build":
			message = "Выберите предприятие или достопримечательность"
			if acting:
				if not selected.is_empty():
					var landmark := Data.LANDMARKS.has(selected)
					var definition: Dictionary = Data.LANDMARKS[selected] if landmark else catalog[selected]
					var affordable: bool = int(view.coins[int(view.current)]) >= int(definition.cost)
					if landmark:
						affordable = affordable and not view.built[int(view.current)].has(selected)
					else:
						affordable = affordable and int(view.reserve.get(selected, 0)) > 0
						if definition.color == "purple":
							for instance: Dictionary in view.cities[int(view.current)]:
								if instance.id == selected:
									affordable = false
					var button := _action_button("Построить · %d" % int(definition.cost), "landmark" if landmark else "buy", {"card": selected})
					button.disabled = not affordable
					message = str(definition.title)
				_action_button("Пропустить", "pass", {}, selected.is_empty())
		"animation":
			message = str(view.event.get("text", ""))
		"choice":
			message = str(view.choice.get("text", "Выбор"))
		"game_over":
			message = "Победа: %s" % str(view.players[int(view.winner)].name)
	var label := Style.label(message if acting or view.phase in ["animation", "game_over"] else "Ждём %s…" % str(view.players[int(view.current)].name), 14)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 140
	controls.add_child(label)
	controls.move_child(label, 0)
	# Справа от строки остаётся место физическим кубикам.
	var space := Control.new()
	space.custom_minimum_size.x = 136 if view.phase in ["roll", "trawler", "animation"] else 0
	controls.add_child(space)

func _action_button(text: String, kind: String, data: Dictionary = {}, primary: bool = true) -> Button:
	var button := Style.primary(text) if primary else Style.button(text)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(func(): _send(kind, data.duplicate(true)))
	controls.add_child(button)
	return button

func _refresh_choice() -> void:
	if is_instance_valid(choice_panel):
		remove_child(choice_panel)
		choice_panel.queue_free()
	choice_index = -1
	if view.phase != "choice" or not _can_act():
		return
	choice_panel = PanelContainer.new()
	choice_panel.z_index = 35
	choice_panel.minimum_size_changed.connect(_layout.call_deferred)
	add_child(choice_panel)
	var col := Style.column(16)
	choice_panel.add_child(col)
	var title := Style.heading(str(view.choice.text), 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 180
	col.add_child(scroll)
	var options := Style.column(8)
	options.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(options)
	var confirm := Style.primary("Подтвердить выбор")
	confirm.disabled = true
	for i in view.choice.options.size():
		var button := Style.button(str(view.choice.options[i].label))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var kind: String = view.choice.kind
		if kind in ["tv", "business", "shipping"] and int(view.choice.options[i].value) >= 0:
			var seat := int(view.choice.options[i].value)
			button.icon = PlayerTag.dot(Net.color_of(int(view.players[seat].get("color", seat))), 18)
		var index: int = i
		button.pressed.connect(func():
			choice_index = index
			for item: Button in options.get_children():
				UISel.pick(item, item == button)
			confirm.disabled = false)
		options.add_child(button)
	confirm.pressed.connect(func():
		if choice_index >= 0:
			_send("choose", {"index": choice_index}))
	col.add_child(confirm)

func _sync_dice() -> void:
	var waiting: bool = view.phase in ["roll", "trawler"]
	var n: int = 2 if view.phase == "trawler" else dice_count
	var mandatory: bool = _can_act() and (view.phase == "trawler" or (
		view.phase == "roll" and not view.built[int(view.current)].has("station")
	))
	var serial := int(view.throw_serial)
	for i in dice_nodes.size():
		var die: TossDie = dice_nodes[i]
		var next_companion := i == 1 and (dice_nodes[0] as TossDie).is_busy() and not die.is_busy()
		die.set_reel_prompt(mandatory and i < n and not next_companion, (i - (n - 1) * 0.5) * 1.12)
		die.visible = ((i < n if waiting else i < view.dice.size()) or die.is_busy()) and view.phase != "game_over"
		var pending := waiting and i == 0 and local_throw_serial == serial + 1 and die.state == "flying"
		die.draggable = waiting and i == 0 and _can_act() and not pending
		# Пока прошлый бросок показывает результат, новый не начинаем: досмотрим и вернёмся (_dice_finished).
		var showing: bool = die.state in ["flying", "settled", "returning"]
		if waiting and not pending and not showing and die.state != "waiting" and not (die.state == "dragging" and die.draggable):
			die.wait_for_roll()
		if not die.draggable and waiting and not showing:
			die.modulate.a = 0.45 if not _can_act() else 1.0
	if seen_throw != serial and not view.dice.is_empty():
		seen_throw = serial
		var local := serial == local_throw_serial
		var velocity := local_throw_velocity if local else Vector2(580, -620)
		for i in view.dice.size():
			var die: TossDie = dice_nodes[i]
			die.draggable = false
			die.visible = true
			if local and i == 0 and die.state == "flying":
				# Жест уже запустил кубик из точки отпускания. От хоста нужна только грань.
				die.set_result(int(view.dice[i]))
			else:
				die.throw(velocity.rotated(0.4 * i), int(view.dice[i]), local)

func _dice_finished() -> void:
	if not view.is_empty():
		_sync_dice()

## Хост не прислал грань (бросок отклонён/потерян) — снова разрешаем бросить.
func _dice_stalled() -> void:
	local_throw_serial = -1
	var companion: TossDie = dice_nodes[1]
	if companion._reel != null and not companion.is_busy():
		companion._reel.release_local_throw()

func _thrown(velocity: Vector2) -> void:
	local_throw_serial = int(view.throw_serial) + 1
	local_throw_velocity = velocity
	if dice_count == 2 or view.phase == "trawler":
		(dice_nodes[1] as TossDie).hold_reel_throw()
	_send("roll", {"count": dice_count})

func _hover(card: Control, on: bool) -> void:
	preview_token += 1
	_close_preview()
	if not on:
		return
	if preload("res://hub/card_magnifier.gd").offer(card):
		return
	var token := preview_token
	await get_tree().create_timer(0.125).timeout  # приближение вдвое быстрее (06.11)
	if not is_instance_valid(card) or token != preview_token:
		return
	preview = Card.new()
	preview.id = card.id
	preview.large = true
	preview.closed = card.closed
	preview.built = card.built
	preview.interactive = false
	preview.mouse_filter = MOUSE_FILTER_IGNORE
	preview.z_index = 80
	add_child(preview)
	preview.position = Vector2(clampf(card.global_position.x + card.size.x + 16, 16, size.x - 352), clampf(card.global_position.y - 120, TopBar.HEIGHT + 16, size.y - 480))
	preview.size = Vector2(320, 452)
	_finish_preview_layout(weakref(preview), card.get_global_rect())

func _finish_preview_layout(reference: WeakRef, source: Rect2) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = reference.get_ref() as Control
	if is_instance_valid(panel) and panel == preview:
		panel.size = Vector2(320, panel.get_combined_minimum_size().y)
		panel.position = Vector2(clampf(source.end.x + 16, 16, size.x - 336), clampf(source.position.y - 120, TopBar.HEIGHT + 16, maxf(TopBar.HEIGHT + 16, size.y - panel.size.y - 16)))

func _close_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = null

func restyle() -> void:
	bg.queue_redraw()
	for panel: PanelContainer in [market_panel, side, city_panel, landmark_panel]:
		panel.add_theme_stylebox_override("panel", Style.box())
	# Верхнюю полосу обновляем через перестроение стола: она хранит состояние меню сама.
	app.show_table.call_deferred()

func _process(delta: float) -> void:
	if not view.is_empty() and not view.event.is_empty() and not Net.paused:
		event_elapsed += delta
	if is_instance_valid(fx):
		fx.queue_redraw()

func _draw_effect() -> void:
	if view.is_empty() or view.event.is_empty():
		return
	var duration := float(view.event.duration)
	var progress := clampf((duration - event_remaining + event_elapsed) / duration, 0.0, 0.99)
	for mutation: Dictionary in view.event.get("mutations", []):
		if mutation.op in ["buy", "transfer", "landmark"]:
			var from := Vector2(market_panel.size.x * 0.5, market_panel.position.y + market_panel.size.y * 0.5)
			var to := city_panel.position + city_panel.size * 0.5
			var point := from.lerp(to, progress)
			var rect := Rect2(point - Vector2(60, 32), Vector2(120, 64))
			fx.draw_style_box(Style.box(Style.ACCENT, 8), rect)
			var caption: String = "Обмен" if mutation.op == "transfer" else "Снос" if mutation.op == "landmark" and not mutation.value else "Строительство"
			fx.draw_string(Style.BODY, rect.position + Vector2(8, 36), caption, HORIZONTAL_ALIGNMENT_LEFT, 104, 14, Color("f2f0df"))
		if mutation.op != "money" or int(mutation.amount) <= 0:
			continue
		var source := Vector2(96, TopBar.HEIGHT + 32) if int(mutation.from) < 0 else Vector2(size.x - 148, TopBar.HEIGHT + 88 + int(mutation.from) * 48)
		var target := Vector2(96, TopBar.HEIGHT + 32) if int(mutation.to) < 0 else Vector2(size.x - 148, TopBar.HEIGHT + 88 + int(mutation.to) * 48)
		var t := clampf((progress - 0.35) / 0.6, 0.0, 1.0)
		var point := source.lerp(target, t) + Vector2(0, -sin(t * PI) * 56)
		fx.draw_circle(point + Vector2(0, 3), 15, Color(0, 0, 0, 0.15))
		fx.draw_circle(point, 14, Color("c69e55"))
		fx.draw_string(Style.BODY, point + Vector2(-5, 6), str(mutation.amount), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color("203c40"))
