extends "res://tests/test_focus29_pi_dw.gd"
## Границы PI autofocus: только собственный guess, не пауза/чат/зритель/другое место/закрытый экран.

func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	for boundary: String in ["normal", "chat", "pause", "seat", "spectator", "closed", "match"]:
		net.host_offline("phantom_ink")
		net.set_bots(3)
		net.settings.pi_roles = [0, 1, 2, 3]
		check(net.start_game() == "", boundary + ": старт")
		net.set_process(false)
		fresh_pi()
		check(net.phantom.action(0, "guess_begin"), boundary + ": законный guess")
		net._push_state()
		app = load("res://games/phantom_ink/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await settle()
		await unlock(0)
		var table: Control = app.screen
		var edit: LineEdit = entry()
		await click(edit)
		check(edit.has_focus(), boundary + ": реальный клик по полю")
		edit.text = "а"
		await key(KEY_ENTER)
		check(net.phantom.phase == "judge" and entry() == null, boundary + ": ожидание духа без поля")
		var focus: Control = root.gui_get_focus_owner()
		print("PI BOUNDARY ", boundary, " intent=", table._guess_focus, " focus=", focus.get_path() if focus else "null", " chat=", table._top.chat._input.has_focus())
		if boundary == "chat":
			await click(table._top._esc_btn)
			await click(table._top._chat_btn)
			await click(table._top.chat._input)
			check(table._top.chat._input.has_focus(), "Перед ответом духа чат намеренно получил фокус")
		elif boundary == "pause":
			net.set_paused(true)
		elif boundary == "seat":
			net.pi_switch_seat(2)
		check(net.phantom.action(1, "judge", true), boundary + ": законный ответ духа")
		net._push_state()
		if boundary == "spectator":
			var spectator: Dictionary = net.view.duplicate(true)
			spectator.spectator = true
			spectator.can_act = false
			table._changed(spectator)
		elif boundary == "closed":
			app.show_lobby()
		elif boundary == "match":
			var other_match: Dictionary = net.view.duplicate(true)
			other_match.game_id = "another-test-match"
			table._changed(other_match)
		await settle()
		var next_edit: LineEdit = entry() if boundary != "closed" else null
		if boundary == "normal":
			check(next_edit != null and next_edit.has_focus(), "Обычный возврат guess получает фокус")
			await key(KEY_NONE, "б".unicode_at(0))
			await key(KEY_ENTER)
			check(net.phantom.phase == "judge" and net.phantom.rows[0].back().pending == "Б", "Вторая буква дошла настоящим вводом")
		elif boundary == "chat":
			check(next_edit != null and not next_edit.has_focus() and table._top.chat._input.has_focus(), "Возврат guess не отбирает фокус чата")
		elif boundary == "pause":
			check(next_edit != null and not next_edit.has_focus(), "На паузе autofocus не выполняется")
			net.set_paused(false)
		elif boundary == "seat":
			check(next_edit == null, "Чужое место не получает поле медиума")
			await unlock(0)
			next_edit = entry()
			check(next_edit != null and not next_edit.has_focus(), "Возвращение места не восстанавливает старое намерение")
		elif boundary == "spectator":
			check(next_edit == null and table._guess_focus.is_empty(), "Зритель не получает поле и старое намерение")
		elif boundary == "closed":
			check(app.screen != table, "Отложенный autofocus не обращается к закрытому столу")
		else:
			check(next_edit != null and not next_edit.has_focus() and table._guess_focus.is_empty(), "Новая партия не наследует намерение фокуса")
		app.queue_free()
		current_scene = null
		net.leave()
		await settle()
	print("PI FOCUS BOUNDARIES: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
