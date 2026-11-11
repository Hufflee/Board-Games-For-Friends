extends RefCounted
## Стикеры хаба (подключать через preload("res://hub/stickers.gd")): каталог наклеек, личное хранилище и проверка сетевых данных.
## Свои коробки игрок обклеивает сам; на доску в комнате стикеры клеят только друзья (в режиме наблюдения),
## автор может снять свои. Доска хранится у её хозяина (user://hub_stickers.json), чужие видят её через
## StickerNet (hub/sticker_net.gd). Арт — tools/hub_stickers.py, hub/art/stickers/.
##
## Форматы (компактные массивы — их же шлём по сети):
##   стикер коробки: [id стикера, u, v, поворот, размер, сторона]  u, v — доли стороны (0..1, от левого верхнего угла);
##                   сторона 0 — обложка, 1 — оборот, 2 — корешок, 3 — второй торец, 4 — верх, 5 — низ (GameBox.FACES)
##   стикер доски:   [uid, id стикера, u, v, поворот, ключ автора, ник автора, размер]
## Размер — множитель SCALE_MIN..SCALE_MAX; записи без него (до 06.11) читаются с размером 1.

const PATH := "user://hub_stickers.json"
const DIR := "res://hub/art/stickers/"
const BOX_MAX := 200  # стикеров на одной коробке: не ограничение игрока, только защита сетевого снимка
const BOXES_MAX := 64
const BOARD_MAX := 40  # на доске; лишние — самые старые — отклеиваются
const POSTERS := 3  # стандартных плакатов в комнате (свои картинки — Ready Set Bet, монеты, Стиллион)
const POSTERS_MAX := 12  # всего плакатов: игрок добавляет новые в редакторе шкафа (11.11)
const BOARDS_MAX := 6  # досок друзей: основная (номер 0) + добавленные в редакторе шкафа
const POSTER_SCALE_MAX := 2.0  # плакат можно сделать вдвое больше обычного
const POSTER_MAX_SIDE := 1280  # своя картинка плаката ужимается до этого размера (качество, но не вес)
const POSTER_MAX_BYTES := 900000
const SCALE_MIN := 1.0 / 3.0  # втрое меньше стартового
const SCALE_MAX := 2.0  # вдвое больше стартового
const BOARD_PER_AUTHOR := 6  # стикеров одного человека на одной доске
## Где висит доска (центр, м) — на задней стене комнаты; по умолчанию справа от шкафа.
const BOARD_DEFAULT := Vector2(1.13, 1.02)
const WALL_X := 2.62  # |x| центра доски
const WALL_Y := Vector2(0.38, 2.48)  # высота центра доски

## Порядок — как в панели. kind: emoji — из обычных эмодзи, own — нарисованы для игры.
const CATALOG := [
	{"id": "fire", "title": "Огонёк", "kind": "emoji"},
	{"id": "mind_blown", "title": "Взрыв мозга", "kind": "emoji"},
	{"id": "joy", "title": "До слёз", "kind": "emoji"},
	{"id": "skull", "title": "Череп", "kind": "emoji"},
	{"id": "thumbs_up", "title": "Класс", "kind": "emoji"},
	{"id": "neon_die", "title": "Шестёрка", "kind": "own"},
	{"id": "crown", "title": "Корона", "kind": "own"},
	{"id": "gg", "title": "GG!", "kind": "own"},
	{"id": "neon_star", "title": "Звезда", "kind": "own"},
	{"id": "pixel_heart", "title": "Сердечко", "kind": "own"},
	{"id": "six_seven", "title": "6 7", "kind": "own"},
]

static var _textures := {}


static func ids() -> Array:
	return CATALOG.map(func(entry): return str(entry.id))


static func valid_id(id: String) -> bool:
	return ids().has(id)


static func title(id: String) -> String:
	for entry: Dictionary in CATALOG:
		if entry.id == id:
			return str(entry.title)
	return id


static func texture(id: String) -> Texture2D:
	if not valid_id(id):
		return null
	if not _textures.has(id):
		_textures[id] = load(DIR + id + ".png")
	return _textures[id]


const CLIP := preload("res://hub/sticker_clip.gdshader")


## Квад стикера с обрезкой по краю поверхности: at — положение относительно коробки/доски,
## half — полуразмеры поверхности в её координатах (ось, по которой не режем, — большое число).
static func make_quad(id: String, side: float, at: Transform3D, half: Vector3) -> MeshInstance3D:
	var tex := texture(id)
	if tex == null:
		return null
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * side
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = CLIP
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("to_surface", Projection(at))
	mat.set_shader_parameter("half_size", half)
	quad.material_override = mat
	quad.transform = at
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad


