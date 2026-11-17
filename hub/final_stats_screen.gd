extends Control
## Прокручиваемая итоговая таблица всех мест за столом.

static func open(parent: Node, data: Dictionary) -> void:
	if data.is_empty() or parent.has_node("FinalStats"):
		return
	var panel := load("res://hub/final_stats_screen.gd").new() as Control
	panel.name = "FinalStats"
	panel.set("data", data)
	parent.add_child(panel)


var data: Dictionary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 120
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 32
	margin.offset_right = -32
	margin.offset_top = 72
	margin.offset_bottom = -32
	add_child(margin)
	var panel := HubStyle.panel(HubStyle.CYAN)
	margin.add_child(panel)
	var body := HubStyle.vbox(12)
	panel.add_child(body)
	var head := HubStyle.hbox(12)
	body.add_child(head)
	var title := HubStyle.label("Статистика партии", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := HubStyle.button("Закрыть", 15)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = data.columns.size() + 1
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	grid.add_child(HubStyle.label("Игрок", 16))
	for key in data.columns:
		grid.add_child(HubStyle.label(str(data.columns[key]), 15, HubStyle.CYAN))
	for row: Dictionary in data.rows:
		grid.add_child(HubStyle.label(str(row.name), 16))
		for key in data.columns:
			var value: Variant = row.values.get(key)
			var numbers := []
			for rival: Dictionary in data.rows:
				if rival.values.has(key):
					numbers.append(rival.values[key])
			var tint := HubStyle.TEXT
			if value != null and numbers.size() > 1 and numbers.min() != numbers.max():
				tint = Color("9aefad") if value == numbers.max() else Color("ff939e") if value == numbers.min() else tint
			grid.add_child(HubStyle.label("—" if value == null else str(value), 16, tint))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
