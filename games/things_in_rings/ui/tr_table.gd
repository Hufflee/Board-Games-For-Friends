extends Control
## Приватный 2D стол: кольца, архив областей, человеческая проверка и горячие места.
const Style := preload("res://games/things_in_rings/ui/tr_style.gd")
const Data := preload("res://games/things_in_rings/logic/tr_data.gd")
const Field := preload("res://games/things_in_rings/ui/tr_field.gd")
const Card := preload("res://games/things_in_rings/ui/tr_card.gd")
const Hand := preload("res://hub/private_hand.gd")
var app: Node
var view: Dictionary = {}
var _top: TopBar
var _left: VBoxContainer
var _main: VBoxContainer
var _picture: TextureRect
var _translation: Label
var _selection: Label
var _selected := -1
var _mask := 0
var _archive := 0
var _field: Control
var _hand_orders := {}
var _preview_generation := 0
var _hand: Control
var _margin: MarginContainer
var _judge_reject: Button
var _postgame_seen := false
var _dark := false
var _previous_faces: Array = []
var _rule_flips: Array[Node] = []
const Flip := preload("res://hub/card_flip.gd")

func _ready() -> void:
	_hand_orders = app.hand_orders
	_dark = Prefs.dark_theme()
	_top = TopBar.make(self, "Things in Rings", Style.button, null, Style.ink(), Style.HEAD)
	for item: Array in [["Правила", app.show_rules], ["Настройки", app.show_settings]]:
		var b := Style.button(item[0], 16)
		b.pressed.connect(item[1])
		_top.actions.add_child(b)
	var theme_button := ThemeToggle.make(Style.button, 16)
	Prefs.changed.connect(_theme_changed)
	_top.actions.add_child(theme_button)
	var leave := Style.button("Выйти", 16)
	LeaveGuard.wire(leave, "Выйти?", "Вернуться к выбору игры.", app.back_to_hub)
	_top.actions.add_child(leave)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", int(TopBar.HEIGHT) + 16)
	add_child(margin)
	var row := Style.row(16)
	margin.add_child(row)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 168
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left_scroll)
	_left = Style.column(8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_left)
	_main = Style.column(8)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_main)
	var sidebar := Style.column(8)
	sidebar.custom_minimum_size.x = 200
	row.add_child(sidebar)
	sidebar.add_child(Style.label("ВЕЩИ И СМЫСЛ", 16))
	_picture = TextureRect.new()
	var corners := ShaderMaterial.new()
	corners.shader = preload("res://hub/card_corners.gdshader")
	_picture.material = corners
	_picture.custom_minimum_size = Vector2(200, 304)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_child(_picture)
	_translation = Style.label("", 16, Color(Style.muted(), 0.8))
	_translation.name = "Translation"
	_translation.custom_minimum_size = Vector2(200, 120)
	_translation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_translation)
	var hint := Style.label("Наведите на открытую карту. «Название» — по английскому оригиналу.", 12, Style.muted())
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 200
	sidebar.add_child(hint)
	Style.outline(_picture)
	Net.state_changed.connect(_state)
	if not Net.view.is_empty():
		_state(Net.view)

func _theme_changed() -> void:
	if _dark == Prefs.dark_theme():
		return
	_dark = Prefs.dark_theme()
	get_tree().root.theme = Style.theme()
	app.theme = get_tree().root.theme
	get_tree().call_group("tr_backdrop", "queue_redraw")
	app.show_table()

func _state(next: Dictionary) -> void:
	var prior: Array = view.get("revealed_conditions", []).duplicate()
	_previous_faces = prior
	view = next
	_selected = -1
	_mask = int(view.get("pending", {}).get("proposed", 0))
	clear_preview()
	_rebuild()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feedback(view.get("feedback", {}))

func _send(kind: String, payload: Dictionary = {}) -> void:
	payload["revision"] = int(view.get("revision", -1))
	Net.send_action(kind, payload)

