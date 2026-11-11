class_name ShelfConfig
extends RefCounted
## Личные размеры шкафа, ячейки и положения коробок. Старую раскладку читаем при первом запуске.
const FILE := "user://shelf_editor.cfg"
const DEFAULT_FILE := "res://hub/defaults/shelf_editor.cfg"  # стартовая расстановка владельца (если у игрока своей нет)
const BOARD := 0.03
const GAP := 0.006
const CUP_SPACE := 0.17
const CELL_DEPTH := 0.36
const SCATTER := 1.1
const FIGURINES := ["shelf_girl", "shelf_andy", "shelf_mummy", "shelf_fighter", "shelf_anime"]  # последние три — ShelfFigurine.TRIPO
## Свои фигурки игроков (будущая мастерская) — id «figure:<код>». Все проверки шкафа и наблюдения
## спрашивают is_figure(), а не список выше, поэтому новые фигурки не ломают ни раскладку, ни комнаты друзей.
const WORKSHOP_PREFIX := "figure:"


static func is_figure(id: Variant) -> bool:
	var text := str(id)
	return text in FIGURINES or (text.begins_with(WORKSHOP_PREFIX) and text.length() <= WORKSHOP_PREFIX.length() + 64)
const MIN_WIDTH := 0.20
# При центре шкафа x=0,25 и масштабе 0,95 правая грань остаётся левее тумбы (x=1,17),
# левая — правее скейтборда. Верх вместе с кубом остаётся ниже потолка комнаты.
const MAX_WIDTH := 1.8
const MAX_HEIGHT := 2.4
## Фигурка по умолчанию стоит на телевизоре слева (доля ширины свободного верха ТВ).
## Новым игрокам — сразу, в старом сохранении — один раз (метка fig_tv_31).
const DEFAULT_FIGURE_SURFACES := {"shelf_girl": {"surface": "tv", "x": 0.15}}


# --- Размеры колонок и полок (08.11) ------------------------------------------------------
## Ширина каждой колонки — col_widths, высота каждого ряда (сверху вниз) — row_heights; без них все
## ячейки одинаковые (width / height). width / height при этом — средние, для старого кода и друзей.
const MIN_HEIGHT := 0.14
const MAX_CELL_HEIGHT := 0.7


static func col_width(config: Dictionary, col: int) -> float:
	var list: Variant = config.get("col_widths", [])
	return float(list[col]) if list is Array and col < (list as Array).size() else float(config.get("width", 0.65))


static func row_height(config: Dictionary, row: int) -> float:
	var list: Variant = config.get("row_heights", [])
	return float(list[row]) if list is Array and row < (list as Array).size() else float(config.get("height", 0.36))


# --- Ячейки произвольной ширины (09.11) ---------------------------------------------------
## cells — список ячеек [{row, span, x, w}]: ряд сверху, сколько рядов занимает (объединённые по
## вертикали), левый край от внутренней стенки и ширина (м). Перегородки у каждого ряда свои, полки — во
## всю ширину (меняют высоту ряда). Без cells ячейки — обычная сетка rows × cols. Порядок ячеек — по
## ряду, затем слева направо; placements и cups — по этому порядку.
## Ячейки объединяются (убрать перегородку или кусок полки) и разделяются обратно: merge_cells / split_cell.
const MERGE_EPS := 0.004


static func has_cells(config: Dictionary) -> bool:
	return config.get("cells") is Array and not (config.cells as Array).is_empty()


static func shelf_cells(config: Dictionary) -> Array:
	if has_cells(config):
		return config.cells
	var out: Array = []
	for r in int(config.get("rows", 1)):
		var x := 0.0
		for c in int(config.get("cols", 1)):
			var w := col_width(config, c)
			out.append({"row": r, "span": 1, "x": x, "w": w})
			x += w + BOARD
	return out


static func cell_count(config: Dictionary) -> int:
	return shelf_cells(config).size()


static func inner_width(config: Dictionary) -> float:
	if has_cells(config):
		var best := 0.0
		for cell: Dictionary in config.cells:
			best = maxf(best, float(cell.x) + float(cell.w))
		return best
	var total := (int(config.cols) - 1) * BOARD
	for c in int(config.cols):
		total += col_width(config, c)
	return total


static func cell_width(config: Dictionary, cell: int) -> float:
	if has_cells(config):
		return float(config.cells[cell].w)
	return col_width(config, cell % maxi(1, int(config.get("cols", 1))))


static func cell_height(config: Dictionary, cell: int) -> float:
	if has_cells(config):
		var c: Dictionary = config.cells[cell]
		var total := (int(c.span) - 1) * BOARD
		for r in range(int(c.row), int(c.row) + int(c.span)):
			total += row_height(config, r)
		return total
	return row_height(config, cell / maxi(1, int(config.get("cols", 1))))


