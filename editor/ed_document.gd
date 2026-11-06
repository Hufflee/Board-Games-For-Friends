class_name EDDocument
extends RefCounted
## Модель редактора: команды/undo200, проверка, сохранение полноценной игры и незавершённого черновика.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Definition := preload("res://games/custom/logic/cg_def.gd")
const LIMIT := 200
var data: Dictionary = {}
var dirty := false
var last_error := ""
var draft := false
var undo_stack: Array = []
var redo_stack: Array = []
var _audit: Dictionary = {}

static func blank() -> Dictionary:
	return {"format": 1, "meta": {"title": "Новая игра", "players": [2, 8], "time": "", "description": "", "phase_titles": {"turn": "Ход"}},
		"box": {"template": "square", "thickness": 0.06, "faces": {}}, "assets": {},
		"elements": {"decks": [], "dice": [], "tokens": []},
		"layout": {"screens": [{"id": "main", "items": [
			{"kind": "zone", "id": "draw", "title": "Колода", "owner": "shared", "view": "pile", "free": true},
			{"kind": "zone", "id": "hand", "title": "Ваша рука", "owner": "player", "view": "fan", "free": true},
			{"kind": "zone", "id": "table", "title": "Стол", "owner": "shared", "view": "row", "free": true}]}]},
		"rules": {"roles": [{"id": "leader", "name": "Ведущий"}, {"id": "player", "name": "Игрок"}], "vars": [], "phases": ["turn"], "chains": []}}

func create(template: String = "blank") -> bool:
	var initial := blank()
	if template in ["card_race", "higher_lower", "dice_bid"]:
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string("res://games/custom/examples/%s.json" % template)) != OK:
			last_error = "Не удалось открыть шаблон."
			return false
		initial = parser.data
	if not initial.has("assets"):
		initial.assets = {}
	var result := Library.create(initial)
	last_error = str(result.error)
	if not last_error.is_empty():
		return false
	data = result.definition
	_clear_history()
	return true

func open(id: String) -> bool:
	data = Library.load_game(id)
	if data.is_empty():
		last_error = "Не удалось прочитать игру."
		return false
	if not data.has("assets"):
		data.assets = {}
	_clear_history()
	var path := Library.folder(id) + "/draft.json"
	if FileAccess.file_exists(path):
		last_error = "Черновик повреждён. Открыта последняя сохранённая игра."
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= 1024 * 1024:
			var parser := JSON.new()
			if parser.parse(file.get_as_text()) == OK and parser.data is Dictionary:
				var copy: Dictionary = parser.data
				var structure: bool = Definition._json_only(copy, 0) and copy.get("id") == id
				for section: String in ["meta", "elements", "layout", "rules"]:
					structure = structure and copy.get(section) is Dictionary
				if structure:
					structure = copy.layout.get("screens", []) is Array and copy.elements.get("decks", []) is Array and copy.rules.get("vars", []) is Array and copy.rules.get("chains", []) is Array
				if structure:
					structure = _editable_structure(copy)
				if structure:
					data = copy
					draft = true
					last_error = ""
	return true

