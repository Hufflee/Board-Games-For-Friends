extends RefCounted
## Мини-игра «Сумо» (общая комната, все против всех): правила и физика без UI. Считает только хост.
## Круглая арена радиусом 1. Каждый шарик катится к своей точке (курсор игрока) и по щелчку делает рывок.
## Шарики упруго расталкивают друг друга; центр шарика за краем — вылетел, через RESPAWN секунд снова в игре.
## Очко — тому, кто последним толкнул вылетевшего (не дольше CREDIT секунд назад). Серия сбрасывается при вылете.
## Курсор ушёл с поля дольше AWAY секунд — шарик-призрак: полупрозрачный, никого не толкает и сам не толкается.
## Курсор вернулся к призраку — шарик сразу едет, но WAKE секунд проявляется и всё ещё неуязвим и безвреден.
## Ставший призраком шарик мгновенно теряет всю инерцию. Начался ход игрока в основной игре — шарик
## сразу призрак (force_ghost), без секунды ожидания.
## Состояние: {"balls": {peer: {...}}, "time", "feed": [строки], "seq"}.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const RADIUS := 0.075
const ACCEL := 2.6
const MAX_SPEED := 1.08
const DRAG := 1.6
const DASH := 1.8
const DASH_COOLDOWN := 1.92
const BOUNCE := 1.15  # толчок чуть сильнее упругого — так веселее
const RESPAWN := 1.5
const CREDIT := 4.0
const FEED_MAX := 4
const AWAY := 1.0  # через столько секунд без курсора на поле шарик становится призраком
const WAKE := 1.5  # столько секунд призрак проявляется после возвращения курсора
const GHOST_ALPHA := 0.35


static func new_state() -> Dictionary:
	return {"game": "balls", "balls": {}, "time": 0.0, "feed": [], "seq": 0}


static func join(state: Dictionary, peer: int, nick: String, color: int, rng: RandomNumberGenerator) -> void:
	if state.balls.has(peer):
		return
	var ball := {"name": nick, "color": color, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "aim": Vector2.ZERO, "steer": false,
		"score": 0, "alive": true, "respawn": 0.0, "hit_by": 0, "hit_at": -100.0, "dash_at": -100.0,
		"off_at": float(state.time), "wake_at": -100.0}
	state.balls[peer] = ball
	_spawn(state, peer, rng)
	state.seq = int(state.seq) + 1


static func leave(state: Dictionary, peer: int) -> void:
	if state.balls.erase(peer):
		state.seq = int(state.seq) + 1


## Ввод игрока: точка на арене (steer = false — курсор вне поля, шарик тормозит) и рывок.
static func steer(state: Dictionary, peer: int, aim: Vector2, on: bool) -> void:
	if not state.balls.has(peer):
		return
	var ball: Dictionary = state.balls[peer]
	var now := float(state.time)
	ball.aim = aim.limit_length(1.4)
	if on and not bool(ball.steer) and now - float(ball.off_at) >= AWAY:
		ball.wake_at = now  # курсор вернулся к призраку — проявляется
	elif not on and bool(ball.steer):
		ball.off_at = now
	ball.steer = on


## Сразу сделать шарик призраком и остановить (начался ход игрока — мини-игры заблокированы).
static func force_ghost(state: Dictionary, peer: int) -> void:
	if not state.balls.has(peer):
		return
	var ball: Dictionary = state.balls[peer]
	var now := float(state.time)
	ball.steer = false
	ball.off_at = minf(float(ball.off_at), now - AWAY)  # как будто курсор ушёл секунду назад
	ball.vel = Vector2.ZERO


## Насколько шарик виден: 1 — обычный, GHOST_ALPHA — призрак, между ними — проявляется.
static func opacity(ball: Dictionary, now: float) -> float:
	if not bool(ball.get("steer", false)):
		return GHOST_ALPHA if now - float(ball.get("off_at", now)) >= AWAY else 1.0
	var t := (now - float(ball.get("wake_at", -100.0))) / WAKE
	return 1.0 if t >= 1.0 else lerpf(GHOST_ALPHA, 1.0, clampf(t, 0.0, 1.0))


## Призрак и проявляющийся шарик не толкают и не толкаются.
static func intangible(ball: Dictionary, now: float) -> bool:
	return opacity(ball, now) < 1.0


static func dash(state: Dictionary, peer: int) -> bool:
	if not state.balls.has(peer):
		return false
	var ball: Dictionary = state.balls[peer]
	var now := float(state.time)
	if not bool(ball.alive) or now - float(ball.dash_at) < DASH_COOLDOWN:
		return false
	var dir: Vector2 = (ball.aim as Vector2) - (ball.pos as Vector2)
	if dir.length() < 0.001:
		dir = (ball.vel as Vector2) if (ball.vel as Vector2).length() > 0.001 else Vector2.RIGHT
	ball.vel = (ball.vel as Vector2) + dir.normalized() * DASH
	ball.dash_at = now
	return true


