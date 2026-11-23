extends RefCounted
## «Гонка»: пять замкнутых трасс, лёд, вентиляторы, круги и заезды. Вся симуляция на хосте.
## Управление и призрак — как в «Сумо». Тест: tests/test_race.gd с --audio-driver Dummy.

const Balls := preload("res://hub/minigames/logic/mg_balls.gd")
const NAMES := ["Змейка", "Шиканы", "Подкова", "Каскад", "Серпантин"]
const SAMPLES := 120
const WIDTH := 0.105
const ROAD_EDGE := WIDTH + 0.0125  # внешний край серой каймы тоже относится к дороге
const RADIUS := 0.04
const LAPS := 3
const COUNTDOWN := 10.0
const RESULTS := 5.0
const FALL_TIME := 0.65
const MAX_SPEED := Balls.MAX_SPEED * 0.9 * 0.6
const INERTIA := 1.1
const ACCEL := Balls.ACCEL / INERTIA
const DRAG := Balls.DRAG / INERTIA
const DASH_FACTOR := 0.7
const SIDE_HALF_LIFE := 0.150
const ICE_SIDE_HALF_LIFE := 1.5
const TURN_RATE := PI * 1.5  # при обычной скорости тяга поворачивается примерно на 135°/с
const SPAWN_MARGIN := 0.02  # после пересечения при появлении нужно разойтись чуть дальше двух радиусов


static func track(index: int) -> PackedVector2Array:
	# Опорные точки замкнутых трасс. S-связки и шпильки различаются у всех пяти маршрутов.
	var routes := [
		[
			Vector2(-1.1, -0.55), Vector2(-0.65, -0.65), Vector2(-0.25, -0.25),
			Vector2(0.2, -0.65), Vector2(0.75, -0.62), Vector2(1.1, -0.3),
			Vector2(0.85, 0.12), Vector2(1.05, 0.6), Vector2(0.45, 0.62),
			Vector2(0.05, 0.22), Vector2(-0.45, 0.65), Vector2(-1.05, 0.52),
			Vector2(-0.82, 0.0)
		],
		[
			Vector2(-1.1, -0.55), Vector2(-0.55, -0.62), Vector2(-0.25, -0.18),
			Vector2(0.25, -0.18), Vector2(0.55, -0.62), Vector2(1.07, -0.5),
			Vector2(1.08, 0.42), Vector2(0.6, 0.62), Vector2(0.25, 0.2),
			Vector2(-0.2, 0.2), Vector2(-0.55, 0.65), Vector2(-1.05, 0.48)
		],
		[
			Vector2(-1.1, -0.6), Vector2(-0.55, -0.65), Vector2(-0.4, -0.1),
			Vector2(0.05, 0.18), Vector2(0.45, -0.1), Vector2(0.58, -0.62),
			Vector2(1.07, -0.5), Vector2(1.1, 0.4), Vector2(0.6, 0.65),
			Vector2(0.05, 0.52), Vector2(-0.5, 0.65), Vector2(-1.05, 0.4)
		],
		[
			Vector2(-1.1, -0.5), Vector2(-0.65, -0.65), Vector2(-0.1, -0.42),
			Vector2(0.45, -0.65), Vector2(1.07, -0.5), Vector2(0.87, -0.08),
			Vector2(1.08, 0.4), Vector2(0.65, 0.65), Vector2(0.28, 0.22),
			Vector2(-0.15, 0.55), Vector2(-0.6, 0.18), Vector2(-1.05, 0.5),
			Vector2(-0.88, -0.02)
		],
		[
			Vector2(-1.08, -0.55), Vector2(-0.6, -0.65), Vector2(-0.12, -0.2),
			Vector2(0.45, -0.65), Vector2(1.05, -0.5), Vector2(0.7, 0.0),
			Vector2(1.05, 0.5), Vector2(0.45, 0.65), Vector2(0.0, 0.28),
			Vector2(-0.45, 0.65), Vector2(-1.05, 0.5), Vector2(-0.7, 0.0)
		]
	]
	var nodes: Array = routes[index]
	var points := PackedVector2Array()
	for i in SAMPLES:
		var along := float(i) * nodes.size() / SAMPLES
		var k := int(along)
		var t := along - k
		var a: Vector2 = nodes[k % nodes.size()]
		var b: Vector2 = nodes[(k + 1) % nodes.size()]
		var prev: Vector2 = nodes[posmod(k - 1, nodes.size())]
		var next: Vector2 = nodes[(k + 2) % nodes.size()]
		points.append(a.cubic_interpolate(b, prev, next, t))
	return points


