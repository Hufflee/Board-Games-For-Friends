extends Control
## Холст1280×720: сетка8px, выбор/перенос/размер, панорама и зум к курсору. TopBar заблокирован.

signal selected(index: int)
signal changed(index: int, rect: Rect2)
const Style := preload("res://games/custom/ui/cg_style.gd")
var items: Array = []
## Фон стола (layout.background) и его картинка — рисуются под элементами, как в игре.
var background: Dictionary = {}
var background_texture: Texture2D
## Оформление игры (meta.look): холст рисуется в цветах игры, как будет на столе.
var look: Dictionary = {}
## Предпросмотр «Игроков: N»: полосы игроков и соперников делятся на места, как на столе (cg_table.gd).
var preview_players := 4
var selection := -1
## Зоны на планшетах (их место на столе не проверяется) — задаёт редактор.
var board_zones: Dictionary = {}
## Индексы элементов с конфликтом раскладки — красная обводка (CGDef.layout_conflicts).
var conflicts: Dictionary = {}
var perspective := "all"
var zoom := 1.0
var pan := Vector2.ZERO
var guides_enabled := true
var _guides: Array[Dictionary] = []
var _drag := ""
var _start := Vector2.ZERO
var _original := Rect2()
var _draft := Rect2()

func _init() -> void:
	custom_minimum_size = Vector2(480, 288)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func _factor() -> float:
	return maxf(0.05, minf((size.x - 24) / 1280.0, (size.y - 24) / 720.0)) * zoom

func _origin() -> Vector2:
	return (size - Vector2(1280, 720) * _factor()) * 0.5 + pan

func design_point(local: Vector2) -> Vector2:
	return (local - _origin()) / _factor()

func screen_point(design: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * (_origin() + design * _factor())

func item_rect(index: int) -> Rect2:
	var item: Dictionary = items[index]
	var raw: Variant = item.get("rect", [])
	if raw is Array and raw.size() == 4:
		var valid := true
		for number: Variant in raw:
			valid = valid and (number is int or number is float)
		if valid:
			return Rect2(float(raw[0]), float(raw[1]), maxf(32, float(raw[2])), maxf(32, float(raw[3])))
	if item.get("owner") == "player":
		return Rect2(288, 400, 704, 192)
	if item.get("id") == "table":
		return Rect2(720, 176, 368, 200)
	return Rect2(176 + (index % 2) * 400, 176 + (index / 2) * 96, 368, 200)

func _visible(item: Dictionary) -> bool:
	var values: Variant = item.get("visible", ["all"])
	if perspective == "all" or not values is Array:
		return true
	return values.has("all") or values.has(perspective)

func _draw() -> void:
	# Подложка вокруг предпросмотра — цвета оболочки редактора («Неоновый портал»), сам предпросмотр — стиля игры.
	var shell: GDScript = load("res://editor/ed_style.gd")
	draw_rect(Rect2(Vector2.ZERO, size), Color(shell.bg(), 0.55))
	draw_rect(Rect2(Vector2.ZERO, size), Color(shell.accent2(), 0.3), false, 1)
	# Только на время рисования стола: оболочка редактора остаётся в теме приложения.
	Style.set_game_look(look)
	draw_set_transform(_origin(), 0, Vector2.ONE * _factor())
	Style.draw_table_background(self, Rect2(0, 0, 1280, 720), background, background_texture)
	for x in range(0, 1281, 8):
		draw_line(Vector2(x, 48), Vector2(x, 720), Color(Style.ink(), 0.035), 1.0)
	for y in range(48, 721, 8):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(Style.ink(), 0.035), 1.0)
	draw_rect(Rect2(0, 0, 1280, 48), Style.panel())
	draw_string(Style.BODY, Vector2(16, 31), "Верхняя полоса · название, чат, пауза и общие действия", HORIZONTAL_ALIGNMENT_LEFT, 1248, 20, Style.ink())
	if _drag.is_empty():
		conflicts = load("res://games/custom/logic/cg_def.gd").layout_conflicts(items, board_zones).bad
	for index in items.size():
		var item: Dictionary = items[index]
		if not _visible(item):
			continue
		var rect := _draft if index == selection and _drag in ["move", "resize"] else item_rect(index)
		var color := Style.panel()
		if item.get("kind") == "button":
			color = Style.accent().darkened(0.2) if not bool(item.get("main", false)) else Style.accent()
		draw_style_box(Style.box(color, 0), rect)
		var title := str(item.get("title", item.get("text", item.get("id", "Элемент"))))
		draw_string(Style.BODY, rect.position + Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 24, Style.ink())
		if item.get("kind") == "zone" and rect.size.y > 96:
			var card := Rect2(rect.position + Vector2(24, 48), Vector2(64, minf(96, rect.size.y - 64)))
			draw_style_box(Style.box(Style.ink().darkened(0.2), 0), card)
		if item.get("kind") in ["opponents", "players"]:
			var seats := preview_players - 1 if item.kind == "opponents" else preview_players
			var columns := mini(4, maxi(1, seats))
			var rows := ceili(seats / float(columns))
			var inner := Rect2(rect.position + Vector2(8, 36), rect.size - Vector2(16, 44))
			var cell := Vector2((inner.size.x - (columns - 1) * 8) / columns, (inner.size.y - (rows - 1) * 8) / maxi(1, rows))
			for seat in seats:
				var place := Rect2(inner.position + Vector2((seat % columns) * (cell.x + 8), floori(seat / float(columns)) * (cell.y + 8)), cell)
				if place.size.x > 8 and place.size.y > 4:
					draw_style_box(Style.box(Style.panel().lerp(Style.ink(), 0.12), 0), place)
					draw_string(Style.BODY, place.position + Vector2(6, minf(place.size.y - 2, 16)), "Игрок %d" % (seat + (2 if item.kind == "opponents" else 1)), HORIZONTAL_ALIGNMENT_LEFT, place.size.x - 12, 12, Color(Style.ink(), 0.7))
		if item.get("kind") == "zone" and board_zones.has(str(item.get("id", ""))):
			draw_string(Style.BODY, rect.position + Vector2(16, 52), "лежит на планшете", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, 16, Color(Style.ink(), 0.6))
		if conflicts.has(index):
			# Толщина постоянная на экране: холст обычно уменьшен.
			draw_rect(rect.grow(1.5 / _factor()), Color("e5484d"), false, 3.0 / _factor())
	if selection >= 0 and selection < items.size() and _visible(items[selection]):
		var rect := _draft if _drag in ["move", "resize"] else item_rect(selection)
		draw_rect(rect.grow(2), Style.accent(), false, 3)
		draw_rect(Rect2(rect.end - Vector2(8, 8), Vector2(16, 16)), Style.accent())
	draw_rect(Rect2(0, 0, 1280, 720), Color(Style.ink(), 0.3), false, 2)
	Style.set_game_look({})
	for guide: Dictionary in _guides:
		var coordinate: float = guide.value
		if guide.axis == 0:
			draw_line(Vector2(coordinate, 48), Vector2(coordinate, 720), Style.accent(), 1.0 / _factor())
		else:
			draw_line(Vector2(0, coordinate), Vector2(1280, coordinate), Style.accent(), 1.0 / _factor())
	draw_set_transform(Vector2.ZERO)

