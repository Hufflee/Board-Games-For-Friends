extends "res://tests/test_focus29_remaining.gd"
## Узкие границы отложенного TT autofocus: rebuild и устаревшие ссылки/контекст.
func run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	await start("tip_top")
	var edit: LineEdit = entry()
	await click(edit)
	edit.release_focus()
	var old_ref: WeakRef = weakref(edit)
	table._update_right()
	table._focus_answer_if_free(old_ref, table._seat(), table._round)
	check(not edit.has_focus(), "старая queued_free ссылка не фокусируется после rebuild")
	await settle()
	edit = entry()
	check(edit.has_focus(), "актуальное поле получает отложенный фокус")
	edit.release_focus()
	table._focus_answer_if_free(weakref(edit), table._seat() + 1, table._round)
	check(not edit.has_focus(), "устаревшее место не фокусируется")
	table._focus_answer_if_free(weakref(edit), table._seat(), table._round + 1)
	check(not edit.has_focus(), "устаревший раунд не фокусируется")
	var phase: String = table._v.phase
	table._v.phase = "order"
	table._focus_answer_if_free(weakref(edit), table._seat(), table._round)
	check(not edit.has_focus(), "неактуальная фаза не фокусируется")
	table._v.phase = phase
	# Между планированием и deferred callback открывается чат.
	table._update_right()
	table._top.chat.expanded = true
	await settle()
	check(not entry().has_focus(), "чат, открытый после планирования, блокирует autofocus")
	table._top.chat.expanded = false
	table._update_right()
	net.set_paused(true)
	await settle()
	check(not entry().has_focus(), "пауза после планирования блокирует autofocus")
	net.set_paused(false)
	await settle()
	edit = entry()
	if root.gui_get_focus_owner() != null:
		root.gui_get_focus_owner().release_focus()
	table._update_right()
	table._v.spectator = true
	await settle()
	check(not entry().has_focus(), "зритель после планирования не получает фокус ответа")
	table._v.spectator = false
	# Отдельный владелец фокуса появляется после планирования.
	if root.gui_get_focus_owner() != null:
		root.gui_get_focus_owner().release_focus()
	table._update_right()
	table._top.chat.expanded = true
	table._top.chat._input.grab_focus()
	await settle()
	check(table._top.chat._input.has_focus(), "новый владелец фокуса не теряет его в deferred")
	table._top.chat.expanded = false
	await stop()
	print("TT BOUNDARIES29: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)

