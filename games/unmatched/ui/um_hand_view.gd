extends VBoxContainer
## Личная рука Unmatched. Стол вызывает dock_to_bottom() и передаёт проекцию хоста в present().

signal submitted(answer: Dictionary)
signal hand_requested(seat: int)
signal handoff_confirmed
signal card_preview_requested(texture: Texture2D)
signal card_preview_closed
signal play_drag_changed(active: bool)

const Roster := preload("res://games/unmatched/logic/um_roster.gd")
const Catalog := preload("res://games/unmatched/logic/um_catalog.gd")
const Art := preload("res://games/unmatched/ui/um_card_art.gd")
const HAND_CARD := Vector2(192, 267)
const HAND_VISIBLE_HEIGHT := 215.0
const KIND_ORDER := [Catalog.Kind.ATTACK, Catalog.Kind.VERSATILE, Catalog.Kind.DEFENSE, Catalog.Kind.SCHEME]
const FIGHTER_ORDER := [Catalog.Fighter.HERO, Catalog.Fighter.ANY, Catalog.Fighter.SIDEKICK]

var drop_zone := Rect2()
var external_preview := false
var external_pass := false
var drag_to_play := false
var playable: Callable
var play_drop: Callable
var _fan: PrivateHand
var _tabs: HBoxContainer
var _prompt: Label
var _confirm: Button
var _preview: PanelContainer
var _picture: TextureRect
var _curtain: Button
var _view := {}
var _choice := {}
var _picked: Array = []
var _orders: Dictionary = {}
var _tab_seats: Array = []
var _tab_heroes := PackedStringArray()
var _locked := false
var _handoff_pending := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_tabs = HBoxContainer.new()
	_tabs.mouse_filter = MOUSE_FILTER_IGNORE
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_tabs)
	var actions := HBoxContainer.new()
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	add_child(actions)
	_prompt = Label.new()
	actions.add_child(_prompt)
	_confirm = Button.new()
	_confirm.pressed.connect(_submit)
	actions.add_child(_confirm)

	_curtain = Button.new()
	_curtain.custom_minimum_size.y = 160
	_curtain.pressed.connect(_finish_handoff)
	add_child(_curtain)
	_fan = PrivateHand.new()
	_fan.card_size = HAND_CARD
	_fan.edge_peek = true
	_fan.preview_delay = 0.375
	_fan.drop_action = _drop
	_fan.chosen.connect(_toggle)
	_fan.order_changed.connect(func(order: Array): _orders[int(_view.get("hand", -1))] = order)
	_fan.preview_requested.connect(_open_preview)
	_fan.preview_closed.connect(_close_preview)
	_fan.drag_began.connect(func(entry: Dictionary): play_drag_changed.emit(_can_drop(str(entry.key))))
	_fan.drag_ended.connect(func(): play_drag_changed.emit(false))
	add_child(_fan)
	_fan.custom_minimum_size.y = HAND_VISIBLE_HEIGHT

	_preview = PanelContainer.new()
	_preview.top_level = true
	_preview.z_index = 80
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(272, 378)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Art.round_corners(_picture)
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(_picture)
	add_child(_preview)
	_close_preview()
	present(_view)


## Вызывается после добавления руки в полноэкранный слой стола.
func dock_to_bottom(side_margin: float = 40.0) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = side_margin
	offset_right = -side_margin
	offset_bottom = 0.0
	if not minimum_size_changed.is_connected(_fit_dock):
		minimum_size_changed.connect(_fit_dock)
	_fit_dock()


func _fit_dock() -> void:
	offset_top = -get_combined_minimum_size().y


## Применяет проекцию хоста. При явном отклонении отправки стол вызывает unlock().
func present(view: Dictionary) -> void:
	if _handoff_pending:
		return
	var choice: Dictionary = view.get("choice", {})
	if view.get("hand") != _view.get("hand") or choice.get("id") != _choice.get("id"):
		_picked.clear()
		_locked = false
		_close_preview()
	_view = view
	_choice = choice
	if not is_node_ready():
		return
	_curtain.hide()
	_fan.show()
	_tabs.show()
	var hand := int(view.get("hand", -1))
	var entries: Array = []
	var ranks := {}
	for card: Dictionary in view.get("cards", []):
		var existing: Control = _fan._cards.get(str(card.key))
		var texture: Texture2D = existing.get_meta("hand_entry").texture if existing != null else Art.face(card)
		if texture != null:
			entries.append({"key": card.key, "texture": texture})
			var kind := KIND_ORDER.find(card.get("kind", Catalog.Kind.SCHEME))
			var fighter := FIGHTER_ORDER.find(card.get("fighter", Catalog.Fighter.ANY))
			var group := kind * FIGHTER_ORDER.size() + fighter
			ranks[card.key] = Vector2i(group, -int(card.get("value", 0)))
	var order: Array = _orders.get(hand, []).filter(func(key): return ranks.has(key))
	for entry: Dictionary in entries:
		if not order.has(entry.key):
			_insert_card(order, entry.key, ranks)
	_fan.sync_cards(entries, order)
	_orders[hand] = _fan.order.duplicate()
	_picked = _picked.filter(func(key): return key in _fan.order and key in _choice.get("allowed", []))
	_update_tabs(hand)
	_refresh_selection()


## Вставляем в промежуток с минимумом карт не на своей стороне, сохраняя ручной порядок.
func _insert_card(order: Array, key: String, ranks: Dictionary) -> void:
	var rank: Vector2i = ranks[key]
	var conflicts := 0
	for existing: String in order:
		if ranks[existing] < rank:
			conflicts += 1
	var best := conflicts
	var position := 0
	for index in order.size():
		var existing: Vector2i = ranks[order[index]]
		conflicts += int(existing > rank) - int(existing < rank)
		if conflicts <= best:
			best = conflicts
			position = index + 1
	order.insert(position, key)


