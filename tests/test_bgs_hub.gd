extends SceneTree
## Проверки BGS Social, итогов партии и столкновений с фигурными полками.
## Godot --audio-driver Dummy --path . --script res://tests/test_bgs_hub.gd

const Stats := preload("res://hub/final_stats.gd")
const Upper := preload("res://hub/upper_shelves.gd")
var errors := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors += 1
		push_error(message)


func run() -> void:
	var players := [{"name": "Мира"}, {"name": "Лев"}, {"name": "Саша"}]
	var rows := [{"messages": 3, "dice": {"2": 2, "3": 1}}, {"messages": 1}, {"messages": 7}]
	var data := Stats.make("green_team", {"phase": "end", "scores": [5, 3, 9]}, players, rows, null)
	check(data.ratings[0].rating == 50 and data.ratings[2].rating == 100, "Рейтинг показывает долю обойдённых соперников.")
	check(data.rows[0].values.rolls == 3 and data.rows[2].values.messages == 7, "Универсальные счётчики включены в общую таблицу.")
	check(Stats.make("green_team", {"phase": "answer"}, players, rows, null).is_empty(), "Таблица доступна по итогам.")
	var gloom := Stats.make("gloom", {"phase": "game_over", "players": players, "winners": [0], "finals": [-100, -60, -40]}, players, rows, null)
	check(gloom.ratings[0].rating == 100 and gloom.ratings[1].rating == 50 and gloom.ratings[2].rating == 0, "В Gloom меньше очков соответствует более высокому месту.")
	var coop := Stats.make("the_gang", {"phase": "game_over", "players": players, "won": true}, players, rows, null)
	check(coop.ratings[0] == {"kind": "coop", "rating": 100, "result": "win"}, "Успех кооператива считается отдельно.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bgs_stats.json"))  # от прошлого запуска
	var stats := PlayerStatsStore.new("user://test_bgs_stats.json")
	var snapshot := {"id": "bgs/1", "game": "green_team", "seat": 0, "totals": {"kind": "rank", "rating": 50}}
	check(stats.consume(snapshot) and not stats.consume(snapshot), "Повтор итога не учитывается дважды.")
	check(stats.summary().rating_totals.rank == 50 and stats.summary().rating_counts.rank == 1, "Личная статистика сохраняет рейтинг.")
	var faces: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-0.4, 1.0), Vector2(0.4, 1.4), Vector2(0.4, 1.37), Vector2(-0.4, 0.97)])]
	var at := Vector3(0, 1.245, Upper.FRONT - 0.04)
	var hit := Upper.ball_contact(faces, at, 0.07, Upper.DEPTH)
	check(not hit.is_empty() and (hit[0] as Vector3).y > 0.7, "Удар о диагональ отражает мяч по её нормали.")
	check(Upper.ball_contact(faces, at, 0.07, Upper.SHALLOW_DEPTH).is_empty(), "Мяч перед узкой полкой проходит свободно.")
	var ui: Control = load("res://hub/final_stats_screen.gd").new()
	ui.set("data", data)
	root.add_child(ui)
	await process_frame
	check(ui.get_child_count() == 2, "Итоговая таблица строится.")
	if DisplayServer.get_name() != "headless" and OS.has_environment("BGS_STATS_SHOT"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("BGS_STATS_SHOT"))
	ui.queue_free()
	if DisplayServer.get_name() != "headless":
		var hub: Node = load("res://hub/hub.tscn").instantiate()
		root.add_child(hub)
		await create_timer(0.7).timeout
		var room: Node = hub.get("_room")
		root.get_node("Prefs").set("shelf_camera_zoom", 0.75)
		await create_timer(0.7).timeout
		room.ball_on = false
		room.ball_left_on = true
		var ball: Node3D = room.get("_ball")
		var cam: Camera3D = room.get("camera")
		cam.fov = 75.0
		for y: float in [1.65, 1.85, 2.05, 2.25]:
			ball.position = Vector3(-1.6, y, -1.72)
			if room.ball_visible():
				break
		room._apply_ball_on()
		check(ball.visible and room.ball_visible(), "Отдалённая камера видит мяч слева при включении мяча для левой стороны.")
		room._ball_hidden_time = 4.99
		room._ball_check = 0.19
		room._ball_step(0.03)
		check(room._ball_hidden_time == 0.0 and ball.position.x < -1.45, "Видимый мяч сбрасывает таймер невидимости без респавна.")
		var before := ball.position
		room._ball_v = Vector3(0.1, -0.2, 0.05)
		room.look_left_wall(true)
		check(ball.position == before and room._ball_v == Vector3(0.1, -0.2, 0.05), "Поворот камеры сохраняет положение и скорость мяча.")
		hub.queue_free()
		await process_frame
		root.set_meta(&"bgs_social", true)
		var social: Node = load("res://hub/social/social.tscn").instantiate()
		root.add_child(social)
		current_scene = social
		await create_timer(0.5).timeout
		var panel: Control = social.get("_panel")
		check(root.always_on_top and root.borderless and not panel.is_open(), "Social запускается кнопкой поверх окон, окно без рамки.")
		panel.toggle()
		await create_timer(0.5).timeout
		check(panel.is_open(), "Кнопка разворачивает чат и мини-игры.")
		if OS.has_environment("BGS_SHOT"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("BGS_SHOT"))
		panel.set_mode(1)
		await create_timer(0.5).timeout
		check(not panel.is_open(), "Кнопка сворачивает панель обратно.")
	print("BGS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
