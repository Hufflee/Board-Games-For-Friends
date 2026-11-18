extends Control
## Стол Unmatched. Принимает готовую проекцию партии и передаёт действия её контроллеру.

signal submitted(answer: Dictionary)
signal target_pressed(cell: int)
signal hand_requested(seat: int)
signal handoff_confirmed
signal action_requested(kind: String, argument: Dictionary)
signal exit_requested

const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const Style := preload("res://games/unmatched/ui/um_style.gd")
const Board := preload("res://games/unmatched/ui/um_board_view.gd")
const HandView := preload("res://games/unmatched/ui/um_hand_view.gd")
const PileView := preload("res://games/unmatched/ui/um_pile_view.gd")
const Parallax := preload("res://hub/cursor_parallax.gd")
const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Rules := preload("res://games/unmatched/logic/um_rules.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const CombatShow := preload("res://games/unmatched/ui/um_combat_show.gd")
const HeroChoice := preload("res://games/unmatched/ui/um_hero_choice.gd")
const Maps := preload("res://games/unmatched/logic/um_maps.gd")

var _state := {}
var _arena := ""
var _dark := false
var _colors := {}
var _backdrop: TextureRect
var _shade: ColorRect
var _top: TopBar
var _board: Control
var _arena_title: Label
var _selection_label: Label
var _fight_frame: PanelContainer
var _stage: VBoxContainer
var _preview_column: VBoxContainer
var _shown_scheme := 0
var _shown_misery := 0
var _preview: TextureRect
var _preview_hint: Label
var _piles: VBoxContainer
var _hand: VBoxContainer
var _attack: TextureRect
var _defense: TextureRect
var _attack_hint: Label
var _defense_hint: Label
var _attack_name: Label
var _defense_name: Label
var _opponents: VBoxContainer
var _opponent_text: Label
var _opponent_cards: HBoxContainer
var _reply: Button
var _status: Label
var _preview_source := ""
var _card_back: Texture2D
var _back_outline: ShaderMaterial
var _hero_backs: Dictionary = {}
var _actions: HBoxContainer
var _action_slot: Control
var _fighter := 0
var _last_place := -1
var _target_cells := {}
var _staged_attack := ""
var _maneuver_preview := false
var _combat_show: CombatShow
var _hero_choice: HeroChoice


func _ready() -> void:
	_build()
	resized.connect(_update_drop_zone.call_deferred)
	Prefs.changed.connect(_on_prefs)
	present(_state)


func present(view: Dictionary) -> void:
	_state = view
	if not is_node_ready():
		return
	var arena := str(view.get("arena", "marmoreal"))
	if arena not in Maps.NAMES:
		arena = "marmoreal"
	if arena != _arena or Prefs.dark_theme() != _dark:
		_apply_palette(arena, Prefs.dark_theme())
	_top.info.text = str(view.get("phase_title", "Unmatched"))
	_status.text = str(view.get("step", ""))
	_status.tooltip_text = ""
	if view.has("phase_id"):
		if view.phase_id != Rules.Phase.ACTION or view.get("handoff", false) or view.active != _last_place:
			_staged_attack = ""
			_maneuver_preview = false
		_present_actions(view)
	else:
		_board.present(_arena, view.get("fighters", []), view.get("targets", {}))
	_piles.present(view.get("piles", []))
	_show_scheme(view.get("scheme_notice", {}))
	var misery: Dictionary = view.get("misery_notice", {})
	if int(misery.get("id", 0)) > _shown_misery:
		_shown_misery = misery.id
		_set_preview(Art.face(misery.card), "misery")
	if view.has("handoff") and not view.handoff:
		_hand.accept_handoff()
	var hand: Dictionary = view.get("hand", {})
	var effect: Dictionary = view.get("effect", {})
	if effect.get("hand_discard", false) and hand.get("hand", -1) == effect.seat:
		hand = hand.duplicate()
		hand["choice"] = {"id": effect.id, "allowed": effect.options, "min": int(not effect.optional),
			"max": 1, "prompt": effect.prompt}
	_hand.present(hand)
	var combat: Dictionary = view.get("combat", {})
	_combat_show.present(combat, view.get("combat_outcome", {}), _attack.get_global_rect(), _defense.get_global_rect(), _fight_frame.get_global_rect())
	_update_combat(combat)
	var draft: Dictionary = view.get("draft", {})
	_hero_choice.visible = not draft.is_empty() and not view.get("handoff", false)
	if _hero_choice.visible:
		_hero_choice.sync(draft.offers, draft.remaining, str(view.get("actor_name", "")))
	_update_opponent(view.get("hand", {}).get("counts", []), view.get("hand", {}).get("owned", []))
	_update_drop_zone.call_deferred()


func hide_for_handoff(player_name: String) -> void:
	_hand.hide_for_handoff(player_name)
	_set_preview(null, "")


func _build() -> void:
	_backdrop = TextureRect.new()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Parallax.follow_texture(_backdrop, 10.0)
	_shade = ColorRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	body.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	body.offset_left = 32
	body.offset_right = -32
	body.offset_top = TopBar.HEIGHT + 16
	body.offset_bottom = -198

	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 8)
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(field)
	var tools := Control.new()
	tools.mouse_filter = MOUSE_FILTER_IGNORE
	tools.custom_minimum_size.y = 30.0
	field.add_child(tools)
	_arena_title = _label("", 20, true)
	_ink_on_backdrop(_arena_title)
	_arena_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tools.add_child(_arena_title)
	_arena_title.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_selection_label = _label("", 14)
	_ink_on_backdrop(_selection_label)
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tools.add_child(_selection_label)
	_selection_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_board = Board.new()
	_board.size_flags_vertical = SIZE_EXPAND_FILL
	_board.target_pressed.connect(_board_clicked)
	_board.door_pressed.connect(func(door: int): action_requested.emit("door", {"fighter": _fighter, "door": door}))
	_board.item_pressed.connect(func(id: int): action_requested.emit("battlefield_item", {"fighter": _fighter, "item": id}))
	_board.item_hovered.connect(func(id: int) -> void:
		if id < 0:
			_clear_preview("field_item")
		else:
			_set_preview(Art.face(Maps.Battlefields.card(id)), "field_item"))
	field.add_child(_board)
	_board.character_hovered.connect(func(hero: String):
		if hero.is_empty():
			_clear_preview("character")
		else:
			_set_preview(Art.reference_face(hero), "character"))
	_action_slot = Control.new()
	_action_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_action_slot.hide()
	field.add_child(_action_slot)
	_action_slot.item_rect_changed.connect(_sync_action_row)

	_fight_frame = PanelContainer.new()
	_fight_frame.custom_minimum_size.x = 464
	body.add_child(_fight_frame)
	var fight := VBoxContainer.new()
	fight.add_theme_constant_override("separation", 8)
	_fight_frame.add_child(fight)
	var header := HBoxContainer.new()
	fight.add_child(header)
	var title := _label("Бой", 20, true)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	_status = _label("", 12)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status)
	_piles = PileView.new()
	_piles.float_browser = true
	_piles.columns = 2
	_piles.preview_requested.connect(func(card: Dictionary): _set_preview(Art.face(card), "discard"))
	_piles.preview_closed.connect(_clear_preview.bind("discard"))
	fight.add_child(_piles)
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 20)
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	fight.add_child(middle)
	_build_battle(middle)
	_build_preview(middle)

	_opponents = VBoxContainer.new()
	_opponents.add_theme_constant_override("separation", 8)
	add_child(_opponents)
	_opponents.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	_opponents.offset_left = 32
	_opponents.offset_right = 167
	_opponents.offset_top = -124
	_opponents.offset_bottom = -16
	_opponent_text = _label("Рука соперника", 12)
	_ink_on_backdrop(_opponent_text)
	_opponents.add_child(_opponent_text)
	_opponent_cards = HBoxContainer.new()
	_opponent_cards.add_theme_constant_override("separation", -12)
	_opponents.add_child(_opponent_cards)

	_hand = HandView.new()
	_hand.external_preview = true
	_hand.external_pass = true
	_hand.drag_to_play = true
	_hand.playable = _can_play_from_hand
	_hand.play_drop = _play_from_hand
	_hand.play_drag_changed.connect(func(active: bool):
		_update_drop_zone()
		_board.drop_highlight = active)
	_hand.submitted.connect(func(answer: Dictionary):
		var effect: Dictionary = _state.get("effect", {})
		if effect.get("hand_discard", false) and answer.request == effect.id:
			action_requested.emit("effect", {"request": effect.id, "answer": answer.cards.front()})
		else:
			submitted.emit(answer))
	_hand.hand_requested.connect(func(seat: int): hand_requested.emit(seat))
	_hand.handoff_confirmed.connect(func(): handoff_confirmed.emit())
	_hand.card_preview_requested.connect(func(texture: Texture2D): _set_preview(texture, "hand"))
	_hand.card_preview_closed.connect(_clear_preview.bind("hand"))
	add_child(_hand)
	_ink_on_backdrop(_hand._prompt)
	_hand.dock_to_bottom(176.0)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions.mouse_filter = MOUSE_FILTER_IGNORE
	_actions.z_index = 60
	_actions.hide()
	add_child(_actions)
	_actions.minimum_size_changed.connect(_sync_action_row)
	_build_action_aid()
	_top = TopBar.make(self, "Unmatched", _top_button, null, Color("fff0e5"), Style.TITLE)
	_top.info.add_theme_font_override("font", Style.TITLE)
	_combat_show = CombatShow.new()
	add_child(_combat_show)
	_combat_show.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_combat_show.cards_revealed.connect(func(): _update_combat(_state.get("combat", {})))
	_hero_choice = HeroChoice.new()
	add_child(_hero_choice)
	_hero_choice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_hero_choice.chosen.connect(func(hero: String): action_requested.emit("draft_hero", {"hero": hero}))