## Ячейки правильные: каждый ряд покрыт без дыр и наложений, ширина везде одна, размеры в пределах.
static func cells_valid(list: Variant, rows: int) -> bool:
	if not list is Array or (list as Array).is_empty() or (list as Array).size() > 48:
		return false
	var by_row: Array = []
	for r in rows:
		by_row.append([])
	for item: Variant in list:
		if not item is Dictionary:
			return false
		var c: Dictionary = item
		for key in ["row", "span", "x", "w"]:
			if not (c.get(key) is int or c.get(key) is float) or not is_finite(float(c[key])):
				return false
		if int(c.row) < 0 or int(c.span) < 1 or int(c.row) + int(c.span) > rows or float(c.x) < -0.0001 or float(c.w) < MIN_WIDTH - 0.0001 or float(c.w) > MAX_WIDTH:
			return false
		for r in range(int(c.row), int(c.row) + int(c.span)):
			by_row[r].append([float(c.x), float(c.w)])
	var width := -1.0
	for r in rows:
		var parts: Array = by_row[r]
		if parts.is_empty():
			return false
		parts.sort_custom(func(a, b): return a[0] < b[0])
		var at := 0.0
		for p: Array in parts:
			if absf(float(p[0]) - at) > 0.002:
				return false
			at = float(p[0]) + float(p[1]) + BOARD
		var row_width := at - BOARD
		if width < 0.0:
			width = row_width
		elif absf(row_width - width) > 0.002:
			return false
	return width + 2 * BOARD <= MAX_WIDTH + 0.002


static func _sorted_cells(list: Array) -> Array:
	var out := list.duplicate(true)
	out.sort_custom(func(a, b): return int(a.row) < int(b.row) or (int(a.row) == int(b.row) and float(a.x) < float(b.x)))
	return out


## Ячейки шкафа явным списком (для правок отдельных ячеек); сетка переводится как есть.
static func with_cells(config: Dictionary) -> Dictionary:
	var out := config.duplicate(true)
	out.cells = shelf_cells(config).duplicate(true)
	out.erase("col_widths")
	return out


## Соседи справа от ячейки a в её рядах (их левый край — сразу за перегородкой a).
static func right_neighbors(list: Array, a: int) -> Array:
	var cell: Dictionary = list[a]
	var edge := float(cell.x) + float(cell.w) + BOARD
	var out: Array = []
	for i in list.size():
		var n: Dictionary = list[i]
		if i != a and absf(float(n.x) - edge) < MERGE_EPS and int(n.row) < int(cell.row) + int(cell.span) and int(n.row) + int(n.span) > int(cell.row):
			out.append(i)
	return out


## Перегородка справа от ячейки a сдвигается на d: a шире, соседи справа в её рядах — уже.
## Нельзя, если чья-то ширина станет меньше минимума или сосед выходит за ряды a (сдвинул бы чужой ряд).
static func move_divider(config: Dictionary, a: int, d: float) -> Dictionary:
	var out := with_cells(config)
	var list: Array = out.cells
	var cell: Dictionary = list[a]
	var neighbors := right_neighbors(list, a)
	if neighbors.is_empty():
		return {}
	var low := MIN_WIDTH - float(cell.w)
	var high := INF
	for i: int in neighbors:
		var n: Dictionary = list[i]
		if int(n.row) < int(cell.row) or int(n.row) + int(n.span) > int(cell.row) + int(cell.span):
			return {}  # высокий сосед: его левая стенка общая и с другими рядами
		high = minf(high, float(n.w) - MIN_WIDTH)
	d = clampf(d, low, high)
	cell.w = float(cell.w) + d
	for i: int in neighbors:
		list[i].x = float(list[i].x) + d
		list[i].w = float(list[i].w) - d
	return out


## Внешний край шкафа: крайние ячейки каждого ряда шире / уже на d (side: -1 левый, 1 правый).
static func move_outer(config: Dictionary, side: int, d: float) -> Dictionary:
	var out := with_cells(config)
	var list: Array = out.cells
	var inner := inner_width(out)
	for c: Dictionary in list:
		var edge_cell: bool = (absf(float(c.x)) < MERGE_EPS) if side < 0 else (absf(float(c.x) + float(c.w) - inner) < MERGE_EPS)
		if edge_cell and float(c.w) + d < MIN_WIDTH:
			return {}
	for c: Dictionary in list:
		var left_cell: bool = absf(float(c.x)) < MERGE_EPS
		var right_cell: bool = absf(float(c.x) + float(c.w) - inner) < MERGE_EPS
		if side < 0:
			if left_cell:
				c.w = float(c.w) + d
			else:
				c.x = float(c.x) + d
		elif right_cell:
			c.w = float(c.w) + d
	return out


