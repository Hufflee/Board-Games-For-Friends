extends RefCounted
## Гибридный редактор правил: шапка события и вертикальные цепочки с вложенными гнёздами.

const Style := preload("res://games/custom/ui/cg_style.gd")
const Model := preload("res://editor/ed_logic_model.gd")
const Socket := preload("res://editor/ed_socket.gd")
const Blocks := preload("res://games/custom/logic/cg_blocks.gd")
const Minimap := preload("res://editor/ed_logic_map.gd")
const Canvas := preload("res://editor/ed_logic_canvas.gd")
var app: Control
var document: RefCounted
var model: RefCounted
var tools: VBoxContainer
var center: VBoxContainer
var properties: VBoxContainer
var _palette: VBoxContainer
var _map: Control

func setup(owner: Control, left: VBoxContainer, middle: VBoxContainer, right: VBoxContainer) -> void:
	app = owner
	document = app.document
	model = Model.new(document)
	tools = left
	center = middle
	properties = right
	_build()

func _refresh() -> void:
	app._status_text()
	app._render.call_deferred()

func _selected(button: Button) -> void:
	# Цвет выбранного блока сохраняет контраст с обычным текстом в обеих темах.
	for state: String in ["normal", "hover", "pressed"]:
		var amount := 0.24 if state == "normal" else 0.32
		button.add_theme_stylebox_override(state, Style.box(Style.panel().lerp(Style.accent(), amount)))