static func _spawn(state: Dictionary, peer: int, rng: RandomNumberGenerator) -> void:
	var ball: Dictionary = state.balls[peer]
	var best := Vector2.ZERO
	var best_gap := -1.0
	for attempt in 12:
		var point := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.55
		var gap := 10.0
		for other: int in state.balls:
			if other != peer and bool(state.balls[other].alive):
				gap = minf(gap, point.distance_to(state.balls[other].pos))
		if gap > best_gap:
			best_gap = gap
			best = point
		if gap > RADIUS * 3.0:
			break
	ball.pos = best
	ball.vel = Vector2.ZERO
	ball.alive = true
	ball.hit_by = 0
	ball.hit_at = -100.0


## Шаг физики на dt секунд. Возвращает события: [{"kind": "out", ...}].
static func step(state: Dictionary, dt: float, rng: RandomNumberGenerator) -> Array:
	var events := []
	state.time = float(state.time) + dt
	var now := float(state.time)
	var peers: Array = state.balls.keys()
	for peer: int in peers:
		var ball: Dictionary = state.balls[peer]
		if not bool(ball.alive):
			if now >= float(ball.respawn):
				_spawn(state, peer, rng)
			continue
		var vel: Vector2 = ball.vel
		if not bool(ball.steer) and now - float(ball.off_at) >= AWAY:
			vel = Vector2.ZERO  # посерел до конца — инерция пропадает мгновенно
		if bool(ball.steer):
			var want: Vector2 = (ball.aim as Vector2) - (ball.pos as Vector2)
			var target_vel := want.limit_length(0.25) / 0.25 * MAX_SPEED
			vel += (target_vel - vel).limit_length(ACCEL * dt)
		vel -= vel * minf(1.0, DRAG * dt * (0.4 if bool(ball.steer) else 1.0))
		ball.vel = vel
		ball.pos = (ball.pos as Vector2) + vel * dt
	# столкновения попарно
	for i in peers.size():
		var a: Dictionary = state.balls[peers[i]]
		if not bool(a.alive) or intangible(a, now):
			continue
		for j in range(i + 1, peers.size()):
			var b: Dictionary = state.balls[peers[j]]
			if not bool(b.alive) or intangible(b, now):
				continue
			var delta: Vector2 = (b.pos as Vector2) - (a.pos as Vector2)
			var dist := delta.length()
			if dist >= RADIUS * 2.0:
				continue
			var normal := delta / dist if dist > 0.0001 else Vector2.RIGHT
			var overlap := RADIUS * 2.0 - dist
			a.pos = (a.pos as Vector2) - normal * overlap * 0.5
			b.pos = (b.pos as Vector2) + normal * overlap * 0.5
			var closing := ((a.vel as Vector2) - (b.vel as Vector2)).dot(normal)
			if closing > 0.0:
				var push := normal * closing * BOUNCE
				a.vel = (a.vel as Vector2) - push
				b.vel = (b.vel as Vector2) + push
			a.hit_by = int(peers[j])
			a.hit_at = now
			b.hit_by = int(peers[i])
			b.hit_at = now
	# вылет за край
	for peer: int in peers:
		var ball: Dictionary = state.balls[peer]
		if not bool(ball.alive) or (ball.pos as Vector2).length() <= 1.0:
			continue
		ball.alive = false
		ball.score = 0
		ball.respawn = now + RESPAWN
		var by := int(ball.hit_by)
		var line := ""
		if by != 0 and state.balls.has(by) and bool(state.balls[by].alive) and now - float(ball.hit_at) <= CREDIT:
			state.balls[by].score = int(state.balls[by].score) + 1
			line = "%s вытолкнул(а) %s" % [str(state.balls[by].name), str(ball.name)]
		else:
			by = 0
			line = "%s укатился(-ась) сам(а)" % str(ball.name)
		_feed(state, line)
		events.append({"kind": "out", "peer": peer, "by": by})
	if not events.is_empty():
		state.seq = int(state.seq) + 1
	return events


static func _feed(state: Dictionary, line: String) -> void:
	var feed: Array = state.feed
	feed.push_front(line)
	while feed.size() > FEED_MAX:
		feed.pop_back()


## Сжатый снимок для рассылки: позиции и скорости — числами, остальное как есть.
static func snapshot(state: Dictionary) -> Dictionary:
	var list := []
	for peer: int in state.balls:
		var ball: Dictionary = state.balls[peer]
		list.append([peer, str(ball.name), int(ball.color), (ball.pos as Vector2), (ball.vel as Vector2), bool(ball.alive),
			int(ball.score), float(state.time) - float(ball.dash_at) < 0.25, opacity(ball, float(state.time)),
			clampf((float(state.time) - float(ball.dash_at)) / DASH_COOLDOWN, 0.0, 1.0)])
	return {"game": "balls", "list": list,
		"feed": (state.feed as Array).duplicate(), "seq": int(state.seq)}