func _build_action_aid() -> void:
	var aid := TextureRect.new()
	aid.texture = Art.reference_face("actions")
	aid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aid.mouse_filter = MOUSE_FILTER_STOP
	aid.tooltip_text = "В свой ход"
	add_child(aid)
	aid.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	aid.offset_left = -142
	aid.offset_right = -32
	aid.offset_top = -180
	aid.offset_bottom = -24
	Art.round_corners(aid)
	aid.mouse_entered.connect(func(): _set_preview(aid.texture, "actions"))
	aid.mouse_exited.connect(_clear_preview.bind("actions"))


func wire_party_menu() -> void:
	var settings := _top_button("Настройки", 14)
	settings.pressed.connect(_show_settings)
	_top.actions.add_child(settings)
	var rules_button := _top_button("Правила", 14)
	_top.actions.add_child(rules_button)
	rules_button.pressed.connect(_show_rules)
	var journal := _top_button("Журнал", 14)
	_top.actions.add_child(journal)
	journal.pressed.connect(_show_journal)
	var back := _top_button("Выйти", 14)
	_top.actions.add_child(back)
	LeaveGuard.hold(back, func(): exit_requested.emit())


func _show_settings() -> void:
	var settings := preload("res://games/king_of_12/ui/settings_screen.gd").new()
	settings.theme = theme
	settings.ink = _colors.ink
	settings.make_panel = func() -> PanelContainer:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Style.frame(_colors.panel, _colors.rim, 16))
		return panel
	settings.make_title = func(title: String) -> Label: return _label(title, 22, true)
	settings.make_primary = func(title: String) -> Button: return _button(title)
	settings.z_index = 100
	add_child(settings)


