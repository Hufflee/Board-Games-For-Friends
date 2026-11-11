extends RefCounted
## Только публичные данные шкафа. Сетевые поля не становятся путями ресурсов или настройками игрока.
const MAX_BYTES := 16384
## Фигурки шкафа — общий список (раньше тут были только две старые, и комнаты с новыми фигурками
## отбрасывались целиком: в 0.9.0.2 «глазик» наблюдения перестал включаться).
const Shelf := preload("res://hub/shelf_config.gd")
const FIGURINES: Array = Shelf.FIGURINES
## Друг может быть на другой версии: незнакомые игры и фигурки пропускаем, а не отбрасываем всю комнату.

static func clean(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() > 8:
		return {}
	# Сначала ограничиваем вложенность и объём; сериализация объектов запрещена.
	if not _bounded(value, 0) or var_to_bytes(value).size() > MAX_BYTES:
		return {}
	if not value.get("config") is Dictionary or not value.get("placements") is Array or not value.get("poses") is Dictionary:
		return {}
	var source: Dictionary = value.config
	var config: Dictionary = {}
	for key in ["rows", "cols", "cups"]:
		if not source.get(key) is int:
			return {}
		config[key] = source[key]
	if config.rows < 1 or config.rows > 8 or config.cols < 1 or config.cols > 6:
		return {}
	# свои ячейки (09.11): перегородки по рядам, объединённые ячейки
	var cell_list: Variant = source.get("cells", null)
	if cell_list != null:
		if not Shelf.cells_valid(cell_list, int(config.rows)):
			return {}
		config.cells = (cell_list as Array).map(func(c): return {"row": int(c.row), "span": int(c.span), "x": float(c.x), "w": float(c.w)})
	var cell_total: int = (config.cells as Array).size() if config.has("cells") else config.rows * config.cols
	if config.cups < 0 or config.cups >= cell_total:
		return {}
	for key in ["width", "height"]:
		if not (source.get(key) is float or source.get(key) is int):
			return {}
		var number := float(source[key])
		if not is_finite(number) or number < (0.2 if key == "width" else 0.14) or number > (1.8 if key == "width" else 0.7):
			return {}
		config[key] = number
	if (not config.has("cells") and config.cols * config.width + (config.cols + 1) * 0.03 > 1.801) or config.rows * config.height + (config.rows + 1) * 0.03 > 2.401:
		return {}
	# свои размеры колонок / полок (08.11): списки чисел по числу колонок / рядов
	for pair in [["col_widths", "cols", 0.2, 0.9], ["row_heights", "rows", 0.14, 0.7]]:
		var list: Variant = source.get(pair[0], null)
		if list == null:
			continue
		if not list is Array or (list as Array).size() != int(config[pair[1]]):
			return {}
		var clean_list: Array = []
		for item: Variant in list:
			if not (item is float or item is int) or not is_finite(float(item)) or float(item) < float(pair[2]) - 0.0001 or float(item) > float(pair[3]) + 0.0001:
				return {}
			clean_list.append(float(item))
		config[pair[0]] = clean_list
	if not source.get("neighbor_order", false) is bool:
		return {}
	config.neighbor_order = source.get("neighbor_order", false)
	# Свободное место фигурок в ячейке (доля ширины) — друзья видят их там же.
	var free: Variant = source.get("figure_cells", {})
	if not free is Dictionary or free.size() > 16:
		return {}
	if not free.is_empty():
		config.figure_cells = {}
		for id in free:
			var share: Variant = free[id]
			if not Shelf.is_figure(id):
				continue
			if not (share is float or share is int) or not is_finite(float(share)) or float(share) < 0 or float(share) > 1:
				return {}
			config.figure_cells[id] = float(share)
	var positions: Variant = source.get("figure_positions", {})
	if not positions is Dictionary:
		return {}
	config.figure_positions = {}
	for id in FIGURINES:
		var number: Variant = positions.get(id, source.get("figure_x", 1.0))
		if not (number is float or number is int) or not is_finite(float(number)) or float(number) < 0 or float(number) > 1:
			return {}
		config.figure_positions[id] = float(number)
	for field in ["figure_yaw", "figure_surfaces"]:
		var entries: Variant = source.get(field, {})
		if not entries is Dictionary or entries.size() > 16:
			return {}
		if not source.has(field):
			continue
		config[field] = {}
		for id in entries:
			if not Shelf.is_figure(id):
				continue
			var entry: Variant = entries[id]
			if field == "figure_yaw":
				if not (entry is float or entry is int) or not is_finite(float(entry)) or absf(float(entry)) > PI + 0.0001:
					return {}
				config[field][id] = float(entry)
			else:
				if not entry is Dictionary or entry.size() != 2 or not entry.get("surface", "") in ["tv", "stand_left", "stand_right", "cabinet"]:
					return {}
				var fraction: Variant = entry.get("x")
				if not (fraction is float or fraction is int) or not is_finite(float(fraction)) or float(fraction) < 0 or float(fraction) > 1:
					return {}
				config[field][id] = {"surface": entry.surface, "x": float(fraction)}
	var allowed: Array = FIGURINES.duplicate()
	var custom: Dictionary = {}
	var entries: Variant = value.get("custom", {})
	if not entries is Dictionary or entries.size() > 24:
		return {}
	for id: String in entries:
		if not id.begins_with("custom:") or not preload("res://games/custom/logic/cg_library.gd").uuid_valid(id.trim_prefix("custom:")):
			return {}
		var entry: Variant = entries[id]
		if not entry is Dictionary or not entry.get("title") is String or entry.title.length() > 64 or not entry.get("size") is Array or entry.size.size() != 3:
			return {}
		for extent: Variant in entry.size:
			if not (extent is int or extent is float) or not is_finite(float(extent)) or float(extent) < 0.02 or float(extent) > 0.6:
				return {}
		custom[id] = {"title": entry.title, "size": entry.size.duplicate()}
		allowed.append(id)
	for game in preload("res://hub/games.gd").LIST:
		allowed.append(str(game.id))
	var placements: Array = value.placements
	if placements.size() != cell_total:
		return {}
	var seen: Dictionary = {}
	var rows: Array = []
	for row in placements:
		if not row is Array or row.size() > 48:
			return {}
		var kept: Array = []
		for id in row:
			if not id is String or seen.has(id):
				return {}
			if not allowed.has(id) and not Shelf.is_figure(id):
				continue  # игра из более новой версии — у нас её нет
			seen[id] = true
			kept.append(id)
		rows.append(kept)
	placements = rows
	if seen.is_empty() or seen.size() > 48:
		return {}
	for id: String in custom.keys():
		if not seen.has(id): custom.erase(id)
	var poses: Dictionary = {}
	for id in value.poses:
		if not value.poses[id] is int or value.poses[id] < 0 or value.poses[id] > 3:
			return {}
		if seen.has(id):
			poses[id] = value.poses[id]
	var selected: Variant = value.get("selected", "")
	if not selected is String or not value.get("editor", false) is bool:
		return {}
	if selected != "" and (not allowed.has(selected) or Shelf.is_figure(selected)):
		selected = ""
	var clean_room := {"config": config, "placements": placements.duplicate(true), "poses": poses,
		"selected": selected, "editor": value.get("editor", false), "custom": custom}
	var camera := _clean_camera(value.get("camera", {}))
	if not camera.is_empty():
		clean_room["camera"] = camera
	return clean_room


static func _clean_camera(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("frame") is Array or value.frame.size() != 7:
		return {}
	var zoom: Variant = value.get("zoom")
	if not (zoom is int or zoom is float) or not is_finite(float(zoom)) or float(zoom) < 0.75 or float(zoom) > 1.6:
		return {}
	var frame: Array = value.frame
	for number: Variant in frame:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 12.0:
			return {}
	var rotation := Quaternion(frame[3], frame[4], frame[5], frame[6])
	if absf(rotation.length_squared() - 1.0) > 0.001:
		return {}
	return {"zoom": float(zoom), "frame": frame.duplicate()}

static func _bounded(value: Variant, depth: int, budget: Array = [512]) -> bool:
	if depth == 0:
		budget = [512]
	budget[0] -= 1
	if depth > 5 or budget[0] < 0:
		return false
	if value is Dictionary:
		if value.size() > 64:
			return false
		for key in value:
			if not (key is String or key is StringName) or str(key).length() > 64 or not _bounded(value[key], depth + 1, budget):
				return false
	elif value is Array:
		if value.size() > 64:
			return false
		for item in value:
			if not _bounded(item, depth + 1, budget):
				return false
	elif value is String:
		return value.length() <= 64
	elif not (value is int or value is float or value is bool):
		return false
	return true
