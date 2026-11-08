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


static func cell_width(config: Dictionary, cell: int) -> float:
	return col_width(config, cell % maxi(1, int(config.get("cols", 1))))


static func cell_height(config: Dictionary, cell: int) -> float:
	return row_height(config, cell / maxi(1, int(config.get("cols", 1))))


## Ширина / высота всего шкафа с досками.
static func full_width(config: Dictionary) -> float:
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
	for id: String in ids:
		if not is_figure(id) or capacity <= 0.0:
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
		if figures.any(func(figure): return figure.id == str(id)):
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
	var boxes: Dictionary = {}
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
	var layout := row_layout(ids, sizes, poses, float(config.height), figure_ratios(config), float(config.width) - GAP)
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
	out.cups = clampi(int(out.get("cups", 2)), 0, int(out.rows) * int(out.cols) - 1)
	# Свои размеры колонок / полок: число должно совпадать с колонками / рядами, иначе — одинаковые.
	var widths := _clean_sizes(out.get("col_widths", []), int(out.cols), MIN_WIDTH, 0.9, MAX_WIDTH - (int(out.cols) + 1) * BOARD)
	var heights := _clean_sizes(out.get("row_heights", []), int(out.rows), MIN_HEIGHT, MAX_CELL_HEIGHT, MAX_HEIGHT - (int(out.rows) + 1) * BOARD)
	out.erase("col_widths")
	out.erase("row_heights")
	if not widths.is_empty() and widths.any(func(w): return not is_equal_approx(w, widths[0])):
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
	for i in int(config.rows) * int(config.cols):
		out.append(cell_width(config, i) - GAP)
	return out


## Сначала сохраняем привычные места; если не помещается — ищем общую раскладку без потери коробок.
## allow_repack = false — только привычные места + свободное место для новых коробок; без общей перекладки.
static func solve(
	config: Dictionary, placements: Array, sizes: Dictionary, poses: Dictionary, old_cols: int = 1, allow_repack: bool = true
) -> Dictionary:
	var cfg := normalized(config)
	var count: int = int(cfg.rows) * int(cfg.cols)
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
		var cup_cell: int = clampi(int(config.get("cups", 2)), 0, int(config.rows) * int(config.cols) - 1)
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