func _show_rules() -> PopupPanel:
	var rules := RichTextLabel.new()
	rules.add_theme_color_override("default_color", _colors.ink)
	rules.add_theme_font_size_override("normal_font_size", 16)
	rules.add_theme_constant_override("line_separation", 4)
	rules.text = (
		"Выполните два действия: манёвр, приём или атаку.\n\n"
		+ "Манёвр: возьмите карту и при желании переместите бойцов. Одну карту можно сбросить ради усиления движения.\n"
		+ "Приём: выберите подходящего бойца и сыграйте карту со значком молнии.\n"
		+ "Атака: выберите бойца и подсвеченного противника. Защитник выбирает карту или принимает бой без защиты.\n\n"
		+ "В конце хода сбросьте лишние карты до семи. За каждую попытку добора из пустой колоды все ваши бойцы получают по 2 урона.\n"
		+ "Чтобы победить, повергните всех героев команды соперника.")
	var height := 410
	if _arena == "heorot":
		rules.text += "\n\nДвери Хеорота начинают открытыми. Во время манёвра выберите бойца и нажмите на соседнюю дверь. Закрытие бесплатно, открытие стоит один шаг. Закрытая дверь перекрывает дорожки, разрывает смежность и разделяет зону, если через неё проходил кратчайший путь."
		height = 476
	elif Maps.Battlefields.POOLS.has(_arena):
		rules.text += "\n\nПредметы одноразовые. Чтобы использовать предмет-приём, поставьте на его клетку своего бойца и нажмите на жетон или его название. Это расходует действие. Боевой предмет можно присоединить при выборе карты атаки или защиты. Его прибавка применяется во время боя и отменяется вместе с эффектами карты. Наведите курсор на жетон, чтобы прочитать его."
		height = 476
	elif _arena == "pandemonium":
		rules.text += "\n\nОпасные пути Пандемониума: первое пересечение красной дорожки каждым бойцом в течение хода наносит ему 1 урон. Это действует также при перемещениях от эффектов. Помещение на клетку без перемещения не пересекает дорожки."
		height = 476
	return _open_info("Правила Unmatched", rules, Vector2i(620, height))


func _show_journal() -> PopupPanel:
	var entries := ItemList.new()
	entries.add_theme_stylebox_override("panel", Style.frame(_colors.well, _colors.rim, 8, 4))
	entries.add_theme_stylebox_override("selected", Style.frame(_colors.track, _colors.rim, 4, 3))
	entries.add_theme_stylebox_override("selected_focus", Style.frame(_colors.track, _colors.rim, 4, 3))
	entries.add_theme_color_override("font_color", _colors.ink)
	entries.add_theme_color_override("font_selected_color", _colors.ink)
	entries.add_theme_constant_override("v_separation", 8)
	for line: String in _state.get("journal", []):
		entries.add_item(line)
	if entries.item_count == 0:
		entries.add_item("Событий ещё нет.")
	var popup := _open_info("Журнал партии", entries, Vector2i(560, 388))
	if entries.item_count > 1:
		entries.select(entries.item_count - 1)
		entries.ensure_current_is_visible()
	return popup


