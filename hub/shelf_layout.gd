class_name ShelfLayout
extends RefCounted
## Личная раскладка шкафа: какие коробки на какой полке и в каком порядке (слева направо).
## Коробки стоят впритык, поэтому полка — просто список id; влезает ли — по сумме толщин.
## Хранится локально у игрока (user://shelf_layout.cfg), пати не синхронизирует.
## Проверка: godot --headless --path . --script res://tests/test_shelf_layout.gd

const FILE := "user://shelf_layout.cfg"


## Суммарная толщина коробок полки.
static func row_width(ids: Array, widths: Dictionary) -> float:
	var w := 0.0
	for id in ids:
		w += float(widths.get(id, 0.0))
	return w


## Влезает ли полка в свою ширину.
static func fits(ids: Array, widths: Dictionary, limit: float) -> bool:
	return row_width(ids, widths) <= limit + 0.0005


## Куда вставить коробку с центром x в ряд, где центры остальных — centers (по возрастанию).
static func insert_index(centers: Array, x: float) -> int:
	var i := 0
	for c in centers:
		if float(c) < x:
			i += 1
	return i


## Стопка — единая группа: слева открываем щель перед ней, справа — после неё.
## Считаем по центрам стопок без переносимой коробки, чтобы предпросмотр не менял сам себя.
static func pile_insert_index(piles: Array, ids: Array, x: float) -> int:
	for pile: Dictionary in piles:
		if x <= float(pile.x) + float(pile.width) * 0.5:
			return ids.find(pile.ids[0])
	return ids.size()


## Сохранённая раскладка или раскладка по умолчанию, если сохранённая устарела/не влезает.
## Новые игры (их нет в сохранении) дописываются в конец своей полки по умолчанию.
static func load_rows(default_rows: Array, widths: Dictionary, limits: Array, path: String = FILE) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default_rows.duplicate(true)
	var saved = cfg.get_value("shelf", "rows", [])
	if not saved is Array or (saved as Array).size() != default_rows.size():
		return default_rows.duplicate(true)
	var rows: Array = []
	var seen := {}
	for r in default_rows.size():
		var row: Array = []
		if not saved[r] is Array:
			return default_rows.duplicate(true)
		for id in saved[r]:
			var key := str(id)
			if widths.has(key) and not seen.has(key):  # удалённые игры и повторы — пропускаем
				row.append(key)
				seen[key] = true
		rows.append(row)
	for r in default_rows.size():
		for id in default_rows[r]:
			if not seen.has(id):
				rows[r].append(id)
				seen[id] = true
	for r in rows.size():
		if not fits(rows[r], widths, float(limits[r])):
			return default_rows.duplicate(true)  # коробки стали толще — шкаф не ломаем
	return rows


static func save_rows(rows: Array, path: String = FILE) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("shelf", "rows", rows)
	return cfg.save(path)
