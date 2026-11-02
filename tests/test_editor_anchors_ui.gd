extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Настоящий стол при1280×720/1920×720/1280×960: якоря, растяжение, legacy и неизменность состояния.

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1)
		return
	var net := root.get_node("Net")
	var folder := "res://build/shots/editor_anchors/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for theme: String in ["dark", "light"]:
		root.get_node("Prefs").set_value("theme_mode", theme)
		root.size = Vector2i(1280, 720)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		app.document.create("card_race")
		app._editing = true
		app._tab = 1
		app._layout_selected = 0
		app._render()
		await frames()
		var before := JSON.stringify(app.document.data)
		await click(button("Якоря окна"))
		check(app.document.data.layout.screens[0].items[0].anchors == {"x": "center", "y": "top"}, "Настоящий переключатель включает независимые якоря")
		app.document.undo()
		check(JSON.stringify(app.document.data) == before, "Якоря отменяются одной командой")
		app.queue_free()
		await frames()
		net.host_offline("cg")
		check(net.mode == "offline" and net.party_game == "cg", "Создана офлайн-партия")
		net.set_bots(1)
		net.set_setting("cg_example", "card_race")
		check(net.start_game().is_empty(), "Правила стартовали")
		var table: Control = load("res://games/custom/ui/cg_table.gd").new()
		var owner := Control.new()
		owner.set_script(load("res://games/custom/ui/cg_app.gd"))
		# Корень игры нужен только для штатной кнопки возврата.
		table.app = owner
		table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(table)
		await frames(6)
		var items: Array = [
			{"id": "anchor_left", "kind": "text", "text": "Слева сверху", "rect": [32, 96, 240, 48], "anchors": {"x": "left", "y": "top"}},
			{"id": "anchor_right", "kind": "text", "text": "Справа снизу", "rect": [1008, 592, 240, 48], "anchors": {"x": "right", "y": "bottom"}},
			{"id": "anchor_center", "kind": "text", "text": "В центре", "rect": [520, 304, 240, 48], "anchors": {"x": "center", "y": "center"}},
			{"id": "anchor_wide", "kind": "text", "text": "Растяжение по ширине", "rect": [32, 176, 1216, 48], "anchors": {"x": "stretch", "y": "top"}}]
		for original: Dictionary in net.cg.definition.layout.screens[0].items:
			if original.get("kind") != "zone":
				continue
			var zone := original.duplicate(true)
			zone.rect = [32, 224, 240, 192] if zone.id == "draw" else ([864, 224, 368, 192] if zone.id == "table" else [288, 432, 704, 176])
			zone.anchors = {"x": "left" if zone.id == "draw" else ("right" if zone.id == "table" else "stretch"), "y": "bottom" if zone.id == "hand" else "top"}
			items.append(zone)
		table._shown = true
		net.cg.definition.layout = {"custom": true, "screens": [{"id": "main", "items": items}]}
		net._push_state()
		await frames(6)
		var revision: int = net.cg.state.revision
		for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 720), Vector2i(1280, 960)]:
			root.size = dimensions
			await frames(8)
			var left: Label
			var right: Label
			var center: Label
			var wide: Label
			for label: Node in table._field.find_children("*", "Label", false, false):
				match label.text:
					"Слева сверху": left = label
					"Справа снизу": right = label
					"В центре": center = label
					"Растяжение по ширине": wide = label
			check(is_instance_valid(left) and is_instance_valid(right) and is_instance_valid(center) and is_instance_valid(wide), "Все элементы нарисованы при %s" % dimensions)
			if not is_instance_valid(right):
				continue
			check(left.position == Vector2(32, 48), "Левый верхний отступ фиксирован")
			check(is_equal_approx(table._field.size.x - right.position.x - 240, 32) and is_equal_approx(table._field.size.y - right.position.y - 48, 80), "Правый нижний отступ сохраняется при изменении окна")
			check(center.position.is_equal_approx(Vector2(520, 256) + (table._field.size - Vector2(1280, 672)) * 0.5), "Центр смещается на половину свободного места")
			check(is_equal_approx(wide.size.x, table._field.size.x - 64), "Растянутая надпись сохраняет два боковых отступа")
			check(left.get_global_rect().position.y >= 48 and net.cg.state.revision == revision, "TopBar свободен, изменение окна не меняет состояние партии")
			var hand_rect: Rect2 = table._zones["hand@0"].get_global_rect()
			check(table._cards.values().all(func(card): return hand_rect.encloses(card.get_global_rect())), "Уменьшенные карты целиком внутри панели руки")
			root.get_texture().get_image().save_png(folder + "%s_%dx%d.png" % [theme, dimensions.x, dimensions.y])
		root.size = Vector2i(1920, 720)
		await frames(8)
		var action: Dictionary = net.view.legal[0]
		var card: Control = table._cards[str(action.card)]
		var start: Vector2 = root.get_final_transform() * (card.global_position + Vector2(40, 48))
		var finish: Vector2 = root.get_final_transform() * table._zones.table.get_global_rect().get_center()
		for down: bool in [true, false]:
			if not down:
				var motion := InputEventMouseMotion.new()
				motion.position = finish
				motion.global_position = finish
				motion.relative = finish - start
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				Input.parse_input_event(motion)
				Input.flush_buffered_events()
				await frames(2)
			var event := InputEventMouseButton.new()
			event.position = start if down else finish
			event.global_position = event.position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await frames(2)
		await frames(6)
		check(net.cg.state.current == 1 and net.cg.state.zones.table.size() == 1, "Настоящий перенос карты в сдвинутую якорем зону выполняет правила")
		# Без якорей сохраняется старый центрированный стол с полями.
		for item: Dictionary in items:
			item.erase("anchors")
		net._push_state()
		root.size = Vector2i(1920, 720)
		await frames(8)
		check(table._field.size.is_equal_approx(Vector2(1280, 672)) and is_equal_approx(table._field.position.x, 320), "Без якорей широкий экран использует прежнее центрирование")
		table.queue_free()
		owner.free()
		net.leave()
		await frames()
	print("EDITOR ANCHORS UI: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
