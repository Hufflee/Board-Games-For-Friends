extends RefCounted
## Только публичные данные шкафа (режим наблюдения за комнатой друга). Сетевые поля не становятся путями
## ресурсов или настройками игрока.
##
## СОВМЕСТИМОСТЬ ВЕРСИЙ (14.11, после многих «наблюдение сломалось после обновления»): снимок проверяют
## отправитель, хост-ретранслятор и каждый зритель — каждый своей версией игры. Поэтому:
##   • незнакомые поля (верхнего уровня и в config) молча пропускаются;
##   • битая или незнакомая запись необязательного поля (поза, место фигурки, своя игра, поверхность…)
##     пропускается по одной, а не отбрасывает всю комнату;
##   • комната отбрасывается целиком только если сломан каркас: ряды/столбцы/ячейки/размеры/раскладка
##     или снимок небезопасен (объекты, глубина, объём).
## Новое поле в снимке — только необязательное, со значением по умолчанию у старых версий.
## Проверка: tests/test_public_room_compat.gd.
const MAX_BYTES := 65536
const MAX_ITEMS := 160  # предметов в шкафу: игры + свои игры + фигурки (раньше 48 — уже впритык)
const MAX_ROWS := 12
const MAX_COLS := 10
## Фигурки шкафа — общий список (раньше тут были только две старые, и комнаты с новыми фигурками
## отбрасывались целиком: в 0.9.0.2 «глазик» наблюдения перестал включаться).
const Shelf := preload("res://hub/shelf_config.gd")
const FIGURINES: Array = Shelf.FIGURINES
const Upper := preload("res://hub/upper_shelves.gd")
const SURFACES := ["tv", "stand_left", "stand_right", "cabinet", "wall_lower", "wall_upper"]
const WALL_SURFACES := ["wall_lower", "wall_upper"]


