extends SceneTree
## Оконная проверка новых значков/палитр, лобби Word Slam и четырёх карт в строке.
## godot --audio-driver Dummy --path . --resolution 1280x720 --script res://tests/test_batch22_visual.gd

var net: Node
var prefs: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)


func _run() -> void:
	net = root.get_node("Net")
	prefs = root.get_node("Prefs")
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/shots/batch22")
	for game in ["word_slam", "colt_express", "in_broad_strokes", "the_mind", "khorom"]:
		net.host_offline(game)
		net.set_bots(3 if game == "word_slam" else 2)
		net.set_setting("ws_words", "simple")
		change_scene_to_file("res://games/" + game + "/ui/main.tscn")
		await scene_changed
		if game == "word_slam":
			for mode in ["light", "dark"]:
				prefs.theme_mode = mode
				prefs.changed.emit()
				await _shot("ws_lobby_" + mode)
		check(net.start_game().is_empty(), "Запуск " + game)
		if game == "word_slam":
			var w: RefCounted = net.wslam
			for seat: int in w.storytellers:
				w.set_ready(seat)
			var words: Array = w.catalog_order.noun.slice(0, 4)
			check(w.set_holders(w.storytellers[0], [words, []]), "Четыре карты на подставке")
			net._push_state()
		elif game == "khorom":
			net.khr.round_no = 1
			net.khr._start_round()
			net._push_state()
		var light := Color.TRANSPARENT
		for mode in ["light", "dark"]:
			prefs.theme_mode = mode
			prefs.changed.emit()
			await process_frame
			await process_frame
			var bars := get_nodes_in_group("top_bar")
			if not bars.is_empty():
				var bar: Node = bars.back()
				bar.set_menu_open(true)
				var toggle_script: Script = load("res://hub/theme_toggle.gd")
				check(bar.actions.get_children().any(func(child: Node) -> bool: return child.get_script() == toggle_script), "Штатный значок темы " + game)
			var panel: Control = net.chat.panel()
			panel._repaint()
			panel.set_mode(1)
			var color: Color = panel._button_fill()
			if mode == "light":
				light = color
			else:
				check(not color.is_equal_approx(light), "Общение меняет цвет " + game)
			await _shot(game + "_" + mode)
		net.leave()
		await process_frame
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	print("ВИЗУАЛ 22.11: %d проверок, %d ошибок" % [checks, failures])
	root.get_node("Sfx").request_quit(1 if failures else 0)


func _shot(title: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shots/batch22/" + title + ".png")