static func surface(index: int, segment: int) -> bool:
	var shifted := posmod(segment + index * 11, SAMPLES)
	return shifted in range(22, 38) or shifted in range(77, 91)


static func fans(index: int) -> Array:
	var points := track(index)
	var out := []
	for k in 2:
		var at := (48 + k * 53 + index * 7) % SAMPLES
		var tangent := (points[(at + 1) % SAMPLES] - points[at]).normalized()
		var side := tangent.orthogonal() * (1.0 if k == 0 else -1.0)
		var direction := (-side + tangent * (0.6 if k == 0 else -0.15)).normalized()
		var origin: Vector2 = points[at] + side * 0.26
		# Сам вентилятор всегда за дорогой; струя пересекает её и может столкнуть за дальний край.
		for attempt in 8:
			if float(nearest(points, origin).distance) > WIDTH + 0.04:
				break
			origin += side * 0.04
		out.append({"pos": origin, "dir": direction})
	return out


static func nearest(points: PackedVector2Array, pos: Vector2) -> Dictionary:
	var best := INF
	var segment := 0
	var fraction := 0.0
	for i in points.size():
		var a := points[i]
		var edge := points[(i + 1) % points.size()] - a
		var t := clampf((pos - a).dot(edge) / edge.length_squared(), 0.0, 1.0)
		var distance := pos.distance_squared_to(a + edge * t)
		if distance < best:
			best = distance
			segment = i
			fraction = t
	return {"distance": sqrt(best), "segment": segment, "u": (segment + fraction) / points.size()}


static func _on_road(points: PackedVector2Array, before: Vector2, after: Vector2) -> bool:
	# Рывок не должен перепрыгивать узкий разрыв между соседними ветвями трассы.
	var steps := maxi(1, int(ceilf(before.distance_to(after) / 0.015)))
	for i in range(1, steps + 1):
		# Проверяется центр, без прибавления радиуса: шарик может свисать над пропастью.
		if float(nearest(points, before.lerp(after, float(i) / steps)).distance) >= ROAD_EDGE - 0.000001:
			return false
	return true


static func new_state(rng: RandomNumberGenerator) -> Dictionary:
	var index := rng.randi_range(0, NAMES.size() - 1)
	return {"game": "race", "track": index, "path": track(index), "fans": fans(index), "players": {},
		"time": 0.0, "phase": "solo", "until": 0.0, "go_until": 0.0, "finish": [], "seq": 0, "round": 1}


static func _reset(state: Dictionary, ball: Dictionary) -> void:
	var slot := 0
	if state.players.size() > 1:
		slot = maxi(0, state.players.keys().find(int(ball.get("peer", 0))))
	var segment := posmod(-int(slot / 2) * 2, SAMPLES)
	var start: Vector2 = state.path[segment]
	var tangent: Vector2 = (state.path[(segment + 1) % SAMPLES] as Vector2) - start
	ball.pos = start + tangent.normalized().orthogonal() * (0.045 if slot % 2 else -0.045) if state.players.size() > 1 else start
	ball.vel = Vector2.ZERO
	ball.alive = true
	ball.fall_at = -1.0
	ball.fall_velocity = Vector2.ZERO
	ball.course = Vector2.ZERO
	ball.start_guard = true
	ball.start_pos = ball.pos
	ball.start_dir = tangent.normalized()
	ball.spawn_pending = true
	ball.spawn_ghost = false
	ball.steer = false
	ball.aim = ball.pos
	var u := float(nearest(state.path, ball.pos).u)
	ball.u = u
	ball.progress = u - 1.0 if u > 0.5 else u


