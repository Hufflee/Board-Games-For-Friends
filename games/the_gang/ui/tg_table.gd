extends Control
## 2D-стол: публичная история фишек, закрытая личная рука и общее вскрытие.

const Flip := preload("res://hub/card_flip.gd")
const Chip := preload("res://games/the_gang/ui/tg_chip.gd")

var _faces: Array[bool] = [false, false]
var _flips: Array[Node] = []
var _hand_key := ""
var _center_zone: Control
var _hand_zone: Control
var _drag_chip: Control
var _drag_ghost: Control
var _drag_revision := -1
var _drag_seat := -1
var _drag_value := 0
var _drag_holder := -1

var app: Node
var _view: Dictionary = {}
var _top: TopBar
var _players: VBoxContainer
var _main: VBoxContainer
var _preview: PanelContainer
var _peek := false
var _last_seat := -2
var _last_heist := -1
const FRAME := 28
## Своя фишка-игрушка у карт: место переживает перестройку стола (ключ — партия/ограбление/раунд/номинал).
var _toy: Control
var _toy_key := ""
var _toy_pos := Vector2(-1, -1)

func _ready() -> void:
	var background := TGStyle.Background.new()
	background.decor = false
	add_child(background)
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
	# Панели внутри двойной рамки фона (линии на 10 и 20 px от края).
	margin.add_theme_constant_override("margin_left", FRAME)
	margin.add_theme_constant_override("margin_right", FRAME)
	margin.add_theme_constant_override("margin_top", int(TopBar.HEIGHT) + 8)
	margin.add_theme_constant_override("margin_bottom", FRAME)
	add_child(margin)
	var row := TGStyle.row(16)
	margin.add_child(row)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 280
	side.add_theme_stylebox_override("panel", TGStyle.box(Color.TRANSPARENT, 12))
	row.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_players = TGStyle.column(4)
	_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players)
	# Весь стол помещается на экране без прокрутки, в том числе при 10 игроках.
	_main = TGStyle.column(10)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_main)
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
	var hand_key := str([view.get("game_id", ""), view.get("hand", []), view.get("spectator", false)])
	if seat != _last_seat or heist != _last_heist or hand_key != _hand_key:
		_faces = [false, false]
		_peek = false
	_hand_key = hand_key
	_last_seat = seat
	_last_heist = heist
	_rebuild()

func _send(kind: String, data: Dictionary = {}) -> void:
	data["revision"] = int(_view.get("revision", -1))
	Net.send_action(kind, data)

func _rebuild() -> void:
	if _view.is_empty():
		return
	_cancel_drag()
	if is_instance_valid(_toy):
		_toy_pos = _toy.position
	_toy = null
	for flip in _flips:
		if is_instance_valid(flip):
			flip.cancel()
	_flips.clear()
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
		var player_row := TGStyle.row(4)
		var title := TGStyle.button(("● " if seat == me else "") + str(players[seat].get("name", "Игрок")), 14)
		title.name = "Seat%d" % seat
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.add_theme_color_override("font_color", TGStyle.GOLD if seat == me else TGStyle.INK)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			title.add_theme_stylebox_override(state, TGStyle.box(TGStyle.PANEL, 1))
		title.disabled = not bool(_view.get("hotseat", false))
		title.pressed.connect(func(): Net.send_action("view_seat", {"seat": seat}))
		player_row.add_child(title)
		var chip_row := TGStyle.row(4)
		for index in 4:
			var value := 0
			if index < history.size() and history[index] is Array and seat < history[index].size():
				value = int(history[index][seat])
			if index == round_number - 1 and phase == "rank" and seat < chips.size():
				value = int(chips[seat])
			if index == round_number - 1 and phase == "rank" and value > 0 and seat != me:
				chip_row.add_child(_chip(value, seat, 28))
			else:
				var marker := TGStyle.label("%d" % value if value > 0 else "·", 12, TGStyle.ROUND_COLORS[index])
				marker.custom_minimum_size = Vector2(28, 28)
				marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				chip_row.add_child(marker)
		player_row.add_child(chip_row)
		_players.add_child(player_row)
	var status := TGStyle.row(24)
	status.add_child(TGStyle.heading("ХРАНИЛИЩА %d / 3" % int(_view.get("vaults", 0)), 24))
	status.add_child(TGStyle.heading("ТРЕВОГИ %d / 3" % int(_view.get("alarms", 0)), 24))
	_main.add_child(status)
	var board_panel := PanelContainer.new()
	board_panel.add_theme_stylebox_override("panel", TGStyle.box(Color.TRANSPARENT, 12))
	_main.add_child(board_panel)
	var board := TGStyle.column(8)
	board_panel.add_child(board)
	board.add_child(TGStyle.label("ОБЩИЕ КАРТЫ", 14, TGStyle.MUTED))
	var board_row := TGStyle.row(10)
	board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(board_row)
	var community: Array = _view.get("community", [])
	for index in 5:
		_add_card(board_row, int(community[index]) if index < community.size() else -1, Vector2(84, 120))
	if phase == "rank":
		_build_rank(me, chips, players)
	else:
		_build_result(phase, players)

