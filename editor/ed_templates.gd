extends RefCounted
## Шаблоны редактора (ТЗ 3.5): раскладки стола по жанрам знакомых настолок и готовые фоны стола.
## Только механика и расположение — без чужого арта и текстов. Логика без UI, проверяется headless:
## tests/test_editor_templates.gd. Окно выбора — editor/ed_app.gd (_layout_templates_dialog).

const Assets := preload("res://editor/ed_assets.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")

## Раскладки: слоты элементов в координатах 1280×720 (под верхней полосой 48 px).
## Применение переставляет существующие элементы того же вида в слоты (ссылки колод и правил на зоны
## сохраняются), недостающие создаёт, лишние оставляет на месте.
const LAYOUTS := [
	{"id": "cards", "title": "Карточная", "hint": "Колода и сброс в центре, рука снизу — как «Дурак», «Уно»", "slots": [
		{"kind": "opponents", "title": "Соперники", "rect": [24, 56, 1232, 96]},
		{"kind": "phase", "title": "Фаза / ход", "rect": [32, 176, 320, 40]},
		{"kind": "zone", "owner": "shared", "view": "pile", "title": "Колода", "rect": [384, 176, 184, 216]},
		{"kind": "zone", "owner": "shared", "view": "discard", "title": "Сброс", "rect": [600, 176, 184, 216]},
		{"kind": "counter", "title": "Очки", "rect": [896, 176, 360, 48]},
		{"kind": "journal", "title": "Журнал", "rect": [896, 240, 360, 152]},
		{"kind": "zone", "owner": "player", "view": "fan", "title": "Ваша рука", "rect": [208, 424, 864, 200]},
		{"kind": "button", "title": "Пас", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "words", "title": "Объясни слово", "hint": "Слово по центру, команды со счётом, «Угадали» — как «Алиас», «Шляпа»", "slots": [
		{"kind": "teams", "title": "Команды", "rect": [24, 64, 300, 320]},
		{"kind": "phase", "title": "Фаза / ход", "rect": [440, 112, 400, 40]},
		{"kind": "zone", "owner": "shared", "view": "row", "title": "Слово", "rect": [440, 176, 400, 240]},
		{"kind": "counter", "title": "Очки", "rect": [920, 64, 336, 48]},
		{"kind": "journal", "title": "Журнал", "rect": [920, 128, 336, 200]},
		{"kind": "button", "title": "Угадали", "main": true, "rect": [464, 560, 176, 56]},
		{"kind": "button", "title": "Пропуск", "rect": [656, 560, 160, 56]},
	]},
	{"id": "dice", "title": "Кубики и ставки", "hint": "Лоток кубиков в центре, ставка и игроки — как «Перудо»", "slots": [
		{"kind": "players", "title": "Игроки", "rect": [24, 56, 1232, 96]},
		{"kind": "dice_tray", "title": "Лоток d6", "rect": [176, 176, 928, 288]},
		{"kind": "counter", "title": "Ставка", "rect": [176, 480, 440, 48]},
		{"kind": "phase", "title": "Фаза / ход", "rect": [176, 544, 440, 40]},
		{"kind": "journal", "title": "Журнал", "rect": [952, 480, 304, 144]},
		{"kind": "button", "title": "Бросить", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "board", "title": "Ходилка", "hint": "Большое поле, игроки справа, кубик и кнопка хода — как «Бродилка»", "slots": [
		{"kind": "zone", "owner": "shared", "view": "free", "title": "Поле", "rect": [24, 64, 936, 424]},
		{"kind": "players", "title": "Игроки", "rect": [976, 64, 280, 296]},
		{"kind": "dice_tray", "title": "Лоток d6", "rect": [976, 376, 280, 200]},
		{"kind": "zone", "owner": "player", "view": "fan", "title": "Мои карты", "rect": [24, 504, 600, 120]},
		{"kind": "phase", "title": "Фаза / ход", "rect": [640, 504, 320, 40]},
		{"kind": "button", "title": "Ход", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "roles", "title": "Ведущий и роли", "hint": "Карта роли у каждого, общий стол, голосование — как «Мафия»", "slots": [
		{"kind": "players", "title": "Игроки", "rect": [24, 56, 1232, 96]},
		{"kind": "zone", "owner": "player", "view": "row", "title": "Моя роль", "rect": [24, 176, 288, 240]},
		{"kind": "zone", "owner": "shared", "view": "row", "title": "Стол", "rect": [336, 176, 608, 240]},
		{"kind": "journal", "title": "Журнал", "rect": [968, 176, 288, 320]},
		{"kind": "phase", "title": "Фаза / ход", "rect": [336, 432, 608, 40]},
		{"kind": "button", "title": "Голосовать", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "market", "title": "Рынок и планшеты", "hint": "Общий ряд карт сверху, свои карты и ресурсы снизу — как «Сплендор»", "slots": [
		{"kind": "opponents", "title": "Соперники", "rect": [24, 56, 1232, 96]},
		{"kind": "zone", "owner": "shared", "view": "pile", "title": "Колода", "rect": [24, 168, 160, 200]},
		{"kind": "zone", "owner": "shared", "view": "row", "title": "Рынок", "rect": [200, 168, 1056, 200]},
		{"kind": "zone", "owner": "player", "view": "row", "title": "Мои карты", "rect": [24, 392, 760, 232]},
		{"kind": "counter", "title": "Ресурс", "rect": [808, 392, 448, 48]},
		{"kind": "journal", "title": "Журнал", "rect": [808, 456, 448, 168]},
		{"kind": "button", "title": "Купить", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "scale", "title": "Шкала", "hint": "Шкала по центру, ведущий даёт подсказку — как «Длина волны»", "slots": [
		{"kind": "phase", "title": "Фаза / ход", "rect": [440, 64, 400, 40]},
		{"kind": "zone", "owner": "shared", "view": "free", "title": "Шкала", "rect": [240, 120, 800, 320]},
		{"kind": "players", "title": "Игроки", "rect": [24, 456, 1232, 96]},
		{"kind": "counter", "title": "Очки", "rect": [24, 576, 320, 48]},
		{"kind": "button", "title": "Ответить", "main": true, "rect": [560, 640, 160, 48]},
	]},
	{"id": "grid", "title": "Сетка карт", "hint": "Поле 5×5 карт и две команды — как «Кодовые имена»", "slots": [
		{"kind": "teams", "title": "Команды", "rect": [24, 64, 240, 560]},
		{"kind": "zone", "owner": "shared", "view": "grid", "title": "Поле", "rect": [288, 64, 704, 560]},
		{"kind": "counter", "title": "Очки", "rect": [1016, 64, 240, 48]},
		{"kind": "journal", "title": "Журнал", "rect": [1016, 128, 240, 160]},
		{"kind": "button", "title": "Готово", "main": true, "rect": [1016, 576, 240, 48]},
	]},
]

## Готовые фоны: плитка 256×256, нарисованная кодом (свой арт, не из чужих игр), и затемнение под неё.
const BACKGROUNDS := [
	{"id": "felt", "title": "Сукно", "color": "#2f6b45", "dim": 0.1},
	{"id": "wood_dark", "title": "Тёмное дерево", "color": "#4a2f1d", "dim": 0.15},
	{"id": "wood_light", "title": "Светлое дерево", "color": "#b98a57", "dim": 0.25},
	{"id": "parchment", "title": "Пергамент", "color": "#e3d4b0", "dim": 0.0},
	{"id": "stone", "title": "Подземелье", "color": "#4a4a52", "dim": 0.3},
	{"id": "tavern", "title": "Таверна", "color": "#3b2416", "dim": 0.2},
	{"id": "neon", "title": "Неон", "color": "#120e24", "dim": 0.0},
	{"id": "space", "title": "Космос", "color": "#0b0d1c", "dim": 0.0},
	{"id": "paper", "title": "Тетрадь", "color": "#f4f1e8", "dim": 0.0},
]

static var _cache := {}

static func layout(id: String) -> Dictionary:
	for entry: Dictionary in LAYOUTS:
		if entry.id == id:
			return entry
	return {}

static func background(id: String) -> Dictionary:
	for entry: Dictionary in BACKGROUNDS:
		if entry.id == id:
			return entry
	return {}

## Переставить элементы проекта по шаблону раскладки. Возвращает копию данных (для document.replace).
static func apply_layout(data: Dictionary, id: String) -> Dictionary:
	var template := layout(id)
	var copy: Dictionary = data.duplicate(true)
	if template.is_empty():
		return copy
	if copy.layout.get("screens", []).is_empty():
		copy.layout["screens"] = [{"id": "main", "items": []}]
	var items: Array = copy.layout.screens[0].get("items", [])
	var slots: Array = template.slots
	var taken := {}
	var placed := {}
	# Два прохода: сначала точное совпадение (вид, владелец, вид зоны), потом зона того же владельца.
	for strict: bool in [true, false]:
		for s in slots.size():
			if placed.has(s):
				continue
			for i in items.size():
				if taken.has(i) or not _fits(items[i], slots[s], strict):
					continue
				taken[i] = true
				placed[s] = i
				break
	var vars: Array = copy.rules.get("vars", [])
	var original_count := items.size()
	for s in slots.size():
		var slot: Dictionary = slots[s]
		if placed.has(s):
			var item: Dictionary = items[placed[s]]
			item["rect"] = slot.rect.duplicate()
			item.erase("anchors")
			if slot.get("main", false) and item.get("kind") == "button":
				item["main"] = true
			continue
		var item := {"kind": slot.kind, "id": _free_id(items, str(slot.kind)), "title": slot.title, "visible": ["all"], "rect": slot.rect.duplicate()}
		match str(slot.kind):
			"zone":
				item.merge({"owner": slot.owner, "view": slot.view, "free": true})
			"button":
				item["action"] = item.id
				item["main"] = bool(slot.get("main", false))
			"counter":
				item["var"] = str(vars[0].id) if not vars.is_empty() else ""
		items.append(item)
	# Элементы проекта, которым не нашлось слота, переносим на свободное место (если мешают).
	var occupied: Array = []
	for i in items.size():
		if taken.has(i) or i >= original_count:
			occupied.append(Definition.layout_rect(items[i], i))
	for i in original_count:
		if taken.has(i):
			continue
		var rect := Definition.layout_rect(items[i], i)
		if rect.size == Vector2.ZERO:
			continue
		if _free(rect, occupied):
			occupied.append(rect)
			continue
		var spot := _find_spot(rect.size, occupied)
		if spot.size != Vector2.ZERO:
			items[i]["rect"] = [spot.position.x, spot.position.y, spot.size.x, spot.size.y]
			items[i].erase("anchors")
			occupied.append(spot)
		else:
			occupied.append(rect)
	# Главная кнопка одна: у остальных кнопок шаблонной раскладки снимаем пометку.
	var main_index := -1
	for s in slots.size():
		if slots[s].get("main", false):
			main_index = placed.get(s, -1)
	for i in items.size():
		if items[i].get("kind") == "button" and items[i].get("main", false) and main_index >= 0 and i != main_index and taken.has(i):
			items[i]["main"] = false
	copy.layout.screens[0]["items"] = items
	copy.layout["custom"] = true
	return copy

## Внутри стола и не пересекается с занятым (с зазором 8 px).
static func _free(rect: Rect2, occupied: Array) -> bool:
	if rect.position.x < 0 or rect.position.y < 48 or rect.end.x > 1280 or rect.end.y > 720:
		return false
	for other: Rect2 in occupied:
		if other.size != Vector2.ZERO and rect.grow(7).intersects(other):
			return false
	return true

## Свободное место под элемент: исходный размер, затем меньше (не меньше 128×64). Сетка 16 px.
static func _find_spot(wanted: Vector2, occupied: Array) -> Rect2:
	for size: Vector2 in [wanted, wanted.min(Vector2(360, 200)), wanted.min(Vector2(240, 144)), Vector2(160, 96).min(wanted), Vector2(128, 64).min(wanted)]:
		var y := 56.0
		while y + size.y <= 712:
			var x := 24.0
			while x + size.x <= 1256:
				var rect := Rect2(Vector2(x, y), size)
				if _free(rect, occupied):
					return rect
				x += 16
			y += 16
	return Rect2()

static func _fits(item: Dictionary, slot: Dictionary, strict: bool) -> bool:
	if item.get("kind") != slot.kind:
		return false
	if slot.kind != "zone":
		return true
	if str(item.get("owner", "shared")) != str(slot.owner):
		return false
	return not strict or str(item.get("view", "row")) == str(slot.view)

static func _free_id(items: Array, kind: String) -> String:
	var number := 1
	while items.any(func(item: Dictionary): return str(item.get("id", "")) == "%s_%d" % [kind, number]):
		number += 1
	return "%s_%d" % [kind, number]

## Плитка фона (256×256, бесшовная). Кэшируется: окно фона рисует миниатюры всех вариантов.
static func background_image(id: String) -> Image:
	if _cache.has(id):
		return _cache[id]
	var size := 256
	var look := background(id)
	var base := Color(str(look.get("color", "#333333")))
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.03
	var field: Image = noise.get_seamless_image(size, size, false, false, 0.2)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new()
	random.seed = 11
	for y in size:
		for x in size:
			var n := field.get_pixel(x, y).r
			var color := base
			match id:
				"felt":
					color = base.lightened((n - 0.5) * 0.18 + random.randf_range(-0.04, 0.04))
				"wood_dark", "wood_light":
					var grain := sin(TAU * 6.0 * y / size + n * 9.0) * 0.5 + 0.5
					color = base.darkened(grain * 0.22 + (n - 0.5) * 0.1)
				"tavern":
					var plank := posmod(x, 64)
					var grain := sin(TAU * 4.0 * y / size + n * 7.0 + floori(x / 64.0) * 1.7) * 0.5 + 0.5
					color = base.lightened(grain * 0.12).darkened(0.45 if plank < 2 else 0.0)
				"parchment":
					color = base.darkened(clampf((n - 0.45) * 0.35, 0.0, 0.2) + random.randf_range(0.0, 0.03))
				"stone":
					color = base.lightened((n - 0.5) * 0.35).darkened(0.35 if posmod(x + (32 if posmod(floori(y / 64.0), 2) == 1 else 0), 128) < 2 or posmod(y, 64) < 2 else 0.0)
				"neon":
					var line := posmod(x, 32) == 0 or posmod(y, 32) == 0
					color = base.lerp(Color("ff3fb4") if posmod(floori(x / 32.0) + floori(y / 32.0), 3) == 0 else Color("3fe0ff"), 0.35 if line else n * 0.06)
				"space":
					color = base.lerp(Color("2a1f55"), n * 0.5)
				"paper":
					var blue := posmod(x, 32) == 0 or posmod(y, 32) == 0
					color = base.lerp(Color("8fb3d9"), 0.5) if blue else base.darkened(random.randf_range(0.0, 0.02))
			image.set_pixel(x, y, color)
	if id == "space":
		for star in 90:
			var spot := Vector2i(random.randi_range(0, size - 1), random.randi_range(0, size - 1))
			image.set_pixelv(spot, Color(1, 1, 1).darkened(random.randf_range(0.0, 0.6)))
	_cache[id] = image
	return image

## Положить фон-пресет в ассеты игры и в layout.background. Возвращает {data, error}.
static func apply_background(data: Dictionary, id: String) -> Dictionary:
	var look := background(id)
	if look.is_empty():
		return {"data": data, "error": "Неизвестный фон."}
	var stored: Dictionary = Assets._store(str(data.get("id", "")), background_image(id).save_webp_to_buffer(false), "webp", "")
	if not str(stored.error).is_empty():
		return {"data": data, "error": str(stored.error)}
	var copy: Dictionary = data.duplicate(true)
	if not copy.has("assets"):
		copy["assets"] = {}
	stored.asset["name"] = "Фон: " + str(look.title)
	copy.assets[stored.hash] = stored.asset
	copy.layout["background"] = {"color": str(look.color), "image": stored.hash, "fit": "tile", "dim": float(look.dim)}
	return {"data": copy, "error": ""}

## Шаблоны лица карты: слои в долях карты, привязанные к колонкам таблицы (колонки создаются, если их нет).
## Слой: [вид, поле, x, y, w, h, кегль в долях высоты, выравнивание]. Фон карты (бумага) сохраняется.
const FACES := [
	{"id": "suit", "title": "Число и масть", "hint": "Углы и крупное значение — игральные карты", "columns": {"rank": "text", "suit": "text"}, "frame": true, "layers": [
		["text", "rank", 0.09, 0.06, 0.3, 0.12, 0.09, "left"],
		["text", "suit", 0.09, 0.17, 0.3, 0.1, 0.06, "left"],
		["text", "rank", 0.0, 0.36, 1.0, 0.28, 0.22, "center"],
		["text", "rank", 0.61, 0.82, 0.3, 0.12, 0.09, "right"],
	]},
	{"id": "classic", "title": "Название, рисунок, текст", "hint": "Карты действий и предметов", "columns": {"title": "text", "art": "image", "text": "text"}, "frame": true, "layers": [
		["text", "title", 0.08, 0.04, 0.84, 0.11, 0.06, "center"],
		["image", "art", 0.08, 0.17, 0.84, 0.45, 0.0, ""],
		["text", "text", 0.08, 0.65, 0.84, 0.3, 0.042, "left"],
	]},
	{"id": "word", "title": "Слово", "hint": "Одно крупное слово — объяснялки и ассоциации", "columns": {"word": "text"}, "frame": true, "layers": [
		["text", "word", 0.05, 0.38, 0.9, 0.24, 0.1, "center"],
	]},
	{"id": "role", "title": "Карта роли", "hint": "Портрет, имя роли и способность — «Мафия» и т. п.", "columns": {"art": "image", "role": "text", "ability": "text"}, "frame": true, "layers": [
		["image", "art", 0.15, 0.06, 0.7, 0.42, 0.0, ""],
		["text", "role", 0.08, 0.5, 0.84, 0.1, 0.07, "center"],
		["text", "ability", 0.08, 0.63, 0.84, 0.32, 0.042, "center"],
	]},
	{"id": "cost", "title": "Стоимость в углу", "hint": "Карты рынка: цена, название, рисунок, эффект", "columns": {"cost": "number", "title": "text", "art": "image", "text": "text"}, "frame": false, "layers": [
		["badge", "", 0.72, 0.03, 0.22, 0.14, 0.0, ""],
		["text", "cost", 0.72, 0.03, 0.22, 0.14, 0.08, "center"],
		["text", "title", 0.06, 0.05, 0.64, 0.12, 0.055, "left"],
		["image", "art", 0.06, 0.2, 0.88, 0.4, 0.0, ""],
		["text", "text", 0.08, 0.63, 0.84, 0.32, 0.042, "left"],
	]},
	{"id": "qa", "title": "Вопрос — ответ", "hint": "Викторины: вопрос сверху, ответ снизу", "columns": {"question": "text", "answer": "text"}, "frame": true, "layers": [
		["text", "question", 0.08, 0.06, 0.84, 0.4, 0.055, "center"],
		["line", "", 0.08, 0.495, 0.84, 0.01, 0.0, ""],
		["text", "answer", 0.08, 0.54, 0.84, 0.4, 0.05, "center"],
	]},
]

const FACE_COLUMN_TITLES := {"rank": "Значение", "suit": "Масть", "title": "Название", "art": "Рисунок", "text": "Описание", "word": "Слово", "role": "Роль", "ability": "Способность", "cost": "Цена", "question": "Вопрос", "answer": "Ответ"}

static func face(id: String) -> Dictionary:
	for entry: Dictionary in FACES:
		if entry.id == id:
			return entry
	return {}

## Применить шаблон лица к колоде: колонки добавляются (с пустыми значениями в строках), слои заменяются,
## фон карты (бумага) остаётся. Возвращает изменённую копию колоды.
static func apply_face(deck: Dictionary, id: String) -> Dictionary:
	var template := face(id)
	var copy: Dictionary = deck.duplicate(true)
	if template.is_empty():
		return copy
	var Faces: GDScript = load("res://games/custom/logic/cg_faces.gd")
	var columns: Array = Faces.columns(copy)
	var known := {}
	for column: Dictionary in columns:
		known[str(column.id)] = str(column.get("type", "text"))
	for key: String in template.columns:
		if not known.has(key):
			columns.append({"id": key, "type": template.columns[key]})
			known[key] = template.columns[key]
			for row: Dictionary in copy.get("rows", []):
				if not row.has(key):
					row[key] = 0 if template.columns[key] == "number" else ""
	copy["columns"] = columns
	var dimensions: Array = Faces.dimensions(copy)
	var width := float(dimensions[0])
	var height := float(dimensions[1])
	if not copy.get("face") is Dictionary:
		copy["face"] = {}
	var old: Array = copy.face.get("layers", []) if copy.face.get("layers") is Array else []
	var layers: Array = []
	if not old.is_empty() and Faces.is_card_background(old[0], 0):
		layers.append(old[0])
	else:
		layers.append({"kind": "fill", "title": "Фон", "role": "card", "rect": [0, 0, width, height], "color": Faces.paper(copy), "locked": true})
	if template.frame:
		layers.append({"kind": "frame", "title": "Рамка", "rect": [24, 24, width - 48, height - 48], "border": 12, "radius": 24, "fill": "", "color": "#30263f", "rotation": 0, "opacity": 1.0})
	for spec: Array in template.layers:
		var rect := [roundf(spec[2] * width), roundf(spec[3] * height), maxf(8, roundf(spec[4] * width)), maxf(8, roundf(spec[5] * height))]
		match str(spec[0]):
			"text":
				layers.append({"kind": "text", "title": str(FACE_COLUMN_TITLES.get(spec[1], spec[1])), "field": spec[1], "rect": rect, "text": "", "asset": "",
					# Строка выше слоя при clip_text не рисуется вовсе — кегль не больше высоты слоя / 1,5.
					"font_size": clampi(mini(roundi(spec[6] * height), floori(float(rect[3]) / 1.5)), 8, 512), "color": "#30263f", "align": spec[7], "rotation": 0, "opacity": 1.0})
			"image":
				layers.append({"kind": "image", "title": str(FACE_COLUMN_TITLES.get(spec[1], spec[1])), "field": spec[1], "rect": rect, "text": "", "asset": "", "rotation": 0, "opacity": 1.0})
			"badge":
				layers.append({"kind": "fill", "title": "Значок цены", "rect": rect, "color": "#e0b84e", "radius": 2048, "rotation": 0, "opacity": 1.0})
			"line":
				layers.append({"kind": "fill", "title": "Линия", "rect": rect, "color": "#30263f", "rotation": 0, "opacity": 0.5})
	copy.face["layers"] = layers
	return copy

## Игральная колода на 36 или 52 карты: значение (текст), масть, цвет масти (для цвета надписей) и число
## для правил (6…14 / 2…14); лицо «Число и масть» с красными червами и бубнами.
static func playing_deck(deck: Dictionary, count: int) -> Dictionary:
	var copy: Dictionary = deck.duplicate(true)
	var ranks: Array = ["6", "7", "8", "9", "10", "В", "Д", "К", "Т"]
	if count == 52:
		ranks = ["2", "3", "4", "5"] + ranks
	var suits := [["Пики", "#30263f"], ["Трефы", "#30263f"], ["Червы", "#b3261e"], ["Бубны", "#b3261e"]]
	var rows: Array = []
	for suit: Array in suits:
		for index in ranks.size():
			rows.append({"rank": ranks[index], "suit": suit[0], "suit_color": suit[1], "value": 14 - ranks.size() + 1 + index, "copies": 1})
	copy["title"] = "Колода %d" % count
	copy["columns"] = [{"id": "rank", "type": "text"}, {"id": "suit", "type": "text"}, {"id": "suit_color", "type": "color"}, {"id": "value", "type": "number"}]
	copy["rows"] = rows
	copy.erase("face")
	copy = apply_face(copy, "suit")
	for layer: Dictionary in copy.face.layers:
		if layer.get("kind") == "text":
			layer["color_field"] = "suit_color"
	return copy

## ---------- Из игр сборника (решение владельца 12.11): фоны, раскладки и рубашки карт наших настолок.
## friends — арт из оригинальной игры: только для игры с друзьями (как и в самой игре), в источник ассета
## пишется пометка. Игры, которых нет в сборке (Four Souls в релизе), просто не показываются.
const FRIENDS_NOTE := "Из игры сборника «%s» — только для игры с друзьями (арт оригинальной игры)."
const GAME_BACKGROUNDS := [
	{"id": "k12_planks", "game": "Дюжина короля", "title": "Деревянный пол", "path": "res://games/king_of_12/art/env/dark_wooden_planks_diff_1k.jpg", "fit": "tile", "dim": 0.2, "friends": false},
	{"id": "k12_leather", "game": "Дюжина короля", "title": "Кожа", "path": "res://games/king_of_12/art/env/brown_leather_albedo_1k.jpg", "fit": "tile", "dim": 0.25, "friends": false},
	{"id": "stillion_circus", "game": "Стиллион", "title": "Цирк", "path": "res://games/stillion/art/bg_circus_approved.png", "fit": "cover", "dim": 0.15, "friends": false},
	{"id": "stillion_stage", "game": "Стиллион", "title": "Сцена", "path": "res://games/stillion/art/bg_stage.jpg", "fit": "cover", "dim": 0.2, "friends": false},
	{"id": "mind_diner", "game": "Unspoken", "title": "Закусочная", "path": "res://games/the_mind/art/diner.png", "fit": "cover", "dim": 0.25, "friends": false},
	{"id": "machi_day", "game": "Мачи Коро", "title": "Город днём", "path": "res://games/machi_koro/art/city_day.png", "fit": "cover", "dim": 0.15, "friends": true},
	{"id": "machi_night", "game": "Мачи Коро", "title": "Город ночью", "path": "res://games/machi_koro/art/city_night.png", "fit": "cover", "dim": 0.1, "friends": true},
	{"id": "botc_night", "game": "Кровь на часовой башне", "title": "Ночной город", "path": "res://games/blood_on_the_clocktower/art/town_night.png", "fit": "cover", "dim": 0.2, "friends": true},
	{"id": "dw_room", "game": "Опасные слова", "title": "Подземелье", "path": "res://games/dangerous_words/art/room_1.png", "fit": "cover", "dim": 0.35, "friends": true},
	{"id": "brodilka_board", "game": "Большая бродилка", "title": "Поле", "path": "res://games/brodilka/art/board.webp", "fit": "center", "dim": 0.0, "friends": true},
	{"id": "fs_floor", "game": "The Binding of Isaac: Four Souls", "title": "Пол подвала", "path": "res://games/four_souls/art/table_floor.webp", "fit": "cover", "dim": 0.3, "friends": true},
]

## Раскладка шаблона — по мотивам стола игры сборника; bg — фон этой игры (картинка из GAME_BACKGROUNDS).
const LAYOUT_GAMES := {
	"cards": {"game": "Дюжина короля / Покер", "bg": "k12_leather"},
	"words": {"game": "Опасные слова", "bg": "dw_room"},
	"dice": {"game": "Перудо", "bg": "k12_planks"},
	"board": {"game": "Большая бродилка", "bg": "brodilka_board"},
	"roles": {"game": "Кровь на часовой башне", "bg": "botc_night"},
	"market": {"game": "Мачи Коро", "bg": "machi_day"},
	"scale": {"game": "Длина волны", "bg": "stillion_stage"},
	"grid": {"game": "Hues and Cues", "bg": "mind_diner"},
}

const GAME_BACKS := [
	{"id": "poker", "game": "Покер", "title": "Покер", "path": "res://games/poker/art/card_back.png", "friends": false},
	{"id": "gloom", "game": "Gloom", "title": "Gloom", "path": "res://games/gloom/art/cards/back.webp", "friends": true},
	{"id": "the_gang", "game": "The Gang", "title": "The Gang", "path": "res://games/the_gang/art/cards/back.webp", "friends": true},
	{"id": "brodilka_good", "game": "Большая бродилка", "title": "Хорошо-плохо", "path": "res://games/brodilka/art/cards/gb_back.webp", "friends": true},
	{"id": "brodilka_shop", "game": "Большая бродилка", "title": "Лавка", "path": "res://games/brodilka/art/cards/shop_back.webp", "friends": true},
	{"id": "brodilka_tadam", "game": "Большая бродилка", "title": "Тадам", "path": "res://games/brodilka/art/cards/tadam_back.webp", "friends": true},
	{"id": "rsb_exotic", "game": "Ready Set Bet", "title": "Экзотика", "path": "res://games/ready_set_bet/art/exotic_back.png", "friends": true},
	{"id": "rsb_vip", "game": "Ready Set Bet", "title": "VIP", "path": "res://games/ready_set_bet/art/vip_back.png", "friends": true},
	{"id": "tir_thing", "game": "Things in Rings", "title": "Предметы", "path": "res://games/things_in_rings/art/cards/back_thing.webp", "friends": true},
	{"id": "tir_word", "game": "Things in Rings", "title": "Слова", "path": "res://games/things_in_rings/art/cards/back_word.webp", "friends": true},
	{"id": "dw_curse", "game": "Опасные слова", "title": "Проклятие", "path": "res://games/dangerous_words/art/curse_back.png", "friends": true},
]

## Рубашки, нарисованные кодом (свой арт): узор на цвете. 252×352 — картинка под стандартную карту.
const DRAWN_BACKS := [
	{"id": "diamonds", "title": "Ромбы", "color": "#7a1f2b", "ink": "#e8d3b0"},
	{"id": "stripes", "title": "Полосы", "color": "#1f3b5c", "ink": "#d9c27a"},
	{"id": "dots", "title": "Горошек", "color": "#2f5d46", "ink": "#e9e2cf"},
	{"id": "cross", "title": "Рамка с крестом", "color": "#40334e", "ink": "#8e7ba7"},
]

## Доступные в этой сборке записи (ресурс есть).
static func available(entries: Array) -> Array:
	return entries.filter(func(entry: Dictionary): return ResourceLoader.exists(str(entry.path)))

static func entry_of(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry
	return {}

## Картинка ресурса проекта (из импортированной текстуры — работает и в экспортированной сборке).
static func project_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	if maxi(image.get_width(), image.get_height()) > 2048:
		var scale := 2048.0 / maxi(image.get_width(), image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return image

## Положить картинку в ассеты игры с пометкой источника. Возвращает {data, hash, error}.
static func _store_image(data: Dictionary, image: Image, title: String, source: String) -> Dictionary:
	if image == null:
		return {"data": data, "hash": "", "error": "Картинка не найдена в этой сборке."}
	var stored: Dictionary = Assets._store(str(data.get("id", "")), image.save_webp_to_buffer(false), "webp", source)
	if not str(stored.error).is_empty():
		return {"data": data, "hash": "", "error": str(stored.error)}
	var copy: Dictionary = data.duplicate(true)
	if not copy.has("assets"):
		copy["assets"] = {}
	stored.asset["name"] = title
	copy.assets[stored.hash] = stored.asset
	return {"data": copy, "hash": stored.hash, "error": ""}

static func _source(entry: Dictionary) -> String:
	return FRIENDS_NOTE % entry.game if bool(entry.get("friends", false)) else "Из игры сборника «%s»." % entry.game

## Фон из игры сборника → ассет + layout.background.
static func apply_game_background(data: Dictionary, id: String) -> Dictionary:
	var entry := entry_of(GAME_BACKGROUNDS, id)
	if entry.is_empty():
		return {"data": data, "error": "Неизвестный фон."}
	var result := _store_image(data, project_image(str(entry.path)), "Фон: %s — %s" % [entry.game, entry.title], _source(entry))
	if not str(result.error).is_empty():
		return result
	result.data.layout["background"] = {"color": "", "image": result.hash, "fit": str(entry.fit), "dim": float(entry.dim)}
	return result

## Нарисованная кодом рубашка.
static func drawn_back_image(id: String) -> Image:
	var key := "back_" + id
	if _cache.has(key):
		return _cache[key]
	var look := entry_of(DRAWN_BACKS, id)
	var base := Color(str(look.get("color", "#40334e")))
	var ink := Color(str(look.get("ink", "#8e7ba7")))
	var image := Image.create(252, 352, false, Image.FORMAT_RGB8)
	image.fill(base)
	for y in 352:
		for x in 252:
			var inside := x >= 14 and x < 238 and y >= 14 and y < 338
			var edge := inside and (x < 18 or x >= 234 or y < 18 or y >= 334)
			var mark := false
			match id:
				"diamonds":
					mark = inside and (posmod(x + y, 28) < 2 or posmod(x - y, 28) < 2)
				"stripes":
					mark = inside and posmod(x + y, 20) < 6
				"dots":
					mark = inside and Vector2(posmod(x, 24) - 12, posmod(y + (12 if posmod(floori(x / 24.0), 2) == 1 else 0), 24) - 12).length() < 5
				"cross":
					mark = inside and (absi(x * 324 - (y - 14) * 224 - 14 * 324) < 600 or absi((238 - x) * 324 - (y - 14) * 224) < 600)
			if edge or mark:
				image.set_pixel(x, y, ink)
	_cache[key] = image
	return image

## Рубашка колоды из шаблона: kind "game" (из игры сборника) или "drawn". Возвращает {data, error}.
static func apply_back(data: Dictionary, deck_index: int, kind: String, id: String) -> Dictionary:
	var result: Dictionary
	if kind == "game":
		var entry := entry_of(GAME_BACKS, id)
		if entry.is_empty():
			return {"data": data, "error": "Неизвестная рубашка."}
		result = _store_image(data, project_image(str(entry.path)), "Рубашка: %s — %s" % [entry.game, entry.title], _source(entry))
	else:
		var look := entry_of(DRAWN_BACKS, id)
		if look.is_empty():
			return {"data": data, "error": "Неизвестная рубашка."}
		result = _store_image(data, drawn_back_image(id), "Рубашка: " + str(look.title), "")
	if not str(result.error).is_empty():
		return result
	result.data.elements.decks[deck_index]["back"] = result.hash
	return result

## Оформление игры (ТЗ 3.5 п. 6): основной цвет + акцент; нейтральные строит CGStyle.set_game_look.
const LOOKS := [
	{"id": "tavern", "title": "Таверна", "main": "#3b2a1e", "accent": "#e0a84a", "font": "builtin:kellyslab"},
	{"id": "neon", "title": "Неон", "main": "#120e24", "accent": "#ff3fb4", "font": "builtin:unbounded"},
	{"id": "kids", "title": "Детская", "main": "#fff4d6", "accent": "#2f8fdc", "font": "builtin:comfortaa"},
	{"id": "noir", "title": "Нуар", "main": "#161616", "accent": "#c8b27a", "font": "builtin:cormorant"},
	{"id": "nature", "title": "Природа", "main": "#e6efd9", "accent": "#3d7a3a", "font": "builtin:balsamiq"},
	{"id": "sea", "title": "Море", "main": "#0f2a3a", "accent": "#5fd3c9", "font": "builtin:exo"},
]

## ---------- Шаблоны правил (ТЗ 3.5 п. 5): готовые цепочки блоков. Нужные зоны, ресурс «Очки», кнопки и фаза
## «turn» находятся в проекте или создаются; цепочки добавляются к уже существующим.
const RULES := [
	{"id": "draw_play", "title": "Взять карту или сыграть", "hint": "Раздать по 5; в свой ход — сыграть карту из руки на стол или взять карту", "game": "Дюжина короля, Уно"},
	{"id": "dice_points", "title": "Брось кубики — получи очки", "hint": "Кнопка «Бросить»: 2 кубика, сумма — в очки, ход дальше", "game": "Перудо, Тип Топ"},
	{"id": "goal_points", "title": "Игра до 20 очков", "hint": "В конце хода: 20 очков и больше — победа", "game": "почти все игры сборника"},
	{"id": "deck_end", "title": "Пока не кончится колода", "hint": "В конце хода: колода пуста — у кого больше очков, тот победил", "game": "Gloom, Мачи Коро"},
	{"id": "leader_out", "title": "Ведущий выбирает, кто выбывает", "hint": "Кнопка ведущего «Выбрать»: выбранный игрок выбывает", "game": "Кровь на часовой башне"},
]

static func rule(id: String) -> Dictionary:
	return entry_of(RULES, id)

## Добавить цепочки шаблона правил. Возвращает копию данных.
static func apply_rules(data: Dictionary, id: String) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	if rule(id).is_empty():
		return copy
	if copy.layout.get("screens", []).is_empty():
		copy.layout["screens"] = [{"id": "main", "items": []}]
	var rules: Dictionary = copy.rules
	var phases: Array = rules.get("phases", [])
	if not phases.has("turn"):
		phases.append("turn")
	rules["phases"] = phases
	var chains: Array = rules.get("chains", [])
	var actor := {"op": "actor"}
	var score := _ensure_score(copy)
	match id:
		"draw_play":
			var deck := _ensure_zone(copy, "shared", "pile", "draw", "Колода")
			var hand := _ensure_zone(copy, "player", "fan", "hand", "Ваша рука")
			var table := _ensure_zone(copy, "shared", "discard", "table", "На столе")
			var take := _ensure_button(copy, "take_card", "Взять карту", false)
			var own_hand := {"op": "zone", "id": hand, "player": actor}
			chains.append({"event": {"type": "start"}, "blocks": [{"op": "shuffle", "zone": deck}, {"op": "deal", "from": deck, "to": own_hand, "count": 5}, {"op": "phase", "phase": "turn"}]})
			chains.append({"event": {"type": "card", "id": "play_card", "phase": "turn", "by": "current", "zone": own_hand}, "blocks": [{"op": "move", "card": {"op": "card"}, "to": table}, {"op": "open", "card": {"op": "card"}}, {"op": "next"}]})
			chains.append({"event": {"type": "button", "id": take, "phase": "turn", "by": "current"}, "blocks": [{"op": "draw", "from": deck, "to": own_hand, "count": 1}, {"op": "next"}], "guard": {"op": "gt", "a": {"op": "count", "zone": deck}, "b": 0}})
		"dice_points":
			var roll := _ensure_button(copy, "roll_dice", "Бросить", true)
			_ensure_layout(copy, "dice_tray", "Лоток d6", [176, 176, 928, 288])
			chains.append({"event": {"type": "start"}, "blocks": [{"op": "phase", "phase": "turn"}]})
			chains.append({"event": {"type": "button", "id": roll, "phase": "turn", "by": "current"}, "blocks": [{"op": "roll", "count": 2, "visible": "all"}]})
			chains.append({"event": {"type": "rolled", "phase": "turn"}, "blocks": [{"op": "change", "var": score, "value": {"op": "dice_sum", "player": actor}}, {"op": "next"}]})
		"goal_points":
			chains.append({"event": {"type": "turn_end"}, "blocks": [{"op": "if", "condition": {"op": "ge", "a": {"op": "var", "id": score, "player": actor}, "b": 20}, "then": [{"op": "win", "player": actor}]}]})
		"deck_end":
			var deck := _ensure_zone(copy, "shared", "pile", "draw", "Колода")
			chains.append({"event": {"type": "turn_end"}, "blocks": [{"op": "if", "condition": {"op": "eq", "a": {"op": "count", "zone": deck}, "b": 0}, "then": [{"op": "finish", "var": score}]}]})
		"leader_out":
			var choose := _ensure_button(copy, "leader_choose", "Выбрать", true)
			# Счётчик выбывших (общий): когда остаются ведущий и один игрок — ведущий побеждает.
			var vars: Array = copy.rules.get("vars", [])
			var out_id := "out"
			while vars.any(func(v: Dictionary): return str(v.id) == out_id):
				out_id += "_x"
			vars.append({"id": out_id, "title": "Выбыло", "type": "number", "scope": "shared", "init": 0, "visible": "all"})
			copy.rules["vars"] = vars
			chains.append({"event": {"type": "start"}, "blocks": [{"op": "phase", "phase": "turn"}]})
			chains.append({"event": {"type": "button", "id": choose, "phase": "turn", "by": "leader"}, "blocks": [
				{"op": "ask_player", "player": {"op": "leader"}},
				{"op": "if", "condition": {"op": "ne", "a": {"op": "answer"}, "b": {"op": "leader"}}, "then": [
					{"op": "eliminate", "player": {"op": "answer"}},
					{"op": "change", "var": out_id, "value": 1},
					{"op": "log", "text": "Ведущий выбрал, кто выбывает."},
					{"op": "if", "condition": {"op": "ge", "a": {"op": "var", "id": out_id}, "b": {"op": "sub", "a": {"op": "players_count"}, "b": 2}}, "then": [{"op": "win", "player": {"op": "leader"}}]},
				], "else": [{"op": "log", "text": "Ведущий не может выбыть сам."}]},
			]})
	rules["chains"] = chains
	copy.layout["custom"] = true
	return copy

## Личный числовой ресурс «Очки» (первый подходящий или новый).
static func _ensure_score(data: Dictionary) -> String:
	var vars: Array = data.rules.get("vars", [])
	for v: Dictionary in vars:
		if v.get("scope", "shared") == "player" and v.get("type", "number") == "number":
			return str(v.id)
	var id := "score"
	var number := 1
	while vars.any(func(v: Dictionary): return str(v.id) == id):
		number += 1
		id = "score_%d" % number
	vars.append({"id": id, "title": "Очки", "type": "number", "scope": "player", "init": 0, "visible": "all"})
	data.rules["vars"] = vars
	var items: Array = data.layout.screens[0].items
	if not items.any(func(item: Dictionary): return item.get("kind") == "counter"):
		var rect := _find_spot(Vector2(320, 48), _occupied(items))
		items.append({"kind": "counter", "id": _free_id(items, "counter"), "title": "Очки", "var": id, "visible": ["all"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y] if rect.size != Vector2.ZERO else [24, 64, 320, 48]})
	return id

## Зона нужного вида: сначала по виду и владельцу, затем по владельцу, иначе новая на свободном месте.
static func _ensure_zone(data: Dictionary, owner: String, view: String, wanted_id: String, title: String, loose: bool = true) -> String:
	var items: Array = data.layout.screens[0].items
	for strict: bool in ([true, false] if loose else [true]):
		for item: Dictionary in items:
			# Мягкий поиск не подменяет стол колодой (иначе сыгранные карты уходят обратно в колоду).
			if item.get("kind") == "zone" and str(item.get("owner", "shared")) == owner and (str(item.get("view", "row")) == view if strict else (view == "pile" or str(item.get("view", "row")) != "pile")):
				return str(item.id)
	var id := wanted_id
	var number := 1
	while items.any(func(item: Dictionary): return str(item.get("id", "")) == id):
		number += 1
		id = "%s_%d" % [wanted_id, number]
	var size := Vector2(704, 192) if owner == "player" else Vector2(320, 200)
	var rect := _find_spot(size, _occupied(items))
	items.append({"kind": "zone", "id": id, "title": title, "owner": owner, "view": view, "free": false, "visible": ["all"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y] if rect.size != Vector2.ZERO else [352, 176, 320, 192]})
	return id

## Кнопка стола с действием (и её название для логики).
static func _ensure_button(data: Dictionary, action: String, title: String, main: bool) -> String:
	var items: Array = data.layout.screens[0].items
	if not items.any(func(item: Dictionary): return item.get("kind") == "button" and str(item.get("action", item.get("id", ""))) == action):
		var rect := _find_spot(Vector2(176, 48), _occupied(items))
		var has_main := items.any(func(item: Dictionary): return item.get("kind") == "button" and item.get("main", false))
		items.append({"kind": "button", "id": _free_id(items, "button"), "title": title, "action": action, "main": main and not has_main, "visible": ["all"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y] if rect.size != Vector2.ZERO else [560, 640, 176, 48]})
	var titles: Dictionary = data.meta.get("action_titles", {})
	titles[action] = title
	data.meta["action_titles"] = titles
	return action

static func _ensure_layout(data: Dictionary, kind: String, title: String, wanted: Array) -> void:
	var items: Array = data.layout.screens[0].items
	if items.any(func(item: Dictionary): return item.get("kind") == kind):
		return
	var rect := Rect2(wanted[0], wanted[1], wanted[2], wanted[3])
	if not _free(rect, _occupied(items)):
		rect = _find_spot(rect.size, _occupied(items))
	if rect.size == Vector2.ZERO:
		rect = Rect2(wanted[0], wanted[1], wanted[2], wanted[3])
	items.append({"kind": kind, "id": _free_id(items, kind), "title": title, "visible": ["all"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})

static func _occupied(items: Array) -> Array:
	var out: Array = []
	for i in items.size():
		out.append(Definition.layout_rect(items[i], i))
	return out

## Вид кнопок (ТЗ 3.5, решение владельца 12.11): только внешний вид — заливка, текст, окантовка, скругление,
## шрифт, тень. Действия кнопок (и кнопок верхней полосы) не меняются.
const BUTTON_STYLES := [
	{"id": "wood", "title": "Дерево", "game": "Дюжина короля", "buttons": {"fill": "#6b4a2b", "text": "#f3e3c3", "border": "#3b2716", "border_width": 2, "radius": 6, "font": "builtin:kellyslab", "shadow": true}},
	{"id": "circus", "title": "Цирк", "game": "Стиллион", "buttons": {"fill": "#b3261e", "text": "#fff4d6", "border": "#f2c14e", "border_width": 3, "radius": 10, "font": "builtin:ruslan", "shadow": true}},
	{"id": "neon", "title": "Неон", "game": "", "buttons": {"fill": "#1a1030", "text": "#ff8ad8", "border": "#ff3fb4", "border_width": 2, "radius": 14, "font": "builtin:unbounded", "shadow": false}},
	{"id": "pill", "title": "Таблетки", "game": "", "buttons": {"fill": "#f4efe6", "text": "#2f2a3a", "border": "", "border_width": 0, "radius": 28, "font": "builtin:comfortaa", "shadow": true}},
	{"id": "pixel", "title": "Пиксели", "game": "", "buttons": {"fill": "#2d2d44", "text": "#f6e05e", "border": "#f6e05e", "border_width": 3, "radius": 0, "font": "builtin:pressstart", "shadow": false}},
	{"id": "noir", "title": "Тонкая рамка", "game": "", "buttons": {"fill": "#161616", "text": "#e8dcc0", "border": "#c8b27a", "border_width": 1, "radius": 2, "font": "builtin:cormorant", "shadow": false}},
	{"id": "flat", "title": "Плоские", "game": "", "buttons": {"fill": "", "text": "", "border": "", "border_width": 0, "radius": 4, "font": "", "shadow": false}},
]

## ---------- Новая игра из шаблона (ТЗ 3.5 п. 7): готовый набор из раскладки, фона, колоды (лицо + рубашка),
## компонентов, правил, цветов и вида кнопок — по мотивам игр сборника. Дальше всё правится как обычно.
const KITS := [
	{"id": "cards", "title": "Карточная", "game": "Дюжина короля", "layout": "cards", "background": "game:k12_leather", "look": "tavern", "buttons": "wood",
		"deck": {"kind": "playing", "count": 36}, "back": "diamonds", "rules": ["draw_play", "deck_end"]},
	{"id": "dice", "title": "Кубики на очки", "game": "Перудо", "layout": "dice", "background": "game:k12_planks", "look": "tavern", "buttons": "wood",
		"dice": {"title": "5 белых d6", "count": 5, "color": "#ffffff", "pips": "#202020", "faces": "dots", "visible": "all"}, "rules": ["dice_points", "goal_points"]},
	{"id": "words", "title": "Слова", "game": "Опасные слова", "layout": "words", "background": "game:dw_room", "look": "noir", "buttons": "noir",
		"deck": {"kind": "rows", "face": "word", "rows": ["Замок", "Дракон", "Факел", "Сундук", "Ловушка", "Карта", "Ключ", "Призрак", "Зелье", "Корона", "Мост", "Пещера", "Рыцарь", "Меч", "Щит", "Башня", "Колодец", "Лабиринт", "Сокровище", "Гоблин", "Свиток", "Фонарь", "Компас", "Руна", "Тролль", "Ворон", "Лестница", "Цепь", "Котёл", "Маска", "Кинжал", "Плащ", "Подземелье", "Алтарь", "Паук", "Скелет", "Трон", "Арка", "Портал", "Амулет"]}, "back": "cross", "rules": ["draw_play", "deck_end"]},
	{"id": "roles", "title": "Ведущий и роли", "game": "Кровь на часовой башне", "layout": "roles", "background": "game:botc_night", "look": "noir", "buttons": "noir",
		"deck": {"kind": "roles", "face": "role", "rows": [["Мирный житель", "Голосует днём", 4], ["Мафия", "Ночью выбирает жертву", 2], ["Доктор", "Ночью спасает одного", 1], ["Шериф", "Ночью проверяет одного", 1]]}, "back": "stripes", "rules": ["leader_out"]},
	{"id": "market", "title": "Рынок", "game": "Мачи Коро", "layout": "market", "background": "game:machi_day", "look": "kids", "buttons": "pill",
		"deck": {"kind": "market", "face": "cost", "rows": [["Пекарня", 1, "+1 монета в свой ход"], ["Ферма", 1, "+1 монета каждому"], ["Кафе", 2, "Забирает монету у бросившего"], ["Лавка", 2, "+3 монеты в свой ход"], ["Рынок", 3, "+2 монеты за каждую ферму"], ["Шахта", 6, "+5 монет"]]},
		"back": "dots", "coins": true, "rules": ["draw_play", "goal_points", "deck_end"]},
	{"id": "party", "title": "Неоновая вечеринка", "game": "Hues and Cues", "layout": "grid", "background": "preset:neon", "look": "neon", "buttons": "neon",
		"deck": {"kind": "rows", "face": "word", "rows": ["Луна", "Кофе", "Ракета", "Гитара", "Пицца", "Кактус", "Робот", "Радуга", "Волна", "Звезда", "Котик", "Неон", "Диско", "Пляж", "Арбуз", "Сёрфинг", "Комета", "Фламинго", "Коктейль", "Лазер", "Караоке", "Пончик", "Пальма", "Кассета", "Ролики", "Жвачка", "Сияние", "Вулкан", "Медуза", "Дракон", "Облако", "Фейерверк", "Мороженое", "Акула", "Глобус", "Магнит", "Фонарик", "Попугай", "Батут", "Неон 2"]}, "back": "stripes", "rules": ["draw_play", "deck_end"]},
]

static func kit(id: String) -> Dictionary:
	return entry_of(KITS, id)

## Собрать игру по набору поверх данных проекта (сохранённого: картинки кладутся в его ассеты).
## Возвращает {data, error}; ошибка картинки (например, игры нет в сборке) не мешает остальному.
static func apply_kit(data: Dictionary, id: String) -> Dictionary:
	var spec := kit(id)
	if spec.is_empty():
		return {"data": data, "error": "Неизвестный шаблон игры."}
	# Новая игра: стол только из шаблона (зоны пустого проекта не занимают чужие места — колода не встанет в поле 5×5).
	var start: Dictionary = data.duplicate(true)
	start.layout["screens"] = [{"id": "main", "items": []}]
	var copy: Dictionary = apply_layout(start, str(spec.layout))
	copy.meta["title"] = str(spec.title)
	# Раздача по 5 карт: колоды наборов рассчитаны до 6 игроков.
	copy.meta["players"] = [2, 6] if spec.has("deck") and "draw_play" in spec.get("rules", []) else [2, 8]
	var note := ""
	if spec.has("deck"):
		var zone := _ensure_zone(copy, "shared", "pile", "draw", "Колода", false)
		var decks: Array = copy.elements.get("decks", [])
		var deck := {"id": "deck_%d" % (decks.size() + 1), "title": "Колода", "size": 3, "zone": zone, "columns": [], "rows": []}
		var deck_spec: Dictionary = spec.deck
		match str(deck_spec.kind):
			"playing":
				deck = playing_deck(deck, int(deck_spec.count))
			"rows":
				deck.rows = deck_spec.rows.map(func(word: String): return {"word": word, "copies": 1})
				deck = apply_face(deck, str(deck_spec.face))
			"roles":
				deck.title = "Роли"
				deck.rows = deck_spec.rows.map(func(row: Array): return {"role": row[0], "ability": row[1], "art": "", "copies": row[2]})
				deck = apply_face(deck, str(deck_spec.face))
			"market":
				deck.title = "Рынок"
				deck.rows = deck_spec.rows.map(func(row: Array): return {"title": row[0], "cost": row[1], "text": row[2], "art": "", "copies": 6})
				deck = apply_face(deck, str(deck_spec.face))
		decks.append(deck)
		copy.elements["decks"] = decks
		if spec.has("back"):
			var back := apply_back(copy, decks.size() - 1, "drawn", str(spec.back))
			if str(back.error).is_empty():
				copy = back.data
			else:
				note = str(back.error)
	if spec.has("dice"):
		var dice: Array = copy.elements.get("dice", [])
		var entry: Dictionary = spec.dice.duplicate(true)
		entry["id"] = "dice_%d" % (dice.size() + 1)
		entry["free"] = true
		dice.append(entry)
		copy.elements["dice"] = dice
	if spec.get("coins", false):
		var tokens: Array = copy.elements.get("tokens", [])
		var table := _ensure_zone(copy, "shared", "row", "table", "Стол")
		for coin: Array in [[1, "#d9a441", 10], [5, "#b8c4cc", 6], [10, "#e0b84e", 4]]:
			tokens.append({"id": "token_%d" % (tokens.size() + 1), "title": "Монета %d" % coin[0], "value": coin[0], "color": coin[1], "count": coin[2], "shape": "circle", "zone": table, "free": true})
		copy.elements["tokens"] = tokens
	for rule_id: String in spec.get("rules", []):
		copy = apply_rules(copy, rule_id)
	# Кнопки раскладки без цепочки правил были бы выключены всегда — убираем; место главной получает кнопка правил.
	var actions := {}
	for chain: Dictionary in copy.rules.get("chains", []):
		if chain.get("event", {}).get("type") == "button":
			actions[str(chain.event.get("id", ""))] = true
	var main_rect: Variant = null
	var kept: Array = []
	for item: Dictionary in copy.layout.screens[0].items:
		if item.get("kind") == "button" and not actions.has(str(item.get("action", item.get("id", "")))):
			if item.get("main", false):
				main_rect = item.rect
			continue
		kept.append(item)
	if main_rect != null and not kept.any(func(item: Dictionary): return item.get("kind") == "button" and item.get("main", false)):
		for item: Dictionary in kept:
			if item.get("kind") == "button":
				item["rect"] = main_rect
				item["main"] = true
				break
	copy.layout.screens[0]["items"] = kept
	# Зоны ведут правила (без ручных «Взять → …» и «Перемешать»), счётчики показывают «Очки».
	var score := _ensure_score(copy)
	for item: Dictionary in copy.layout.screens[0].items:
		if item.get("kind") == "zone":
			item["free"] = false
		elif item.get("kind") == "counter" and str(item.get("var", "")).is_empty():
			item["var"] = score
			item["title"] = "Очки"
	var look: Dictionary = entry_of(LOOKS, str(spec.get("look", "")))
	var buttons: Dictionary = entry_of(BUTTON_STYLES, str(spec.get("buttons", "")))
	if not look.is_empty():
		copy.meta["look"] = {"main": str(look.main), "accent": str(look.accent), "font": str(look.get("font", ""))}
		if not buttons.is_empty():
			copy.meta.look["buttons"] = buttons.buttons.duplicate()
	var background := str(spec.get("background", ""))
	var result := {"data": copy, "error": ""}
	if background.begins_with("game:") and ResourceLoader.exists(str(entry_of(GAME_BACKGROUNDS, background.trim_prefix("game:")).get("path", ""))):
		result = apply_game_background(copy, background.trim_prefix("game:"))
	elif background.begins_with("preset:"):
		result = apply_background(copy, background.trim_prefix("preset:"))
	if not str(result.error).is_empty():
		note = str(result.error)
		result.data = copy
	result.error = note
	return result
