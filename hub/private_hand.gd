class_name PrivateHand
extends Control
## Общая закрытая рука: перекрытие, подъём, настраиваемый просмотр и сортировка.
## Использование: entries + необязательные card_size/preview_delay/drop_action до add_child().
signal chosen(entry: Dictionary)
signal preview_requested(entry: Dictionary)
signal preview_closed
## Игра может ускорить просмотр, сохранив общий стандарт для остальных рук.
var preview_delay := 0.75  # приближение карты при наведении (06.11 — вдвое быстрее)
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
var _laid_out := false


func _ready() -> void:
	custom_minimum_size = Vector2(100, card_size.y * (0.6 if edge_peek else 1.0) + 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sync_cards(entries, order)
	resized.connect(_layout)


## Обновляет состав, сохраняя узлы оставшихся карт и их перетаскивание.
func sync_cards(next: Array, preferred_order: Array) -> void:
	var keys: Array = next.map(func(entry): return str(entry.key))
	var new_cards := []
	for key in _cards.keys():
		if key not in keys:
			var card: K12TableCard = _cards[key]
			if _hover == key:
				_hover = ""
				_preview_token += 1
				preview_closed.emit()
			if card.dragging:
				drag_ended.emit()
			remove_child(card)
			card.queue_free()
			_cards.erase(key)
	entries = next
	order = preferred_order.filter(func(key): return key in keys)
	for entry: Dictionary in entries:
		var key: String = str(entry.key)
		if not order.has(key):
			order.append(key)
		if _cards.has(key):
			var existing: K12TableCard = _cards[key]
			existing.set_meta("hand_entry", entry)
			existing.face_up = bool(entry.get("face_up", true))
			var face := existing._face as TextureRect
			face.texture = entry.get("texture")
			if entry.get("material") != null:
				face.material = entry.material
			continue
		var image := TextureRect.new()
		image.texture = entry.get("texture")
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# своя отрисовка карты (напр. ч/б разряженного предмета Four Souls) — entry.material
		var material_value: ShaderMaterial = entry.get("material", null)
		if material_value == null:
			material_value = ShaderMaterial.new()
			material_value.shader = preload("res://hub/card_corners.gdshader")
		image.material = material_value
		var card := K12TableCard.new(key, bool(entry.get("face_up", true)), image, card_size)
		card.set_meta("hand_entry", entry)
		card.draggable = movable
		card.back_drawer = entry.get("back_drawer", Callable())
		_cards[key] = card
		add_child(card)
		new_cards.append(card)
		if card.back_drawer.is_valid():
			card._back.material = material_value
		card.clicked.connect(
			func(_card):
				drag_ended.emit()
				if _card.face_up:
					chosen.emit(_card.get_meta("hand_entry"))
		)
		card.hovered.connect(func(c, on): _on_hover(c, on, c.get_meta("hand_entry")))
		card.drag_started.connect(
			func(_card):
				_preview_token += 1
				preview_closed.emit()
				drag_began.emit(_card.get_meta("hand_entry"))
		)
		card.dropped.connect(_dropped)
	_layout.call_deferred(new_cards)


func _layout(new_cards: Array = []) -> void:
	if not is_inside_tree():
		return
	if size.x <= 1.0:
		return  # контейнер ещё не разложен — ждём resized
	# первая раскладка — сразу на места: иначе новые карты «прилетают» в руку из угла
	var first := not _laid_out
	_laid_out = true
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
		var highlighted: bool = order[i] == _hover and get_node("/root/Prefs").card_preview_mode != "magnifier"
		if highlighted:
			center.y -= 24 * card_size.y / 140.0
		card.z_index = 50 if highlighted else i
		if first or card in new_cards:
			card.place(center, off * 0.012, 1.0)
		else:
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
		if preload("res://hub/card_magnifier.gd").offer(card):
			return
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