## Убрать перегородку / кусок полки между ячейками a и b: две ячейки становятся одной.
## Возвращает {config, placements, map} (map: старый номер ячейки → новый) или {} — если так нельзя
## (у ячеек разная ширина или разные ряды — прямоугольник не получится).
static func merge_cells(config: Dictionary, placements: Array, a: int, b: int) -> Dictionary:
	var out := with_cells(config)
	var list: Array = out.cells
	if a < 0 or b < 0 or a >= list.size() or b >= list.size() or a == b:
		return {}
	var ca: Dictionary = list[a]
	var cb: Dictionary = list[b]
	var merged := {}
	var same_rows := int(ca.row) == int(cb.row) and int(ca.span) == int(cb.span)
	var same_cols := absf(float(ca.x) - float(cb.x)) < MERGE_EPS and absf(float(ca.w) - float(cb.w)) < MERGE_EPS
	if same_rows and absf(float(ca.x) + float(ca.w) + BOARD - float(cb.x)) < MERGE_EPS:
		merged = {"row": ca.row, "span": ca.span, "x": ca.x, "w": float(ca.w) + BOARD + float(cb.w)}
	elif same_rows and absf(float(cb.x) + float(cb.w) + BOARD - float(ca.x)) < MERGE_EPS:
		merged = {"row": ca.row, "span": ca.span, "x": cb.x, "w": float(ca.w) + BOARD + float(cb.w)}
	elif same_cols and int(ca.row) + int(ca.span) == int(cb.row):
		merged = {"row": ca.row, "span": int(ca.span) + int(cb.span), "x": ca.x, "w": ca.w}
	elif same_cols and int(cb.row) + int(cb.span) == int(ca.row):
		merged = {"row": cb.row, "span": int(ca.span) + int(cb.span), "x": ca.x, "w": ca.w}
	else:
		return {}
	merged.id = a
	var rest: Array = []
	for i in list.size():
		if i != a and i != b:
			var c: Dictionary = (list[i] as Dictionary).duplicate()
			c.id = i
			rest.append(c)
	rest.append(merged)
	return _reindex(out, rest, placements, {a: a, b: a})


## Разделить ячейку: horizontal — поставить перегородку посередине (две ячейки рядом),
## иначе — вернуть кусок полки (ячейка на несколько рядов → верхний ряд и остальное). Коробки остаются
## в первой части (раскладка потом сама переложит то, что не влезло).
static func split_cell(config: Dictionary, placements: Array, a: int, horizontal: bool, top: int = 1) -> Dictionary:
	var out := with_cells(config)
	var list: Array = out.cells
	if a < 0 or a >= list.size():
		return {}
	var c: Dictionary = list[a]
	var first := {}
	var second := {}
	if horizontal:
		var half := (float(c.w) - BOARD) * 0.5
		if half < MIN_WIDTH:
			return {}
		first = {"row": c.row, "span": c.span, "x": c.x, "w": half}
		second = {"row": c.row, "span": c.span, "x": float(c.x) + half + BOARD, "w": float(c.w) - half - BOARD}
	else:
		top = clampi(top, 1, int(c.span) - 1)
		if int(c.span) < 2:
			return {}
		first = {"row": c.row, "span": top, "x": c.x, "w": c.w}
		second = {"row": int(c.row) + top, "span": int(c.span) - top, "x": c.x, "w": c.w}
	first.id = a
	second.id = -1
	var rest: Array = []
	for i in list.size():
		if i != a:
			var other: Dictionary = (list[i] as Dictionary).duplicate()
			other.id = i
			rest.append(other)
	rest.append(first)
	rest.append(second)
	return _reindex(out, rest, placements, {a: a})


## Новый порядок ячеек (по ряду, слева направо) и перенос коробок / стаканчиков по старым номерам.
static func _reindex(out: Dictionary, rest: Array, placements: Array, joined: Dictionary) -> Dictionary:
	var ordered := _sorted_cells(rest)
	var map := {}
	for n in ordered.size():
		var old := int(ordered[n].id)
		if old >= 0:
			map[old] = n
		ordered[n].erase("id")
	for old: int in joined:
		map[old] = map[int(joined[old])]
	var moved: Array = []
	for n in ordered.size():
		moved.append([])
	for old in placements.size():
		if map.has(old) and placements[old] is Array:
			(moved[int(map[old])] as Array).append_array(placements[old])
	out.cells = ordered
	out.cups = int(map.get(int(out.get("cups", 0)), 0))
	return {"config": out, "placements": moved, "map": map}


## Ширина / высота всего шкафа с досками.
static func full_width(config: Dictionary) -> float:
	if has_cells(config):
		return inner_width(config) + 2 * BOARD
	var total := (int(config.cols) + 1) * BOARD
	for c in int(config.cols):
		total += col_width(config, c)
	return total


static func full_height(config: Dictionary) -> float:
	var total := (int(config.rows) + 1) * BOARD
	for r in int(config.rows):
		total += row_height(config, r)
	return total