static func join(state: Dictionary, peer: int, nick: String, color: int) -> void:
	if state.players.has(peer):
		return
	var ball := {"peer": peer, "name": nick, "color": color, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "aim": Vector2.ZERO,
		"steer": false, "off_at": float(state.time), "wake_at": -100.0, "dash_at": -100.0,
		"alive": true, "lap": 0, "progress": 0.0, "u": 0.0, "done": false, "started": -1.0,
		"record": 0.0, "record_seq": 0, "falls": 0}
	state.players[peer] = ball
	_reset(state, ball)
	if state.players.size() == 2 and state.phase == "solo":
		_begin(state)
	_update_spawn_ghosts(state)
	state.seq = int(state.seq) + 1


static func change_track(state: Dictionary, peer: int, rng: RandomNumberGenerator) -> bool:
	if state.phase != "solo" or state.players.size() != 1 or not state.players.has(peer):
		return false
	state.track = (int(state.track) + rng.randi_range(1, NAMES.size() - 1)) % NAMES.size()
	state.path = track(int(state.track))
	state.fans = fans(int(state.track))
	state.round = int(state.round) + 1
	var ball: Dictionary = state.players[peer]
	_reset(state, ball)
	ball.lap = 0
	ball.started = -1.0
	ball.record = 0.0
	ball.falls = 0
	ball.steer = false
	ball.off_at = float(state.time) - Balls.AWAY
	ball.dash_at = -100.0
	state.seq = int(state.seq) + 1
	return true


static func _begin(state: Dictionary) -> void:
	state.phase = "countdown"
	state.until = float(state.time) + COUNTDOWN
	state.finish = []
	for ball: Dictionary in state.players.values():
		_reset(state, ball)
		ball.lap = 0
		ball.done = false
		ball.started = -1.0
		ball.falls = 0
		ball.record = 0.0
	_update_spawn_ghosts(state)
	state.seq = int(state.seq) + 1


static func leave(state: Dictionary, peer: int) -> void:
	if not state.players.erase(peer):
		return
	if state.players.size() == 1:
		state.phase = "solo"
		state.finish = []
		for ball: Dictionary in state.players.values():
			_reset(state, ball)
			ball.lap = 0
			ball.done = false
			ball.started = -1.0
			ball.record = 0.0
	elif state.phase == "race":
		_end_if_ready(state)
	_update_spawn_ghosts(state)
	state.seq = int(state.seq) + 1


static func steer(state: Dictionary, peer: int, aim: Vector2, on: bool) -> void:
	# Сумо использует тот же формат ввода и таймеры призрака.
	if not aim.is_finite():
		return
	var keep_start_course := false
	if state.players.has(peer) and on:
		var ball: Dictionary = state.players[peer]
		if bool(ball.get("start_guard", false)):
			var want := aim - (ball.pos as Vector2)
			var forward := want.dot(ball.start_dir)
			on = forward > 0.01
			aim = (ball.pos as Vector2) + want.limit_length(0.25)
			keep_start_course = on
	Balls.steer({"balls": state.players, "time": state.time}, peer, aim, on)
	if keep_start_course:
		# Круговой ограничитель координат «Сумо» не должен менять угол у внешнего края трассы.
		state.players[peer].aim = aim


static func force_ghost(state: Dictionary, peer: int) -> void:
	Balls.force_ghost({"balls": state.players, "time": state.time}, peer)


