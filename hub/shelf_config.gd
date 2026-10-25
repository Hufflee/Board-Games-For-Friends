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
const FIGURINES := ["shelf_girl", "shelf_andy"]
const MIN_WIDTH := 0.20
# При центре шкафа x=0,25 и масштабе 0,95 правая грань остаётся левее тумбы (x=1,17),
# левая — правее скейтборда. Верх вместе с кубом остаётся ниже потолка комнаты.
const MAX_WIDTH := 1.8
const MAX_HEIGHT := 2.4


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
	if id in FIGURINES:
		return Basis.IDENTITY
	if id == "perudo":
		return (Basis.IDENTITY if mode == 0 else Basis(Vector3.UP, -PI * 0.5)).scaled(Vector3.ONE * 0.65)
	if id == "dangerous_words" and mode == 2:
		return Basis(Vector3.BACK, PI * 0.5)  # крышка сверху, торец читается слева направо
	return pose_basis(mode)


static func item_extent(id: String, size_value: Vector3, mode: int) -> Vector3:
	if id in FIGURINES:
		return size_value
	if id == "perudo":
		var basis := item_basis(id, mode)
		return basis.x.abs() * size_value.x + basis.y.abs() * size_value.y + basis.z.abs() * size_value.z
	return extent(size_value, mode)


static func item_occupied(id: String, size_value: Vector3, mode: int) -> Vector3:
	return item_extent(id, size_value, mode) if id == "perudo" or id in FIGURINES else occupied_extent(size_value, mode)


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
	for id: String in FIGURINES:
		if not ids.has(id) or capacity <= 0.0:
			continue
		var ratio: float = float(figure_ratio.get(id, 1.0)) if figure_ratio is Dictionary else float(figure_ratio)
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
		var lying: bool = int(poses.get(id, 1)) in [2, 3] and not str(id) in FIGURINES
		var ext := item_occupied(str(id), sizes[id], int(poses.get(id, 1)))
		if (
			not piles.is_empty()
			and (lying or int(poses.get(id, 1)) == 0)
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
		out.append(float(config.width) - GAP)
	return out


## Сначала сохраняем привычные места; если не помещается — ищем общую раскладку без потери коробок.
static func solve(
	config: Dictionary, placements: Array, sizes: Dictionary, poses: Dictionary, old_cols: int = 1
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
		if ext.y > float(cfg.height) + 0.0005 or ext.z > CELL_DEPTH + 0.0005:
			return {
				"ok": false,
				"message":
				"Коробка не помещается по высоте. Увеличьте высоту полок или измените положение коробки."
			}
		widths[id] = ext.x
	var remaining: Array = capacities.duplicate()
	var fitted := true
	for id in ordered:
		var destination: int = int(preferred[id])
		if (
			destination < 0
			or destination >= count
			or (
				float(
					(
						row_layout(
							cells[destination] + [id],
							sizes,
							poses,
							float(cfg.height),
							cfg.get("figure_positions", cfg.get("figure_x", 1.0)),
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
				if (
					float(
						(
							row_layout(
								cells[i] + [id],
								sizes,
								poses,
								float(cfg.height),
								cfg.get("figure_positions", cfg.get("figure_x", 1.0)),
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
						float(cfg.height),
						cfg.get("figure_positions", cfg.get("figure_x", 1.0)),
						float(capacities[destination])
					)
					. width
				)
			)
		)
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
			float(cfg.height),
			ordered,
			capacities,
			cfg.get("figure_positions", cfg.get("figure_x", 1.0))
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
	height: float,
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
			height,
			ordered,
			capacities,
			figure_ratio
		):
			return true
		cells[cell] = before
		remaining[cell] = free
	return false


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
	if not loaded and path == FILE:
		loaded = file.load(DEFAULT_FILE) == OK
	if loaded and int(file.get_value("cabinet", "version", 0)) == 1:
		var geometry: Variant = file.get_value("cabinet", "geometry", {})
		var stored_rows: Variant = file.get_value("cabinet", "placements", [])
		var stored_poses: Variant = file.get_value("cabinet", "poses", {})
		if geometry is Dictionary and stored_rows is Array and stored_poses is Dictionary:
			config = geometry
			rows = stored_rows
			poses = stored_poses
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
	var result := solve(config, rows, sizes, poses, int(config.get("cols", 1)))
	if not result.ok:
		result = solve(default_config, default_rows, sizes, {}, 1)
	return result