static func max_row_height(config: Dictionary) -> float:
	var best := 0.0
	for r in int(config.rows):
		best = maxf(best, row_height(config, r))
	return best


## Шкаф шире на amount в каждой колонке (новая игра не влезла).
static func widened(config: Dictionary, amount: float) -> Dictionary:
	if has_cells(config):
		var grown := move_outer(config, 1, amount)
		return grown if not grown.is_empty() else config.duplicate(true)
	var out := config.duplicate(true)
	out.width = float(config.get("width", 0.65)) + amount
	if out.get("col_widths", []) is Array and not (out.get("col_widths", []) as Array).is_empty():
		out.col_widths = (config.col_widths as Array).map(func(w): return float(w) + amount)
	return out


static func _clean_sizes(list: Variant, count: int, low: float, high: float, total_max: float) -> Array:
	if not list is Array or (list as Array).size() != count:
		return []
	var out: Array = []
	for value: Variant in list:
		if not (value is float or value is int) or not is_finite(float(value)):
			return []
		out.append(clampf(float(value), low, high))
	var total := 0.0
	for value: float in out:
		total += value
	if total > total_max:
		var k := total_max / total
		out = out.map(func(v): return maxf(low, v * k))
	return out


static func pose_basis(mode: int) -> Basis:
	if mode == 0:
		return Basis(Vector3.UP, -PI * 0.5)  # обложка +X к игроку (+Z)
	if mode == 3:
		return Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN)  # лёжа, крышкой к игроку
	if mode == 2:
		return Basis(Vector3.BACK, -PI * 0.5)  # корешок +Z к игроку, надпись слева направо
	return Basis.IDENTITY


static func extent(size_value: Vector3, mode: int) -> Vector3:
	if mode == 0:
		return Vector3(size_value.z, size_value.y, size_value.x)
	if mode == 3:
		return Vector3(size_value.y, size_value.z, size_value.x)
	if mode == 2:
		return Vector3(size_value.y, size_value.x, size_value.z)
	return size_value


## Перудо на полке — миниатюрный набор, в руках используется исходная крупная геометрия.
static func item_basis(id: String, mode: int) -> Basis:
	if is_figure(id):
		return Basis.IDENTITY
	if id == "perudo":
		return (Basis.IDENTITY if mode == 0 else Basis(Vector3.UP, -PI * 0.5)).scaled(Vector3.ONE * 0.65)
	if id == "dangerous_words" and mode == 2:
		return Basis(Vector3.BACK, PI * 0.5)  # крышка сверху, торец читается слева направо
	return pose_basis(mode)


static func item_extent(id: String, size_value: Vector3, mode: int) -> Vector3:
	if is_figure(id):
		return size_value
	if id == "perudo":
		var basis := item_basis(id, mode)
		return basis.x.abs() * size_value.x + basis.y.abs() * size_value.y + basis.z.abs() * size_value.z
	return extent(size_value, mode)


static func item_occupied(id: String, size_value: Vector3, mode: int) -> Vector3:
	return item_extent(id, size_value, mode) if id == "perudo" or is_figure(id) else occupied_extent(size_value, mode)


## Запас для небольшого разворота и сдвига лежащей коробки, включая края стопки.
static func occupied_extent(size_value: Vector3, mode: int) -> Vector3:
	var ext := extent(size_value, mode)
	if mode in [2, 3]:
		return ext + Vector3(ext.z * 0.05 + 0.012, 0.0, ext.x * 0.05 + 0.02) * SCATTER
	return ext


