extends Control
## 2D-стол: публичная история фишек, закрытая личная рука и общее вскрытие.

var app: Node
var _view: Dictionary = {}
var _top: TopBar
var _players: VBoxContainer
var _main: VBoxContainer
var _preview: PanelContainer
var _peek := false
var _last_seat := -2
var _last_heist := -1

func _ready() -> void:
	add_child(TGStyle.Background.new())
	_top = TopBar.make(self, "The Gang", TGStyle.button, null, TGStyle.INK, TGStyle.HEAD)
	var rules := TGStyle.button("Правила", 14)
	rules.name = "Rules"
	rules.pressed.connect(func(): app.show_rules())
	_top.actions.add_child(rules)
	var settings := TGStyle.button("Настройки", 14)
	settings.name = "Settings"
	settings.pressed.connect(func(): app.show_settings())
	_top.actions.add_child(settings)
	var leave := TGStyle.button("Выйти", 14)
	LeaveGuard.wire(leave, "Завершить игру?", "Возвращение к выбору игры.", func(): app.back_to_hub())
	_top.actions.add_child(leave)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", int(TopBar.HEIGHT) + 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var row := TGStyle.row(16)
	margin.add_child(row)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 244
	row.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_players = TGStyle.column(4)
	_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players)
	var main_scroll := ScrollContainer.new()
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(main_scroll)
	_main = TGStyle.column(12)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.add_child(_main)
	_preview = PanelContainer.new()
	_preview.z_index = 95
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	add_child(_preview)
	Net.state_changed.connect(_on_state)
	if not Net.view.is_empty():
		_on_state(Net.view)

func _on_state(view: Dictionary) -> void:
	_view = view
	var seat := int(view.get("seat", -1))
	var heist := int(view.get("heist_no", 0))
	if seat != _last_seat or heist != _last_heist:
		_peek = false
	_last_seat = seat
	_last_heist = heist
	_rebuild()

func _send(kind: String, data: Dictionary = {}) -> void:
	data["revision"] = int(_view.get("revision", -1))
	Net.send_action(kind, data)

func _rebuild() -> void:
	if _view.is_empty():
		return
	_preview.hide()
	TGStyle.clear(_players)
	TGStyle.clear(_main)
	var players: Array = _view.get("players", [])
	var phase := str(_view.get("phase", ""))
	var round_number := clampi(int(_view.get("round_no", 1)), 1, 4)
	var me := int(_view.get("seat", -1))
	_top.info.text = "Ограбление %d · %s" % [int(_view.get("heist_no", 1)), ["Префлоп", "Флоп", "Тёрн", "Ривер"][round_number - 1]]
	_players.add_child(TGStyle.heading("КОМАНДА", 24))
	if bool(_view.get("hotseat", false)):
		_players.add_child(TGStyle.label("Нажмите имя для смены места", 12, TGStyle.MUTED))
	_players.add_child(TGStyle.label("ИСТОРИЯ ФИШЕК", 14, TGStyle.MUTED))
	var history: Array = _view.get("history", [])
	var chips: Array = _view.get("chips", [])
	for seat in players.size():
		var player_row := TGStyle.column(2)
		var title := TGStyle.button(("● " if seat == me else "") + str(players[seat].get("name", "Игрок")), 14)
		title.name = "Seat%d" % seat
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.add_theme_color_override("font_color", TGStyle.GOLD if seat == me else TGStyle.INK)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			title.add_theme_stylebox_override(state, TGStyle.box(TGStyle.PANEL, 1))
		title.disabled = not bool(_view.get("hotseat", false))
		title.pressed.connect(func(): Net.send_action("view_seat", {"seat": seat}))
		player_row.add_child(title)
		var chip_row := TGStyle.row(6)
		for index in 4:
			var value := 0
			if index < history.size() and history[index] is Array and seat < history[index].size():
				value = int(history[index][seat])
			if index == round_number - 1 and phase == "rank" and seat < chips.size():
				value = int(chips[seat])
			var marker := TGStyle.button("%d" % value if value > 0 else "·", 12)
			marker.custom_minimum_size = Vector2(40, 20)
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				marker.add_theme_stylebox_override(state, TGStyle.box(TGStyle.PANEL, 1))
			marker.add_theme_color_override("font_color", TGStyle.ROUND_COLORS[index])
			marker.disabled = phase != "rank" or index != round_number - 1 or value == 0 or me < 0 or bool(_view.get("spectator", false))
			marker.pressed.connect(_take.bind(value))
			chip_row.add_child(marker)
		player_row.add_child(chip_row)
		_players.add_child(player_row)
	var status := TGStyle.row(24)
	status.add_child(TGStyle.heading("ХРАНИЛИЩА %d / 3" % int(_view.get("vaults", 0)), 24))
	status.add_child(TGStyle.heading("ТРЕВОГИ %d / 3" % int(_view.get("alarms", 0)), 24))
	_main.add_child(status)
	var board_panel := PanelContainer.new()
	_main.add_child(board_panel)
	var board := TGStyle.column(8)
	board_panel.add_child(board)
	board.add_child(TGStyle.label("ОБЩИЕ КАРТЫ", 14, TGStyle.MUTED))
	var board_row := TGStyle.row(10)
	board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(board_row)
	var community: Array = _view.get("community", [])
	for index in 5:
		_add_card(board_row, int(community[index]) if index < community.size() else -1, Vector2(92, 132))
	if phase == "rank":
		_build_rank(me, chips, players)
	else:
		_build_result(phase, players)

