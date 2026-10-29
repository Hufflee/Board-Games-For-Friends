extends Control
## Все 2^N областей: геометрия отпускания совпадает с размещением открытых карт.
const Style := preload("res://games/things_in_rings/ui/tr_style.gd")
var table: Control
var rings: Array = []
var centers: Array[Vector2] = []
var label_rects: Array[Rect2] = []
var radius := 160.0
var _layout_pending := false

func _ready() -> void:
	custom_minimum_size = Vector2(400, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_schedule_layout)
	gui_input.connect(_input_at)
	_schedule_layout()

func _geometry() -> void:
	var inner_height := maxf(80.0, size.y - 56.0)
	radius = minf(size.x / 3.2, inner_height / 2.9)
	centers.clear()
	var middle := Vector2(size.x * 0.52, 28.0 + inner_height * 0.43)
	if rings.size() == 1:
		centers.append(middle)
	else:
		centers.append(middle + Vector2(-radius * 0.48, -radius * 0.23))
		centers.append(middle + Vector2(radius * 0.48, -radius * 0.23))
		if rings.size() == 3:
			centers.append(middle + Vector2(0, radius * 0.57))
	label_rects.clear()
	for i: int in centers.size():
		var width := Style.HEAD.get_string_size(Style.category_name(str(rings[i])), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var at := centers[i] + Vector2(-width * 0.5, -radius - 24)
		if i == 2:
			at.y = centers[i].y + radius + 8
		label_rects.append(Rect2(at, Vector2(width, 20)))

func mask_at(at: Vector2) -> int:
	_geometry()
	return _mask(at)

func _mask(at: Vector2) -> int:
	var mask := 0
	for i: int in centers.size():
		if at.distance_to(centers[i]) <= radius:
			mask |= 1 << i
	return mask

func _schedule_layout() -> void:
	queue_redraw()
	if not _layout_pending:
		_layout_pending = true
		_layout_cards.call_deferred()

## Для каждой области ищем непересекающиеся прямоугольники с девятью точками внутри.
## Размер уменьшается до вмещения всех карт; архив слева сохраняет крупный доступ.
func slots_for(mask: int, amount: int) -> Array[Rect2]:
	_geometry()
	var result: Array[Rect2] = []
	if amount <= 0:
		return result
	var width := minf(82.0, radius * 0.56)
	for attempt: int in 35:
		result.clear()
		var dimensions := Vector2(width, width * 1.527)
		var step := dimensions + Vector2(4, 4)
		var y := 16.0
		while y + dimensions.y < size.y - 8:
			var x := 8.0
			while x + dimensions.x < size.x - 8:
				var rect := Rect2(Vector2(x, y), dimensions)
				if _inside_region(rect, mask):
					result.append(rect)
					if result.size() == amount:
						return result
				x += step.x
			y += step.y
		width *= 0.86
	return result

func _inside_region(rect: Rect2, mask: int) -> bool:
	for label_rect: Rect2 in label_rects:
		if rect.intersects(label_rect.grow(4)):
			return false
	for dx: float in [0.0, 0.5, 1.0]:
		for dy: float in [0.0, 0.5, 1.0]:
			if _mask(rect.position + rect.size * Vector2(dx, dy)) != mask:
				return false
	return true

func _layout_cards() -> void:
	_layout_pending = false
	if not is_inside_tree():
		return
	Style.clear(self)
	for mask: int in 1 << rings.size():
		var entries: Array = []
		for entry: Dictionary in table.view.get("board", []):
			if int(entry.mask) == mask:
				entries.append(entry)
		var pending: Dictionary = table.view.get("pending", {})
		if not pending.is_empty() and int(pending.get("proposed", -1)) == mask:
			entries.append({"card": pending.card, "pending": true})
		var slots := slots_for(mask, entries.size())
		for i: int in mini(entries.size(), slots.size()):
			var card: Control = table._card(int(entries[i].card), slots[i].size, false)
			card.name = "PendingCard" if entries[i].get("pending", false) else "BoardCard%d" % entries[i].card
			card.position = slots[i].position
			add_child(card)
			if entries[i].get("pending", false):
				var badge := Style.label("?", 16, Style.ink())
				badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(badge)
				var pulse := card.create_tween().set_loops()
				pulse.tween_property(card, "modulate:a", 0.55, 0.7)
				pulse.tween_property(card, "modulate:a", 1.0, 0.7)

func _draw() -> void:
	_geometry()
	for i: int in centers.size():
		var category := ["Attribute", "Word", "Context"].find(str(rings[i]))
		var color: Color = Style.RINGS[maxi(0, category)]
		draw_circle(centers[i], radius, Color(color, 0.14))
		draw_arc(centers[i], radius, 0, TAU, 128, color, 5, true)
		draw_string(Style.HEAD, label_rects[i].position + Vector2(0, 16), Style.category_name(str(rings[i])), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.ink())
	draw_string(Style.HEAD, Vector2(16, 16), "Вне колец", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.muted())

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("tr_card") and data.get("revision") == table.view.revision and data.get("seat") == table.view.you and table.can_place()

func _drop_data(at: Vector2, data: Variant) -> void:
	table.drop_card(int(data.tr_card), mask_at(at))

func _input_at(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		table.region_clicked(mask_at(event.position))