## Детерминированная укладка: соседние лежащие коробки образуют стопки в пределах высоты ячейки.
## Смещения привязаны к ID, поэтому обновление, отмена и загрузка не заставляют коробки дрожать.
static func row_layout(
	ids: Array,
	sizes: Dictionary,
	poses: Dictionary,
	height: float,
	figure_ratio: Variant = -1.0,
	capacity: float = 0.0
) -> Dictionary:
	var figures: Array = []
	var outside := {}
	for id: String in ids:
		if not is_figure(id):
			continue
		if sizes[id] == Vector3.ZERO:
			outside[id] = Transform3D.IDENTITY
			continue
		if capacity <= 0.0:
			continue
		var ratio: float = float(figure_ratio.get(id, -1.0)) if figure_ratio is Dictionary else float(figure_ratio)
		if ratio < 0.0:
			continue
		var figure_size: Vector3 = sizes[id]
		var left := clampf(ratio, 0.0, 1.0) * maxf(0.0, capacity - figure_size.x)
		figures.append({"id": id, "left": left, "right": left + figure_size.x})
	figures.sort_custom(func(a, b): return float(a.left) < float(b.left))
	# При совпадении желаемых мест вторая фигурка занимает ближайшее место справа.
	var figure_end := 0.0
	for figure: Dictionary in figures:
		var shift := maxf(0.0, figure_end - float(figure.left))
		figure.left = float(figure.left) + shift
		figure.right = float(figure.right) + shift
		figure_end = float(figure.right)
	var piles: Array = []
	for id in ids:
		if outside.has(id) or figures.any(func(figure): return figure.id == str(id)):
			continue
		var lying: bool = int(poses.get(id, 1)) in [2, 3] and not is_figure(id)
		var ext := item_occupied(str(id), sizes[id], int(poses.get(id, 1)))
		if (
			not piles.is_empty()
			and (lying or int(poses.get(id, 1)) == 0)
			and not is_figure(id)
			and bool(piles.back().lying)
			and float(piles.back().height) + ext.y <= height + 0.0005
		):
			var pile: Dictionary = piles.back()
			pile.ids.append(id)
			pile.width = maxf(float(pile.width), ext.x)
			pile.depth = maxf(float(pile.depth), ext.z)
			pile.height = float(pile.height) + ext.y
			pile.lying = lying
		else:
			piles.append({"ids": [id], "lying": lying, "width": ext.x, "depth": ext.z, "height": ext.y})
	var boxes: Dictionary = outside
	var x := 0.0
	for pile: Dictionary in piles:
		for figure: Dictionary in figures:
			if x < float(figure.right) and x + float(pile.width) > float(figure.left) + 0.0005:
				x = float(figure.right)
		pile.x = x
		var y := 0.0
		for id in pile.ids:
			var mode: int = int(poses.get(id, 1))
			var ext := item_extent(str(id), sizes[id], mode)
			var rng := RandomNumberGenerator.new()
			rng.seed = str(id).hash()
			var angle := rng.randf_range(-0.045, 0.045) * SCATTER if mode in [2, 3] else 0.0
			var dx := rng.randf_range(-0.004, 0.004) * SCATTER if mode in [2, 3] else 0.0
			var dz := rng.randf_range(-0.008, 0.008) * SCATTER if mode in [2, 3] else 0.0
			var z := float(pile.depth) * 0.5 + dz
			if mode in [0, 1, 2, 3] or str(id) in ["shelf_girl", "perudo"]:
				var own_depth: float = item_occupied(str(id), sizes[id], mode).z
				z = CELL_DEPTH - 0.024 - own_depth * 0.5 + dz
			boxes[id] = Transform3D(
				item_basis(str(id), mode).rotated(Vector3.UP, angle),
				Vector3(x + float(pile.width) * 0.5 + dx, y + ext.y * 0.5, z)
			)
			y += ext.y
		x += float(pile.width)
	for figure: Dictionary in figures:
		var figure_size: Vector3 = sizes[figure.id]
		boxes[figure.id] = Transform3D(
			Basis.IDENTITY,
			Vector3(float(figure.left) + figure_size.x * 0.5, figure_size.y * 0.5, CELL_DEPTH - 0.024 - figure_size.z * 0.5)
		)
		x = maxf(x, float(figure.right))
	return {"boxes": boxes, "piles": piles, "width": x}


## Старые свободные места действуют до первого ручного переноса.
static func figure_ratios(config: Dictionary) -> Variant:
	if not bool(config.get("neighbor_order", false)):
		return config.get("figure_positions", config.get("figure_x", 1.0))
	# Порядок соседей: фигурки, которые игрок поставил в ячейку рукой (figure_cells), стоят свободно
	# в своём месте по ширине; остальные — в общем ряду, как раньше.
	var cells: Dictionary = config.get("figure_cells", {})
	var out := {}
	for id: String in FIGURINES:
		out[id] = float(cells[id]) if cells.has(id) else -1.0
	for id: String in cells:
		if is_figure(id):
			out[id] = float(cells[id])
	return out


## Миграция идёт по видимым группам, сохраняя внутренний порядок горизонтальных стопок.
static func visible_order(ids: Array, sizes: Dictionary, poses: Dictionary, config: Dictionary) -> Array:
	var occupied := sizes_on_shelf(config, sizes)
	var layout := row_layout(ids, occupied, poses, float(config.height), figure_ratios(config), float(config.width) - GAP)
	var groups: Array = layout.piles.duplicate(true)
	for id: String in ids:
		if is_figure(id) and not groups.any(func(group): return group.ids.has(id)):
			var ext: Vector3 = sizes[id]
			groups.append({"ids": [id], "x": (layout.boxes[id] as Transform3D).origin.x - ext.x * 0.5})
	groups.sort_custom(func(a, b): return float(a.x) < float(b.x))
	var ordered: Array = []
	for group: Dictionary in groups:
		ordered.append_array(group.ids)
	return ordered


## Фигурка на отдельной поверхности остаётся в сохранении, но не занимает место в ячейке.
static func sizes_on_shelf(config: Dictionary, sizes: Dictionary, entering: String = "") -> Dictionary:
	var occupied := sizes.duplicate()
	for id: String in config.get("figure_surfaces", {}):
		if id != entering and is_figure(id) and occupied.has(id):
			occupied[id] = Vector3.ZERO
	return occupied


