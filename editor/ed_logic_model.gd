class_name EDLogicModel
extends RefCounted
## Команды визуальных правил: шапки, блоки, ветви, порядок и фазы. Изменения идут через общий undo.

const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
var document: RefCounted

func _init(doc: RefCounted) -> void:
	document = doc

func set_turn_mode(mode: String) -> bool:
	if mode not in Blocks.TURN_MODES:
		return false
	return document.set_value(["rules", "turn_mode"], mode, "Порядок ходов")

static func at(data: Dictionary, path: Array) -> Variant:
	var current: Variant = data
	for key: Variant in path:
		if current is Dictionary and current.has(key):
			current = current[key]
		elif current is Array and key is int and key >= 0 and key < current.size():
			current = current[key]
		else:
			return null
	return current

func add_event(kind: String) -> int:
	if kind not in Blocks.EVENTS:
		return -1
	var copy: Dictionary = document.data.duplicate(true)
	var event := {"type": kind, "by": "all"}
	if kind == "button":
		var id := ""
		for screen: Dictionary in copy.layout.screens:
			for item: Dictionary in screen.get("items", []):
				if item.get("kind") == "button":
					id = str(item.get("action", item.id))
					break
		if id.is_empty():
			id = "action_1"
			if copy.layout.screens.is_empty():
				copy.layout.screens.append({"id": "main", "items": []})
			copy.layout.screens[0].items.append({"kind": "button", "id": id, "action": id, "title": "Действие", "rect": [832, 608, 320, 48]})
			copy.layout["custom"] = true
		event["id"] = id
	elif kind == "card":
		event["zone"] = zone(true)
		event.by = "current"
	elif kind == "move":
		event["from"] = zone(false)
		event["to"] = zone(true)
	elif kind in ["phase_enter", "phase_exit"]:
		event["phase"] = str(copy.rules.phases[0])
	copy.rules.chains.append({"event": event, "guard": true, "blocks": []})
	document.replace(copy, "Добавить событие")
	return copy.rules.chains.size() - 1

func zone(personal: bool, prefer: String = "") -> Variant:
	var fallback: Variant = ""
	for screen: Dictionary in document.data.layout.get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") != "zone":
				continue
			var owner := str(item.get("owner", "shared"))
			if personal != (owner == "player"):
				continue
			var result := {"op": "zone", "id": str(item.id)}
			if personal:
				result["player"] = {"op": "actor"}
			if fallback is String:
				fallback = result
			if str(item.id) == prefer or prefer.is_empty():
				return result
	return fallback

func default_block(op: String) -> Dictionary:
	var actor := {"op": "actor"}
	var card := {"op": "card"}
	var base := {"op": op, "id": "block_" + str(Time.get_ticks_usec())}
	match op:
		"shuffle": base["zone"] = zone(false, "draw")
		"deal", "draw": base.merge({"from": zone(false, "draw"), "to": zone(true), "count": 1})
		"move": base.merge({"card": card, "to": zone(false, "table")})
		"open", "close", "show":
			base["card"] = card
			if op != "close":
				base["for"] = "all"
		"collect": base["to"] = zone(false, "draw")
		"roll", "roll_player": base.merge({"player": actor, "count": 1, "visible": "all"})
		"next": base["player"] = {"op": "next"}
		"phase": base["phase"] = str(document.data.rules.phases[0])
		"skip", "leader", "eliminate", "win": base["player"] = actor
		"ask_card": base.merge({"player": actor, "zone": zone(true)})
		"ask_player": base["player"] = actor
		"ask_option": base.merge({"player": actor, "options": ["Да", "Нет"]})
		"ask_number": base.merge({"player": actor, "min": 0, "max": 10})
		"set", "change", "finish":
			var vars: Array = document.data.rules.get("vars", [])
			var selected: Dictionary = {}
			for entry: Dictionary in vars:
				if op == "set" or entry.get("type", "number") == "number":
					selected = entry
					break
			base["var"] = str(selected.get("id", ""))
			if op != "finish":
				base["value"] = 1 if op == "change" else selected.get("init", 0)
				base["player"] = actor
				if selected.get("scope") == "team":
					base["player"] = {"op": "team", "player": actor}
		"if": base.merge({"condition": true, "then": [], "else": []})
		"repeat": base.merge({"count": 1, "body": []})
		"each_player": base["body"] = []
		"each_card": base.merge({"zone": zone(true), "body": []})
		"wait": base["seconds"] = 1
		"log", "hint": base["text"] = "Сообщение"
		"sound": base["name"] = "click"
	return base

