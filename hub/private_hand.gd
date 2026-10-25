class_name PrivateHand
extends Control
## Общая закрытая рука: перекрытие, подъём, настраиваемый просмотр и сортировка.
## Использование: entries + необязательные card_size/preview_delay/drop_action до add_child().
signal chosen(entry: Dictionary)
signal preview_requested(entry: Dictionary)
signal preview_closed
## Игра может ускорить просмотр, сохранив общий стандарт для остальных рук.
var preview_delay := 1.5
signal order_changed(keys: Array)
signal drag_began(entry: Dictionary)
signal drag_ended
var card_size := Vector2(96, 140)
var edge_peek := false
var drop_action: Callable
var entries: Array = []
var order: Array = []
var movable := true
var _cards: Dictionary = {}
var _hover := ""
var _preview_token := 0
const CARD_SIZE := Vector2(96, 140)


func _ready() -> void:
	custom_minimum_size = Vector2(100, card_size.y * (0.6 if edge_peek else 1.0) + 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in entries:
		var key: String = str(entry.key)
		if not order.has(key):
			order.append(key)
		var image := TextureRect.new()
		image.texture = entry.get("texture")
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var material_value := ShaderMaterial.new()
		material_value.shader = preload("res://hub/card_corners.gdshader")
		image.material = material_value
		var card := K12TableCard.new(key, bool(entry.get("face_up", true)), image, card_size)
		card.draggable = movable
		card.back_drawer = entry.get("back_drawer", Callable())
		_cards[key] = card
		add_child(card)
		if card.back_drawer.is_valid():
			card._back.material = material_value
		card.clicked.connect(
			func(_card):
				drag_ended.emit()
				if bool(entry.get("face_up", true)):
					chosen.emit(entry)
		)
		card.hovered.connect(func(c, on): _on_hover(c, on, entry))
		card.drag_started.connect(
			func(_card):
				_preview_token += 1
				preview_closed.emit()
				drag_began.emit(entry)
		)
		card.dropped.connect(_dropped)
	order = order.filter(func(key): return _cards.has(key))
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	if not is_inside_tree():
		return
	var step := minf(
		64.0 * card_size.x / 96.0,
		maxf(12.0 * card_size.x / 96.0, (size.x - card_size.x) / maxi(1, order.size() - 1))
	)
	for i in order.size():
		var card: K12TableCard = _cards[order[i]]
		if card.dragging:
			continue
		var off := float(i) - float(order.size() - 1) * 0.5
		var center := Vector2(size.x * 0.5 + off * step, card_size.y * 0.5 + 10 + minf(off * off, 16) * 0.5)
		var highlighted: bool = order[i] == _hover
		if highlighted:
			center.y -= 24 * card_size.y / 140.0
		card.z_index = 50 if highlighted else i
		card.move_to(center, 0.0 if highlighted else off * 0.012, 1.08 if highlighted else 1.0, 0.12)
	_sync_order.call_deferred()


func _sync_order() -> void:
	if not is_inside_tree():
		return
	for i in order.size():
		move_child(_cards[order[i]], i)
	if _cards.has(_hover):
		move_child(_cards[_hover], get_child_count() - 1)


func _on_hover(card: K12TableCard, on: bool, entry: Dictionary) -> void:
	if card.dragging:
		return
	_preview_token += 1
	if on:
		_hover = card.card
	elif _hover == card.card:
		_hover = ""
	preview_closed.emit()
	_layout()
	if on and bool(entry.get("face_up", true)):
		var token := _preview_token
		await get_tree().create_timer(preview_delay).timeout
		if is_instance_valid(card) and token == _preview_token and _hover == card.card and not card.dragging:
			preview_requested.emit(entry)


func _dropped(card: K12TableCard, at: Vector2) -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in entries:
		if str(candidate.key) == card.card:
			entry = candidate
			break
	var consumed: bool = (
		drop_action.is_valid() and bool(drop_action.call(entry, get_global_transform_with_canvas() * at))
	)
	drag_ended.emit()
	if consumed:
		_hover = ""
		_layout()
		return
	order.erase(card.card)
	var index := 0
	for key in order:
		if (_cards[key] as K12TableCard).center().x < at.x:
			index += 1
	order.insert(index, card.card)
	_hover = ""
	_layout()
	order_changed.emit(order.duplicate())
