class_name LeaveGuard
## Опасная кнопка выхода из партии / пати: приглушённый стиль (вариация темы «QuietButton»), отступ от
## соседних кнопок и подтверждение удержанием — кнопку надо зажать, она заполняется слева направо,
## и выход срабатывает, только когда заполнится (HoldFill). Отпустил раньше — заливка стекает обратно.
## ask() — окно подтверждения для других важных действий (стать зрителем, сбросить руку…):
## оформление из темы игры («ConfirmPanel», «SelectedButton», «QuietButton»).

const HOLD_TIME := 1.0  # сколько держать кнопку выхода, с


static func wire(btn: Button, question: String, _detail: String, on_yes: Callable) -> void:
	btn.theme_type_variation = "QuietButton"
	btn.ready.connect(func(): _add_gap_ref.call_deferred(weakref(btn)), CONNECT_ONE_SHOT)
	hold(btn, on_yes, question)


## Подтверждение удержанием: зажать кнопку на HOLD_TIME — сработает on_yes.
static func hold(btn: Button, on_yes: Callable, question: String = "") -> void:
	var tip := "Удерживайте кнопку, чтобы подтвердить"
	btn.tooltip_text = (question + "\n" + tip) if question != "" else tip
	var fill := HoldFill.new()
	fill.on_done = on_yes
	btn.add_child(fill)
	btn.button_down.connect(fill.start)
	btn.button_up.connect(fill.stop)
	btn.mouse_exited.connect(fill.stop)


## Отступ перед опасной кнопкой (после того как родитель достроен — иначе add_child во время сборки падает).
static func _add_gap_ref(reference: WeakRef) -> void:
	var button: Button = reference.get_ref() as Button
	if is_instance_valid(button):
		_add_gap(button)


static func _add_gap(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var p := btn.get_parent()
	if p is BoxContainer:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(14, 14)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(gap)
		p.move_child(gap, btn.get_index())


static func ask(from: Control, question: String, detail: String, yes_text: String, on_yes: Callable, no_text: String = "Остаться в игре") -> void:
	# окно — поверх сцены игры (внутри неё, чтобы досталась тема игры)
	var host: Node = from.get_tree().current_scene if from.get_tree().current_scene is Control else from.get_tree().root
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.top_level = true
	root.z_index = 100
	host.add_child(root)
	root.size = root.get_viewport_rect().size
	var layer := root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ConfirmPanel"
	panel.custom_minimum_size.x = 440
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var q := Label.new()
	q.text = question
	q.add_theme_font_size_override("font_size", 22)
	q.add_theme_color_override("font_color", panel.get_theme_color("font_color", "ConfirmPanel"))
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(q)
	if detail != "":
		var d := Label.new()
		d.text = detail
		d.add_theme_font_size_override("font_size", 15)
		d.add_theme_color_override("font_color", panel.get_theme_color("font_color", "ConfirmPanel"))
		d.modulate.a = 0.72
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var close := func(): layer.queue_free()
	var yes := Button.new()
	yes.text = yes_text
	yes.theme_type_variation = "QuietButton"
	yes.add_theme_font_size_override("font_size", 15)
	yes.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	yes.pressed.connect(func():
		close.call()
		on_yes.call())
	row.add_child(yes)
	var stay := Button.new()
	stay.text = no_text
	stay.theme_type_variation = "SelectedButton"
	stay.add_theme_font_size_override("font_size", 16)
	stay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stay.pressed.connect(close)
	row.add_child(stay)
	stay.grab_focus.call_deferred()
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close.call())
	Sfx.play("click", -8)
