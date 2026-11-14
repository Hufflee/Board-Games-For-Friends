extends RefCounted
## Мини-игра «Лови звёздочку» (общая комната, все против всех): правила без UI. Считает только хост.
## Время от времени у всех участников в случайном месте экрана появляется звёздочка (координаты — доли экрана).
## Кто первым нажал — получает очко, звезда исчезает у всех. Не поймали за LIFE секунд — улетает.
## Состояние: {"players": {peer: {name, color, score}}, "star": {} или {id, x, y, until}, "next", "time", "last", "seq"}.
## Тесты: godot --headless --path . --script res://tests/test_minigames.gd

const LIFE := 6.0
const GAP_MIN := 4.0
const GAP_MAX := 10.0
const EDGE := 0.07  # звезда не ближе этой доли к краю экрана


static func new_state() -> Dictionary:
	return {"game": "stars", "players": {}, "star": {}, "next": 3.0, "time": 0.0, "last": "", "seq": 0, "ids": 0}


static func join(state: Dictionary, peer: int, nick: String, color: int) -> void:
	if not state.players.has(peer):
		state.players[peer] = {"name": nick, "color": color, "score": 0}
		state.seq = int(state.seq) + 1


static func leave(state: Dictionary, peer: int) -> void:
	if state.players.erase(peer):
		state.seq = int(state.seq) + 1


## Шаг времени. Возвращает true, если звезда появилась или пропала (надо разослать снимок).
static func step(state: Dictionary, dt: float, rng: RandomNumberGenerator) -> bool:
	state.time = float(state.time) + dt
	var now := float(state.time)
	var star: Dictionary = state.star
	if not star.is_empty():
		if now < float(star.until):
			return false
		state.star = {}
		state.last = "Звёздочка улетела"
		state.next = now + rng.randf_range(GAP_MIN, GAP_MAX)
		state.seq = int(state.seq) + 1
		return true
	if (state.players as Dictionary).is_empty() or now < float(state.next):
		return false
	state.ids = int(state.ids) + 1
	state.star = {"id": int(state.ids), "x": rng.randf_range(EDGE, 1.0 - EDGE), "y": rng.randf_range(EDGE, 1.0 - EDGE), "until": now + LIFE}
	state.seq = int(state.seq) + 1
	return true


## Нажатие на звезду id. Первый — получает очко; опоздавшим — false.
static func catch_star(state: Dictionary, peer: int, id: int, rng: RandomNumberGenerator) -> bool:
	var star: Dictionary = state.star
	if star.is_empty() or int(star.id) != id or not state.players.has(peer):
		return false
	var player: Dictionary = state.players[peer]
	player.score = int(player.score) + 1
	state.last = "%s поймал(а) звёздочку" % str(player.name)
	state.star = {}
	state.next = float(state.time) + rng.randf_range(GAP_MIN, GAP_MAX)
	state.seq = int(state.seq) + 1
	return true


static func snapshot(state: Dictionary) -> Dictionary:
	var list := []
	for peer: int in state.players:
		var player: Dictionary = state.players[peer]
		list.append([peer, str(player.name), int(player.color), int(player.score)])
	var star: Dictionary = state.star
	var view_star := {} if star.is_empty() else {"id": int(star.id), "x": float(star.x), "y": float(star.y)}
	return {"game": "stars", "list": list, "star": view_star, "last": str(state.last), "seq": int(state.seq)}