func _open_info(title: String, content: Control, dimensions: Vector2i) -> PopupPanel:
	var popup := PopupPanel.new()
	popup.title = title
	popup.theme = theme
	popup.add_theme_stylebox_override("panel", Style.frame(_colors.panel, _colors.rim, 16))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	popup.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	var heading := _label(title, 22, true)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(heading)
	var close := _button("Закрыть")
	close.pressed.connect(popup.hide)
	header.add_child(close)
	content.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(content)
	popup.popup_hide.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(dimensions)
	return popup


func _present_actions(view: Dictionary) -> void:
	_clear_preview("option")
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	var figures: Array = view.fighters.duplicate(true)
	if _last_place != view.active:
		_last_place = view.active
		_fighter = 0
	var own: Array = figures.filter(func(figure: Dictionary) -> bool: return figure.seat == view.active)
	if not own.is_empty() and not own.any(func(figure: Dictionary) -> bool: return figure.fighter == _fighter):
		_fighter = own[0].fighter
	var active_targets: Dictionary = view.targets.duplicate()
	var effect: Dictionary = view.effect
	_selection_label.text = ""
	var combatant: Vector2i = view.combat.get("defender", Vector2i(-1, -1))
	var defending: bool = not view.hand.choice.is_empty() and view.hand.choice.get("pass_label") == "Без защиты"
	if defending and combatant.x in view.hand.get("owned", []):
		_status.text = "Атакуют: %s" % view.combat.get("defense_name", "")
		_status.add_theme_color_override("font_color", Color("ff858d") if _dark else Color("9d1634"))
	else:
		_status.remove_theme_color_override("font_color")
	if view.get("handoff", false):
		_actions.visible = false
	elif not view.setup.is_empty():
		if view.setup.get("choose_size", false):
			_add_action("Большая Алиса", "size", {"large": true})
			_add_action("Маленькая Алиса", "size", {"large": false})
		elif not active_targets.is_empty():
			_add_board_hint("Расстановка · выберите подсвеченную клетку")
	elif not effect.is_empty():
		_effect_actions(effect)
		for option: Variant in effect.options:
			if effect.get("cells", false) and option is int and view.positions.has(option):
				active_targets[option] = view.positions[option]
			elif option is Vector2i:
				for figure: Dictionary in figures:
					if figure.seat == option.x and figure.fighter == option.y:
						active_targets[figure.cell] = figure.at
	elif view.can_act:
		match view.phase_id:
			Rules.Phase.ACTION:
				for item: Dictionary in view.get("battlefield_items", []):
					if item.get("spent", false) or Maps.Battlefields.ITEMS[item.id][2] > 0:
						continue
					if own.any(func(figure: Dictionary) -> bool: return figure.fighter == _fighter and figure.cell == item.cell):
						_add_action(Maps.Battlefields.ITEMS[item.id][0], "battlefield_item", {"fighter": _fighter, "item": item.id})
				if _maneuver_preview:
					for cell: int in view.moves.get(_fighter, []):
						active_targets[cell] = view.positions[cell]
					_status.text = "Выберите клетку"
					_add_action("Начать манёвр", "maneuver", {})
					var cancel_maneuver := _button("Отменить манёвр")
					cancel_maneuver.pressed.connect(_set_maneuver_preview.bind(false))
					_actions.add_child(cancel_maneuver)
				else:
					var maneuver := _button("Манёвр")
					Style.primary(maneuver, _colors)
					maneuver.pressed.connect(_set_maneuver_preview.bind(true))
					_actions.add_child(maneuver)
				if not _staged_attack.is_empty() and not _maneuver_preview:
					for cell: int in view.attacks.get(_fighter, []):
						active_targets[cell] = view.positions[cell]
					_status.text = "Выберите цель атаки"
					var cancel := _button("Отменить выбор")
					cancel.pressed.connect(func():
						_staged_attack = ""
						present(_state))
					_actions.add_child(cancel)
			Rules.Phase.MANEUVER:
				var cards: Array = view.hand.cards
				if view.hand.hand == view.active and view.get("boost_allowed", false):
					_add_card_options(cards.filter(func(card: Dictionary) -> bool: return card.boost >= 0), "Усилить", "boost", {})
				if not view.get("maneuver_in_transit", false):
					_add_action("Завершить манёвр", "end_maneuver", {})
				for cell: int in view.moves.get(_fighter, []):
					active_targets[cell] = view.positions[cell]
				if view.get("maneuver_in_transit", false):
					_add_board_hint("Продолжите движение на свободную клетку")
				elif not view.get("doors", []).is_empty():
					_add_board_hint("Дверь · закрыть бесплатно, открыть за 1 шаг")
			Rules.Phase.DISCARD:
				if view.hand.hand == view.active:
					_add_card_options(view.hand.cards, "Сбросить", "discard", {})
	for figure: Dictionary in figures:
		figure["under_attack"] = defending and figure.seat == combatant.x and figure.fighter == combatant.y
		var can_select: bool = view.can_act and view.phase_id in [Rules.Phase.ACTION, Rules.Phase.MANEUVER]
		figure["selected"] = (figure.seat == combatant.x and figure.fighter == combatant.y) if defending else (
			can_select and figure.seat == view.active and figure.fighter == _fighter)
		if figure.selected:
			_selection_label.text = "%s · %s" % [figure.name, "герой" if figure.hero else "помощник"]
		figure["attackable"] = view.phase_id == Rules.Phase.ACTION and figure.cell in view.attacks.get(_fighter, [])
	_target_cells = active_targets
	var doors: Array = view.get("doors", []).duplicate(true)
	for door: Dictionary in doors:
		door["enabled"] = not view.get("handoff", false) and _fighter in door.allowed
	var items: Array = view.get("battlefield_items", []).duplicate(true)
	for item: Dictionary in items:
		item["enabled"] = not item.get("spent", false) and Maps.Battlefields.ITEMS[item.id][2] == 0 and view.can_act and view.phase_id == Rules.Phase.ACTION and effect.is_empty() and own.any(
			func(figure: Dictionary) -> bool: return figure.fighter == _fighter and figure.cell == item.cell)
	_board.present(_arena, figures, active_targets, view.combat.is_empty() or view.combat.get("board_focus", false), doors, items)
	_actions.visible = _actions.get_child_count() > 0
	_action_slot.visible = _actions.visible
	_sync_action_row()