func _rebuild() -> void:
	for flip: Node in _rule_flips:
		if is_instance_valid(flip):
			flip.cancel()
	_rule_flips.clear()
	if is_instance_valid(_hand):
		remove_child(_hand)
		_hand.queue_free()
	_hand = null
	_field = null
	Style.clear(_left)
	Style.clear(_main)
	if view.is_empty():
		return
	var people: Array = view.players
	var phase: String = view.phase
	var me: int = view.you
	var active: int = view.actor
	_top.info.text = "Круг %d · %s" % [view.round_no, "финал" if phase in ["postgame", "game_over"] else "знающий" if active == view.knower else "искатель"]
	_left.add_child(Style.heading("ЗА СТОЛОМ"))
	for seat: int in people.size():
		var label := "%s · %d" % [people[seat].name, view.counts[seat]]
		if seat == view.knower:
			label += " · З"
		var b := Style.button(label, 12)
		b.name = "Seat%d" % seat
		UISel.pick(b, seat == me)
		b.disabled = not bool(view.get("hotseat", false))
		b.pressed.connect(func(): Net.send_action("view_seat", {"seat": seat}))
		_left.add_child(b)
	_left.add_child(Style.label("З — знающий · карт: %d" % view.deck_left, 12, Style.muted()))
	_left.add_child(Style.label("Передайте экран и нажмите своё имя." if view.get("hotseat", false) else "Ваши карты видны только вам.", 12, Style.muted()))
	if phase != "choose_rules":
		_build_archive()
	_margin.add_theme_constant_override("margin_bottom", 16 if phase in ["choose_rules", "judge", "postgame", "game_over"] else 104)
	var text := _phase_text()
	if view.get("disconnected", []).has(active):
		text = "Ожидаем возвращения: " + str(people[active].name)
	var caption := Style.label(text)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.size.x = maxf(400.0, _main.size.x)
	_main.add_child(caption)
	if phase == "choose_rules":
		_build_choices()
		return
	var field := Field.new()
	field.name = "RingField"
	field.table = self
	field.rings = view.rings
	_main.add_child(field)
	if phase in ["postgame", "game_over"]:
		field.custom_minimum_size.y = 240
	_field = field
	_selection = Style.label("Перетащите вещь в кольца или выберите карту и нажмите область.", 12, Style.muted())
	if phase in ["postgame", "game_over"]:
		_selection.text = "Нажмите закрытое условие, чтобы перевернуть." if me == view.knower else "Знающий открывает условия по одному."
	_main.add_child(_selection)
	if phase == "judge":
		var judge_row := Style.row()
		var confirm := Style.button("Верно · оставить")
		confirm.name = "JudgeConfirm"
		confirm.theme_type_variation = "SelectedButton"
		confirm.disabled = me != int(view.knower)
		confirm.pressed.connect(func(): _send("judge", {"mask": int(view.pending.proposed)}))
		judge_row.add_child(confirm)
		_judge_reject = Style.button("Исправить область")
		_judge_reject.name = "JudgeCorrect"
		_judge_reject.disabled = me != int(view.knower) or _mask == int(view.pending.proposed)
		_judge_reject.pressed.connect(func(): _send("judge", {"mask": _mask}))
		judge_row.add_child(_judge_reject)
		_main.add_child(judge_row)
	elif phase not in ["postgame", "game_over"]:
		_build_hand()
	var actions := Style.row()
	if phase in ["postgame", "game_over"]:
		_build_final_rules()
		if phase == "postgame":
			var victory := Style.button("Экран победы")
			victory.name = "ShowVictory"
			victory.disabled = not Net.is_host()
			victory.theme_type_variation = "SelectedButton"
			victory.pressed.connect(func(): _send("show_victory"))
			actions.add_child(victory)
		var why := {"no_clue": "Подсказки закончились — общий проигрыш.", "deck_empty": "Колода исчерпана — завершение без победителя."}
		_main.add_child(Style.label(why.get(str(view.reason), "Партия завершена. Попробуйте угадать правила!"), 16))
	_main.add_child(actions)
	if phase not in ["postgame", "game_over"] and not view.secret_rules.is_empty():
		var rules_row := Style.row()
		for category: String in view.rings:
			if view.secret_rules.has(category):
				rules_row.add_child(_card(int(view.secret_rules[category]), Vector2(40, 60), false))
		_left.add_child(Style.label("Правила · наведите для просмотра", 12, Style.muted()))
		_left.add_child(rules_row)

