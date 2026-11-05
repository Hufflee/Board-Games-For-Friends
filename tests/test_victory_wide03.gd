extends SceneTree
## Процедурная вспышка для1/2/4/8/9победителей: команды/ничьи, две темы, геометрия на пике появления.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors += 1; push_error(message)

func settle() -> void:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if not OS.get_environment("APPDATA").replace("\\", "/").contains("/build/"):
		quit(1); return
	root.size = Vector2i(1280, 720)
	var net := root.get_node("Net")
	var prefs := root.get_node("Prefs")
	var folder := "res://build/shots/victory_wide03/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	net.host_offline("hues_and_cues")
	net.set_bots(3)
	check(net.start_game().is_empty(), "Настоящий стол подготовлен")
	net.set_process(false)
	var app: Control
	var screen: Control
	for theme: String in ["light", "dark"]:
		prefs.theme_mode = theme
		net._push_state()
		app = load("res://games/hues_and_cues/ui/main.tscn").instantiate()
		root.add_child(app)
		await settle()
		screen = app.screen.get_node("VictoryScreen")
		for count: int in [1, 2, 4, 8, 9]:
			for team: bool in [false, true]:
				var players: Array = []
				for seat: int in count:
					players.append({"name": "Длинное имя участника %d" % seat, "steam_id": 0, "team": 0})
				var view: Dictionary = net.view.duplicate(true)
				view.phase = "game_over"
				view.players = players
				view.winners = range(count)
				view.coop = team
				view.game_id = "%s_%d_%s" % [theme, count, str(team)]
				view.clock = false
				view.turn_total = 0
				net.view = view
				screen.sync(view)
				screen._burst.preview_time = 0.5
				await settle()
				check(screen.is_visible_in_tree() and screen._burst.is_visible_in_tree() and not screen._burst._outline.is_empty(), "Процедурная вспышка видна на реальном столе: %s/%d/%s" % [theme, count, team])
				var center := Vector2(screen.size.x * 0.5, screen.size.y * 0.4)
				var peak_safe := true
				for point: Vector2 in screen.star_polygon():
					var peak := center + (point - center) * 1.107 + Vector2(1, 10)
					peak_safe = peak_safe and Rect2(8, 48, screen.size.x - 16, screen.size.y - 120).has_point(peak)
				check(peak_safe, "На пике отскока звезда не перекрывает заголовок и кнопки и не обрезается")
				var portraits_inside := true
				for card: Control in screen._cards:
					var avatar: Control = card.get_node("Avatar")
					var rect := Rect2(card.position + avatar.position, avatar.size)
					for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
						portraits_inside = portraits_inside and Geometry2D.is_point_in_polygon(corner, screen.star_polygon())
				check(portraits_inside, "Все аватары расположены внутри реального контура")
				root.get_texture().get_image().save_png(folder + "%s_%d_%s.png" % [theme, count, "team" if team else "tie"])
		app.queue_free()
		await settle()
	net.leave()
	await settle()
	print("VICTORY WIDE03: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