func _sync_action_row() -> void:
	if _actions == null or not _actions.visible:
		return
	_action_slot.custom_minimum_size.y = _actions.get_combined_minimum_size().y
	_actions.global_position = _action_slot.global_position
	_actions.size = _action_slot.size


func _board_clicked(cell: int) -> void:
	target_pressed.emit(cell)
	if not _state.has("phase_id") or _state.get("handoff", false):
		return
	if _state.phase_id == Rules.Phase.ACTION and _state.can_act and _state.effect.is_empty() and cell in _state.attacks.get(_fighter, []):
		for fighter: Dictionary in _state.fighters:
			if fighter.cell == cell:
				var key := _staged_attack
				_staged_attack = ""
				_maneuver_preview = false
				action_requested.emit("attack", {"fighter": _fighter, "target": Vector2i(fighter.seat, fighter.fighter), "key": key})
				return
	if _target_cells.has(cell):
		if not _state.setup.is_empty():
			action_requested.emit("place", {"cell": cell})
		elif not _state.effect.is_empty():
			var effect: Dictionary = _state.effect
			if effect.get("cells", false) and cell in effect.options:
				action_requested.emit("effect", {"request": effect.id, "answer": cell})
			else:
				for target: Dictionary in _state.fighters:
					var id := Vector2i(target.seat, target.fighter)
					if target.cell == cell and id in effect.options:
						action_requested.emit("effect", {"request": effect.id, "answer": id})
						return
		elif _state.phase_id == Rules.Phase.MANEUVER:
			action_requested.emit("move", {"fighter": _fighter, "cell": cell})
		elif _state.phase_id == Rules.Phase.ACTION and _maneuver_preview:
			action_requested.emit("maneuver", {"fighter": _fighter, "cell": cell})
		return
	if _state.can_act:
		for fighter: Dictionary in _state.fighters:
			if fighter.cell == cell and fighter.seat == _state.active:
				_fighter = fighter.fighter
				_staged_attack = ""
				_set_maneuver_preview(_state.phase_id == Rules.Phase.ACTION)
				return


func _set_maneuver_preview(active: bool) -> void:
	_maneuver_preview = active
	if active:
		_staged_attack = ""
	present(_state)


func _can_play_from_hand(key: String) -> bool:
	if _state.get("phase_id", -1) != Rules.Phase.ACTION or not _state.get("can_act", false) or _state.get("handoff", false):
		return false
	if _state.hand.hand != _state.active or not _state.effect.is_empty():
		return false
	for card: Dictionary in _state.schemes.get(_fighter, []):
		if card.key == key:
			return true
	if _state.attacks.get(_fighter, []).is_empty():
		return false
	for fighter: Dictionary in _state.fighters:
		if fighter.seat != _state.active or fighter.fighter != _fighter:
			continue
		for card: Dictionary in _state.hand.cards:
			if card.key == key:
				return Catalog.can_play(card, Catalog.Kind.ATTACK, fighter.hero)
	return false