static func _number(value: Variant, low: float, high: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return NAN
	var number := float(value)
	return number if number >= low - 0.0001 and number <= high + 0.0001 else NAN


static func _hex6(value: Variant) -> bool:
	return value is String and (value as String).length() == 6 and (value as String).is_valid_hex_number()


static func clean(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	# Сначала ограничиваем вложенность и объём; сериализация объектов запрещена.
	if not _bounded(value, 0) or var_to_bytes(value).size() > MAX_BYTES:
		return {}
	if not value.get("config") is Dictionary or not value.get("placements") is Array or not value.get("poses") is Dictionary:
		return {}
	var source: Dictionary = value.config
	var config: Dictionary = {}
	# --- каркас шкафа: без него комнату не построить ---
	for key in ["rows", "cols", "cups"]:
		if not source.get(key) is int:
			return {}
		config[key] = source[key]
	if config.rows < 1 or config.rows > MAX_ROWS or config.cols < 1 or config.cols > MAX_COLS:
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
		var number := _number(source.get(key), 0.2 if key == "width" else 0.14, Shelf.MAX_WIDTH if key == "width" else 0.7)
		if is_nan(number):
			return {}
		config[key] = number
	if (not config.has("cells") and config.cols * config.width + (config.cols + 1) * 0.03 > Shelf.MAX_WIDTH + 0.001) \
			or config.rows * config.height + (config.rows + 1) * 0.03 > Shelf.MAX_HEIGHT + 0.001:
		return {}
	# свои размеры колонок / полок (08.11): списки чисел по числу колонок / рядов; битый список — без него
	for pair in [["col_widths", "cols", 0.2, 0.9], ["row_heights", "rows", 0.14, 0.7]]:
		var list: Variant = source.get(pair[0], null)
		if not list is Array or (list as Array).size() != int(config[pair[1]]):
			continue
		var clean_list: Array = []
		for item: Variant in list:
			var number := _number(item, float(pair[2]), float(pair[3]))
			if is_nan(number):
				clean_list = []
				break
			clean_list.append(number)
		if not clean_list.is_empty():
			config[pair[0]] = clean_list
	# --- необязательное: битое пропускаем ---
	config.neighbor_order = source.get("neighbor_order", false) == true
	# цвет шкафа хозяина (hex без #) — друзья видят шкаф его цвета
	if _hex6(source.get("wood", "")):
		config.wood = source.wood
	if _hex6(source.get("shelves", "")):  # цвет полок на левой стене
		config.shelves = source.shelves
	if source.get("cube_hidden", false) == true:  # неоновый куб на шкафу невидим
		config.cube_hidden = true
	# режимы гирлянд зимней комнаты [ёлка, стены], 0..2
	var lights: Variant = source.get("lights", [])
	if lights is Array and (lights as Array).size() == 2 and (lights as Array).all(func(m): return m is int and m >= 0 and m <= 2):
		config.lights = (lights as Array).duplicate()
	# Свободное место фигурок в ячейке (доля ширины) — друзья видят их там же.
	var free: Variant = source.get("figure_cells", {})
	if free is Dictionary and not free.is_empty():
		config.figure_cells = {}
		for id: Variant in free:
			var share := _number(free[id], 0.0, 1.0)
			if Shelf.is_figure(id) and not is_nan(share) and config.figure_cells.size() < 64:
				config.figure_cells[id] = share
	var positions: Variant = source.get("figure_positions", {})
	config.figure_positions = {}
	for id in FIGURINES:
		var number := _number(positions.get(id, source.get("figure_x", 1.0)) if positions is Dictionary else source.get("figure_x", 1.0), 0.0, 1.0)
		config.figure_positions[id] = 1.0 if is_nan(number) else number
	var box_positions: Variant = source.get("box_positions", {})
	if box_positions is Dictionary and not box_positions.is_empty():
		config.box_positions = {}
		for id: Variant in box_positions:
			var share := _number(box_positions[id], 0.0, 1.0)
			if id is String and (id as String).length() <= 80 and not is_nan(share) and config.box_positions.size() < MAX_ITEMS:
				config.box_positions[id] = share
	var upper_edges := Upper.read(source)
	var upper_surfaces: Dictionary = {}
	if not upper_edges.is_empty():
		Upper.store(config, upper_edges)
		var shallow := Upper.shallow_keys(source, upper_edges)
		if not shallow.is_empty():
			config.upper_shallow_edges = shallow
		for segment: Array in upper_edges:
			if segment[0].y == segment[1].y:
				upper_surfaces[Upper.surface(segment)] = true
		var smoothing := _number(source.get("upper_smoothing", 0.0), 0.0, 1.0)
		if not is_nan(smoothing) and smoothing > 0.0:
			config.upper_smoothing = smoothing
	for field in ["figure_yaw", "figure_surfaces"]:
		var entries: Variant = source.get(field, {})
		if not entries is Dictionary or not source.has(field):
			continue
		config[field] = {}
		for id: Variant in entries:
			var entry: Variant = entries[id]
			if not id is String or (id as String).length() > 80 or (config[field] as Dictionary).size() >= MAX_ITEMS:
				continue
			var wall_item: bool = field == "figure_surfaces" and entry is Dictionary and (entry.get("surface", "") in WALL_SURFACES or upper_surfaces.has(entry.get("surface", "")))
			if not Shelf.is_figure(id) and not wall_item:
				continue
			if field == "figure_yaw":
				var yaw := _number(entry, -PI, PI)
				if not is_nan(yaw):
					config[field][id] = yaw
			elif entry is Dictionary and (entry.get("surface", "") in SURFACES or upper_surfaces.has(entry.get("surface", ""))):
				var fraction := _number(entry.get("x"), 0.0, 1.0)
				if not is_nan(fraction):
					config[field][id] = {"surface": entry.surface, "x": fraction}
					if upper_surfaces.has(entry.surface) and entry.get("fit", false) == true:
						config[field][id].fit = true
			# незнакомая поверхность (из новой версии) — предмет у нас стоит в шкафу, комната не пропадает
	# --- предметы шкафа ---
	var allowed: Array = FIGURINES.duplicate()
	var custom: Dictionary = {}
	var entries: Variant = value.get("custom", {})
	if entries is Dictionary:
		for id: Variant in entries:
			if custom.size() >= 32 or not id is String or not (id as String).begins_with("custom:"):
				continue
			if not preload("res://games/custom/logic/cg_library.gd").uuid_valid((id as String).trim_prefix("custom:")):
				continue
			var entry: Variant = entries[id]
			if not entry is Dictionary or not entry.get("title") is String or not entry.get("size") is Array or entry.size.size() != 3:
				continue
			if not (entry.size as Array).all(func(extent): return not is_nan(_number(extent, 0.02, 0.6))):
				continue
			custom[id] = {"title": (entry.title as String).left(64), "size": (entry.size as Array).duplicate()}
			allowed.append(id)
	for game in preload("res://hub/games.gd").LIST:
		allowed.append(str(game.id))
	var placements: Array = value.placements
	if placements.size() != cell_total:
		return {}
	var seen: Dictionary = {}
	var rows: Array = []
	for row: Variant in placements:
		if not row is Array:
			return {}
		var kept: Array = []
		for id: Variant in row:
			if not id is String or seen.has(id) or seen.size() >= MAX_ITEMS:
				continue  # повтор или лишнее — пропускаем предмет, а не комнату
			if not allowed.has(id) and not Shelf.is_figure(id):
				continue  # игра из более новой версии — у нас её нет
			seen[id] = true
			kept.append(id)
		rows.append(kept)
	placements = rows
	if seen.is_empty():
		return {}
	for id: String in custom.keys():
		if not seen.has(id):
			custom.erase(id)
	var poses: Dictionary = {}
	for id: Variant in value.poses:
		var pose: Variant = value.poses[id]
		if seen.has(id) and pose is int and pose >= 0 and pose <= 3:
			poses[id] = pose
	var selected: Variant = value.get("selected", "")
	if not selected is String or (selected != "" and (not allowed.has(selected) or Shelf.is_figure(selected))):
		selected = ""
	var clean_room := {"config": config, "placements": placements.duplicate(true), "poses": poses,
		"selected": selected, "editor": value.get("editor", false) == true, "custom": custom}
	# комната хозяина (HubRooms): только короткий id; неизвестный зритель заменит своей
	var room: Variant = value.get("room", "")
	if preload("res://hub/rooms/hub_rooms.gd").valid_id(room):
		clean_room["room"] = room
	var camera := _clean_camera(value.get("camera", {}))
	if not camera.is_empty():
		clean_room["camera"] = camera
	return clean_room


static func _clean_camera(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("frame") is Array or value.frame.size() != 7:
		return {}
	var zoom := _number(value.get("zoom"), 0.75, 1.6)
	if is_nan(zoom):
		return {}
	var frame: Array = value.frame
	for number: Variant in frame:
		if is_nan(_number(number, -12.0, 12.0)):
			return {}
	var rotation := Quaternion(frame[3], frame[4], frame[5], frame[6])
	if absf(rotation.length_squared() - 1.0) > 0.001:
		return {}
	return {"zoom": zoom, "frame": frame.duplicate()}


## Безопасная оболочка: только словари/массивы/строки/числа/bool, глубина ≤ 6, не больше 4096 узлов.
## Запас большой: шкаф растёт (игры, свои игры, фигурки, места коробок), а превышение отбрасывает комнату.
static func _bounded(value: Variant, depth: int, budget: Array = [4096]) -> bool:
	if depth == 0:
		budget = [4096]
	budget[0] -= 1
	if depth > 6 or budget[0] < 0:
		return false
	if value is Dictionary:
		if value.size() > 256:
			return false
		for key in value:
			if not (key is String or key is StringName) or str(key).length() > 96 or not _bounded(value[key], depth + 1, budget):
				return false
	elif value is Array:
		if value.size() > 256:
			return false
		for item in value:
			if not _bounded(item, depth + 1, budget):
				return false
	elif value is String:
		return value.length() <= 128
	elif not (value is int or value is float or value is bool):
		return false
	return true
