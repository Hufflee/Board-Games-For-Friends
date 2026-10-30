extends RefCounted
## Только публичные данные шкафа. Сетевые поля не становятся путями ресурсов или настройками игрока.
const MAX_BYTES := 16384

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
	if config.cups < 0 or config.cups >= config.rows * config.cols:
		return {}
	for key in ["width", "height"]:
		if not (source.get(key) is float or source.get(key) is int):
			return {}
		var number := float(source[key])
		if not is_finite(number) or number < (0.2 if key == "width" else 0.14) or number > (1.8 if key == "width" else 0.7):
			return {}
		config[key] = number
	if config.cols * config.width + (config.cols + 1) * 0.03 > 1.801 or config.rows * config.height + (config.rows + 1) * 0.03 > 2.401:
		return {}
	if not source.get("neighbor_order", false) is bool:
		return {}
	config.neighbor_order = source.get("neighbor_order", false)
	var positions: Variant = source.get("figure_positions", {})
	if not positions is Dictionary:
		return {}
	config.figure_positions = {}
	for id in ["shelf_girl", "shelf_andy"]:
		var number: Variant = positions.get(id, source.get("figure_x", 1.0))
		if not (number is float or number is int) or not is_finite(float(number)) or float(number) < 0 or float(number) > 1:
			return {}
		config.figure_positions[id] = float(number)
	for field in ["figure_yaw", "figure_surfaces"]:
		var entries: Variant = source.get(field, {})
		if not entries is Dictionary or entries.size() > 2:
			return {}
		if not source.has(field):
			continue
		config[field] = {}
		for id in entries:
			if not id in ["shelf_girl", "shelf_andy"]:
				return {}
			var entry: Variant = entries[id]
			if field == "figure_yaw":
				if not (entry is float or entry is int) or not is_finite(float(entry)) or absf(float(entry)) > PI + 0.0001:
					return {}
				config[field][id] = float(entry)
			else:
				if not entry is Dictionary or entry.size() != 2 or not entry.get("surface", "") in ["tv", "cabinet"]:
					return {}
				var fraction: Variant = entry.get("x")
				if not (fraction is float or fraction is int) or not is_finite(float(fraction)) or float(fraction) < 0 or float(fraction) > 1:
					return {}
				config[field][id] = {"surface": entry.surface, "x": float(fraction)}
	var allowed: Array = ["shelf_girl", "shelf_andy"]
	for game in preload("res://hub/games.gd").LIST:
		allowed.append(str(game.id))
	var placements: Array = value.placements
	if placements.size() != config.rows * config.cols:
		return {}
	var seen: Dictionary = {}
	for row in placements:
		if not row is Array or row.size() > 48:
			return {}
		for id in row:
			if not id is String or not allowed.has(id) or seen.has(id):
				return {}
			seen[id] = true
	if seen.is_empty() or seen.size() > 48:
		return {}
	var poses: Dictionary = {}
	for id in value.poses:
		if not allowed.has(id) or not value.poses[id] is int or value.poses[id] < 0 or value.poses[id] > 3:
			return {}
		if seen.has(id):
			poses[id] = value.poses[id]
	var selected: Variant = value.get("selected", "")
	if not selected is String or (selected != "" and (not allowed.has(selected) or selected in ["shelf_girl", "shelf_andy"])) or not value.get("editor", false) is bool:
		return {}
	return {"config": config, "placements": placements.duplicate(true), "poses": poses, "selected": selected, "editor": value.get("editor", false)}

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
