extends SceneTree
## Фоны игр для экрана победы рисуются отдельно от стола (без поля). Кадры — build/q30/bd_<игра>.png.
## Godot --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_victory_backdrops30.gd
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.size = Vector2i(640, 360)
	var screen: GDScript = load("res://hub/victory_screen.gd")
	for game: String in ["brodilka", "four_souls", "gloom", "not_a_hat", "phantom_ink", "ready_set_bet", "stillion", "the_gang", "tip_top", "dangerous_words", "hues_and_cues", "word_slam", "wavelength", "king_of_12", "perudo"]:
		var probe: Control = screen.new()
		probe.game = game
		var art: Control = probe._game_backdrop()
		probe.free()
		if art == null:
			errors += 1
			push_error("Нет фона " + game)
			continue
		root.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/q30/bd_" + game + ".png")
		art.queue_free()
		await process_frame
	print("BACKDROPS30 errors ", errors)
	quit(1 if errors else 0)