func _take(value: int) -> void:
	_send("take", {"value": value})

func _build_rank(me: int, chips: Array, players: Array) -> void:
	var note := TGStyle.label("Перетащите фишку к своим картам. 1 — слабейшая, %d — сильнейшая. Чужую можно забрать. Карты и комбинацию не называйте." % players.size(), 14, TGStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main.add_child(note)
	var center_panel := PanelContainer.new()
	center_panel.name = "ChipCenter"
	center_panel.add_theme_stylebox_override("panel", TGStyle.box(Color.TRANSPARENT, 12))
	_center_zone = center_panel
	_main.add_child(center_panel)
	var center := TGStyle.column(4)
	center_panel.add_child(center)
	center.add_child(TGStyle.label("ЦЕНТР · сюда можно вернуть свою фишку", 14, TGStyle.MUTED))
	var chip_row := TGStyle.row(6)
	chip_row.custom_minimum_size.y = 54
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(chip_row)
	for value in range(1, players.size() + 1):
		if chips.find(value) < 0:
			chip_row.add_child(_chip(value, -1, 52))
	var hand_panel := PanelContainer.new()
	hand_panel.name = "HandDropZone"
	hand_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_panel.add_theme_stylebox_override("panel", TGStyle.box(Color.TRANSPARENT, 12))
	_hand_zone = hand_panel
	_main.add_child(hand_panel)
	var hand := TGStyle.column(8)
	hand_panel.add_child(hand)
	var hand_header := TGStyle.row(16)
	hand.add_child(hand_header)
	hand_header.add_child(TGStyle.heading("ВАШИ КАРТЫ" if me >= 0 else "РЕЖИМ ЗРИТЕЛЯ", 24))
	var flip_hint := TGStyle.label("Потяните край карты, чтобы открыть или скрыть её", 14, TGStyle.MUTED)
	flip_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_header.add_child(flip_hint)
	var cards := TGStyle.row(12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.add_child(cards)
	var personal: Array = _view.get("hand", [])
	for index in 2:
		_add_personal(cards, int(personal[index]) if index < personal.size() and me >= 0 and not bool(_view.get("spectator", false)) else -1, index)
	var play := Control.new()
	play.name = "ChipPlay"
	play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_panel.add_child(play)
	if me >= 0 and me < chips.size() and int(chips[me]) > 0:
		var own := _chip(int(chips[me]), me, 64)
		own.toy = true
		own.size = Vector2.ONE * 64
		own.tooltip_text = "Свою фишку можно катать и подбрасывать. Перетащите в центр, чтобы вернуть"
		own.released.connect(_toy_released)
		play.add_child(own)
		_toy = own
		var key := str([_view.get("game_id", ""), _view.get("heist_no", 0), _view.get("round_no", 0), int(chips[me])])
		if key != _toy_key:
			_toy_key = key
			_toy_pos = Vector2(-1, -1)
		_place_toy.call_deferred(own, play)

func _place_toy(own: Control, play: Control) -> void:
	if not is_instance_valid(own):
		return
	if _toy_pos.x < 0.0:
		_toy_pos = Vector2(play.size.x * 0.5 + 150.0, play.size.y * 0.5 - 4.0)
	own.position = _toy_pos.clamp(Vector2.ZERO, (play.size - own.size).max(Vector2.ZERO))

## Игрушку отпустили над центром — это прежнее действие «вернуть фишку».
func _toy_released(at: Vector2) -> void:
	if _can_play() and is_instance_valid(_center_zone) and _center_zone.get_global_rect().has_point(at):
		_send("return")

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
	var card := TextureRect.new()
	card.texture = texture
	card.custom_minimum_size = dimensions
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var corners := ShaderMaterial.new()
	corners.shader = preload("res://hub/card_corners.gdshader")
	card.material = corners
	if id >= 0:
		card.mouse_entered.connect(func(): _show_preview(texture, card))
		card.mouse_exited.connect(_preview.hide)
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


func _can_play() -> bool:
	return str(_view.get("phase", "")) == "rank" and int(_view.get("seat", -1)) >= 0 		and not bool(_view.get("spectator", false)) and not Net.paused and not bool(_view.get("game_paused", false))


func _chip(value: int, holder: int, diameter: int) -> Control:
	var chip := Chip.new()
	chip.name = "Chip%d" % value
	chip.value = value
	chip.round_index = clampi(int(_view.get("round_no", 1)) - 1, 0, 3)
	chip.custom_minimum_size = Vector2.ONE * diameter
	chip.tooltip_text = "Перетащите к своим картам" if holder != int(_view.get("seat", -1)) else "Перетащите в центр"
	chip.gui_input.connect(_chip_input.bind(chip, value, holder))
	return chip


func _chip_input(event: InputEvent, chip: Control, value: int, holder: int) -> void:
	if chip.toy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _can_play():
		_cancel_drag()
		_drag_chip = chip
		_drag_value = value
		_drag_holder = holder
		_drag_seat = int(_view.seat)
		_drag_revision = int(_view.revision)
		var ghost := Chip.new()
		ghost.value = value
		ghost.round_index = clampi(int(_view.round_no) - 1, 0, 3)
		ghost.size = Vector2.ONE * 64
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.z_index = 94
		add_child(ghost)
		_drag_ghost = ghost
		ghost.global_position = event.global_position - ghost.size * 0.5
		chip.modulate.a = 0.35
		chip.accept_event()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_drag_ghost):
		return
	if not _can_play() or _drag_revision != int(_view.get("revision", -1)) or _drag_seat != int(_view.get("seat", -1)):
		_cancel_drag()
		return
	if event is InputEventMouseMotion:
		_drag_ghost.global_position = event.position - _drag_ghost.size * 0.5
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var take: bool = _hand_zone.get_global_rect().has_point(event.position) and _drag_holder != _drag_seat
		var give_back: bool = _center_zone.get_global_rect().has_point(event.position) and _drag_holder == _drag_seat
		var value := _drag_value
		_cancel_drag()
		get_viewport().set_input_as_handled()
		if take:
			_send("take", {"value": value})
		elif give_back:
			_send("return")


func _process(_delta: float) -> void:
	if not _can_play():
		_cancel_drag()
		for flip in _flips:
			if is_instance_valid(flip) and flip.busy:
				flip.cancel()


func _cancel_drag() -> void:
	if is_instance_valid(_drag_chip):
		_drag_chip.modulate.a = 1.0
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_chip = null
	_drag_ghost = null


func _add_personal(parent: Control, id: int, index: int) -> void:
	# Лицо берём только из личного view; закрытый preview не содержит его текстуры.
	var card := TextureRect.new()
	card.name = "PersonalCard%d" % index
	card.custom_minimum_size = Vector2(100, 142)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var corners := ShaderMaterial.new()
	corners.shader = preload("res://hub/card_corners.gdshader")
	card.material = corners
	parent.add_child(card)
	var show_side := func(up: bool):
		card.texture = load("res://games/the_gang/art/cards/%s.webp" % (str(id) if up and id >= 0 else "back"))
		_preview.hide()
	var flip: Node = Flip.attach(card, show_side, _faces[index] and id >= 0, true)
	flip.can_interact = func(): return _can_play() and id >= 0
	flip.flipped.connect(func(up: bool):
		_faces[index] = up
		_peek = _faces.has(true))
	_flips.append(flip)
	card.mouse_entered.connect(func():
		if flip.face_up and not flip.busy and id >= 0:
			_show_preview(card.texture, card))
	card.mouse_exited.connect(_preview.hide)