func add_block(op: String, array_path: Array) -> Array:
	if not Blocks.OPS.has(op) or not at(document.data, array_path) is Array:
		return []
	var copy: Dictionary = document.data.duplicate(true)
	var array: Array = at(copy, array_path)
	var block := default_block(op)
	if op in ["set", "change", "finish"] and str(block.get("var", "")).is_empty():
		var used: Array = []
		for entry: Dictionary in copy.rules.vars:
			used.append(str(entry.id))
		var id := "score"
		var number := 1
		while used.has(id):
			id = "score_%d" % number
			number += 1
		copy.rules.vars.append({"id": id, "title": "Очки", "scope": "player", "type": "number", "init": 0})
		block["var"] = id
	array.append(block)
	document.replace(copy, "Добавить блок «%s»" % Blocks.label(op))
	return array_path + [array.size() - 1]

func remove(path: Array) -> bool:
	if path.is_empty() or not path.back() is int:
		return false
	var copy: Dictionary = document.data.duplicate(true)
	var parent: Variant = at(copy, path.slice(0, path.size() - 1))
	if not parent is Array or int(path.back()) < 0 or int(path.back()) >= parent.size():
		return false
	parent.remove_at(int(path.back()))
	return document.replace(copy, "Удалить блок / событие")

func move(path: Array, direction: int) -> Array:
	if path.is_empty() or not path.back() is int:
		return path
	var copy: Dictionary = document.data.duplicate(true)
	var array_path := path.slice(0, path.size() - 1)
	var array: Variant = at(copy, array_path)
	var index := int(path.back())
	var next := index + direction
	if not array is Array or index < 0 or index >= array.size() or next < 0 or next >= array.size():
		return path
	var temp: Variant = array[index]
	array[index] = array[next]
	array[next] = temp
	document.replace(copy, "Порядок блоков")
	return array_path + [next]

func add_phase(title: String) -> String:
	if title.strip_edges().is_empty():
		return ""
	var copy: Dictionary = document.data.duplicate(true)
	var number := 1
	while copy.rules.phases.has("phase_%d" % number):
		number += 1
	var id := "phase_%d" % number
	copy.rules.phases.append(id)
	if not copy.meta.has("phase_titles"):
		copy.meta.phase_titles = {}
	copy.meta.phase_titles[id] = title.strip_edges()
	document.replace(copy, "Добавить фазу")
	return id

func add_variable(title: String, type: String, scope: String) -> String:
	if title.strip_edges().is_empty() or type not in ["number", "bool", "text"] or scope not in ["shared", "player", "team"]:
		return ""
	var copy: Dictionary = document.data.duplicate(true)
	var used: Array = []
	for entry: Dictionary in copy.rules.vars:
		used.append(str(entry.id))
	var number := 1
	while used.has("var_%d" % number):
		number += 1
	var id := "var_%d" % number
	copy.rules.vars.append({"id": id, "title": title.strip_edges(), "type": type, "scope": scope, "init": 0 if type == "number" else (false if type == "bool" else ""), "visible": "all"})
	document.replace(copy, "Добавить переменную")
	return id

func add_role(title: String) -> String:
	if title.strip_edges().is_empty() or document.data.rules.roles.size() >= 16:
		return ""
	var copy: Dictionary = document.data.duplicate(true)
	var used: Array = []
	for entry: Dictionary in copy.rules.roles:
		used.append(str(entry.id))
	var number := 1
	while used.has("role_%d" % number):
		number += 1
	var id := "role_%d" % number
	copy.rules.roles.append({"id": id, "name": title.strip_edges()})
	document.replace(copy, "Добавить роль")
	return id

func rename_phase(id: String, title: String) -> bool:
	if title.strip_edges().is_empty() or not document.data.rules.phases.has(id):
		return false
	var copy: Dictionary = document.data.duplicate(true)
	if not copy.meta.has("phase_titles"):
		copy.meta.phase_titles = {}
	copy.meta.phase_titles[id] = title.strip_edges()
	return document.replace(copy, "Название фазы")

func move_phase(id: String, direction: int) -> bool:
	var copy: Dictionary = document.data.duplicate(true)
	var phases: Array = copy.rules.phases
	var index := phases.find(id)
	var next := index + direction
	if index < 0 or next < 0 or next >= phases.size():
		return false
	phases[index] = phases[next]
	phases[next] = id
	return document.replace(copy, "Порядок фаз")