func _take(value: int) -> void:
	_send("take", {"value": value})

func _build_rank(me: int, chips: Array, players: Array) -> void:
	var note := TGStyle.label("Оцените свою руку. 1 — слабейшая, %d — сильнейшая. Чужую фишку можно забрать." % players.size(), 16, TGStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main.add_child(note)
	var chip_row := TGStyle.row(8)
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_main.add_child(chip_row)
	for value in range(1, players.size() + 1):
		var holder := chips.find(value)
		var b := TGStyle.button("%d★" % value, 20)
		b.name = "Chip%d" % value
		b.custom_minimum_size = Vector2(60, 54)
		var color: Color = TGStyle.ROUND_COLORS[int(_view.round_no) - 1]
		if holder >= 0:
			color = color.darkened(0.4)
		b.add_theme_stylebox_override("normal", TGStyle.box(color, 8))
		b.add_theme_color_override("font_color", Color("102329"))
		b.disabled = me < 0 or bool(_view.get("spectator", false)) or holder == me
		b.tooltip_text = "В центре" if holder < 0 else "У %s" % str(players[holder].get("name", "игрока"))
		b.pressed.connect(_take.bind(value))
		chip_row.add_child(b)
	var hand_panel := PanelContainer.new()
	_main.add_child(hand_panel)
	var hand := TGStyle.column(8)
	hand_panel.add_child(hand)
	var hand_header := TGStyle.row()
	hand.add_child(hand_header)
	hand_header.add_child(TGStyle.heading("ВАШИ КАРТЫ" if me >= 0 else "РЕЖИМ ЗРИТЕЛЯ", 24))
	if me >= 0 and not bool(_view.get("spectator", false)):
		var peek := TGStyle.button("Скрыть карты" if _peek else "Посмотреть карты")
		peek.name = "PeekCards"
		peek.pressed.connect(func():
			_peek = not _peek
			_rebuild())
		hand_header.add_child(peek)
		var give_back := TGStyle.button("Вернуть фишку")
		give_back.disabled = me >= chips.size() or int(chips[me]) == 0
		give_back.pressed.connect(func(): _send("return"))
		hand_header.add_child(give_back)
	var cards := TGStyle.row(12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.add_child(cards)
	var personal: Array = _view.get("hand", [])
	for index in 2:
		_add_card(cards, int(personal[index]) if _peek and index < personal.size() else -1, Vector2(108, 154))
	var tip := TGStyle.label("Не называйте карты и комбинацию: общение идёт через фишки.", 16, TGStyle.MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand.add_child(tip)

func _build_result(phase: String, players: Array) -> void:
	var result: Dictionary = _view.get("result", {})
	var success := bool(result.get("success", false))
	var title := "ХРАНИЛИЩЕ ОТКРЫТО" if success else "СРАБОТАЛА ТРЕВОГА"
	if phase == "game_over":
		title = "КОМАНДА ПОБЕДИЛА" if bool(_view.get("won", false)) else "ОГРАБЛЕНИЕ ПРОВАЛЕНО"
	_main.add_child(TGStyle.heading(title, 28))
	if phase == "showdown" and not bool(_view.get("spectator", false)):
		var next := TGStyle.primary("Следующее ограбление")
		next.name = "NextHeist"
		next.pressed.connect(func(): _send("next"))
		_main.add_child(next)
	elif phase == "game_over" and Net.is_host():
		var again := TGStyle.primary("Собраться на новую партию")
		again.pressed.connect(Net.end_game)
		_main.add_child(again)
	var ranks: Array = result.get("ranks", [])
	var hands: Array = result.get("hands", [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_main.add_child(grid)
	for seat_value in result.get("order", []):
		var seat := int(seat_value)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var column := TGStyle.column(6)
		panel.add_child(column)
		column.add_child(TGStyle.label("%d★ · %s" % [int(_view.chips[seat]), str(players[seat].get("name", "Игрок"))], 16, TGStyle.GOLD))
		if seat < ranks.size():
			column.add_child(TGStyle.label(str(ranks[seat].get("name", ""))))
		var row := TGStyle.row(8)
		column.add_child(row)
		if seat < hands.size():
			for id in hands[seat]:
				_add_card(row, int(id), Vector2(66, 94))

func _add_card(parent: Control, id: int, dimensions: Vector2) -> void:
	var texture := load("res://games/the_gang/art/cards/%s.webp" % (str(id) if id >= 0 else "back")) as Texture2D
	var face := TextureRect.new()
	face.texture = texture
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var card := K12TableCard.new("", true, face, dimensions)
	card.draggable = false
	if id >= 0:
		card.hovered.connect(func(_card: K12TableCard, on: bool):
			if on:
				_show_preview(texture, card)
			else:
				_preview.hide())
	parent.add_child(card)

func _show_preview(texture: Texture2D, card: Control) -> void:
	TGStyle.clear(_preview)
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(210, 300)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(image)
	_preview.reset_size()
	_preview.position = Vector2(clampf(card.global_position.x + card.size.x + 12, 0, size.x - 250), clampf(card.global_position.y - 160, TopBar.HEIGHT + 8, size.y - 350))
	_preview.show()
