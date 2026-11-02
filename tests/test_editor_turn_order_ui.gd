extends "res://tests/test_editor_logic_clipboard_ui.gd"
## Настройка порядка ходов и настоящие кнопки общей готовности, обе темы1280×720.

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		push_error("Нужен отдельный тестовый APPDATA в build.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var net := root.get_node("Net")
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/editor_turn_order/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for mode: String in ["dark", "light"]:
		prefs.set_value("theme_mode", mode)
		app = load("res://editor/main.tscn").instantiate()
		root.add_child(app)
		await frames()
		app.document.create()
		app._editing = true
		app._tab = 2
		app._render()
		await frames()
		await click(button("Переменные и роли"))
		var setting: OptionButton = app.find_child("LogicTurnMode", true, false)
		check(is_instance_valid(setting), "Настройка порядка ходов доступна автору")
		# Здесь проверяется привязка OptionButton; нативный PopupMenu не управляется вводом root viewport.
		setting.select(2)
		setting.item_selected.emit(2)
		await frames()
		check(app.document.data.rules.get("turn_mode") == "simultaneous", "Привязка выбора подключила одновременный режим")
		check(app.document.undo() and app.document.data.rules.get("turn_mode", "circle") == "circle", "Порядок ходов отменяется одной командой")
		check(app.document.redo() and app.document.data.rules.turn_mode == "simultaneous", "Повтор возвращает выбранный режим")
		app.queue_free()
		await frames()
		net.host_offline("cg")
		net.set_bots(2)
		check(net.start_game().is_empty(), "Создана отдельная локальная проверка стола")
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/custom/examples/higher_lower.json"))
		data.rules.turn_mode = "simultaneous"
		data.rules.phases = ["setup", "play"]
		data.rules.chains = []
		data.meta.phase_titles = {"setup": "Выбор", "play": "Ответ"}
		data.layout.custom = false
		var g = load("res://games/custom/logic/cg_rules.gd").new()
		check(g.load_definition(data).is_empty() and g.new_game(net.cg.players, {"seed": 19}).is_empty(), "Подготовлен стол с тремя живыми местами")
		net.cg = g
		net._push_state()
		app = load("res://games/custom/ui/main.tscn").instantiate()
		root.add_child(app)
		await frames(8)
		check(absf(button("Готов").get_global_rect().get_center().x - root.size.x * 0.5) < 3, "Главная готовность находится снизу по центру")
		var original_ready: Button = button("Готов")
		net._push_state()
		await frames(6)
		check(is_instance_valid(original_ready) and original_ready == button("Готов"), "Повтор того же состояния не пересоздаёт кнопку под мышью")
		var pulse: Dictionary = app._screen._view.duplicate()
		pulse.turn_left = float(pulse.get("turn_left", 0)) + 0.1
		app._screen._state(pulse)
		await frames(6)
		check(is_instance_valid(original_ready) and original_ready == button("Готов"), "Обновление часов не пересоздаёт кнопку готовности")
		await click(button("Готов"))
		check(g.phase == "setup" and g.state.ready_seats == [0], "Первая кнопка готовности не пропускает остальных")
		check(app._screen._phase_caption().contains("1/3"), "На столе видно число готовых")
		await click(button("Изменить решение"))
		check(g.state.ready_seats.is_empty(), "Настоящая кнопка отменяет готовность")
		for seat in 3:
			net.send_action("view_seat", {"seat": seat})
			await frames(6)
			await click(button("Готов"))
		check(g.phase == "play" and g.state.ready_seats.is_empty(), "Готовность всех переводит стол в следующую фазу")
		check(app._screen._phase_caption().contains("Ответ") and app._screen._phase_caption().contains("0/3"), "Новая фаза начинает свой счётчик готовности")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + mode + ".png")
		app.queue_free()
		await frames()
		net.leave()
	print("EDITOR TURN ORDER UI: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