static func dash(state: Dictionary, peer: int) -> bool:
	if state.phase not in ["solo", "race"] or not state.players.has(peer) or bool(state.players[peer].done) or not bool(state.players[peer].alive):
		return false
	if bool(state.players[peer].get("start_guard", false)) and not bool(state.players[peer].steer):
		return false
	if float(state.players[peer].started) < 0.0:
		state.players[peer].started = state.time
	var before: Vector2 = state.players[peer].vel
	if not Balls.dash({"balls": state.players, "time": state.time}, peer):
		return false
	state.players[peer].vel = before + ((state.players[peer].vel as Vector2) - before) * DASH_FACTOR
	return true


static func _end_if_ready(state: Dictionary) -> void:
	var count := 0
	for peer: int in state.finish:
		if state.players.has(peer):
			count += 1
	if count >= mini(3, state.players.size()):
		state.phase = "results"
		state.until = float(state.time) + RESULTS
		state.seq = int(state.seq) + 1


static func _progress(state: Dictionary, peer: int, u: float) -> void:
	var ball: Dictionary = state.players[peer]
	if state.phase not in ["solo", "race"] or bool(ball.done) or not bool(ball.alive):
		return
	var change := wrapf(u - float(ball.u), -0.5, 0.5)
	ball.u = u
	# Маленькие последовательные шаги по кольцу; обратный ход отнимает прогресс.
	if absf(change) > 0.08:
		return
	ball.progress = float(ball.progress) + change
	if float(ball.progress) < 1.0 - 0.00001:
		return
	ball.progress = float(ball.progress) - 1.0
	ball.lap = int(ball.lap) + 1
	if state.phase == "solo":
		var elapsed := float(state.time) - float(ball.started)
		if float(ball.started) >= 0.0 and elapsed > 0.0:
			ball.record = elapsed
			ball.record_seq = int(ball.record_seq) + 1
		ball.started = state.time
	elif int(ball.lap) >= LAPS:
		ball.done = true
		ball.vel = Vector2.ZERO
		state.finish.append(peer)
		_end_if_ready(state)
	state.seq = int(state.seq) + 1


## Призрак включается только при появлении внутри другого шарика и снимается после полного расхождения.
## Обход двухфазный: одновременные появления проверяются по окончательным позициям всех игроков.
static func _update_spawn_ghosts(state: Dictionary) -> void:
	for peer: int in state.players:
		var ball: Dictionary = state.players[peer]
		if not bool(ball.get("spawn_pending", false)):
			continue
		ball.spawn_pending = false
		for other: int in state.players:
			var neighbor: Dictionary = state.players[other]
			if other != peer and bool(neighbor.alive) and not bool(neighbor.done) and (ball.pos as Vector2).distance_to(neighbor.pos) < RADIUS * 2.0:
				ball.spawn_ghost = true
				break
	for peer: int in state.players:
		var ball: Dictionary = state.players[peer]
		if not bool(ball.get("spawn_ghost", false)):
			continue
		var overlap := false
		for other: int in state.players:
			var neighbor: Dictionary = state.players[other]
			if other != peer and bool(neighbor.alive) and not bool(neighbor.done) and (ball.pos as Vector2).distance_to(neighbor.pos) <= RADIUS * 2.0 + SPAWN_MARGIN:
				overlap = true
				break
		if not overlap:
			ball.spawn_ghost = false