static func normalized(source: Dictionary) -> Dictionary:
	var out := source.duplicate(true)
	out.rows = clampi(int(out.get("rows", 4)), 1, 8)
	out.cols = clampi(int(out.get("cols", 1)), 1, 6)
	out.width = clampf(
		float(out.get("width", 0.65)), MIN_WIDTH, (MAX_WIDTH - (int(out.cols) + 1) * BOARD) / int(out.cols)
	)
	out.height = clampf(
		float(out.get("height", 0.36)),
		0.14,
		minf(0.7, (MAX_HEIGHT - (int(out.rows) + 1) * BOARD) / int(out.rows))
	)
	# Свои ячейки (09.11): неправильный список — обычная сетка.
	if out.has("cells"):
		if cells_valid(out.cells, int(out.rows)):
			out.cells = _sorted_cells(out.cells).map(func(c): return {"row": int(c.row), "span": int(c.span), "x": float(c.x), "w": float(c.w)})
			out.erase("col_widths")
			out.width = inner_width(out) / maxf(1.0, float(int(out.cols)))
		else:
			out.erase("cells")
	out.cups = clampi(int(out.get("cups", 2)), 0, cell_count(out) - 1)
	# Свои размеры колонок / полок: число должно совпадать с колонками / рядами, иначе — одинаковые.
	var widths := [] if out.has("cells") else _clean_sizes(out.get("col_widths", []), int(out.cols), MIN_WIDTH, 0.9, MAX_WIDTH - (int(out.cols) + 1) * BOARD)
	var heights := _clean_sizes(out.get("row_heights", []), int(out.rows), MIN_HEIGHT, MAX_CELL_HEIGHT, MAX_HEIGHT - (int(out.rows) + 1) * BOARD)
	out.erase("col_widths")
	out.erase("row_heights")
	if out.has("cells"):
		pass
	elif not widths.is_empty() and widths.any(func(w): return not is_equal_approx(w, widths[0])):
		out.col_widths = widths
		out.width = widths.reduce(func(a, b): return a + b, 0.0) / widths.size()
	elif not widths.is_empty():
		out.width = widths[0]
	if not heights.is_empty() and heights.any(func(h): return not is_equal_approx(h, heights[0])):
		out.row_heights = heights
		out.height = heights.reduce(func(a, b): return a + b, 0.0) / heights.size()
	elif not heights.is_empty():
		out.height = heights[0]
	if not out.has("figure_positions"):
		var capacity := float(out.width) - GAP
		out.figure_positions = {
			"shelf_girl": float(out.get("figure_x", 1.0)),
			"shelf_andy": clampf((capacity - 0.14 - 0.15) / maxf(0.001, capacity - 0.15), 0.0, 1.0)
		}
	return out


static func limits(config: Dictionary) -> Array:
	var out: Array = []
	for i in cell_count(config):
		out.append(cell_width(config, i) - GAP)
	return out