## Перед показом другой локальной руки удалить прежние лица и убрать предпросмотр.
func hide_for_handoff(name_for_handoff: String) -> void:
	present({})
	_handoff_pending = true
	_fan.hide()
	_tabs.hide()
	_prompt.hide()
	_curtain.text = "Передайте управление: %s\nПоказать руку" % name_for_handoff
	_curtain.show()


func _finish_handoff() -> void:
	if _handoff_pending:
		_handoff_pending = false
		handoff_confirmed.emit()


func accept_handoff() -> void:
	_handoff_pending = false


func unlock() -> void:
	_locked = false
	_refresh_selection()


func submit_empty() -> void:
	if int(_choice.get("min", 1)) == 0 and not _locked:
		_picked.clear()
		_submit()


func _update_tabs(hand: int) -> void:
	var owned: Array = _view.get("owned", [])
	var heroes: PackedStringArray = _view.get("heroes", PackedStringArray())
	if owned == _tab_seats and heroes == _tab_heroes:
		for tab: Button in _tabs.get_children():
			tab.set_pressed_no_signal(int(tab.get_meta("hand")) == hand)
		return
	_tab_seats = owned.duplicate()
	_tab_heroes = heroes.duplicate()
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	if owned.size() < 2:
		return
	for seat: int in owned:
		var tab := Button.new()
		var hero := heroes[seat] if seat < heroes.size() else ""
		tab.text = str(Roster.HEROES.get(hero, {}).get("name", "Рука %d" % (seat + 1)))
		if Roster.HEROES.has(hero):
			tab.icon = Art.texture("res://games/unmatched/art/tokens/%s.webp" % hero)
			tab.add_theme_constant_override("icon_max_width", 24)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(seat == hand)
		tab.set_meta("hand", seat)
		tab.pressed.connect(func():
			var active := int(_view.get("hand", -1))
			tab.set_pressed_no_signal(seat == active)
			if seat != active:
				hand_requested.emit(seat))
		_tabs.add_child(tab)


func _toggle(entry: Dictionary) -> void:
	if drag_to_play:
		return
	var key := str(entry.get("key", ""))
	if _locked or key not in _choice.get("allowed", []):
		return
	if key in _picked:
		_picked.erase(key)
	elif int(_choice.get("max", 1)) == 1:
		_picked = [key]
	elif _picked.size() < int(_choice.get("max", 1)):
		_picked.append(key)
	_refresh_selection()


func _drop(entry: Dictionary, at: Vector2) -> bool:
	if not drop_zone.has_point(at):
		return false
	var key := str(entry.get("key", ""))
	if _can_drop(key) and not _choice.is_empty():
		_picked = [key]
		_submit()
	elif _can_drop(key) and play_drop.is_valid():
		play_drop.call(key, at)
	return true


func _can_drop(key: String) -> bool:
	if _locked or _handoff_pending:
		return false
	if not _choice.is_empty():
		return int(_choice.get("max", 0)) == 1 and key in _choice.get("allowed", [])
	return playable.is_valid() and playable.call(key)


func _refresh_selection() -> void:
	_prompt.visible = not _choice.is_empty()
	_prompt.text = str(_choice.get("prompt", ""))
	if int(_choice.get("max", 0)) > 1:
		_prompt.text += "  %d/%d" % [_picked.size(), int(_choice.max)]
	_confirm.visible = not drag_to_play and not _choice.is_empty() and not (external_pass and _picked.is_empty() and int(_choice.get("min", 1)) == 0)
	_confirm.disabled = _locked or _picked.size() < int(_choice.get("min", 1))
	_confirm.text = str(_choice.get("pass_label", "Пропустить")) if _picked.is_empty() and int(_choice.get("min", 1)) == 0 else "Подтвердить"
	for key: String in _fan.order:
		var card: Control = _fan._cards[key]
		var available: bool = _choice.is_empty() or key in _choice.get("allowed", [])
		card.modulate = Color.WHITE if available else Color(0.63, 0.63, 0.63)
		var marker := card.get_node_or_null("Selected") as Label
		if marker == null:
			marker = Label.new()
			marker.name = "Selected"
			marker.text = "✓"
			marker.position = Vector2(29, 2)
			marker.add_theme_font_size_override("font_size", 24)
			marker.add_theme_constant_override("outline_size", 7)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(marker)
		marker.visible = key in _picked


func _submit() -> void:
	if _choice.is_empty() or _locked or _picked.size() < int(_choice.get("min", 1)):
		return
	_locked = true
	_refresh_selection()
	submitted.emit({"request": _choice.id, "hand": _view.hand, "cards": _picked.duplicate()})


func _open_preview(entry: Dictionary) -> void:
	if external_preview:
		card_preview_requested.emit(entry.texture)
		return
	_picture.texture = entry.texture
	var anchor: Control = _fan._cards.get(str(entry.key))
	if anchor == null:
		return
	_preview.show()
	_preview.reset_size()
	var screen := get_viewport_rect().size
	var bound := anchor.get_global_rect()
	var x := bound.end.x + 16.0
	if x + _preview.size.x > screen.x - 16.0:
		x = bound.position.x - _preview.size.x - 16.0
	_preview.global_position = Vector2(clampf(x, 16.0, maxf(16.0, screen.x - _preview.size.x - 16.0)), maxf(16.0, global_position.y - _preview.size.y - 8.0))


func _close_preview() -> void:
	if external_preview:
		card_preview_closed.emit()
	if _preview != null:
		_preview.hide()
		_picture.texture = null