static func step(state: Dictionary, dt: float, rng: RandomNumberGenerator) -> bool:
	var old_seq := int(state.seq)
	state.time = float(state.time) + dt
	var now := float(state.time)
	if state.phase == "results" and now >= float(state.until):
		state.track = (int(state.track) + rng.randi_range(1, NAMES.size() - 1)) % NAMES.size()
		state.path = track(int(state.track))
		state.fans = fans(int(state.track))
		state.round = int(state.round) + 1
		_begin(state)
	if state.phase == "countdown" and now >= float(state.until):
		state.phase = "race"
		state.go_until = now + 0.6
		for ball: Dictionary in state.players.values():
			ball.started = now
		state.seq = int(state.seq) + 1
	if state.phase not in ["solo", "race"]:
		_update_spawn_ghosts(state)
		return int(state.seq) != old_seq
	var previous := {}
	for peer: int in state.players:
		var ball: Dictionary = state.players[peer]
		previous[peer] = ball.pos
		if bool(ball.done):
			continue
		if not bool(ball.alive):
			if now >= float(ball.fall_at) + FALL_TIME:
				_reset(state, ball)
				previous[peer] = ball.pos
				state.seq = int(state.seq) + 1
			continue
		if not bool(ball.steer) and now - float(ball.off_at) >= Balls.AWAY:
			ball.vel = Vector2.ZERO
			continue
		var near := nearest(state.path, ball.pos)
		var ice := surface(int(state.track), int(near.segment))
		if bool(ball.steer) and float(ball.started) < 0.0:
			ball.started = now
		var vel := _drive_velocity(ball, dt, ice)
		for fan: Dictionary in state.fans:
			var offset: Vector2 = (ball.pos as Vector2) - (fan.pos as Vector2)
			var along := offset.dot(fan.dir)
			var across := absf(offset.dot((fan.dir as Vector2).orthogonal()))
			if along >= 0.0 and along < 0.70 and across < 0.12:
				vel += (fan.dir as Vector2) * 1.5 * dt
		ball.vel = vel
		ball.pos = (ball.pos as Vector2) + vel * dt
	_update_spawn_ghosts(state)
	# Контакты как в сумо; финишировавшие и призраки не мешают заезду.
	var peers: Array = state.players.keys()
	for i in peers.size():
		var a: Dictionary = state.players[peers[i]]
		if bool(a.done) or not bool(a.alive) or bool(a.spawn_ghost) or Balls.intangible(a, now):
			continue
		for j in range(i + 1, peers.size()):
			var b: Dictionary = state.players[peers[j]]
			if bool(b.done) or not bool(b.alive) or bool(b.spawn_ghost) or Balls.intangible(b, now):
				continue
			var delta: Vector2 = (b.pos as Vector2) - (a.pos as Vector2)
			var dist := delta.length()
			if dist >= RADIUS * 2.0:
				continue
			var normal := delta / dist if dist > 0.0001 else Vector2.RIGHT
			a.pos = (a.pos as Vector2) - normal * (RADIUS - dist * 0.5)
			b.pos = (b.pos as Vector2) + normal * (RADIUS - dist * 0.5)
			var closing := ((a.vel as Vector2) - (b.vel as Vector2)).dot(normal)
			if closing > 0.0:
				a.vel = (a.vel as Vector2) - normal * closing * Balls.BOUNCE
				b.vel = (b.vel as Vector2) + normal * closing * Balls.BOUNCE
	for peer: int in peers:
		var ball: Dictionary = state.players[peer]
		if bool(ball.done) or not bool(ball.alive):
			continue
		var near := nearest(state.path, ball.pos)
		if not _on_road(state.path, previous[peer], ball.pos):
			ball.alive = false
			ball.fall_at = now
			ball.fall_velocity = (ball.vel as Vector2).limit_length(0.4)
			ball.vel = Vector2.ZERO
			ball.falls = int(ball.falls) + 1
			ball.progress = 0.0
			ball.u = 0.0
			if state.phase == "solo":
				ball.started = -1.0
			state.seq = int(state.seq) + 1
		else:
			if bool(ball.get("start_guard", false)) and ((ball.pos as Vector2) - (ball.start_pos as Vector2)).dot(ball.start_dir) >= RADIUS * 2.0:
				ball.start_guard = false
			_progress(state, peer, float(near.u))
	return int(state.seq) != old_seq


