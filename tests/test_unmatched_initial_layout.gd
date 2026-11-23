extends SceneTree
## Начальная раскладка стола до первого кадра: подсказка не должна схлопывать высоту поля.
var checks := 0
var errors := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var net := root.get_node("Net")
	var prefs := root.get_node("Prefs")
	prefs.window_mode = "windowed"
	prefs.resolution = "1280x720"
	for graphics in [0, 1, 2]:
		for existing in [false, true]:
			prefs.graphics = graphics
			prefs.theme_mode = "dark" if existing else "light"
			prefs.apply()
			net.host_offline("unmatched")
			net.set_bots(1)
			net.set_setting("um_hero_mode", "free")
			net.set_setting("um_heroes", ["witches", "shakespeare"])
			if existing: net.start_game()
			var app: Control = load("res://games/unmatched/ui/main.tscn").instantiate()
			root.add_child(app)
			app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if not existing: net.start_game()
			# В сети нет закрывающей стол передачи управления: первая расстановка приходит до кадра.
			if net.view.get("handoff", false): net.send_action("handoff", {})
			for frame in 8: await process_frame
			var table: Control = app._screen
			check(table._board.size.x >= 300 and table._board.size.y >= 200,
				"Начальная расстановка: поле имеет рабочую ширину и высоту, графика %d, вход %s · размер %s" % [graphics, existing, table._board.size])
			check(table._actions.size.y < 100, "Начальная подсказка не занимает высоту всего экрана · %s" % table._actions.size)
			if OS.get_environment("UM_INITIAL_SHOTS") == "1" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://build/shots/unmatched_startup")
				root.get_texture().get_image().save_png("res://build/shots/unmatched_startup/layout_%d_%s.png" % [graphics, existing])
			for step in 20:
				if net.view.get("handoff", false): net.send_action("handoff", {})
				var setup: Dictionary = net.view.get("setup", {})
				if setup.is_empty(): break
				net.send_action("place", {"cell": setup.cells[0]})
			for frame in 8: await process_frame
			check(table._board.size.x >= 300 and table._board.size.y >= 200, "Первый ход сохраняет рабочее поле без смены графики")
			app.queue_free()
			await process_frame
			net.leave()
	print("Unmatched, начальная раскладка: %d проверок, %d ошибок" % [checks, errors])
	quit(int(errors > 0))


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)
