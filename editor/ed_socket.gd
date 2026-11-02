extends VBoxContainer
## Типизированное гнездо блока. Значения собираются контролами, JSON/код пользователю вводить не нужно.

signal edited(value: Variant)
const Style := preload("res://games/custom/ui/cg_style.gd")
var definition: Dictionary
var kind := "number"
var value: Variant
var depth := 0

func setup(type: String, initial: Variant, data: Dictionary, nesting: int = 0) -> void:
	kind = type
	value = initial.duplicate(true) if initial is Dictionary or initial is Array else initial
	definition = data
	depth = nesting
	add_theme_constant_override("separation", 8)
	_build()

func _emit(next: Variant, rebuild: bool = false) -> void:
	value = next.duplicate(true) if next is Dictionary or next is Array else next
	edited.emit(value)
	if rebuild:
		_build.call_deferred()

func _put(key: String, next: Variant) -> void:
	var copy: Dictionary = value.duplicate(true) if value is Dictionary else {}
	copy[key] = next
	_emit(copy)

func _select(labels: Array, values: Array, selected: Variant, callback: Callable) -> void:
	var menu := OptionButton.new()
	menu.custom_minimum_size.y = 40
	menu.size_flags_horizontal = SIZE_EXPAND_FILL
	for text: String in labels:
		menu.add_item(text)
	menu.select(maxi(0, values.find(selected)))
	menu.item_selected.connect(func(index: int): callback.call(values[index]))
	add_child(menu)

func _nested(type: String, key: String, fallback: Variant) -> void:
	var socket = load("res://editor/ed_socket.gd").new()
	add_child(socket)
	socket.setup(type, value.get(key, fallback), definition, depth + 1)
	socket.edited.connect(func(next: Variant): _put(key, next))

func _build() -> void:
	Style.clear(self)
	if depth > 6:
		add_child(Style.label("Глубокое выражение · замените внешнее гнездо для изменения"))
		return
	if kind == "string":
		var raw := LineEdit.new()
		raw.text = str(value if value != null else "")
		raw.max_length = 4096
		raw.text_changed.connect(func(text: String): _emit(text))
		add_child(raw)
		return
	if kind == "value":
		var selected := "bool" if value is bool else ("text" if value is String or value is Dictionary and value.get("op") == "dictionary_word" else "number")
		_select(["Число / выражение", "Текст", "Да / нет"], ["number", "text", "bool"], selected, func(next: String): _emit(0 if next == "number" else (false if next == "bool" else ""), true))
		var inner = load("res://editor/ed_socket.gd").new()
		add_child(inner)
		inner.setup(selected, value, definition, depth + 1)
		inner.edited.connect(func(next: Variant): _emit(next))
		return
	if kind == "text":
		var op := str(value.get("op", "literal")) if value is Dictionary else "literal"
		var labels: Array = ["Текст", "Текст из переменной", "Ответ игрока"]
		var modes: Array = ["literal", "var", "answer"]
		if definition.get("rules", {}).get("dictionary", "") == "shared":
			labels.append("Случайное слово · 1000 слов")
			modes.append("dictionary_word")
		_select(labels, modes, op, func(next: String):
			_emit("" if next == "literal" else {"op": next, "id": "", "player": {"op": "actor"}}, true))
		if op == "var":
			_nested("variable_text", "id", "")
			_nested("player", "player", {"op": "actor"})
			return
		if op in ["answer", "dictionary_word"]:
			return
		var field := LineEdit.new()
		field.text = str(value.get("value", "")) if value is Dictionary else str(value if value != null else "")
		field.max_length = 4096
		field.text_changed.connect(func(text: String): _emit(text))
		add_child(field)
		return
	if kind == "options":
		var field := TextEdit.new()
		field.custom_minimum_size.y = 120
		field.text = "\n".join(value) if value is Array else "Да\nНет"
		field.text_changed.connect(func(): _emit(Array(field.text.split("\n", false))))
		add_child(Style.label("Один вариант на строке"))
		add_child(field)
		return
	if kind in ["zone", "variable", "variable_number", "variable_bool", "variable_text", "phase", "player", "audience"]:
		_entity()
		return
	if kind == "card":
		var op := str(value.get("op", "card")) if value is Dictionary else "card"
		_select(["Эта карта", "Верхняя карта зоны", "Выбранная карта"], ["card", "top", "answer"], op, func(next: String): _emit({"op": next, "zone": _first_zone()}, true))
		if op == "top":
			_nested("zone", "zone", _first_zone())
		return
	if kind == "bool":
		_boolean()
	else:
		_number()