func _build() -> void:
	var data: Array = document.data.rules.get("chains", [])
	if app._logic_chain >= data.size():
		app._logic_chain = data.size() - 1
	var event := MenuButton.new()
	event.text = "+ Событие"
	event.custom_minimum_size.y = 40
	for index in Blocks.EVENTS.size():
		event.get_popup().add_item(Blocks.event_label(Blocks.EVENTS[index]), index)
	event.get_popup().id_pressed.connect(func(index: int):
		app._logic_chain = model.add_event(Blocks.EVENTS[index])
		app._logic_path = []
		app._logic_target = []
		_refresh())
	tools.add_child(event)
	tools.add_child(Style.label("Буфер цепочек"))
	app._clipboard_controls(tools, "chain", ["rules", "chains"], app._logic_chain)
	var search := LineEdit.new()
	search.placeholder_text = "Найти блок"
	search.text_changed.connect(_blocks_palette)
	tools.add_child(search)
	_palette = Style.column(8)
	tools.add_child(_palette)
	_blocks_palette("")
	var resources := Style.button("Переменные и роли")
	resources.pressed.connect(_resources)
	tools.add_child(resources)
	center.add_child(Style.heading("ЛОГИКА ИГРЫ"))
	_phases()
	_canvas_tools()
	var workspace := Style.row(8)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(workspace)
	var scroll := ScrollContainer.new()
	scroll.name = "LogicCanvasScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(scroll)
	var chains := Style.column(16)
	chains.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var canvas := Canvas.new()
	scroll.add_child(canvas)
	canvas.setup(chains, app._logic_zoom)
	_map = Minimap.new()
	workspace.add_child(_map)
	_map.setup(scroll, canvas)
	_restore_scroll(scroll, app._logic_scroll)
	if data.is_empty():
		chains.add_child(Style.label("Добавьте событие, затем выберите действия слева."))
	for index in data.size():
		var chain: Dictionary = data[index]
		if not app._logic_phase.is_empty() and chain.get("event", {}).get("phase", "") not in ["", app._logic_phase]:
			continue
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Style.box(Style.panel()))
		var col := Style.column(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(col)
		chains.add_child(panel)
		var hat := Style.button(Blocks.event_label(str(chain.get("event", {}).get("type", ""))))
		hat.pressed.connect(func():
			app._logic_chain = index
			app._logic_path = []
			app._logic_target = []
			_refresh())
		if app._logic_chain == index:
			_selected(hat)
		var header := Style.row(8)
		col.add_child(header)
		var fold := Style.button("▸" if app._logic_collapsed.has(index) else "▾")
		fold.name = "LogicFold%d" % index
		fold.tooltip_text = "Развернуть цепочку" if app._logic_collapsed.has(index) else "Свернуть цепочку"
		fold.custom_minimum_size.x = 40
		fold.pressed.connect(func():
			if app._logic_collapsed.has(index):
				app._logic_collapsed.erase(index)
			else:
				app._logic_collapsed[index] = true
			if app._logic_chain == index:
				app._logic_path = []
				app._logic_target = []
			_refresh())
		header.add_child(fold)
		hat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(hat)
		_map.register(hat, app._logic_chain == index and app._logic_path.is_empty())
		var comment_text := str(chain.get("comment", ""))
		if not comment_text.is_empty():
			var note := PanelContainer.new()
			note.name = "LogicComment%d" % index
			note.add_theme_stylebox_override("panel", Style.box(Style.panel().lerp(Style.accent(), 0.1)))
			var caption := Style.label(comment_text)
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			caption.max_lines_visible = 8
			caption.tooltip_text = comment_text
			note.add_child(caption)
			col.add_child(note)
		if not app._logic_collapsed.has(index):
			_rows(col, ["rules", "chains", index, "blocks"], 0)
	if app._logic_chain < 0:
		properties.add_child(Style.label("Выберите или добавьте событие"))
		return
	var selected: Variant = Model.at(document.data, app._logic_path)
	if not app._logic_path.is_empty() and selected is Dictionary and selected.has("op"):
		_block_properties(selected)
	else:
		_event_properties(data[app._logic_chain])

func _canvas_tools() -> void:
	var row := Style.row(8)
	center.add_child(row)
	for direction: int in [-1, 1]:
		var button := Style.button("−" if direction < 0 else "+")
		button.name = "LogicZoomOut" if direction < 0 else "LogicZoomIn"
		button.tooltip_text = "Уменьшить цепочки" if direction < 0 else "Увеличить цепочки"
		button.custom_minimum_size.x = 40
		button.disabled = app._logic_zoom <= 0.6 if direction < 0 else app._logic_zoom >= 1.5
		button.pressed.connect(func():
			var previous: float = app._logic_zoom
			app._logic_zoom = clampf(snappedf(previous + direction * 0.1, 0.1), 0.6, 1.5)
			app._logic_scroll = roundi(app._logic_scroll * app._logic_zoom / previous)
			_refresh())
		row.add_child(button)
		if direction < 0:
			var reset := Style.button("%d%%" % roundi(app._logic_zoom * 100))
			reset.name = "LogicZoomReset"
			reset.tooltip_text = "Вернуть масштаб 100%"
			reset.pressed.connect(func():
				app._logic_scroll = roundi(app._logic_scroll / app._logic_zoom)
				app._logic_zoom = 1.0
				_refresh())
			row.add_child(reset)

func _restore_scroll(scroll: ScrollContainer, position: int) -> void:
	var restore := {"pending": true, "changed": false}
	# Слушаем сразу: пользователь может прокрутить поле до отложенной раскладки.
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float):
		if scroll.is_inside_tree():
			if bool(restore.pending):
				restore.changed = true
			app._logic_scroll = roundi(value))
	# До раскладки max_value равен нулю и Godot обрезает сохранённую позицию.
	var tree := scroll.get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	if not bool(restore.changed):
		scroll.scroll_vertical = position
	restore.pending = false

func _blocks_palette(query: String) -> void:
	Style.clear(_palette)
	var category := ""
	for op: String in Blocks.OPS:
		var title := Blocks.label(op)
		if not query.strip_edges().is_empty() and not title.to_lower().contains(query.to_lower()):
			continue
		var next := Blocks.category(op)
		if next != category:
			var label := Style.label(next)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_palette.add_child(label)
			category = next
		var button := Style.button(title)
		button.clip_text = true
		button.disabled = document.data.rules.get("chains", []).is_empty()
		button.pressed.connect(func():
			if app._logic_chain < 0:
				app._logic_chain = 0
			var target: Array = app._logic_target if not app._logic_target.is_empty() else ["rules", "chains", app._logic_chain, "blocks"]
			app._logic_path = model.add_block(op, target)
			_refresh())
		_palette.add_child(button)

