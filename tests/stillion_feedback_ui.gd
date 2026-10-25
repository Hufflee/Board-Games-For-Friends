extends Control
## Настоящий стол 1280×720: обе темы, восемь игроков, ответы, цветная шкала и выстрел.
## Запуск: godot --path . res://tests/stillion_feedback_ui.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var app = load("res://games/stillion/ui/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	Net.host_offline("stillion")
	Net.set_bots(7)
	Net.start_game()
	await get_tree().create_timer(0.5).timeout
	Net.set_process(false)
	var rules: STRules = Net.stillion
	rules.phase = "fuse"
	for i in rules.players.size():
		rules.players[i].last_answer = "Санкт-Петербург" if i % 2 else "Лягушка"
		rules.players[i].parts = ["c", "s", "u", "e"]
		rules.players[i].meter = 10
	for mode in ["light", "dark"]:
		Prefs.theme_mode = mode
		app.restyle()
		await get_tree().create_timer(0.2).timeout
		var tables := get_tree().root.find_children("*", "Control", true, false)
		for table in tables:
			if is_instance_valid(table) and table.get_script() == load("res://games/stillion/ui/st_table.gd"):
				table._on_state(rules.get_view(0))
				await get_tree().create_timer(0.2).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://build/shots/st-feedback-%s.png" % mode)
				table._play_event({"kind": "boom", "seat": 0, "out": false})
				await get_tree().create_timer(0.25).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://build/shots/st-feedback-%s-bang.png" % mode)
	get_tree().quit()



