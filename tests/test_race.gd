extends SceneTree
## Правила «Гонки»: трассы, круги, лёд, ветер, соло и состав комнаты.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_race.gd

const Race := preload("res://hub/minigames/logic/mg_race.gd")
var failed := 0
var checks := 0
var rng := RandomNumberGenerator.new()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("ОШИБКА: " + message)


func state_with(count: int) -> Dictionary:
	var state := Race.new_state(rng)
	for peer in range(1, count + 1):
		Race.join(state, peer, "Игрок %d" % peer, peer)
	return state


func lap(state: Dictionary, peer: int, backward: bool = false) -> void:
	# Последовательно пройти все участки кольца; пересечение старта само по себе не даёт круг.
	for i in range(1, Race.SAMPLES + 1):
		state.time = float(state.time) + 0.1
		var u := float(i) / Race.SAMPLES
		Race._progress(state, peer, fposmod(-u if backward else u, 1.0))


func _init() -> void:
	rng.seed = 42
	var straight := PackedVector2Array([Vector2(-1, 0), Vector2(1, 0)])
	var hanging := Vector2(0, Race.ROAD_EDGE - Race.RADIUS * 0.5)
	check(Race._on_road(straight, hanging, hanging), "Половина шарика свисает за край — вылета нет")
	var curb := Vector2(0, (Race.WIDTH + Race.ROAD_EDGE) * 0.5)
	check(Race._on_road(straight, curb, curb), "Центр над серой каймой остаётся на дороге")
	var edge := Vector2(0, Race.ROAD_EDGE)
	check(not Race._on_road(straight, curb, edge), "Центр коснулся внешнего края — вылет")
	var outside := Vector2(0, Race.ROAD_EDGE + 0.001)
	check(not Race._on_road(straight, curb, outside), "Центр за краем — вылет")
	var turning := {"pos": Vector2.ZERO, "aim": Vector2.DOWN, "vel": Vector2.RIGHT * Race.MAX_SPEED, "steer": true, "course": Vector2.RIGHT}
	var turn90 := Race._drive_velocity(turning, 0.02, false)
	check(turn90.x > Race.MAX_SPEED * 0.98 and turn90.y < 0.01, "Поворот 90°: прежняя скорость сохраняется, мгновенного разгона поперёк нет")
	check((turning.course as Vector2).angle_to(Vector2.DOWN) > 0.5, "Направление тяги не перескакивает к курсору")
	var reverse := {"pos": Vector2.ZERO, "aim": Vector2.LEFT, "vel": Vector2.RIGHT * Race.MAX_SPEED, "steer": true, "course": Vector2.RIGHT}
	check(Race._drive_velocity(reverse, 0.02, false).x > 0.0, "Разворот 180° сохраняет движение по инерции")
	turning.vel = turn90
	for i in 50:
		turning.vel = Race._drive_velocity(turning, 0.02, false)
	var ice_turning := {"pos": Vector2.ZERO, "aim": Vector2.DOWN, "vel": Vector2.RIGHT * Race.MAX_SPEED, "steer": true, "course": Vector2.RIGHT}
	for i in 51:
		ice_turning.vel = Race._drive_velocity(ice_turning, 0.02, true)
	check(absf((turning.vel as Vector2).x) < absf((ice_turning.vel as Vector2).x) and (turning.vel as Vector2).y > 0.3, "На обычной дороге новый курс набран, боковой занос слабее, чем на льду")
	for i in 300:
		turning.vel = Race._drive_velocity(turning, 0.02, false)
	check(absf((turning.vel as Vector2).x) < 0.01, "При длительном движении по одному курсу занос затухает")
	var sliding := {"pos": Vector2.ZERO, "aim": Vector2.ZERO, "vel": Vector2.RIGHT, "steer": false, "course": Vector2.DOWN}
	var dry_slide := Race._drive_velocity(sliding, 0.150, false)
	var ice_slide := Race._drive_velocity(sliding, 1.5, true)
	check(is_equal_approx(dry_slide.x, 0.5) and is_equal_approx(ice_slide.x, 0.5), "Боковая скорость теряет половину за 0,150 с на дороге и за 1,5 с на льду")
	check(Race._drive_velocity(sliding, 0.150, true).x > dry_slide.x, "На льду боковое скольжение сохраняется дольше")
	var fast_turn := {"pos": Vector2.ZERO, "aim": Vector2.DOWN, "vel": Vector2.RIGHT * Race.MAX_SPEED * 2.0, "steer": true, "course": Vector2.RIGHT}
	Race._drive_velocity(fast_turn, 0.02, false)
	check((fast_turn.course as Vector2).y < sin(PI * 1.5 * 0.02 / 2.0), "На высокой скорости направление тяги поворачивается медленнее")
	var shapes := {}
	var boost_state := state_with(1)
	check(bool(Race.snapshot(boost_state).list[0].dash_ready), "Кольцо рывка: перед применением рывок готов")
	Race.steer(boost_state, 1, (boost_state.players[1].pos as Vector2) + (boost_state.players[1].start_dir as Vector2) * 0.2, true)
	Race.dash(boost_state, 1)
	check(not bool(Race.snapshot(boost_state).list[0].dash_ready), "Кольцо рывка: на перезарядке рывок недоступен")
	boost_state.time = float(boost_state.time) + Race.Balls.DASH_COOLDOWN
	check(bool(Race.snapshot(boost_state).list[0].dash_ready), "Кольцо рывка: после перезарядки рывок снова готов")
	# Защита старта действует на каждой трассе и повторно после появления.
	for index in 5:
		var guarded := state_with(1)
		guarded.track = index
		guarded.path = Race.track(index)
		guarded.fans = []
		var guarded_ball: Dictionary = guarded.players[1]
		Race._reset(guarded, guarded_ball)
		var origin: Vector2 = guarded_ball.pos
		var direction: Vector2 = guarded_ball.start_dir
		Race.steer(guarded, 1, origin - direction, true)
		check(not bool(guarded_ball.steer) and not Race.dash(guarded, 1), "Старт: обратное направление и рывок назад не принимаются")
		Race.step(guarded, 0.03, rng)
		check((guarded_ball.pos as Vector2).distance_to(origin) < 0.0001 and float(guarded_ball.started) < 0.0, "Неверный курс на старте не двигает шарик и не запускает таймер")
		Race.steer(guarded, 1, origin + direction + direction.orthogonal(), true)
		var requested := (direction + direction.orthogonal()).normalized()
		check(bool(guarded_ball.steer) and ((guarded_ball.aim as Vector2) - origin).normalized().dot(requested) > 0.999, "Старт: диагональный курс вперёд сохраняется без выравнивания")
		Race.steer(guarded, 1, origin + direction - direction.orthogonal(), true)
		requested = (direction - direction.orthogonal()).normalized()
		check(bool(guarded_ball.steer) and ((guarded_ball.aim as Vector2) - origin).normalized().dot(requested) > 0.999, "Старт: разрешён и другой диагональный курс вперёд")
		for k in 200:
			if not bool(guarded_ball.start_guard):
				break
			Race.steer(guarded, 1, (guarded_ball.pos as Vector2) + direction * 0.25, true)
			Race.step(guarded, 0.01, rng)
		check(bool(guarded_ball.alive) and not bool(guarded_ball.start_guard), "После короткого движения вперёд защита старта снимается")
		Race.steer(guarded, 1, (guarded_ball.pos as Vector2) - direction, true)
		check(bool(guarded_ball.steer), "Вне старта разрешён любой курс")
		Race._reset(guarded, guarded_ball)
		check(bool(guarded_ball.start_guard) and not bool(guarded_ball.steer), "Повторное появление включает защиту и очищает старый ввод")
	var overlapping := state_with(2)
	overlapping.phase = "race"
	overlapping.fans = []
	var spawning: Dictionary = overlapping.players[1]
	var neighbor: Dictionary = overlapping.players[2]
	Race._reset(overlapping, spawning)
	neighbor.pos = (spawning.pos as Vector2) + (spawning.start_dir as Vector2) * Race.RADIUS * 0.5
	for ball: Dictionary in [spawning, neighbor]:
		ball.steer = true
		ball.wake_at = -100.0
		ball.aim = ball.pos
		ball.vel = Vector2.ZERO
	Race._update_spawn_ghosts(overlapping)
	check(bool(spawning.spawn_ghost), "Появление внутри чужого шарика включает призрака")
	var spawn_pos: Vector2 = spawning.pos
	var neighbor_pos: Vector2 = neighbor.pos
	Race.step(overlapping, 0.01, rng)
	check((spawning.pos as Vector2).distance_to(spawn_pos) < 0.0001 and (neighbor.pos as Vector2).distance_to(neighbor_pos) < 0.0001, "Пересекающиеся при появлении шарики не раздвигаются столкновением")
	var ghost_view: Dictionary = Race.snapshot(overlapping).list.filter(func(row: Dictionary) -> bool: return int(row.peer) == 1)[0]
	check(bool(ghost_view.spawn_ghost) and float(ghost_view.alpha) <= Race.Balls.GHOST_ALPHA, "Призрак появления виден в снимке полупрозрачным")
	neighbor.pos = spawn_pos + (spawning.start_dir as Vector2) * (Race.RADIUS * 2.0 + Race.SPAWN_MARGIN * 0.5)
	Race._update_spawn_ghosts(overlapping)
	check(bool(spawning.spawn_ghost), "Призрак сохраняется до выхода за диаметр с запасом")
	neighbor.pos = spawn_pos + (spawning.start_dir as Vector2) * (Race.RADIUS * 2.0 + Race.SPAWN_MARGIN + 0.001)
	Race._update_spawn_ghosts(overlapping)
	check(not bool(spawning.spawn_ghost), "Полное расхождение с запасом возвращает столкновения")
	neighbor.pos = spawn_pos
	Race._update_spawn_ghosts(overlapping)
	check(not bool(spawning.spawn_ghost), "Обычное пересечение вне появления не включает новый призрак")
	Race.step(overlapping, 0.001, rng)
	check((spawning.pos as Vector2).distance_to(neighbor.pos) >= Race.RADIUS * 2.0 - 0.0001, "После снятия призрака столкновения снова раздвигают шарики")
	neighbor.pos = spawning.pos
	spawning.spawn_pending = true
	neighbor.spawn_pending = true
	Race._update_spawn_ghosts(overlapping)
	check(bool(spawning.spawn_ghost) and bool(neighbor.spawn_ghost), "При одновременном появлении внутри друг друга оба становятся призраками")
	Race.leave(overlapping, 2)
	check(not bool(spawning.spawn_ghost), "После выхода другого игрока призрак не застревает")
	for index in Race.NAMES.size():
		var path := Race.track(index)
		shapes[str(path)] = true
		check(path.size() == Race.SAMPLES, "Трасса %d: замкнутая линия" % index)
		var ice := 0
		for i in path.size():
			check(float(Race.nearest(path, path[i]).distance) < 0.0001, "Точка лежит на трассе")
			if Race.surface(index, i):
				ice += 1
		check(ice > 0 and ice < Race.SAMPLES, "Есть лёд и обычные участки")
		check(Race.fans(index).size() == 2, "На трассе два вентилятора")
		for fan: Dictionary in Race.fans(index):
			check(float(Race.nearest(path, fan.pos).distance) > Race.WIDTH, "Вентилятор за пределами дороги")
	check(shapes.size() == 5, "Пять разных трасс")
	var state := state_with(1)
	check(state.phase == "solo", "Один игрок — соло")
	check(is_equal_approx(Race.MAX_SPEED, Race.Balls.MAX_SPEED * 0.9 * 0.6), "Скорость гонки дополнительно уменьшена на 40 процентов")
	check(is_equal_approx(Race.ACCEL * 1.1, Race.Balls.ACCEL) and is_equal_approx(Race.DRAG * 1.1, Race.Balls.DRAG), "Базовая инерция увеличена на 10 процентов")
	state.players[1].vel = Vector2(0.2, 0.1)
	state.players[1].start_guard = false
	state.players[1].aim = (state.players[1].pos as Vector2) + Vector2.RIGHT
	Race.dash(state, 1)
	check(is_equal_approx((state.players[1].vel as Vector2).distance_to(Vector2(0.2, 0.1)), Race.Balls.DASH * 0.7), "Рывок на 30 процентов слабее, текущая скорость сохранена")
	var first_track := int(state.track)
	check(Race.change_track(state, 1, rng) and int(state.track) != first_track, "Соло: кнопка выбирает другую трассу")
	check(not Race.change_track(state, 2, rng), "Посторонний не может сменить трассу")
	state.players[1].started = 0.0
	lap(state, 1)
	check(int(state.players[1].lap) == 1 and float(state.players[1].record) > 0.0, "Соло: рекорд за один круг")
	var record := float(state.players[1].record)
	Race.join(state, 2, "Второй", 2)
	check(state.phase == "countdown" and is_equal_approx(float(state.until) - float(state.time), 10.0), "Второй игрок запускает отсчёт 10 секунд")
	check(not Race.change_track(state, 1, rng), "При двух игроках менять трассу кнопкой нельзя")
	check(float(state.players[1].record) == 0.0 and record > 0.0, "Сетевой заезд не переносит старый рекорд")
	Race.steer(state, 1, Vector2.ZERO, true)
	var start: Vector2 = state.players[1].pos
	Race.step(state, 5.0, rng)
	check(state.players[1].pos == start and not Race.dash(state, 1), "До старта движение и рывок запрещены")
	Race.step(state, 5.0, rng)
	check(state.phase == "race", "После десяти секунд заезд начался")
	Race.join(state, 3, "Поздний", 3)
	check(state.phase == "race" and int(state.players[3].lap) == 0, "Вошедший в заезд участвует с первого круга")
	Race._progress(state, 3, 0.99)
	Race._progress(state, 3, 0.01)
	check(int(state.players[3].lap) == 0, "Пересечение старта туда-обратно не даёт круг")
	state.players[3].u = 0.0
	state.players[3].progress = 0.0
	lap(state, 3, true)
	check(int(state.players[3].lap) == 0, "Обратное направление не даёт круг")
	Race._reset(state, state.players[1])
	state.players[1].lap = 1
	state.players[1].pos = Vector2(8, 8)
	Race.step(state, 0.01, rng)
	check(not bool(state.players[1].alive) and (state.players[1].pos as Vector2).distance_to(state.path[0]) > 1.0, "При вылете начинается падение без мгновенного переноса")
	check(not Race.dash(state, 1), "Во время падения рывок недоступен")
	Race.step(state, Race.FALL_TIME * 0.5, rng)
	check(not bool(state.players[1].alive) and int(state.players[1].lap) == 1, "Во время падения текущий круг сохраняется")
	var falling_snapshot := Race.snapshot(state)
	check(float(falling_snapshot.list[0].fall) > 0.4 and float(falling_snapshot.list[0].fall) < 0.6, "Снимок передаёт фазу падения для анимации")
	Race.step(state, Race.FALL_TIME * 0.5 + 0.01, rng)
	check(bool(state.players[1].alive), "Шарик появляется только после завершения падения")
	check((state.players[1].pos as Vector2).distance_to(state.path[0]) < Race.WIDTH and int(state.players[1].lap) == 1, "Вылет: возврат на старт, второй круг сохранён")
	check(absf(float(state.players[1].progress)) < 0.01, "Прогресс незаконченного круга сброшен")
	lap(state, 1)
	lap(state, 1)
	check(bool(state.players[1].done) and state.phase == "race", "Первый прошёл три круга, остальные продолжают")
	for peer in [2, 3]:
		state.players[peer].u = 0.0
		state.players[peer].progress = 0.0
		for k in 3:
			lap(state, peer)
	check(state.phase == "results" and state.finish == [1, 2, 3], "Гонка на троих закончилась после третьего финиша")
	var old_track := int(state.track)
	Race.step(state, Race.RESULTS, rng)
	check(int(state.track) != old_track and state.phase == "countdown", "Следующий заезд на другой случайной трассе")
	check(int(state.players[1].lap) == 0 and not bool(state.players[1].done), "Новый заезд сбросил круги и финиши")
	state = state_with(2)
	Race.step(state, 10.0, rng)
	for peer in [1, 2]:
		for k in 3:
			lap(state, peer)
	check(state.phase == "results" and state.finish.size() == 2, "На двоих достаточно двух финишей")
	Race.leave(state, 2)
	check(state.phase == "solo" and not bool(state.players[1].done), "Оставшийся один снова играет на рекорд")
	state = state_with(4)
	Race.step(state, 10.0, rng)
	for peer in [1, 2, 3]:
		for k in 3:
			lap(state, peer)
	check(state.phase == "results" and state.finish == [1, 2, 3] and not bool(state.players[4].done), "На четверых гонка заканчивается после трёх финишей")
	lap(state, 4)
	check(state.finish == [1, 2, 3], "После завершения заезда четвёртый финиш не добавляется")
	var standings := Race.snapshot(state)
	check(int(standings.list[0].peer) == 1 and int(standings.list[2].place) == 3 and str(standings.leader) == "Игрок 1", "Места финишировавших и ник лидера передаются снимком")
	var running := state_with(3)
	running.players[1].progress = 0.8
	running.players[2].lap = 1
	running.players[2].progress = 0.1
	running.players[3].progress = 0.9
	var running_view := Race.snapshot(running)
	check(int(running_view.list[0].peer) == 2 and int(running_view.list[1].peer) == 3 and int(running_view.list[2].place) == 3, "Место определяется кругом, затем продвижением внутри круга")
	var solo_fall := state_with(1)
	solo_fall.players[1].started = 0.0
	solo_fall.time = 12.0
	solo_fall.players[1].pos = Vector2(8, 8)
	Race.step(solo_fall, 0.01, rng)
	check(float(solo_fall.players[1].started) < 0.0 and float(Race.snapshot(solo_fall).list[0].elapsed) == 0.0, "Соло: таймер сброшен в момент начала падения")
	Race.step(solo_fall, Race.FALL_TIME + 0.01, rng)
	Race.steer(solo_fall, 1, solo_fall.path[2], true)
	Race.step(solo_fall, 0.02, rng)
	check(float(solo_fall.players[1].started) > 12.0 and float(Race.snapshot(solo_fall).list[0].elapsed) < 0.1, "Соло: после возвращения начинается новая попытка")
	check(not Race._on_road(state.path, state.path[0], state.path[60]), "Нельзя рывком срезать поперёк пропасти")
	# Лёд сохраняет больше боковой скорости, ветер действительно сдвигает шарик.
	state = state_with(1)
	var ball: Dictionary = state.players[1]
	var ice_at := 0
	var dry_at := 0
	for i in Race.SAMPLES:
		if Race.surface(int(state.track), i):
			ice_at = i
		else:
			dry_at = i
	ball.steer = true
	ball.pos = state.path[ice_at]
	ball.aim = ball.pos
	ball.vel = Vector2(0.0, 0.6)
	state.fans = []
	Race.step(state, 0.01, rng)
	var ice_speed := (ball.vel as Vector2).length()
	ball.pos = state.path[dry_at]
	ball.aim = ball.pos
	ball.vel = Vector2(0.0, 0.6)
	Race.step(state, 0.01, rng)
	check(ice_speed > (ball.vel as Vector2).length(), "На льду выше инерция")
	ball.pos = state.path[0]
	ball.aim = ball.pos
	ball.vel = Vector2.ZERO
	state.fans = [{"pos": ball.pos, "dir": Vector2.RIGHT}]
	Race.step(state, 0.01, rng)
	check((ball.vel as Vector2).x > 0.0, "Вентилятор сдвигает шарик")
	Race.force_ghost(state, 1)
	Race.step(state, 0.01, rng)
	check(ball.vel == Vector2.ZERO, "При блокировке основной игрой шарик стоит даже на ветру")
	print("Гонка: проверок %d, ошибок %d" % [checks, failed])
	quit(1 if failed else 0)