func _entity() -> void:
	var labels: Array = []
	var values: Array = []
	match kind:
		"player", "audience":
			labels = ["Действующий игрок", "Сейчас ходит", "Ведущий", "Следующий", "Команда действующего"]
			values = [{"op": "actor"}, {"op": "current"}, {"op": "leader"}, {"op": "next"}, {"op": "team", "player": {"op": "actor"}}]
			for seat in 8:
				labels.append("Игрок %d" % (seat + 1))
				values.append(seat)
			var vars: Array = definition.rules.get("vars", [])
			var resource := str(vars[0].id) if not vars.is_empty() else ""
			var from_resource := {"op": "var", "id": resource, "player": {"op": "actor"}}
			if value is Dictionary and value.get("op") == "var":
				from_resource = value.duplicate(true)
			labels.append("Игрок из ресурса")
			values.append(from_resource)
			if kind == "audience":
				labels.append("Все")
				values.append("all")
		"phase":
			for phase: String in definition.rules.get("phases", []):
				values.append(phase)
				labels.append(str(definition.meta.get("phase_titles", {}).get(phase, phase)))
		"variable", "variable_number", "variable_bool", "variable_text":
			for entry: Dictionary in definition.rules.get("vars", []):
				if kind != "variable" and kind.trim_prefix("variable_") != str(entry.get("type", "number")):
					continue
				values.append(str(entry.id))
				labels.append(str(entry.get("title", entry.id)))
		"zone":
			for screen: Dictionary in definition.layout.get("screens", []):
				for item: Dictionary in screen.get("items", []):
					if item.get("kind") != "zone":
						continue
					var expression := {"op": "zone", "id": str(item.id)}
					if item.get("owner") == "player":
						expression["player"] = {"op": "actor"}
					elif item.get("owner") == "team":
						expression["team"] = {"op": "team", "player": {"op": "actor"}}
					values.append(expression)
					labels.append(str(item.get("title", item.id)))
	var selected: Variant = value
	if kind == "zone":
		var id := str(value.get("id", "")) if value is Dictionary else str(value)
		for expression: Dictionary in values:
			if expression.id == id:
				selected = expression
				break
	if values.is_empty():
		add_child(Style.label("Сначала добавьте нужный элемент / ресурс."))
		return
	_select(labels, values, selected, func(next: Variant): _emit(next, true))
	if kind in ["player", "audience"] and value is Dictionary and value.get("op") == "var":
		_nested("variable", "id", "")
		_nested("player", "player", {"op": "actor"})
	if kind == "zone" and value is Dictionary and value.has("player"):
		add_child(Style.label("Чья зона"))
		_nested("player", "player", {"op": "actor"})

func _number() -> void:
	var op := str(value.get("op", "constant")) if value is Dictionary else "constant"
	var names := ["Число", "Ресурс", "Свойство карты", "Карт в зоне", "Сумма кубиков", "Число выпавших граней", "Игроков", "Номер раунда", "Номер хода", "Ответ", "+", "−", "×", "÷", "Случайное число"]
	var modes := ["constant", "var", "property", "count", "dice_sum", "dice_count", "players_count", "round", "turn", "answer", "add", "sub", "mul", "div", "random"]
	_select(names, modes, op, func(next: String):
		if next == "constant":
			_emit(0, true)
		else:
			var expression := {"op": next}
			if next in ["add", "sub", "mul", "div", "random"]:
				expression.merge({"a": 0, "b": 1})
			elif next == "count":
				expression["zone"] = _first_zone()
			elif next == "property":
				expression.merge({"card": {"op": "card"}, "field": "rank"})
			elif next == "var":
				var vars: Array = definition.rules.get("vars", [])
				expression.merge({"id": str(vars[0].id) if not vars.is_empty() else "", "player": {"op": "actor"}})
			elif next == "dice_count":
				expression["face"] = 1
			_emit(expression, true))
	match op:
		"constant":
			var number := SpinBox.new()
			number.min_value = -999999999
			number.max_value = 999999999
			number.step = 0.1
			number.value = float(value) if value is int or value is float else 0
			number.value_changed.connect(func(next: float): _emit(next))
			add_child(number)
		"var":
			_nested("variable_number", "id", "")
			_nested("player", "player", {"op": "actor"})
		"property":
			var field := LineEdit.new()
			field.placeholder_text = "Свойство карты"
			field.text = str(value.get("field", "rank"))
			field.text_changed.connect(func(text: String): _put("field", text))
			add_child(field)
			_nested("card", "card", {"op": "card"})
		"count": _nested("zone", "zone", _first_zone())
		"dice_count": _nested("number", "face", 1)
		"add", "sub", "mul", "div", "random":
			add_child(Style.label("Первое значение"))
			_nested("number", "a", 0)
			add_child(Style.label("Второе значение"))
			_nested("number", "b", 1)

func _boolean() -> void:
	var op := str(value.get("op", "eq")) if value is Dictionary else ("true" if bool(value) else "false")
	_select(["Да", "Нет", "Флаг из переменной", "Равно", "Не равно", "Меньше", "Не больше", "Больше", "Не меньше", "И", "ИЛИ", "НЕ"], ["true", "false", "var", "eq", "ne", "lt", "le", "gt", "ge", "and", "or", "not"], op, func(next: String):
		if next in ["true", "false"]:
			_emit(next == "true", true)
		elif next == "var":
			_emit({"op": "var", "id": "", "player": {"op": "actor"}}, true)
		else:
			_emit({"op": next, "a": true if next in ["and", "or", "not"] else 0, "b": true if next in ["and", "or"] else 0}, true))
	if op == "var":
		_nested("variable_bool", "id", "")
		_nested("player", "player", {"op": "actor"})
	elif op not in ["true", "false"]:
		var type := "bool" if op in ["and", "or", "not"] else ("value" if op in ["eq", "ne"] else "number")
		_nested(type, "a", true if type == "bool" else 0)
		if op != "not":
			_nested(type, "b", true if type == "bool" else 0)

func _first_zone() -> Variant:
	for screen: Dictionary in definition.layout.get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "zone":
				return {"op": "zone", "id": str(item.id)}
	return ""
