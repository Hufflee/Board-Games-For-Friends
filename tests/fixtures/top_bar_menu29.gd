extends RefCounted
## Мышиным harness раскрывает новое ESC-меню перед нажатием его кнопки.
## Утверждения и реальные игровые клики остаются прежними.
static func reveal(control: Control) -> void:
	if not is_instance_valid(control):
		return
	var node: Node = control
	var in_drawer := false
	while node != null:
		in_drawer = in_drawer or node.name == "ActionDrawer"
		if in_drawer and node.is_in_group("top_bar"):
			if not node.get("_menu_open"):
				var tree := control.get_tree()
				var esc: Control = node.get("_esc_btn")
				var at := esc.get_global_rect().get_center()
				var motion := InputEventMouseMotion.new()
				motion.position = at
				Input.parse_input_event(motion)
				await tree.process_frame
				for pressed: bool in [true, false]:
					var event := InputEventMouseButton.new()
					event.position = at
					event.button_index = MOUSE_BUTTON_LEFT
					event.pressed = pressed
					Input.parse_input_event(event)
					await tree.process_frame
				await tree.create_timer(0.2).timeout
			return
		node = node.get_parent()