static func _editable_structure(copy: Dictionary) -> bool:
	if not copy.get("assets", {}) is Dictionary:
		return false
	for entry: Variant in copy.get("assets", {}).values():
		if not entry is Dictionary or not entry.get("path") is String:
			return false
	if copy.has("box") and (not copy.box is Dictionary or not Definition.box_valid(copy.box) or not Definition._number(copy.box.get("thickness", 0.06)) or copy.box.get("template", "square") not in ["square", "tall", "wide", "small"]):
		return false
	for key: String in ["phase_titles", "action_titles"]:
		if copy.meta.has(key) and not copy.meta[key] is Dictionary:
			return false
	var phases: Variant = copy.rules.get("phases")
	if not phases is Array or phases.is_empty():
		return false
	for phase: Variant in phases:
		if not phase is String:
			return false
	var roles: Variant = copy.rules.get("roles", [])
	if not roles is Array:
		return false
	for role: Variant in roles:
		if not role is Dictionary or not role.get("id") is String or not role.get("name", "") is String:
			return false
	var players: Variant = copy.meta.get("players", [])
	if not players is Array or players.size() != 2 or not Definition._number(players[0]) or not Definition._number(players[1]):
		return false
	for screen: Variant in copy.layout.get("screens", []):
		if not screen is Dictionary or not screen.get("items", []) is Array:
			return false
		for item: Variant in screen.get("items", []):
			if not item is Dictionary:
				return false
			if item.has("rect"):
				if not item.rect is Array or item.rect.size() != 4:
					return false
				for coordinate: Variant in item.rect:
					if not Definition._number(coordinate):
						return false
	for deck: Variant in copy.elements.get("decks", []):
		if not deck is Dictionary or not deck.get("rows", []) is Array or not deck.get("columns", []) is Array or not Definition._number(deck.get("size", 3)):
			return false
		for row: Variant in deck.get("rows", []):
			if not row is Dictionary or not Definition._number(row.get("copies", 1)):
				return false
		for column: Variant in deck.get("columns", []):
			if not column is Dictionary:
				return false
	for kind: String in ["dice", "tokens"]:
		if not copy.elements.get(kind, []) is Array:
			return false
		for entry: Variant in copy.elements.get(kind, []):
			if not entry is Dictionary or not Definition._number(entry.get("count", 1)):
				return false
			if kind == "tokens" and not Definition._number(entry.get("value", 1)):
				return false
	for entry: Variant in copy.rules.get("vars", []):
		if not entry is Dictionary:
			return false
		if entry.get("type", "number") == "number" and not Definition._number(entry.get("init", 0)):
			return false
	for chain: Variant in copy.rules.get("chains", []):
		if not chain is Dictionary or not chain.get("event", {}) is Dictionary or not chain.get("blocks", []) is Array:
			return false
		for block: Variant in chain.get("blocks", []):
			if not block is Dictionary:
				return false
	return true

func _clear_history() -> void:
	undo_stack.clear()
	redo_stack.clear()
	dirty = false
	draft = false
	last_error = ""
	_audit = {}

func replace(copy: Dictionary, label: String) -> bool:
	if data.is_empty() or copy.get("id") != data.get("id") or not Definition._json_only(copy, 0):
		return false
	if JSON.stringify(copy) == JSON.stringify(data):
		return false
	undo_stack.append({"data": data.duplicate(true), "label": label})
	while undo_stack.size() > LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()
	data = copy.duplicate(true)
	_audit = {}
	dirty = true
	return true

func set_value(path: Array, value: Variant, label: String = "Изменение") -> bool:
	if path.is_empty() or path[0] == "id":
		return false
	var copy := data.duplicate(true)
	var target: Variant = copy
	for index in path.size() - 1:
		var key: Variant = path[index]
		if target is Dictionary and target.has(key):
			target = target[key]
		elif target is Array and key is int and key >= 0 and key < target.size():
			target = target[key]
		else:
			return false
	var key: Variant = path.back()
	if target is Dictionary and key is String:
		target[key] = value
	elif target is Array and key is int and key >= 0 and key < target.size():
		target[key] = value
	else:
		return false
	return replace(copy, label)

func undo() -> bool:
	return _step(undo_stack, redo_stack)

func redo() -> bool:
	return _step(redo_stack, undo_stack)

func _step(from: Array, to: Array) -> bool:
	if from.is_empty():
		return false
	var entry: Dictionary = from.pop_back()
	to.append({"data": data.duplicate(true), "label": entry.label})
	data = entry.data.duplicate(true)
	_audit = {}
	dirty = true
	return true

