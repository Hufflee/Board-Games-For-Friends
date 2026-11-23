class_name LocalUIState
extends RefCounted
## Локальные черновики интерфейса, независимые от сетевого снимка.
## update(owner, context, defaults, render) сохраняет форму при повторном view.
## context содержит идентификатор партии, место и смысловую фазу/раунд, но не revision/serial.
## Полям пересоздаваемой формы задавать постоянные имена. Смена context очищает черновики.

var _context: Array = []
var _initialized := false


## Общая страховка Net для всех игр: обновление не прерывает печать в том же задании.
## Состояния выбора и другие свойства формы сохраняются через update(), а не в сетевых данных.
static func network_update(tree: SceneTree, previous: Dictionary, next: Dictionary, render: Callable) -> void:
	var scene := tree.current_scene
	var field := tree.root.gui_get_focus_owner()
	var preserve := scene != null and field != null and scene.is_ancestor_of(field)
	preserve = preserve and (field is LineEdit or field is TextEdit) and _network_context(previous) == _network_context(next)
	var saved := {}
	var path := NodePath()
	var field_key := ""
	if preserve:
		path = scene.get_path_to(field)
		field_key = str(field.get_meta("local_ui_key", ""))
		_capture(scene, field, saved)
	render.call()
	if preserve and is_instance_valid(scene) and scene == tree.current_scene:
		var replacement := scene.get_node_or_null(path)
		if not field_key.is_empty():
			replacement = _find_key(scene, field_key)
		if replacement != null:
			_restore(scene, replacement, saved)


static func _find_key(node: Node, key: String) -> Node:
	if node.is_queued_for_deletion():
		return null
	if str(node.get_meta("local_ui_key", "")) == key:
		return node
	for child: Node in node.get_children():
		var found := _find_key(child, key)
		if found != null:
			return found
	return null


static func _network_context(view: Dictionary) -> Array:
	var context: Array = []
	for key in ["game", "game_id", "seat", "you", "phase", "round", "round_no", "turn_no", "hand_no", "q_no", "trick_no", "word_no", "current", "target"]:
		context.append(view.get(key))
	# В одновременном голосовании чужой ответ меняет turn, но не задание остальных.
	context.append(view.get("turn") if view.get("phase") != "vote" else null)
	return context


func update(owner: Node, context: Array, defaults: Dictionary, render: Callable) -> void:
	var same := _initialized and context == _context
	var saved := {}
	if same:
		_capture(owner, owner, saved)
	else:
		for property: String in defaults:
			var current: Variant = owner.get(property)
			if current is Array and defaults[property] is Array:
				current.clear()
				current.append_array(defaults[property])
			else:
				owner.set(property, _copy(defaults[property]))
	_context = context.duplicate(true)
	_initialized = true
	render.call()
	if same and is_instance_valid(owner):
		_restore(owner, owner, saved)


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _key(root: Node, node: Node) -> String:
	return str(node.get_meta("local_ui_key", root.get_path_to(node)))


static func _capture(root: Node, node: Node, saved: Dictionary) -> void:
	if node.is_queued_for_deletion():
		return
	var path := _key(root, node)
	if node is LineEdit and node.editable:
		saved[path] = {"kind": "line", "text": node.text, "caret": node.caret_column,
			"focus": node.has_focus(), "from": node.get_selection_from_column() if node.has_selection() else 0,
			"to": node.get_selection_to_column() if node.has_selection() else 0, "selected": node.has_selection()}
	elif node is TextEdit and node.editable:
		saved[path] = {"kind": "text", "text": node.text, "line": node.get_caret_line(),
			"column": node.get_caret_column(), "focus": node.has_focus()}
	elif node is OptionButton:
		saved[path] = {"kind": "option", "id": node.get_selected_id()}
	elif node is ScrollContainer:
		saved[path] = {"kind": "scroll", "x": node.scroll_horizontal, "y": node.scroll_vertical}
	for child: Node in node.get_children():
		_capture(root, child, saved)


static func _restore(root: Node, node: Node, saved: Dictionary) -> void:
	if node.is_queued_for_deletion():
		return
	var item: Dictionary = saved.get(_key(root, node), {})
	if not item.is_empty():
		if node is LineEdit and item.kind == "line" and node.editable:
			node.set_block_signals(true)
			node.text = item.text
			node.caret_column = item.caret
			if item.selected:
				node.select(item.from, item.to)
			node.set_block_signals(false)
			if item.focus:
				node.grab_focus()
		elif node is TextEdit and item.kind == "text" and node.editable:
			node.set_block_signals(true)
			node.text = item.text
			node.set_caret_line(item.line)
			node.set_caret_column(item.column)
			node.set_block_signals(false)
			if item.focus:
				node.grab_focus()
		elif node is OptionButton and item.kind == "option":
			var index: int = node.get_item_index(item.id)
			if index >= 0 and not node.is_item_disabled(index):
				node.select(index)
		elif node is ScrollContainer and item.kind == "scroll":
			node.set_deferred("scroll_horizontal", item.x)
			node.set_deferred("scroll_vertical", item.y)
	for child: Node in node.get_children():
		_restore(root, child, saved)