## Сначала сохраняем привычные места; если не помещается — ищем общую раскладку без потери коробок.
## allow_repack = false — только привычные места + свободное место для новых коробок; без общей перекладки.
static func solve(
	config: Dictionary, placements: Array, sizes: Dictionary, poses: Dictionary, old_cols: int = 1, allow_repack: bool = true
) -> Dictionary:
	var cfg := normalized(config)
	sizes = sizes_on_shelf(cfg, sizes)
	var count: int = cell_count(cfg)
	var explicit := has_cells(cfg)  # свои ячейки: номера ячеек в placements уже совпадают
	var cells: Array = []
	var capacities := limits(cfg)
	var widths: Dictionary = {}
	var preferred: Dictionary = {}
	var ordered: Array = []
	for i in count:
		cells.append([])
	for row_index in placements.size():
		if not placements[row_index] is Array:
			continue
		var target: int = (row_index / maxi(1, old_cols)) * int(cfg.cols) + row_index % maxi(1, old_cols)
		if row_index % maxi(1, old_cols) >= int(cfg.cols):
			target = -1
		if explicit:
			target = row_index if row_index < count else -1
		for id in placements[row_index]:
			if sizes.has(id) and not preferred.has(id):
				preferred[id] = target
				ordered.append(id)
	for id in sizes:
		if not preferred.has(id):
			preferred[id] = -1
			ordered.append(id)
	for id in ordered:
		var ext := item_occupied(str(id), sizes[id], int(poses.get(id, 1)))
		if ext.y > max_row_height(cfg) + 0.0005 or ext.z > CELL_DEPTH + 0.0005:
			return {
				"ok": false,
				"message":
				"Коробка не помещается по высоте. Увеличьте высоту полок или измените положение коробки."
			}
		widths[id] = ext.x
	var remaining: Array = capacities.duplicate()
	var heights: Array = []
	for i in count:
		heights.append(cell_height(cfg, i))
	var fits_height := func(id: Variant, cell: int) -> bool:
		return item_occupied(str(id), sizes[id], int(poses.get(id, 1))).y <= float(heights[cell]) + 0.0005
	var fitted := true
	for id in ordered:
		var destination: int = int(preferred[id])
		if (
			destination < 0
			or destination >= count
			or not fits_height.call(id, destination)
			or (
				float(
					(
						row_layout(
							cells[destination] + [id],
							sizes,
							poses,
							float(heights[destination]),
							figure_ratios(cfg),
							float(capacities[destination])
						)
						. width
					)
				)
				> float(capacities[destination]) + 0.0005
			)
		):
			destination = -1
			for i in count:
				if not fits_height.call(id, i):
					continue
				if (
					float(
						(
							row_layout(
								cells[i] + [id],
								sizes,
								poses,
								float(heights[i]),
								figure_ratios(cfg),
								float(capacities[i])
							)
							. width
						)
					)
					<= float(capacities[i]) + 0.0005
				):
					destination = i
					break
		if destination < 0:
			fitted = false
			break
		cells[destination].append(id)
		remaining[destination] = (
			float(capacities[destination])
			- float(
				(
					row_layout(
						cells[destination],
						sizes,
						poses,
						float(heights[destination]),
						figure_ratios(cfg),
						float(capacities[destination])
					)
					. width
				)
			)
		)
	if not fitted and not allow_repack:
		return {"ok": false, "message": "Для новой коробки нет свободного места."}
	if not fitted:
		cells = []
		for i in count:
			cells.append([])
		remaining = capacities.duplicate()
		var sorted_ids := ordered.duplicate()
		sorted_ids.sort_custom(func(a, b): return float(widths[a]) > float(widths[b]))
		var budget: Array = [6000]
		if not _pack(
			sorted_ids,
			0,
			preferred,
			remaining,
			cells,
			budget,
			sizes,
			poses,
			heights,
			ordered,
			capacities,
			figure_ratios(cfg)
		):
			return {
				"ok": false,
				"message": "Для всех коробок не хватает места. Увеличьте размер или количество полок."
			}
		for row: Array in cells:
			row.sort_custom(func(a, b): return ordered.find(a) < ordered.find(b))
	return {"ok": true, "config": cfg, "placements": cells, "poses": poses.duplicate(true)}


## Ограниченный поиск с пропуском одинаковых по вместимости ячеек, чтобы не блокировать ввод.
static func _pack(
	ids: Array,
	index: int,
	preferred: Dictionary,
	remaining: Array,
	cells: Array,
	budget: Array,
	sizes: Dictionary,
	poses: Dictionary,
	heights: Array,
	ordered: Array,
	capacities: Array,
	figure_ratio: Variant
) -> bool:
	budget[0] = int(budget[0]) - 1
	if int(budget[0]) < 0:
		return false
	if index >= ids.size():
		return true
	var id: Variant = ids[index]
	var choices: Array = range(remaining.size())
	choices.sort_custom(
		func(a, b):
			if a == b:
				return false
			if int(a) == int(preferred[id]):
				return true
			if int(b) == int(preferred[id]):
				return false
			return float(remaining[a]) < float(remaining[b])
	)
	var seen: Dictionary = {}
	for cell in choices:
		var free: float = float(remaining[cell])
		var key: int = int(round(free * 10000))
		if (cells[cell] as Array).is_empty() and seen.has(key):
			continue
		var before: Array = cells[cell]
		if before.is_empty():
			seen[key] = true
		var capacity: float = float(capacities[cell])
		var height: float = float(heights[cell])
		if item_occupied(str(id), sizes[id], int(poses.get(id, 1))).y > height + 0.0005:
			continue
		var candidate: Array = before + [id]
		candidate.sort_custom(func(a, b): return ordered.find(a) < ordered.find(b))
		var used: float = float(row_layout(candidate, sizes, poses, height, figure_ratio, capacity).width)
		if used > capacity + 0.0005:
			continue
		remaining[cell] = capacity - used
		cells[cell] = candidate
		if _pack(
			ids,
			index + 1,
			preferred,
			remaining,
			cells,
			budget,
			sizes,
			poses,
			heights,
			ordered,
			capacities,
			figure_ratio
		):
			return true
		cells[cell] = before
		remaining[cell] = free
	return false


## Поза, сохранённая игроком для коробки (-1 — не сохранена).
static func stored_pose(file: ConfigFile, id: String) -> int:
	var stored: Variant = file.get_value("cabinet", "poses", {})
	return int((stored as Dictionary).get(id, -1)) if stored is Dictionary else -1


static func save_state(
	config: Dictionary, placements: Array, poses: Dictionary, path: String = FILE
) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("cabinet", "version", 1)
	cfg.set_value("cabinet", "geometry", config)
	cfg.set_value("cabinet", "placements", placements)
	cfg.set_value("cabinet", "poses", poses)
	return cfg.save(path)