## Анимация наклеивания: стикер прилетает крупнее и приподнятым, «шлёпается» с отскоком и встаёт на место.
## lift — направление «от поверхности» в координатах родителя квада.
static func slap(quad: MeshInstance3D, lift: Vector3) -> void:
	var rest := quad.transform
	quad.scale = Vector3.ONE * 1.6
	quad.position = rest.origin + lift * 0.05
	quad.rotate_object_local(Vector3.BACK, 0.35)
	var tween := quad.create_tween().set_parallel()
	tween.tween_property(quad, "position", rest.origin, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(quad, "basis", rest.basis, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(quad, "scale", Vector3.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)


# --- Личное хранилище -----------------------------------------------------------------

static func load_local() -> Dictionary:
	var data: Variant = null
	if FileAccess.file_exists(PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var clean := clean_public(data if data is Dictionary else {})
	return clean


static func save_local(data: Dictionary) -> void:
	# Пишем во временный файл и подменяем: обрыв записи не портит доску друзей.
	var temporary := PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(clean_public(data)))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(PATH))


# --- Проверка (своё хранилище и всё, что пришло по сети) --------------------------------

static func _number(value: Variant, low: float, high: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return NAN
	return clampf(float(value), low, high)


static func _text(value: Variant, limit: int) -> String:
	return str(value).left(limit) if value is String else ""


## Место доски на стене в пределах стены.
static func clamp_board_pos(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, -WALL_X, WALL_X), clampf(pos.y, WALL_Y.x, WALL_Y.y))


## Битые записи отбрасываются по одной; объём ограничен. Результат всегда {"boxes": {}, "board": []}
## и, если хозяин перевесил доску, "pos": [x, y].
static func clean_public(value: Variant) -> Dictionary:
	var out := {"boxes": {}, "board": []}
	if not value is Dictionary:
		return out
	var boxes: Variant = value.get("boxes", {})
	if boxes is Dictionary:
		for game: Variant in boxes:
			if out.boxes.size() >= BOXES_MAX or not game is String or game.is_empty() or game.length() > 64:
				continue
			var list: Variant = boxes[game]
			if not list is Array:
				continue
			var stickers: Array = []
			for entry: Variant in list:
				var sticker := clean_box_sticker(entry)
				if not sticker.is_empty() and stickers.size() < BOX_MAX:
					stickers.append(sticker)
			if not stickers.is_empty():
				out.boxes[game] = stickers
	var pos: Variant = value.get("pos", [])
	if pos is Array and pos.size() == 2:
		var x := _number(pos[0], -WALL_X, WALL_X)
		var y := _number(pos[1], WALL_Y.x, WALL_Y.y)
		if not is_nan(x) and not is_nan(y):
			out["pos"] = [x, y]
	# Плакаты комнаты: [[x, y, хэш своей картинки ("" — стандартная), размер 1..2] или [] — на стандартном месте], до POSTERS_MAX.
	# Номера с POSTERS и дальше — добавленные игроком: пустая запись там значит «плаката нет».
	var posters: Variant = value.get("posters", [])
	if posters is Array and not posters.is_empty():
		var list: Array = []
		for i in mini(posters.size(), POSTERS_MAX):
			var entry: Variant = posters[i]
			var clean: Array = []
			if entry is Array and entry.size() in [3, 4]:
				var px := _number(entry[0], -3.0, 3.0)
				var py := _number(entry[1], 0.0, 2.8)
				var hash := _text(entry[2], 64)
				var big := _number(entry[3], 1.0, POSTER_SCALE_MAX) if entry.size() == 4 else 1.0
				if not is_nan(px) and not is_nan(py) and not is_nan(big) and (hash.is_empty() or (hash.length() == 64 and hash.is_valid_hex_number())):
					clean = [px, py, hash, big]
			list.append(clean)
		out["posters"] = list
	# Порядок слоёв плакатов: номера снизу вверх (последний перевешенный — сверху).
	var order: Variant = value.get("poster_order", [])
	if order is Array and not order.is_empty() and order.size() <= POSTERS_MAX:
		var layers: Array = []
		for slot: Variant in order:
			if (slot is int or slot is float) and int(slot) >= 0 and int(slot) < POSTERS_MAX and not layers.has(int(slot)):
				layers.append(int(slot))
		out["poster_order"] = layers
	# Снятые стандартные плакаты (номера 0..POSTERS-1).
	var gone: Variant = value.get("poster_gone", [])
	if gone is Array and not gone.is_empty():
		var removed: Array = []
		for slot: Variant in gone:
			if (slot is int or slot is float) and int(slot) >= 0 and int(slot) < POSTERS and not removed.has(int(slot)):
				removed.append(int(slot))
		if not removed.is_empty():
			out["poster_gone"] = removed
	out.board = _clean_board_list(value.get("board", []))
	if value.get("board_gone", false) == true:
		out["board_gone"] = true
	# Добавленные доски: [{"id": 1.., "pos": [x, y], "board": [стикеры]}].
	var more: Variant = value.get("boards", [])
	if more is Array and not more.is_empty():
		var list: Array = []
		var ids: Array = []
		for entry: Variant in more:
			if list.size() >= BOARDS_MAX - 1 or not entry is Dictionary:
				continue
			var id: Variant = entry.get("id", 0)
			var at: Variant = entry.get("pos", [])
			if not (id is int or id is float) or int(id) < 1 or int(id) > 999 or ids.has(int(id)) or not (at is Array and at.size() == 2):
				continue
			var x := _number(at[0], -WALL_X, WALL_X)
			var y := _number(at[1], WALL_Y.x, WALL_Y.y)
			if is_nan(x) or is_nan(y):
				continue
			ids.append(int(id))
			list.append({"id": int(id), "pos": [x, y], "board": _clean_board_list(entry.get("board", []))})
		if not list.is_empty():
			out["boards"] = list
	return out


static func _clean_board_list(board: Variant) -> Array:
	var out: Array = []
	if board is Array:
		for entry: Variant in board.slice(maxi(0, board.size() - BOARD_MAX)):
			var sticker := clean_board_sticker(entry)
			if not sticker.is_empty():
				out.append(sticker)
	return out


# --- Доски и плакаты комнаты -----------------------------------------------------------------

## Номера досок друзей в комнате: 0 — основная (если её не сняли), дальше — добавленные.
static func board_ids(data: Dictionary) -> Array:
	var ids: Array = []
	if not data.get("board_gone", false):
		ids.append(0)
	for entry: Dictionary in data.get("boards", []):
		ids.append(int(entry.id))
	return ids


## Стикеры доски bid (тот же массив, что в data, — для своих правок). Нет доски — пустой массив.
static func board_list(data: Dictionary, bid: int) -> Array:
	if bid == 0:
		if not data.has("board"):
			data["board"] = []
		return data.board
	for entry: Dictionary in data.get("boards", []):
		if int(entry.id) == bid:
			return entry.board
	return []


## Где висит доска bid (центр на задней стене, м).
static func board_pos(data: Dictionary, bid: int) -> Vector2:
	var pos: Array = data.get("pos", []) if bid == 0 else []
	for entry: Dictionary in data.get("boards", []):
		if int(entry.id) == bid:
			pos = entry.pos
	return Vector2(float(pos[0]), float(pos[1])) if pos.size() == 2 else BOARD_DEFAULT


## Номера плакатов, которые висят в комнате: стандартные (если не сняты) и добавленные.
static func poster_slots(data: Dictionary) -> Array:
	var list: Array = data.get("posters", [])
	var gone: Array = data.get("poster_gone", [])
	var slots: Array = []
	for slot in POSTERS_MAX:
		if slot < POSTERS:
			if not gone.has(slot):
				slots.append(slot)
		elif slot < list.size() and list[slot] is Array and (list[slot] as Array).size() >= 3:
			slots.append(slot)
	return slots


static func clean_box_sticker(entry: Variant) -> Array:
	if not entry is Array or not entry.size() in [4, 5, 6] or not entry[0] is String or not valid_id(entry[0]):
		return []
	var face := 0
	if entry.size() == 6:
		if not (entry[5] is int or entry[5] is float) or int(entry[5]) < 0 or int(entry[5]) > 5:
			return []
		face = int(entry[5])
	var u := _number(entry[1], 0.0, 1.0)
	var v := _number(entry[2], 0.0, 1.0)
	var r := wrap_angle(entry[3])
	var k := _number(entry[4], SCALE_MIN, SCALE_MAX) if entry.size() >= 5 else 1.0
	if is_nan(u) or is_nan(v) or is_nan(r) or is_nan(k):
		return []
	return [entry[0], u, v, r, k, face]


## Поворот приводится к −π..π (крутить можно сколько угодно оборотов).
static func wrap_angle(value: Variant) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return NAN
	return wrapf(float(value), -PI, PI)


static func clean_board_sticker(entry: Variant) -> Array:
	if not entry is Array or not entry.size() in [7, 8] or not entry[1] is String or not valid_id(entry[1]):
		return []
	var uid := _text(entry[0], 16)
	var u := _number(entry[2], 0.0, 1.0)
	var v := _number(entry[3], 0.0, 1.0)
	var r := wrap_angle(entry[4])
	var k := _number(entry[7], SCALE_MIN, SCALE_MAX) if entry.size() == 8 else 1.0
	var author := _text(entry[5], 48)
	if uid.is_empty() or author.is_empty() or is_nan(u) or is_nan(v) or is_nan(r) or is_nan(k):
		return []
	return [uid, entry[1], u, v, r, author, _text(entry[6], 32), k]


## Ключ автора: Steam ID, если есть, иначе ник (локальная сеть).
static func author_key(steam_id: int, nick: String) -> String:
	return ("steam:%d" % steam_id) if steam_id != 0 else ("name:" + nick.left(40))