func _play_from_hand(key: String, at: Vector2) -> void:
	_maneuver_preview = false
	for card: Dictionary in _state.schemes.get(_fighter, []):
		if card.key == key:
			action_requested.emit("scheme", {"fighter": _fighter, "key": key})
			return
	_staged_attack = key
	_present_actions(_state)
	var local: Vector2 = _board.get_global_transform_with_canvas().affine_inverse() * at
	var field: Rect2 = _board._field_rect()
	for cell: int in _target_cells:
		if local.distance_to(field.position + (_target_cells[cell] as Vector2) * field.size) <= field.size.x * 0.037:
			_board_clicked(cell)
			return


func _add_action(title: String, kind: String, argument: Dictionary) -> void:
	var button := _button(title)
	if kind in ["maneuver", "end_maneuver"]:
		Style.primary(button, _colors)
	button.pressed.connect(func(): action_requested.emit(kind, argument))
	_actions.add_child(button)


func _add_card_options(cards: Array, title: String, kind: String, data: Dictionary) -> void:
	if cards.is_empty():
		return
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	options.custom_minimum_size.x = 130
	options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for card: Dictionary in cards:
		options.add_item(card.name)
	options.item_selected.connect(func(index: int): _set_preview(Art.face(cards[index]), "option"))
	options.get_popup().id_focused.connect(func(index: int):
		if index >= 0 and index < cards.size():
			_set_preview(Art.face(cards[index]), "option"))
	_actions.add_child(options)
	var button := _button(title)
	button.pressed.connect(func():
		var argument := data.duplicate()
		argument["key"] = cards[options.selected].key
		_clear_preview("option")
		action_requested.emit(kind, argument))
	_actions.add_child(button)


func _add_board_hint(text: String) -> void:
	var hint := _label(text, 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	_ink_on_backdrop(hint)
	_actions.add_child(hint)


func _effect_actions(effect: Dictionary) -> void:
	if effect.get("hand_discard", false):
		if effect.optional:
			_add_action("Пропустить", "effect", {"request": effect.id, "answer": null})
		return
	if effect.get("cells", false) or effect.options.all(func(option: Variant) -> bool: return option is Vector2i):
		_add_board_hint(effect.prompt)
		if effect.get("cells", false) and -1 in effect.options:
			_add_action("Остановиться", "effect", {"request": effect.id, "answer": -1})
		if effect.optional:
			_add_action("Пропустить", "effect", {"request": effect.id, "answer": null})
		return
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	options.custom_minimum_size.x = 144
	options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var cards: Array = effect.get("shown", _state.hand.cards)
	var shows_in_choice := false
	for answer: Variant in effect.options:
		options.add_item(_option_label(answer, cards))
		if answer is String and cards.any(func(card: Dictionary) -> bool: return card.key == answer):
			shows_in_choice = true
	var preview_choice := func(index: int) -> void:
		if index < 0 or index >= effect.options.size():
			return
		for card: Dictionary in cards:
			if effect.options[index] is String and card.key == effect.options[index]:
				_set_preview(Art.face(card), "option")
				return
	options.item_selected.connect(preview_choice)
	options.get_popup().id_focused.connect(preview_choice)
	if effect.has("shown") and not shows_in_choice and not cards.is_empty():
		if cards.size() == 1:
			_set_preview(Art.face(cards[0]), "option")
		else:
			var review := OptionButton.new()
			review.fit_to_longest_item = false
			review.custom_minimum_size.x = 112
			review.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			for card: Dictionary in cards:
				review.add_item(card.name)
			review.item_selected.connect(func(index: int): _set_preview(Art.face(cards[index]), "option"))
			review.get_popup().id_focused.connect(func(index: int):
				if index >= 0 and index < cards.size():
					_set_preview(Art.face(cards[index]), "option"))
			_actions.add_child(review)
			_set_preview(Art.face(cards[0]), "option")
	options.tooltip_text = effect.prompt
	_actions.add_child(options)
	var choose := _button("Выбрать")
	choose.tooltip_text = effect.prompt
	choose.pressed.connect(func():
		_clear_preview("option")
		action_requested.emit("effect", {"request": effect.id, "answer": effect.options[options.selected]}))
	_actions.add_child(choose)
	if effect.optional:
		_add_action("Пропустить", "effect", {"request": effect.id, "answer": null})
	_status.text = "Выбор эффекта"
	_status.tooltip_text = effect.prompt


func _option_label(option: Variant, cards: Array) -> String:
	var labels: Dictionary = _state.get("effect", {}).get("labels", {})
	if labels.has(option):
		return labels[option]
	for card: Dictionary in cards:
		if option is String and card.key == option:
			return card.name
	if option is Vector2i:
		for fighter: Dictionary in _state.fighters:
			if fighter.seat == option.x and fighter.fighter == option.y:
				return fighter.name
	const LABELS := {"confirm": "Готово", "draw": "Добор", "heal": "Лечение",
		"use": "Использовать", "item_first": "Сначала предмет", "item_last": "Сначала карта",
		"reveal": "Открыть ещё", "pay": "Потратить дублон", "strength": "Увеличить значение карты",
		"place": "Размещение", "hand": "В руку", "deck": "Колода", "discard": "Сброс", "action": "Действие", "archer": "Лучник",
		"swap": "Поменять местами", "damage": "Получить урон", "reflect": "Отразить", "sacrifice": "Нанести 2 урона"}
	if option is int and _state.effect.get("modifier_choice", false):
		return "+1 к значению" if option > 0 else "−1 к значению"
	if option is int and _state.effect.get("seat_choice", false):
		var piles: Array = _state.get("piles", [])
		if option >= 0 and option < piles.size():
			return Roster.HEROES[piles[option].hero].name
	if option == -1:
		return "Остановиться"
	return LABELS.get(str(option), str(option))


func _build_battle(parent: HBoxContainer) -> void:
	_stage = VBoxContainer.new()
	_stage.custom_minimum_size.x = 198
	_stage.add_theme_constant_override("separation", 8)
	parent.add_child(_stage)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage.add_child(row)
	for attacking in [true, false]:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 84
		row.add_child(column)
		var fighter := _label("", 14, true)
		fighter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fighter.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(fighter)
		var name := _label("Атака" if attacking else "Защита", 12)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name)
		var frame := PanelContainer.new()
		column.add_child(frame)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(72, 100)
		frame.add_child(slot)
		var face := TextureRect.new()
		face.mouse_filter = MOUSE_FILTER_IGNORE
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Art.round_corners(face)
		slot.add_child(face)
		face.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		var hint := _label("—", 12)
		hint.mouse_filter = MOUSE_FILTER_IGNORE
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(hint)
		hint.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		slot.mouse_entered.connect(func():
			if not bool(face.get_meta("sealed", false)):
				_set_preview(face.texture, "fight"))
		slot.mouse_exited.connect(_clear_preview.bind("fight"))
		if attacking:
			_attack = face
			_attack_hint = hint
			_attack_name = fighter
		else:
			_defense = face
			_defense_hint = hint
			_defense_name = fighter
	_reply = _button("Без защиты", 12)
	_reply.pressed.connect(func(): _hand.submit_empty())
	_stage.add_child(_reply)