static func load_state(
	default_config: Dictionary, default_rows: Array, sizes: Dictionary, path: String = FILE
) -> Dictionary:
	var file := ConfigFile.new()
	var config := default_config
	var rows := default_rows
	var poses: Dictionary = {}
	var loaded := file.load(path) == OK
	var fresh := not loaded and path == FILE  # у игрока ещё нет своей расстановки
	if fresh:
		loaded = file.load(DEFAULT_FILE) == OK
	if loaded and int(file.get_value("cabinet", "version", 0)) == 1:
		var geometry: Variant = file.get_value("cabinet", "geometry", {})
		var stored_rows: Variant = file.get_value("cabinet", "placements", [])
		var stored_poses: Variant = file.get_value("cabinet", "poses", {})
		if geometry is Dictionary and stored_rows is Array and stored_poses is Dictionary:
			config = geometry
			rows = stored_rows
			poses = stored_poses
	# Владелец 31.10: фигурку — к телевизору. Один раз переносим и в уже сохранённой расстановке
	# (метка fig_tv_31 в geometry); дальше игрок ставит её куда хочет.
	if path == FILE and not bool(config.get("fig_tv_31", false)):
		config = config.duplicate(true)
		var surfaces: Dictionary = (config.get("figure_surfaces", {}) as Dictionary).duplicate(true)
		for id: String in DEFAULT_FIGURE_SURFACES:
			if sizes.has(id):
				surfaces[id] = (DEFAULT_FIGURE_SURFACES[id] as Dictionary).duplicate()
		config.figure_surfaces = surfaces
		config.fig_tv_31 = true
	if sizes.has("perudo") and not rows.any(func(row): return row.has("perudo")):
		rows = rows.duplicate(true)
		var cup_cell: int = clampi(int(config.get("cups", 2)), 0, cell_count(normalized(config)) - 1)
		while rows.size() <= cup_cell:
			rows.append([])
		rows[cup_cell].append("perudo")
	# Новая фигурка в старом сохранении появляется именно возле стаканчиков.
	if sizes.has("shelf_andy") and not rows.any(func(row): return row.has("shelf_andy")):
		rows = rows.duplicate(true)
		config = config.duplicate(true)
		var target := clampi(int(config.get("cups", 2)), 0, rows.size() - 1)
		for i in rows.size():
			if rows[i].has("perudo"):
				target = i
		rows[target].insert(maxi(0, rows[target].find("perudo")), "shelf_andy")
		# Оставляем прежние игры в своих ячейках; при необходимости добавляем место в ширину.
		config.width = float(config.width) + (sizes["shelf_andy"] as Vector3).x
	for id in sizes:
		poses[id] = clampi(int(poses.get(id, 1)), 0, 1 if id == "perudo" else 3)
	# Новая коробка (своя игра или игра из обновления) не должна сбрасывать личную расстановку.
	# Сначала подбираем для неё позу по существующей высоте, затем свободную ячейку.
	var existing: Array = []
	for row: Array in rows:
		existing.append_array(row)
	var fresh_ids: Array = sizes.keys().filter(func(id): return not existing.has(id))
	for id: String in fresh_ids:
		if stored_pose(file, id) >= 0:
			continue
		for pose in [1, 2, 3, 0]:
			var ext := item_occupied(id, sizes[id], pose)
			if ext.y <= max_row_height(normalized(config)) and ext.z <= CELL_DEPTH:
				poses[id] = pose
				break
	var cols := int(config.get("cols", 1))
	var result := solve(config, rows, sizes, poses, cols, false)
	if not result.ok and not fresh_ids.is_empty():
		# Не влезает — шкаф чуть шире (все ячейки одинаково), прежние коробки остаются на своих местах,
		# новая встаёт в появившееся место. Пока шкаф не упёрся в предел ширины.
		var wider := config.duplicate(true)
		var last_width := full_width(normalized(config))
		for step in range(1, 46):
			wider = widened(config, step * 0.02)
			if full_width(normalized(wider)) <= last_width + 0.0001:
				break  # дальше расширять некуда
			last_width = full_width(normalized(wider))
			result = solve(wider, rows, sizes, poses, cols, false)
			if result.ok:
				break
	if not result.ok:
		result = solve(config, rows, sizes, poses, cols)
	if not result.ok and sizes.keys().any(func(id): return str(id).begins_with("custom:") and not existing.has(id)):
		# Расширяем в ширину, сохраняя предпочтения старых ячеек и все позы.
		var expanded := config.duplicate(true)
		for step in range(1, 25):
			expanded = widened(config, step * 0.04)
			result = solve(expanded, rows, sizes, poses, int(config.get("cols", 1)))
			if result.ok:
				break
	if not result.ok:
		result = solve(default_config, default_rows, sizes, {}, 1)
	return result