## Тяга поворачивается постепенно, продольная скорость регулируется отдельно от бокового скольжения.
## Боковая скорость теряет половину за 0,150 с на дороге и 1,5 с на льду: постоянный занос, без таймера.
static func _drive_velocity(ball: Dictionary, dt: float, ice: bool) -> Vector2:
	var vel: Vector2 = ball.vel
	var want: Vector2 = (ball.aim as Vector2) - (ball.pos as Vector2)
	var course: Vector2 = ball.get("course", Vector2.ZERO)
	if course.is_zero_approx():
		course = vel.normalized() if not vel.is_zero_approx() else (want.normalized() if not want.is_zero_approx() else Vector2.RIGHT)
	if bool(ball.steer) and want.length() > 0.025:
		var desired := want.normalized()
		if vel.length() < MAX_SPEED * 0.1:
			course = desired  # с места можно ехать сразу в выбранную сторону
		else:
			var turn := TURN_RATE * dt / (1.0 + vel.length() / MAX_SPEED)
			course = course.rotated(clampf(course.angle_to(desired), -turn, turn)).normalized()
	ball.course = course
	var forward := vel.dot(course)
	var sideways := vel - course * forward
	sideways *= pow(0.5, dt / (ICE_SIDE_HALF_LIFE if ice else SIDE_HALF_LIFE))
	if bool(ball.steer):
		var target := MAX_SPEED * minf(1.0, want.length() / 0.25)
		forward = move_toward(forward, target, ACCEL * dt * (0.24 if ice else 1.0))
	# Сопротивление действует вдоль тяги; боковой занос гасит только сцепление выше.
	forward *= exp(-DRAG * dt * (0.08 if ice else (0.4 if bool(ball.steer) else 1.0)))
	return course * forward + sideways


static func _ahead(state: Dictionary, a: int, b: int) -> bool:
	var first: Dictionary = state.players[a]
	var second: Dictionary = state.players[b]
	if bool(first.done) != bool(second.done):
		return bool(first.done)
	if bool(first.done):
		return state.finish.find(a) < state.finish.find(b)
	var first_progress := int(first.lap) + float(first.progress)
	var second_progress := int(second.lap) + float(second.progress)
	return a < b if is_equal_approx(first_progress, second_progress) else first_progress > second_progress


static func snapshot(state: Dictionary) -> Dictionary:
	var list := []
	var peers: Array = state.players.keys()
	peers.sort_custom(func(a: int, b: int) -> bool: return _ahead(state, a, b))
	var place := 0
	for peer: int in peers:
		place += 1
		var ball: Dictionary = state.players[peer]
		list.append({"peer": peer, "place": place, "name": ball.name, "color": ball.color, "pos": ball.pos, "vel": ball.vel,
			"dash_ready": bool(ball.alive) and not bool(ball.done) and state.phase in ["solo", "race"] and float(state.time) - float(ball.dash_at) >= Balls.DASH_COOLDOWN,
			"fall": clampf((float(state.time) - float(ball.fall_at)) / FALL_TIME, 0.0, 1.0) if not bool(ball.alive) else -1.0,
			"fall_velocity": ball.fall_velocity,
			"alpha": minf(Balls.opacity(ball, float(state.time)), Balls.GHOST_ALPHA if bool(ball.spawn_ghost) else 1.0),
			"spawn_ghost": bool(ball.spawn_ghost), "lap": ball.lap, "done": ball.done,
			"elapsed": maxf(0.0, float(state.time) - float(ball.started)) if float(ball.started) >= 0.0 else 0.0,
			"record": ball.record, "record_seq": ball.record_seq, "falls": ball.falls})
	return {"game": "race", "track": state.track, "phase": state.phase, "list": list,
		"leader": str(state.players[peers[0]].name) if not peers.is_empty() else "",
		"left": maxf(0.0, float(state.until) - float(state.time)), "finish": state.finish.duplicate(),
		"go_left": maxf(0.0, float(state.go_until) - float(state.time)), "seq": state.seq, "round": state.round}