func _build_preview(parent: HBoxContainer) -> void:
	_preview_column = VBoxContainer.new()
	_preview_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_column.add_theme_constant_override("separation", 8)
	parent.add_child(_preview_column)
	_preview_column.add_child(_label("Просмотр карты", 14, true))
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(150, 170)
	slot.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_column.add_child(slot)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Art.round_corners(_preview)
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	slot.add_child(_preview)
	_preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_preview_hint = _label("Наведите курсор\nна открытую карту", 12)
	_preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(_preview_hint)
	_preview_hint.set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _update_combat(combat: Dictionary) -> void:
	var attack: Dictionary = combat.get("attack", {})
	var defense: Dictionary = combat.get("defense", {})
	if combat.has("id") and not _combat_show.faces_visible(combat.id):
		if not attack.is_empty():
			attack = {"sealed": true}
		if not defense.is_empty():
			defense = {"sealed": true}
	_apply_slot(_attack, _attack_hint, attack, str(combat.get("attack_hero", "")))
	_apply_slot(_defense, _defense_hint, defense, str(combat.get("defense_hero", "")))
	_attack_name.text = str(combat.get("attack_name", ""))
	_defense_name.text = str(combat.get("defense_name", ""))
	_attack_name.visible = not _attack_name.text.is_empty()
	_defense_name.visible = not _defense_name.text.is_empty()
	var choice: Dictionary = _state.get("hand", {}).get("choice", {})
	_reply.visible = not choice.is_empty() and int(choice.get("min", 1)) == 0 and choice.get("pass_label") == "Без защиты"


func _apply_slot(face: TextureRect, hint: Label, card: Dictionary, hero: String) -> void:
	var sealed := bool(card.get("sealed", false))
	face.set_meta("sealed", sealed)
	face.texture = _back_for(str(card.get("hero", hero))) if sealed else Art.face(card)
	if sealed:
		face.material = _back_outline
	else:
		Art.round_corners(face)
	hint.visible = face.texture == null
	hint.text = "—"


func _back_for(hero: String) -> Texture2D:
	if not _hero_backs.has(hero):
		_hero_backs[hero] = Art.back(hero)
	var texture: Texture2D = _hero_backs[hero]
	return texture if texture != null else _card_back