func _phase_text() -> String:
	var actor_name := ""
	if int(view.actor) >= 0:
		actor_name = str(view.players[view.actor].name)
	match str(view.phase):
		"choose_rules":
			return "Знающий выбирает по одному тайному правилу на кольцо." if view.you != view.knower else "Выберите 1 из 3 правил для каждого кольца. Вещи раздадим после подтверждения."
		"setup_clues":
			return "%s: разместите подсказки · осталось %d" % [actor_name, view.initial_clues_left]
		"knower_clue":
			return "%s: новая подсказка перед следующим кругом" % actor_name
		"judge":
			return "%s: выберите правильную область и подтвердите" % actor_name
		"place":
			return "%s: поместите вещь. После верного ответа играйте снова." % actor_name
	return "Знающий переворачивает условия по одному. Хост открывает экран победы, когда все готовы."

func _build_choices() -> void:
	if int(view.you) != int(view.knower):
		_main.add_child(Style.heading("ТАЙНЫЕ ПРАВИЛА"))
		_main.add_child(Style.label("Дождитесь подсказок знающего.", 16, Style.muted()))
		return
	var categories := Style.row(16)
	categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for category: String in view.rings:
		var panel := PanelContainer.new()
		panel.name = "Choices" + category
		panel.add_theme_stylebox_override("panel", Style.box(Color(Style.paper(), 0.7), 12))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := Style.column(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Style.heading(Style.category_name(category)))
		panel.add_child(col)
		for id: int in view.rule_choices[category]:
			var choice := Button.new()
			choice.name = "Rule%d" % id
			choice.custom_minimum_size = Vector2(208, 140)
			choice.size_flags_vertical = Control.SIZE_EXPAND_FILL
			UISel.pick(choice, view.secret_rules.get(category, -1) == id)
			var card := _card(id, Vector2(86, 130), false)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choice.add_child(card)
			card.position = Vector2(6, 5)
			var translation := Style.label(Data.translation(id), 12, Style.muted())
			translation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			translation.position = Vector2(104, 8)
			translation.size = Vector2(96, 126)
			translation.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choice.add_child(translation)
			choice.mouse_entered.connect(func(): preview_card(id))
			choice.mouse_exited.connect(clear_preview)
			choice.pressed.connect(func(): _send("choose_rule", {"category": category, "card": id}))
			col.add_child(choice)
		categories.add_child(panel)
	_main.add_child(categories)
	var confirm := Style.button("Подтвердить правила и раздать вещи")
	confirm.name = "BeginClues"
	confirm.theme_type_variation = "SelectedButton"
	confirm.disabled = view.secret_rules.size() != view.rings.size()
	confirm.pressed.connect(func(): _send("begin_clues"))
	_main.add_child(confirm)

func _build_hand() -> void:
	var hand := Hand.new()
	hand.name = "PrivateHand"
	hand.card_size = Vector2(88, 132)
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.preview_delay = 0.0
	hand.edge_peek = true
	var order_key := str([view.get("game_id", ""), view.you])
	hand.order = _hand_orders.get(order_key, []).duplicate()
	for id: int in view.hand:
		hand.entries.append({"key": str(id), "id": id, "texture": Data.texture(id), "face_up": true})
	hand.chosen.connect(func(entry: Dictionary):
		if can_place():
			select_card(int(entry.id)))
	hand.order_changed.connect(func(order: Array): _hand_orders[order_key] = order.duplicate())
	hand.preview_requested.connect(func(entry: Dictionary): _show_preview_now(int(entry.id)))
	hand.preview_closed.connect(clear_preview)
	hand.drop_action = _hand_drop
	_hand = hand
	add_child(hand)
	hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hand.offset_left = 200
	hand.offset_right = -224
	hand.offset_top = -82
	hand.offset_bottom = 50
	for id: int in view.hand:
		var card: K12TableCard = hand._cards[str(id)]
		card.name = "Card%d" % id
		Style.outline(card._face)
		card.hovered.connect(func(_card: K12TableCard, on: bool):
			if on:
				_show_preview_now(id))

