extends Control
## Короткая оконная проверка «Гонки», пять трасс и отсчёт. Кадры build/shots/race/.
## APPDATA=<пустой> godot --audio-driver Dummy --resolution 1280x720 --path . res://tools/_mg_probe/race_probe.tscn

const Race := preload("res://hub/minigames/logic/mg_race.gd")
var failed := 0
var panel: Control
var mg: Node
var state: Dictionary


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("334151")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	if not value:
		failed += 1
		printerr("ОШИБКА: " + text)


func wait_frames() -> void:
	for i in 4:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build/shots/race/")
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder + name + ".png")
	print("КАДР ", name)


func _run() -> void:
	Net.host_offline("")
	Net.my_name = "Игрок"
	mg = Net.minigames
	panel = Net.chat.panel()
	await wait_frames()
	mg.join_room("race")
	await wait_frames()
	state = mg._rooms.race.state
	check(mg.sessions.has("room_race"), "Гонка открывается из списка комнат")
	var field: Control = panel.find_child("Field", true, false)
	check(field != null and field.get_script().resource_path.ends_with("mg_race_view.gd"), "Открыто поле гонки")
	check(field.size.x > 100 and field.size.y > 100, "Поле занимает свободное место панели")
	var change := panel.find_child("ChangeTrack", true, false) as Button
	check(change != null and change.visible, "В соло видна кнопка смены трассы")
	var first_track := int(state.track)
	change.pressed.emit()
	await wait_frames()
	check(int(state.track) != first_track, "Кнопка смены трассы работает через хоста")
	# Каждая трасса в обычном размере окна, обе темы.
	for dark: bool in [false, true]:
		Prefs.theme_mode = "dark" if dark else "light"
		for index in 5:
			state.track = index
			state.path = Race.track(index)
			state.fans = Race.fans(index)
			Race._reset(state, state.players[1])
			mg._room_push("race")
			await wait_frames()
			await shot("track_%d_%s" % [index + 1, "dark" if dark else "light"])
	field = panel.find_child("Field", true, false)
	check(field._screen(field._shown[1]).distance_to(field.size * 0.5) < 0.01, "Камера держит свой шарик в центре")
	var world_point: Vector2 = state.path[3]
	check((field._world(field._screen(world_point)) as Vector2).distance_to(world_point) < 0.0001, "Камера сохраняет обратное преобразование координат управления")
	mg.set_process(false)
	var saved_pos: Vector2 = state.players[1].pos
	state.players[1].pos = state.path[30]
	mg._room_push("race")
	await wait_frames()
	check(field._camera.distance_to(saved_pos) > 0.1, "Камера перемещается вместе с игроком")
	check(field._screen(field._shown[1]).distance_to(field.size * 0.5) < 0.01, "Игрок остаётся в центре после движения камеры")
	await shot("camera_follow")
	state.players[1].pos = saved_pos
	mg._room_push("race")
	await wait_frames()
	mg.set_process(true)
	var input_point: Vector2 = field.get_global_transform_with_canvas() * field._screen(state.path[3])
	var before: Vector2 = state.players[1].pos
	# Проверяем координаты и рывок реальным GUI-событием; системный курсор тест не перемещает.
	field.set_process(false)
	var click := InputEventMouseButton.new()
	click.position = input_point
	click.global_position = input_point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_viewport().push_input(click, true)
	await get_tree().create_timer(0.05).timeout
	check(float(state.players[1].dash_at) > -1.0, "Щелчок мышью запускает рывок")
	check((state.players[1].pos as Vector2).distance_to(before) > 0.01, "Шарик движется к точке щелчка")
	mg._room_push("race")
	await wait_frames()
	check(not bool(mg.sessions.room_race.state.list[0].dash_ready), "Снимок скрывает кольцо на перезарядке")
	await shot("dash_cooldown")
	click.pressed = false
	get_viewport().push_input(click.duplicate(), true)
	field.set_process(true)
	Race.join(state, 2, "Костя", 3)
	mg._room_push("race")
	await wait_frames()
	await shot("countdown")
	check(state.phase == "countdown", "При входе второго участника начинается отсчёт")
	var race_field: Control = panel.find_child("Field", true, false)
	check(race_field.status.text.contains("место") and race_field.foot.text.contains("Лидер:"), "В сетевом заезде видны своё место и лидер")
	check(not (panel.find_child("ChangeTrack", true, false) as Button).visible, "В сетевой гонке кнопка скрыта")
	state.players[2].pos = (state.players[1].pos as Vector2) + (state.players[1].start_dir as Vector2) * Race.RADIUS * 0.5
	state.players[1].spawn_pending = true
	state.players[2].spawn_pending = true
	Race._update_spawn_ghosts(state)
	mg._room_push("race")
	await wait_frames()
	check(bool(state.players[1].spawn_ghost) and bool(state.players[2].spawn_ghost), "Пересекающиеся появления видны призраками")
	await shot("spawn_overlap")
	state.players[2].pos = (state.players[1].pos as Vector2) + (state.players[1].start_dir as Vector2) * (Race.RADIUS * 2.0 + Race.SPAWN_MARGIN + 0.02)
	Race._update_spawn_ghosts(state)
	mg._room_push("race")
	await wait_frames()
	check(not bool(state.players[1].spawn_ghost) and not bool(state.players[2].spawn_ghost), "После расхождения защита появления снята")
	state.until = float(state.time)
	await wait_frames()
	await shot("start_zero")
	check(state.phase == "race", "Разрешено движение после отсчёта")
	# Рекорд сохраняет хостовый снимок, отдельно для каждой трассы, только за соло.
	Race.leave(state, 2)
	state.players[1].started = float(state.time) - 12.0
	# Управляем временем хоста вручную, чтобы снять начало и середину падения.
	mg.set_process(false)
	var ball: Dictionary = state.players[1]
	var at := 35
	var normal: Vector2 = ((state.path[at + 1] as Vector2) - (state.path[at] as Vector2)).normalized().orthogonal()
	var outside: Vector2 = state.path[at] + normal * (Race.ROAD_EDGE + 0.03)
	for i in 10:
		if float(Race.nearest(state.path, outside).distance) > Race.ROAD_EDGE:
			break
		outside += normal * 0.02
	ball.pos = outside
	ball.vel = normal * 0.25
	Race.step(state, 0.001, RandomNumberGenerator.new())
	mg._room_push("race")
	await wait_frames()
	check(not bool(ball.alive), "Вылет запускает падение")
	check(float(Race.snapshot(state).list[0].elapsed) == 0.0, "В соло таймер обнулился при падении")
	await shot("fall_start")
	Race.step(state, Race.FALL_TIME * 0.45, RandomNumberGenerator.new())
	mg._room_push("race")
	await wait_frames()
	await shot("fall_middle")
	Race.step(state, Race.FALL_TIME * 0.6, RandomNumberGenerator.new())
	mg._room_push("race")
	await wait_frames()
	check(bool(ball.alive), "После анимации шарик вернулся на старт")
	await shot("fall_respawn")
	mg.set_process(true)
	state.players[1].record = 12.34
	state.players[1].record_seq = 1
	mg._room_push("race")
	check(is_equal_approx(mg.best_time("race_%d" % int(state.track)), 12.34), "Личный рекорд сохранён на компьютере игрока")
	var track_id := int(state.track)
	mg.reset_party()
	mg._host_room_join(1, "race")
	state = mg._rooms.race.state
	state.track = track_id
	state.path = Race.track(track_id)
	state.players[1].record = 10.0
	state.players[1].record_seq = 1
	mg._room_push("race")
	check(is_equal_approx(mg.best_time("race_%d" % track_id), 10.0), "Первый рекорд после пересоздания комнаты не теряется")
	print("ОКНО ГОНКИ: ошибок ", failed)
	get_tree().quit(1 if failed else 0)