## Края/центры видимых соседей и рабочего поля; расстояние задаётся в пикселях экрана.
func _snap_guides(rect: Rect2, resizing: bool) -> Rect2:
	var targets: Array[Array] = [[0.0, 640.0, 1280.0], [48.0, 384.0, 720.0]]
	for index: int in items.size():
		if index == selection or not _visible(items[index]):
			continue
		var other := item_rect(index)
		for axis: int in 2:
			targets[axis].append_array([other.position[axis], other.get_center()[axis], other.end[axis]])
	for axis: int in 2:
		var anchors: Array = [rect.end[axis]] if resizing else [rect.position[axis], rect.get_center()[axis], rect.end[axis]]
		var distance := minf(16.0, 6.0 / _factor())
		var adjustment := 0.0
		var target_value := 0.0
		var found := false
		for anchor: float in anchors:
			for target: float in targets[axis]:
				var delta := target - anchor
				if absf(delta) < distance:
					distance = absf(delta)
					adjustment = delta
					target_value = target
					found = true
		if found:
			if resizing:
				var extent := rect.size[axis] + adjustment
				if extent < 32 or rect.position[axis] + extent > (1280 if axis == 0 else 720):
					continue
				rect.size[axis] = extent
			else:
				var position_value := rect.position[axis] + adjustment
				if position_value < (0 if axis == 0 else 48) or position_value + rect.size[axis] > (1280 if axis == 0 else 720):
					continue
				rect.position[axis] = position_value
			_guides.append({"axis": axis, "value": target_value})
	return rect

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := design_point(event.position)
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 1.0, 4.0)
			pan += event.position - (_origin() + before * _factor())
			if is_equal_approx(zoom, 1.0):
				pan = Vector2.ZERO
			queue_redraw()
			accept_event()
			return
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_guides.clear()
			_drag = "pan"
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var point := design_point(event.position)
		if point.y < 48:
			return
		var index := -1
		if selection >= 0 and selection < items.size() and _visible(items[selection]) and Rect2(item_rect(selection).end - Vector2(16, 16), Vector2(24, 24)).has_point(point):
			index = selection
		else:
			for candidate in range(items.size() - 1, -1, -1):
				if _visible(items[candidate]) and item_rect(candidate).has_point(point):
					index = candidate
					break
		selection = index
		selected.emit(index)
		if index >= 0:
			_original = item_rect(index)
			_draft = _original
			_draft.size = _draft.size.min(Vector2(1280, 672))
			_start = point
			_drag = "resize" if Rect2(_original.end - Vector2(16, 16), Vector2(24, 24)).has_point(point) else "move"
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	if _drag.is_empty():
		return
	if event is InputEventMouseMotion:
		_guides.clear()
		if _drag == "pan":
			pan += event.relative
		else:
			var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			var offset := design_point(local) - _start
			_draft = _original
			if _drag == "move":
				_draft.position = (_original.position + offset).snapped(Vector2(8, 8))
				_draft.position.x = clampf(_draft.position.x, 0, 1280 - _draft.size.x)
				_draft.position.y = clampf(_draft.position.y, 48, 720 - _draft.size.y)
			else:
				_draft.size = (_original.size + offset).snapped(Vector2(8, 8)).max(Vector2(32, 32))
				_draft.size = _draft.size.min(Vector2(1280, 720) - _draft.position)
			if guides_enabled and not event.alt_pressed:
				_draft = _snap_guides(_draft, _drag == "resize")
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed:
		var kind := _drag
		_drag = ""
		_guides.clear()
		if kind in ["move", "resize"] and selection >= 0 and _draft != _original:
			changed.emit(selection, _draft)
		queue_redraw()
		get_viewport().set_input_as_handled()