func _hand_drop(entry: Dictionary, at: Vector2) -> bool:
	if not can_place() or not is_instance_valid(_field) or not _field.get_global_rect().has_point(at):
		return false
	var local_at: Vector2 = _field.get_global_transform_with_canvas().affine_inverse() * at
	drop_card(int(entry.id), _field.mask_at(local_at))
	return true

func _card(id: int, dimensions: Vector2, movable: bool) -> Control:
	var card := Card.new()
	card.name = "Card%d" % id
	card.card = id
	card.table = self
	card.movable = movable
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = dimensions
	card.size = dimensions
	return card

func _build_archive() -> void:
	_left.add_child(Style.heading("АРХИВ ОБЛАСТЕЙ"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_left.add_child(grid)
	for mask: int in (1 << view.rings.size()):
		var amount := 0
		for entry: Dictionary in view.board:
			if int(entry.mask) == mask:
				amount += 1
		var b := Style.button("%s · %d" % [_region_short(mask), amount], 12)
		b.name = "Region%d" % mask
		b.set_meta("spectator_read_only", true)  # Меняет только локально открытый архив.
		UISel.pick(b, _archive == mask)
		b.pressed.connect(func():
			_archive = mask
			_rebuild())
		grid.add_child(b)
	_left.add_child(Style.label(_region_name(_archive), 12, Style.muted()))
	for entry: Dictionary in view.board:
		if int(entry.mask) == _archive:
			_left.add_child(_card(int(entry.card), Vector2(88, 132), false))

func _region_short(mask: int) -> String:
	if mask == 0:
		return "Вне"
	var letters := PackedStringArray()
	for i: int in view.rings.size():
		if mask & (1 << i):
			letters.append(Style.category_name(str(view.rings[i])).left(1))
	return "∩".join(letters)

func _region_name(mask: int) -> String:
	var labels := PackedStringArray()
	for i: int in view.rings.size():
		if mask & (1 << i):
			labels.append(Style.category_name(str(view.rings[i])))
	return "Вне всех колец" if mask == 0 else " ∩ ".join(labels)

func can_place() -> bool:
	return int(view.get("you", -1)) == int(view.get("actor", -2)) and str(view.get("phase", "")) in ["place", "setup_clues", "knower_clue"]

func select_card(id: int) -> void:
	_selected = id
	if is_instance_valid(_selection):
		_selection.text = Data.card_name(id) + " · нажмите нужную область колец"

func drop_card(id: int, mask: int) -> void:
	if can_place() and view.hand.has(id):
		_send("place" if view.phase == "place" else "clue", {"card": id, "mask": mask})

func region_clicked(mask: int) -> void:
	_mask = mask
	if is_instance_valid(_judge_reject) and view.phase == "judge":
		_judge_reject.disabled = view.you != view.knower or _mask == int(view.pending.proposed)
	if is_instance_valid(_selection):
		_selection.text = "Область: " + _region_name(mask)
	if _selected >= 0 and can_place():
		drop_card(_selected, mask)
	elif view.phase != "judge":
		_archive = mask
		_rebuild()

func preview_card(id: int) -> void:
	_show_preview_now(id)

func _show_preview_now(id: int) -> void:
	_preview_generation += 1
	_picture.texture = Data.texture(id)
	_picture.get_node("CardOutline").show()
	_translation.text = Data.translation(id)

func clear_preview() -> void:
	_preview_generation += 1
	if is_instance_valid(_picture):
		_picture.texture = null
		_picture.get_node("CardOutline").hide()
	if is_instance_valid(_translation):
		_translation.text = ""

## Финал остаётся на столе до отдельного действия хоста. Лицо берём только из view.
func _build_final_rules() -> void:
	var row := Style.row(24)
	row.name = "FinalConditions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_main.add_child(row)
	var faces: Array = view.get("condition_faces", [])
	var opened: Array = view.get("revealed_conditions", [])
	var first: bool = not app.final_seen.has(str(view.get("game_id", "")))
	app.final_seen[str(view.get("game_id", ""))] = true
	for ring: int in view.rings.size():
		var category: String = view.rings[ring]
		var id: int = int(faces[ring]) if ring < faces.size() else -1
		var up: bool = ring < opened.size() and bool(opened[ring]) and id >= 0
		var col := Style.column(4)
		row.add_child(col)
		col.add_child(Style.label(Style.category_name(category), 12, Style.muted()))
		var card := TextureRect.new()
		card.name = "FinalCondition%d" % ring
		card.custom_minimum_size = Vector2(94, 144)
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		col.add_child(card)
		Style.outline(card)
		var previous: bool = bool(_previous_faces[ring]) if ring < _previous_faces.size() else up
		var show_side := func(front: bool):
			card.texture = Data.texture(id) if front and id >= 0 else Data.back_texture(category)
		var flip: Node = Flip.attach(card, show_side, previous and up)
		_rule_flips.append(flip)
		if up and not previous:
			flip.flip_to.call_deferred(true)
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if view.you == view.knower and not up and view.phase == "postgame":
					_send("flip_condition", {"ring": ring}))
		card.mouse_entered.connect(func():
			if up and not flip.busy:
				preview_card(id))
		card.mouse_exited.connect(clear_preview)
		if first:
			var material_value := ShaderMaterial.new()
			material_value.shader = preload("res://games/things_in_rings/ui/tr_condition_reveal.gdshader")
			card.material = material_value
			for border: Node in card.get_children():
				if border is CanvasItem:
					border.use_parent_material = true
			var fade := card.create_tween()
			fade.tween_method(func(value: float): material_value.set_shader_parameter("progress", value), 0.0, 1.0, 1.9)
			fade.tween_callback(func():
				card.material = null
				for border: Node in card.get_children():
					if border is CanvasItem:
						border.use_parent_material = false)

## Идентификатор хранится в приложении, чтобы смена темы не повторяла старый ответ.
func _feedback(event: Dictionary) -> void:
	if event.is_empty():
		return
	var key := str([view.get("game_id", ""), event.get("id", -1)])
	if app.feedback_seen.has(key):
		return
	app.feedback_seen[key] = true
	var correct := bool(event.get("correct", false))
	var layer := Control.new()
	layer.name = "AnswerFeedback"
	layer.z_index = 120
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var color := Color("62e6a5") if correct else Color("eb5d71")
	layer.draw.connect(func():
		for i: int in 12:
			var inset := float(i) * 2.0 + 1.0
			layer.draw_rect(Rect2(Vector2(inset, inset), layer.size - Vector2.ONE * inset * 2), Color(color, 0.18 * (1.0 - float(i) / 12.0)), false, 3.0))
	var sound := AudioStreamPlayer.new()
	sound.bus = "SFX"
	sound.volume_db = -6
	var path := "res://games/things_in_rings/audio/%s.ogg" % ("correct" if correct else "wrong")
	if ResourceLoader.exists(path):
		sound.stream = load(path)
	elif FileAccess.file_exists(path):
		sound.stream = AudioStreamOggVorbis.load_from_file(path)
	layer.add_child(sound)
	sound.play()
	var fade := layer.create_tween()
	fade.tween_interval(0.65)
	fade.tween_property(layer, "modulate:a", 0.0, 0.35)
	fade.tween_callback(layer.queue_free)