func _rows(parent: VBoxContainer, path: Array, depth: int) -> void:
	var blocks: Variant = Model.at(document.data, path)
	if not blocks is Array or depth > 16:
		return
	if blocks.is_empty():
		parent.add_child(Style.label("   + Выберите действие слева"))
	for index in mini(200, blocks.size()):
		var block: Variant = blocks[index]
		if not block is Dictionary:
			continue
		var block_path := path + [index]
		var row := Style.row(8)
		row.add_child(Style.label("│"))
		var button := Style.button(Blocks.label(str(block.get("op", ""))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			app._logic_chain = int(block_path[2])
			app._logic_path = block_path.duplicate()
			app._logic_target = path.duplicate()
			_refresh())
		if app._logic_path == block_path:
			_selected(button)
		row.add_child(button)
		_map.register(button, app._logic_path == block_path)
		parent.add_child(row)
		for key: String in ["then", "else", "body"]:
			if not block.has(key):
				continue
			var margin := MarginContainer.new()
			margin.add_theme_constant_override("margin_left", 24)
			parent.add_child(margin)
			var nested := Style.column(8)
			margin.add_child(nested)
			nested.add_child(Style.label({"then": "Если да", "else": "Иначе", "body": "Повторяем"}[key]))
			_rows(nested, block_path + [key], depth + 1)

func _phases() -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	center.add_child(row)
	for phase: String in [""] + document.data.rules.phases:
		var name_value := str(document.data.meta.get("phase_titles", {}).get(phase, phase))
		var button := Style.button("Все фазы" if phase.is_empty() else name_value)
		if phase == app._logic_phase:
			_selected(button)
		button.pressed.connect(func():
			app._logic_phase = phase
			app._logic_scroll = 0
			var chains: Array = document.data.rules.get("chains", [])
			if app._logic_chain >= 0 and app._logic_chain < chains.size() and not phase.is_empty() and chains[app._logic_chain].get("event", {}).get("phase", "") not in ["", phase]:
				app._logic_chain = -1
				app._logic_path = []
				app._logic_target = []
				for index in chains.size():
					if chains[index].get("event", {}).get("phase", "") in ["", phase]:
						app._logic_chain = index
						break
			_refresh())
		row.add_child(button)
	var settings := Style.button("Фазы…")
	settings.name = "LogicPhaseTools"
	settings.tooltip_text = "Добавить, переименовать или переставить фазы"
	settings.pressed.connect(func():
		app._logic_phase_tools = not app._logic_phase_tools
		_refresh())
	row.add_child(settings)
	if not app._logic_phase_tools:
		return
	if not app._logic_phase.is_empty():
		var edit := Style.row(8)
		center.add_child(edit)
		var phase_name := LineEdit.new()
		phase_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		phase_name.text = str(document.data.meta.get("phase_titles", {}).get(app._logic_phase, app._logic_phase))
		edit.add_child(phase_name)
		var rename := Style.button("Переименовать")
		rename.pressed.connect(func():
			model.rename_phase(app._logic_phase, phase_name.text)
			_refresh())
		edit.add_child(rename)
		for direction: int in [-1, 1]:
			var move := Style.button("←" if direction < 0 else "→")
			move.pressed.connect(func():
				model.move_phase(app._logic_phase, direction)
				_refresh())
			edit.add_child(move)
	var add_row := Style.row(8)
	center.add_child(add_row)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Название фазы"
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(name_field)
	var add := Style.button("+ Фаза")
	add.pressed.connect(func():
		if not model.add_phase(name_field.text).is_empty():
			_refresh())
	add_row.add_child(add)

func _enum(caption: String, labels: Array, values: Array, selected: Variant, callback: Callable) -> void:
	properties.add_child(Style.label(caption))
	var menu := OptionButton.new()
	for label: String in labels:
		menu.add_item(label)
	menu.select(maxi(0, values.find(selected)))
	menu.item_selected.connect(func(index: int): callback.call(values[index]))
	properties.add_child(menu)

func _socket(caption: String, path: Array, kind: String, fallback: Variant = null) -> void:
	properties.add_child(Style.label(caption))
	var value: Variant = Model.at(document.data, path)
	var socket := Socket.new()
	properties.add_child(socket)
	socket.setup(kind, fallback if value == null else value, document.data)
	socket.edited.connect(func(next: Variant):
		if kind.begins_with("variable"):
			var copy: Dictionary = document.data.duplicate(true)
			var parent: Variant = Model.at(copy, path.slice(0, path.size() - 1))
			if parent is Dictionary:
				parent[path.back()] = next
				if path.back() == "var" and parent.get("op") == "set":
					for entry: Dictionary in copy.rules.get("vars", []):
						if entry.id != next:
							continue
						var old: Variant = parent.get("value")
						var type := str(entry.get("type", "number"))
						if not old is Dictionary and ((type == "bool" and not old is bool) or (type == "text" and not old is String) or (type == "number" and not (old is int or old is float))):
							parent.value = entry.get("init", 0)
						var owner_value: Variant = parent.get("player", {})
						if owner_value is Dictionary and owner_value.get("op", "") in ["actor", "team"]:
							parent.player = {"op": "team", "player": {"op": "actor"}} if entry.get("scope") == "team" else {"op": "actor"}
				document.replace(copy, caption)
		else:
			document.set_value(path, next, caption)
		app._status_text()
		if kind.begins_with("variable"):
			_refresh())

func _event_properties(chain: Dictionary) -> void:
	var path: Array = ["rules", "chains", app._logic_chain]
	properties.add_child(Style.heading("СОБЫТИЕ"))
	properties.add_child(Style.label("Буфер блоков"))
	app._clipboard_controls(properties, "block", path + ["blocks"], -1)
	var event: Dictionary = chain.get("event", {})
	var labels: Array = ["Все игроки", "Текущий игрок", "Ведущий"]
	var values: Array = ["all", "current", "leader"]
	for role: Dictionary in document.data.rules.get("roles", []):
		if role.id != "leader":
			labels.append(str(role.get("name", role.id)))
			values.append("role:" + str(role.id))
	_enum("Кто может вызвать", labels, values, event.get("by", "all"), func(value: String):
		document.set_value(path + ["event", "by"], value, "Кто вызывает событие")
		app._status_text())
	labels = ["Любая фаза"]
	values = [""]
	for phase: String in document.data.rules.phases:
		values.append(phase)
		labels.append(str(document.data.meta.get("phase_titles", {}).get(phase, phase)))
	_enum("В какой фазе", labels, values, event.get("phase", ""), func(value: String):
		var copy: Dictionary = document.data.duplicate(true)
		var target: Dictionary = Model.at(copy, path + ["event"])
		if value.is_empty():
			target.erase("phase")
		else:
			target.phase = value
		document.replace(copy, "Фаза события")
		app._status_text())
	if event.get("type") == "card":
		_socket("Из какой зоны карта", path + ["event", "zone"], "zone")
	elif event.get("type") == "move":
		_socket("Откуда перенесена", path + ["event", "from"], "zone")
		_socket("Куда перенесена", path + ["event", "to"], "zone")
	elif event.get("type") == "button":
		labels = []
		values = []
		for screen: Dictionary in document.data.layout.screens:
			for item: Dictionary in screen.get("items", []):
				if item.get("kind") == "button":
					labels.append(str(item.get("title", item.id)))
					values.append(str(item.get("action", item.id)))
		if not values.is_empty():
			_enum("Какая кнопка", labels, values, event.get("id", ""), func(value: String):
				document.set_value(path + ["event", "id"], value, "Кнопка события")
				app._status_text())
	_socket("Разрешено, если", path + ["guard"], "bool", true)
	properties.add_child(Style.label("Комментарий к цепочке"))
	var comment := TextEdit.new()
	comment.name = "LogicCommentEditor"
	comment.placeholder_text = "Зачем нужна эта цепочка; что проверить при изменении"
	comment.text = str(chain.get("comment", ""))
	comment.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	comment.custom_minimum_size.y = 128
	properties.add_child(comment)
	var comment_limit := Style.label("До4096символов · не влияет на правила")
	properties.add_child(comment_limit)
	var apply_comment := Style.button("Сохранить комментарий")
	apply_comment.name = "LogicCommentApply"
	apply_comment.disabled = true
	comment.text_changed.connect(func():
		apply_comment.disabled = comment.text == str(chain.get("comment", "")) or comment.text.length() > 4096
		comment_limit.text = "%d / 4096 · не влияет на правила" % comment.text.length())
	apply_comment.pressed.connect(func():
		var copy: Dictionary = document.data.duplicate(true)
		var target: Dictionary = Model.at(copy, path)
		if comment.text.strip_edges().is_empty():
			target.erase("comment")
		else:
			target.comment = comment.text
		document.replace(copy, "Комментарий цепочки")
		_refresh())
	properties.add_child(apply_comment)
	var remove := Style.button("Удалить событие")
	remove.pressed.connect(func():
		model.remove(path)
		app._logic_path = []
		app._logic_target = []
		_refresh())
	properties.add_child(remove)

func _block_properties(block: Dictionary) -> void:
	var path: Array = app._logic_path
	var op := str(block.op)
	properties.add_child(Style.heading(Blocks.label(op)))
	var destination: Array = app._logic_target if not app._logic_target.is_empty() else path.slice(0, path.size() - 1)
	app._clipboard_controls(properties, "block", path.slice(0, path.size() - 1), int(path.back()), destination)
	var order := Style.row()
	for direction: int in [-1, 1]:
		var button := Style.button("↑ Выше" if direction < 0 else "↓ Ниже")
		button.pressed.connect(func():
			app._logic_path = model.move(path, direction)
			_refresh())
		order.add_child(button)
	properties.add_child(order)
	var fields: Array = Blocks.OPS.get(op, []).duplicate()
	for optional: String in ["player", "for", "visible", "mode"]:
		if block.has(optional) and not fields.has(optional):
			fields.append(optional)
	for key: String in fields:
		if key in ["then", "else", "body"]:
			continue
		if op == "sound" and key == "name":
			_enum("Звук", ["Щелчок", "Карта на стол", "Перевернуть карту", "Перемешать", "Жетон", "Выигрыш"], Blocks.SOUNDS, block.get("name", "click"), func(value: String):
				document.set_value(path + ["name"], value, "Встроенный звук")
				app._status_text())
			continue
		var kind := "number"
		var captions := {"zone": "Зона", "from": "Откуда", "to": "Куда", "card": "Карта", "player": "Кто", "for": "Кому", "count": "Количество", "var": "Ресурс", "value": "Значение", "phase": "Фаза", "condition": "Условие", "seconds": "Секунд", "text": "Сообщение", "options": "Варианты", "min": "От", "max": "До", "name": "Название звука", "visible": "Кому виден результат", "mode": "По каким очкам"}
		if key in ["zone", "from", "to"]: kind = "zone"
		elif key in ["card", "phase", "text", "options"]: kind = key
		elif key == "player": kind = "audience" if op == "win" else "player"
		elif key == "for": kind = "audience"
		elif key == "var": kind = "variable_number" if op in ["change", "finish"] else "variable"
		elif key == "condition": kind = "bool"
		elif key in ["name", "visible", "mode"]: kind = "string"
		if key == "value" and op == "set":
			for entry: Dictionary in document.data.rules.get("vars", []):
				if entry.id == block.get("var"):
					kind = str(entry.get("type", "number"))
		_socket(str(captions.get(key, key)), path + [key], kind)
	for key: String in ["then", "else", "body"]:
		if not block.has(key):
			continue
		var enter := Style.button({"then": "+ В ветвь «Да»", "else": "+ В ветвь «Иначе»", "body": "+ Внутрь цикла"}[key])
		enter.pressed.connect(func():
			app._logic_target = path + [key]
			app._message = "Следующее действие будет добавлено в выбранную ветвь."
			_refresh())
		properties.add_child(enter)
	var root := Style.button("К шапке события")
	root.pressed.connect(func():
		app._logic_path = []
		app._logic_target = []
		_refresh())
	properties.add_child(root)
	var remove := Style.button("Удалить блок")
	remove.pressed.connect(func():
		model.remove(path)
		app._logic_path = []
		app._logic_target = []
		_refresh())
	properties.add_child(remove)

func _resources() -> void:
	var popup := Window.new()
	popup.title = "Переменные и роли"
	popup.size = Vector2i(640, 560)
	popup.theme = Style.theme()
	Style.window_surface(popup)
	app.add_child(popup)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -16
	popup.add_child(scroll)
	var col := Style.column(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(Style.heading("ПОРЯДОК ХОДОВ"))
	var turn_mode := OptionButton.new()
	turn_mode.name = "LogicTurnMode"
	for caption: String in ["По кругу", "По кругу от ведущего", "Одновременно · готовность всех", "Только ведущий"]:
		turn_mode.add_item(caption)
	turn_mode.select(maxi(0, Blocks.TURN_MODES.find(str(document.data.rules.get("turn_mode", "circle")))))
	turn_mode.item_selected.connect(func(index: int):
		model.set_turn_mode(Blocks.TURN_MODES[index])
		app._status_text())
	col.add_child(turn_mode)
	var turn_hint := Style.label("В одновременном режиме «Готов» ждёт всех и переключает фазу. Блок «Передать ход» недоступен.")
	turn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(turn_hint)
	col.add_child(Style.heading("ПЕРЕМЕННЫЕ"))
	for index in document.data.rules.vars.size():
		var entry: Dictionary = document.data.rules.vars[index]
		var row := Style.row(8)
		col.add_child(row)
		var title := LineEdit.new()
		title.text = str(entry.get("title", entry.id))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_changed.connect(func(text: String):
			document.set_value(["rules", "vars", index, "title"], text, "Название переменной")
			app._status_text())
		row.add_child(title)
		row.add_child(Style.label({"shared": "Общая", "player": "У игрока", "team": "У команды"}.get(str(entry.get("scope", "shared")), "")))
		var commit := func(value: Variant):
			document.set_value(["rules", "vars", index, "init"], value, "Начальное значение")
			app._status_text()
		match str(entry.get("type", "number")):
			"number":
				var initial := SpinBox.new()
				initial.min_value = -999999999
				initial.max_value = 999999999
				initial.value = float(entry.get("init", 0))
				initial.value_changed.connect(commit)
				col.add_child(initial)
			"bool":
				var initial := CheckBox.new()
				initial.text = "Начальное значение: да"
				initial.button_pressed = bool(entry.get("init", false))
				initial.toggled.connect(commit)
				col.add_child(initial)
			"text":
				var initial := LineEdit.new()
				initial.text = str(entry.get("init", ""))
				initial.max_length = 4096
				initial.text_changed.connect(commit)
				col.add_child(initial)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Название новой переменной"
	col.add_child(name_field)
	var type_field := OptionButton.new()
	for text: String in ["Число", "Да / нет", "Текст"]:
		type_field.add_item(text)
	col.add_child(type_field)
	var scope := OptionButton.new()
	for text: String in ["Общая", "У каждого игрока", "У команды"]:
		scope.add_item(text)
	col.add_child(scope)
	var add := Style.button("Добавить переменную")
	add.pressed.connect(func():
		if not model.add_variable(name_field.text, ["number", "bool", "text"][type_field.selected], ["shared", "player", "team"][scope.selected]).is_empty():
			popup.queue_free()
			_refresh())
	col.add_child(add)
	col.add_child(Style.heading("РОЛИ"))
	for index in document.data.rules.roles.size():
		var role: Dictionary = document.data.rules.roles[index]
		var title := LineEdit.new()
		title.text = str(role.get("name", role.id))
		title.text_changed.connect(func(text: String):
			document.set_value(["rules", "roles", index, "name"], text, "Название роли")
			app._status_text())
		col.add_child(title)
	var role_field := LineEdit.new()
	role_field.placeholder_text = "Название новой роли"
	col.add_child(role_field)
	var add_role := Style.button("Добавить роль")
	add_role.pressed.connect(func():
		if not model.add_role(role_field.text).is_empty():
			popup.queue_free()
			_refresh())
	col.add_child(add_role)
	popup.close_requested.connect(func():
		popup.queue_free()
		_refresh())
	popup.popup_centered()