func _update_opponent(counts: Array, owned: Array) -> void:
	var rival_counts := PackedStringArray()
	var backs := PackedStringArray()
	var heroes: Array = _state.get("piles", [])
	for seat in counts.size():
		if seat not in owned:
			var key := str(heroes[seat].hero) if seat < heroes.size() else ""
			var name := str(Roster.HEROES.get(key, {}).get("name", "Игрок %d" % (seat + 1)))
			rival_counts.append("%s · %d" % [name, int(counts[seat])])
			for i in mini(int(counts[seat]), 5 if counts.size() == 2 else 1):
				backs.append(key)
	_opponents.visible = not rival_counts.is_empty()
	_opponent_text.text = ("Рука соперника\n" if rival_counts.size() == 1 else "Руки соперников\n") + "\n".join(rival_counts)
	var shown := backs.size()
	while _opponent_cards.get_child_count() > shown:
		var card := _opponent_cards.get_child(_opponent_cards.get_child_count() - 1)
		_opponent_cards.remove_child(card)
		card.queue_free()
	while _opponent_cards.get_child_count() < shown:
		var back := TextureRect.new()
		back.custom_minimum_size = Vector2(32, 46)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.mouse_filter = MOUSE_FILTER_IGNORE
		_opponent_cards.add_child(back)
	for i in shown:
		var back := _opponent_cards.get_child(i) as TextureRect
		back.texture = _back_for(backs[i])
		back.material = _back_outline


func _update_drop_zone() -> void:
	if _hand != null and _board != null:
		_hand.drop_zone = (_board.get_global_transform_with_canvas() * _board._field_rect()).intersection(_board.get_global_rect())


func _set_preview(texture: Texture2D, source: String) -> void:
	if texture == null and not source.is_empty():
		return
	_preview_source = source
	_preview.texture = texture
	_preview_hint.visible = texture == null


func _show_scheme(notice: Dictionary) -> void:
	var id := int(notice.get("id", 0))
	if id <= _shown_scheme:
		return
	_shown_scheme = id
	var texture := Art.face(notice.card)
	if texture == null:
		return
	var card := TextureRect.new()
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.texture = texture
	card.mouse_filter = MOUSE_FILTER_IGNORE
	card.z_index = 84
	Art.round_corners(card)
	add_child(card)
	card.size = Vector2(244.0, 339.0)
	card.position = (size - card.size) * 0.5
	await get_tree().create_timer(0.9, false).timeout
	var slot := _preview.get_global_rect()
	var travel := create_tween().set_parallel()
	var duration := 0.01 if Prefs.reduce_motion else 0.33
	travel.tween_property(card, "global_position", slot.position, duration).set_ease(Tween.EASE_IN_OUT)
	travel.tween_property(card, "size", slot.size, duration)
	await travel.finished
	if id == _shown_scheme:
		_set_preview(texture, "scheme")
	card.queue_free()


func _clear_preview(source: String) -> void:
	if _preview_source == source:
		_set_preview(null, "")


func _on_prefs() -> void:
	present(_state)


func _apply_palette(arena: String, dark: bool) -> void:
	_arena = arena
	_dark = dark
	_colors = Style.palette(arena, dark)
	_card_back = Style.card_back(_colors)
	_back_outline = Art.outlined_back(_colors.rim)
	_board.outline_color = _colors.rim
	theme = Style.make_theme(_colors)
	var tint: Color = _colors.bg
	tint.a = 0.42 if dark else 0.52
	_shade.color = tint
	_backdrop.texture = Art.backdrop(arena)
	_arena_title.text = Maps.NAMES[arena]
	_fight_frame.add_theme_stylebox_override("panel", Style.frame(_colors.panel, _colors.rim, 12))
	var top_colors := _colors.duplicate()
	top_colors.track = _colors.band
	top_colors.well = (_colors.band as Color).darkened(0.15)
	top_colors.ink = Color("fff0e5")
	_top.theme = Style.make_theme(top_colors)
	_top._esc_btn.use_themed_face(top_colors.ink)
	_ink_on_backdrop(_top.info)
	_ink_on_backdrop(_top.title)
	Style.primary(_hand._confirm, _colors)


func _ink_on_backdrop(label: Label) -> void:
	label.add_theme_color_override("font_color", Color("fff0e5"))
	label.add_theme_color_override("font_outline_color", Color("24202a"))
	label.add_theme_constant_override("outline_size", 5)


func _label(text: String, size_px: int, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	if heading:
		label.add_theme_font_override("font", Style.TITLE)
	return label


func _button(text: String, size_px: int = 14) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", size_px)
	return button


func _top_button(text: String, size_px: int) -> Button:
	var button := _button(text, size_px)
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	return button