func issues() -> Dictionary:
	if not _audit.is_empty():
		return _audit.duplicate(true)
	_audit = Definition.validate(data)
	if not _audit.errors.is_empty():
		return _audit.duplicate(true)
	for screen: Dictionary in data.layout.get("screens", []):
		var items: Array = screen.get("items", [])
		for first in items.size():
			if items[first].get("kind") != "zone":
				continue
			for second in range(first + 1, items.size()):
				if items[second].get("kind") != "zone":
					continue
				var a: Dictionary = items[first]
				var b: Dictionary = items[second]
				var av: Variant = a.get("visible", ["all"])
				var bv: Variant = b.get("visible", ["all"])
				if av is Array and bv is Array and not av.has("all") and not bv.has("all") and not av.any(func(value: Variant): return bv.has(value)):
					continue
				if layout_rect(a, first).grow(-1).intersects(layout_rect(b, second).grow(-1)):
					_audit.warnings.append("Зоны «%s» и «%s» перекрываются." % [str(a.get("title", a.id)).left(64), str(b.get("title", b.id)).left(64)])
					if _audit.warnings.size() >= 20:
						return _audit.duplicate(true)
	return _audit.duplicate(true)

static func layout_rect(item: Dictionary, index: int) -> Rect2:
	var raw: Variant = item.get("rect", [])
	if raw is Array and raw.size() == 4:
		return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	if item.get("owner") == "player":
		return Rect2(288, 400, 704, 192)
	if item.get("id") == "table":
		return Rect2(720, 176, 368, 200)
	return Rect2(176 + (index % 2) * 400, 176 + (index / 2) * 96, 368, 200)

func save() -> bool:
	if data.is_empty() or not Library.uuid_valid(str(data.get("id", ""))):
		last_error = "Сначала создайте или откройте проект."
		return false
	var check := issues()
	var path := Library.folder(str(data.id)) + "/draft.json"
	if not check.errors.is_empty():
		var bytes := JSON.stringify(data, "\t").to_utf8_buffer()
		if bytes.size() > 1024 * 1024 or Library._atomic_write(path, bytes) != OK:
			last_error = "Не удалось сохранить черновик."
			return false
		draft = true
	else:
		var result := Library.save(str(data.id), data)
		if not str(result.error).is_empty():
			last_error = str(result.error)
			return false
		data = result.definition
		_audit = {}
		draft = false
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	dirty = false
	last_error = ""
	return true

## single = true — элемент «Карта»: одна карта без таблицы, с теми же шаблоном, цветом и размером.
func add_deck(single: bool = false) -> String:
	var copy := data.duplicate(true)
	if copy.layout.get("screens", []).is_empty():
		copy.layout["screens"] = [{"id": "main", "items": []}]
	for zone: Dictionary in blank().layout.screens[0].items:
		if not copy.layout.screens[0].items.any(func(item: Dictionary): return item.get("kind") == "zone" and item.get("id") == zone.id):
			copy.layout.screens[0].items.append(zone.duplicate(true))
	var decks: Array = copy.elements.get("decks", [])
	var number := 1
	while decks.any(func(deck: Dictionary): return deck.id == "deck_%d" % number):
		number += 1
	var id := "deck_%d" % number
	var deck := {"id": id, "title": "Новая колода", "size": 3, "zone": "draw", "columns": [{"id": "title", "type": "text"}],
		"rows": [{"title": "Новая карта", "copies": 1}]}
	if single:
		deck.merge({"title": "Карта", "single": true, "zone": "table" if _has_zone(copy, "table") else "draw",
			"columns": [{"id": "title", "type": "text"}, {"id": "text", "type": "text"}],
			"rows": [{"title": "Карта", "text": "", "copies": 1}]}, true)
	decks.append(deck)
	copy.elements.decks = decks
	replace(copy, "Добавить карту" if single else "Добавить колоду")
	return id

static func _has_zone(definition: Dictionary, zone_id: String) -> bool:
	for item: Dictionary in definition.layout.screens[0].get("items", []):
		if item.get("kind") == "zone" and item.get("id") == zone_id and item.get("owner", "shared") == "shared":
			return true
	return false
