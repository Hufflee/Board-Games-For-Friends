class_name CGRules
extends RefCounted
## Чистое хостовое состояние пользовательской игры. Запуск проверки: tests/test_custom_rules.gd.

const Definition := preload("res://games/custom/logic/cg_def.gd")
const Interp := preload("res://games/custom/logic/cg_interp.gd")
var definition: Dictionary = {}
var state: Dictionary = {}
var players: Array = []
var last_error := ""
var rng := RandomNumberGenerator.new()
var steps := 0
var phase: String:
	get: return str(state.get("phase", "setup"))
var turn_no: int:
	get: return int(state.get("turn_no", 0))

func load_definition(data: Dictionary) -> Array:
	var result := Definition.validate(data)
	if result.errors.is_empty():
		definition = data.duplicate(true)
	return result.errors

func new_game(seats: Array, options: Dictionary = {}) -> String:
	if definition.is_empty():
		return "Сначала загрузите описание игры."
	var limits: Array = definition.meta.get("players", [2, 8])
	if seats.size() < int(limits[0]) or seats.size() > int(limits[1]):
		return "Число игроков не подходит для этой игры."
	players = seats.duplicate(true)
	for player: Dictionary in players:
		player["bot"] = false
		player["eliminated"] = false
		if player.has("steam_id"):
			player.steam_id = str(player.steam_id)
	rng.seed = int(options.get("seed", 1))
	state = {"format": 1, "players": players, "phase": str(definition.rules.phases[0]), "current": 0, "leader": 0,
		"turn_no": 1, "round": 1, "revision": 0, "zones": {}, "cards": {}, "vars": {"shared": {}, "player": [], "team": {}},
		"dice": {}, "reveals": {}, "hints": [], "skips": {}, "pending": {}, "log": [], "trace": [], "winners": [], "rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"turn_seconds": clampf(float(options.get("turn_time", 0)), 0, 3600), "timer_left": clampf(float(options.get("turn_time", 0)), 0, 3600), "timed_out": false}
	state.leader = clampi(int(options.get("leader", 0)), 0, players.size() - 1)
	for s in players.size():
		state.vars.player.append({})
	for v: Dictionary in definition.rules.get("vars", []):
		match str(v.get("scope", "shared")):
			"shared": state.vars.shared[v.id] = v.get("init", 0)
			"player":
				for s in players.size():
					state.vars.player[s][v.id] = v.get("init", 0)
			"team":
				for p: Dictionary in players:
					var key := str(p.get("team", 0))
					if not state.vars.team.has(key):
						state.vars.team[key] = {}
					state.vars.team[key][v.id] = v.get("init", 0)
	for item: Dictionary in zone_defs():
		if item.get("owner", "shared") == "player":
			for s in players.size():
				state.zones["%s@%d" % [item.id, s]] = []
		elif item.get("owner", "shared") == "team":
			for p: Dictionary in players:
				state.zones["%s#%s" % [item.id, str(p.get("team", 0))]] = []
		else:
			state.zones[item.id] = []
	var card_no := 0
	for deck: Dictionary in definition.elements.get("decks", []):
		var destinations: Array = []
		var zone := str(deck.get("zone", deck.id))
		match str(deck.get("owner", "shared")):
			"player":
				for seat in players.size():
					destinations.append("%s@%d" % [zone, seat])
			"team":
				for player: Dictionary in players:
					var destination := zone + "#" + str(player.get("team", 0))
					if not destinations.has(destination):
						destinations.append(destination)
			_:
				destinations.append(zone)
		for destination: String in destinations:
			if not state.zones.has(destination):
				return "Для колоды %s нет начальной зоны %s." % [deck.id, destination]
			for row in deck.rows.size():
				for copy_no in int(deck.rows[row].get("copies", 1)):
					card_no += 1
					var id := "c%d" % card_no
					state.cards[id] = {"id": id, "deck": deck.id, "row": row, "data": deck.rows[row].duplicate(true), "face_up": false, "visible_to": []}
					state.zones[destination].append(id)
	for token: Dictionary in definition.elements.get("tokens", []):
		var destination := str(token.get("zone", "table"))
		if not state.zones.has(destination):
			return "Для жетона не найдена общая зона."
		for index in int(token.get("count", 1)):
			card_no += 1
			var id := "c%d" % card_no
			var data := token.duplicate(true)
			data["kind"] = "token"
			state.cards[id] = {"id": id, "deck": token.id, "data": data, "face_up": true, "visible_to": []}
			state.zones[destination].append(id)
	last_error = ""
	steps = 0
	var context := {"actor": 0, "depth": 0}
	var frames: Array = [{"event": "turn_start", "initial": true, "context": context.duplicate()}, {"event": "round_start", "initial": true, "context": context.duplicate()}]
	frames.append_array(frames_for("start", context))
	var error := Interp.run(self, frames)
	state.rng_state = str(rng.state)
	return error

func zone_defs() -> Array:
	var out: Array = []
	for screen: Dictionary in definition.layout.get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("kind") == "zone":
				out.append(item)
	return out

func zone_def(key: String) -> Dictionary:
	var base := key.get_slice("@", 0).get_slice("#", 0)
	for item: Dictionary in zone_defs():
		if item.id == base:
			return item
	return {}

func zone_owner(key: String) -> int:
	return int(key.get_slice("@", 1)) if key.contains("@") else -1

func owns_zone(key: String, seat: int) -> bool:
	if key.contains("@"):
		return zone_owner(key) == seat
	if key.contains("#"):
		return seat >= 0 and seat < players.size() and str(players[seat].get("team", 0)) == key.get_slice("#", 1)
	return true

func card_zone(id: String) -> String:
	for zone: String in state.zones:
		if state.zones[zone].has(id):
			return zone
	return ""

func card_visible(id: String, seat: int) -> bool:
	if not state.cards.has(id):
		return false
	var key := card_zone(id)
	var zone := zone_def(key)
	var card: Dictionary = state.cards[id]
	var reveal: Dictionary = state.get("reveals", {}).get(id, {})
	var temporary: bool = not reveal.is_empty() and (int(reveal.get("seat", -1)) == -1 or int(reveal.get("seat", -1)) == seat)
	return temporary or bool(card.face_up) or (seat >= 0 and owns_zone(key, seat) and zone.get("owner", "shared") != "shared" and zone.get("view", "row") != "pile") or card.visible_to.has(seat)

func move_card(id: String, destination: String, position: String = "top") -> bool:
	if not state.cards.has(id) or not state.zones.has(destination):
		last_error = "Карта или зона перемещения не найдена."
		return false
	var source := card_zone(id)
	if source.is_empty():
		last_error = "Карта потеряла свою зону."
		return false
	state.zones[source].erase(id)
	if source != destination:
		state.cards[id].erase("pos")
	var target: Array = state.zones[destination]
	if position == "bottom":
		target.push_front(id)
	elif position == "random":
		target.insert(rng.randi_range(0, target.size()), id)
	else:
		target.append(id)
	return true

func next_player(from: int) -> int:
	for distance in range(1, players.size() + 1):
		var candidate := posmod(from + distance, players.size())
		if not bool(players[candidate].get("eliminated", false)) and not state.get("skips", {}).has(str(candidate)):
			return candidate
	return from

func reset_clock() -> void:
	state.timer_left = float(state.get("turn_seconds", 0))
	state.timed_out = false

func var_def(id: String) -> Dictionary:
	for entry: Dictionary in definition.rules.get("vars", []):
		if entry.id == id:
			return entry
	return {}

func get_var(id: String, who: int = 0) -> Variant:
	var v := var_def(id)
	if v.is_empty():
		last_error = "Переменная %s не найдена." % id
		return null
	match str(v.get("scope", "shared")):
		"player":
			if who < 0 or who >= players.size():
				last_error = "Игрок переменной не найден."
				return null
			return state.vars.player[who].get(id)
		"team": return state.vars.team.get(str(who), {}).get(id)
	return state.vars.shared.get(id)

func set_var(id: String, who: int, value: Variant) -> void:
	var v := var_def(id)
	if v.is_empty():
		last_error = "Переменная %s не найдена." % id
		return
	var type := str(v.get("type", "number"))
	if type == "number" and not Definition._number(value) or type == "bool" and not value is bool or type == "text" and not value is String:
		last_error = "Неверный тип значения переменной %s." % id
		return
	match str(v.get("scope", "shared")):
		"player":
			if who < 0 or who >= players.size():
				last_error = "Игрок переменной не найден."
			else:
				state.vars.player[who][id] = value
		"team":
			if not state.vars.team.has(str(who)):
				last_error = "Команда переменной не найдена."
			else:
				state.vars.team[str(who)][id] = value
		_: state.vars.shared[id] = value

func chain_allowed(chain: Dictionary, seat: int, context: Dictionary) -> bool:
	var event: Dictionary = chain.get("event", {})
	if event.has("phase") and str(event.phase) != phase:
		return false
	for key: String in ["from", "to"]:
		if event.has(key) and str(Interp.value(self, event[key], context)) != str(context.get(key, "")):
			return false
	match str(event.get("by", "all")):
		"current":
			if seat != int(state.current): return false
		"leader", "role:leader":
			if seat != int(state.leader): return false
	var by := str(event.get("by", "all"))
	if by.begins_with("role:") and by != "role:leader" and seat >= 0 and seat < players.size():
		if str(players[seat].get("role", "")) != by.trim_prefix("role:"):
			return false
	if seat < 0 or seat >= players.size() or bool(players[seat].get("eliminated", false)):
		return false
	return bool(Interp.value(self, chain.get("guard", true), context))

func fire(kind: String, context: Dictionary) -> String:
	return Interp.run(self, frames_for(kind, context))

func frames_for(kind: String, context: Dictionary) -> Array:
	if int(context.get("depth", 0)) > 16:
		last_error = "Слишком глубокая цепочка событий."
		return []
	var frames: Array = []
	for chain: Dictionary in definition.rules.get("chains", []):
		var event: Dictionary = chain.get("event", {})
		if str(event.get("type", "")) != kind:
			continue
		if event.has("id") and str(event.id) != str(context.get("id", "")):
			continue
		if chain_allowed(chain, int(context.get("actor", state.current)), context):
			frames.push_front({"blocks": chain.get("blocks", []), "index": 0, "context": context.duplicate(true)})
	return frames

func act(seat: int, kind: String, data: Dictionary) -> bool:
	if not Definition._json_only(data, 0):
		return false
	if state.is_empty() or phase == "game_over" or seat < 0 or seat >= players.size():
		return false
	if not Interp._equal(data.get("revision", -1), state.revision):
		return false
	var before := state.duplicate(true)
	var saved_rng := rng.state
	last_error = ""
	steps = 0
	var ok := false
	if not state.pending.is_empty():
		ok = Interp.answer(self, seat, kind, data)
	else:
		for action: Dictionary in legal_actions(seat):
			if not _same_action(action, kind, data):
				continue
			if kind in ["manual_place", "manual_place_top"]:
				if _point(data.get("pos")):
					var id := str(action.card) if kind == "manual_place" else str(state.zones[str(action.id)].back())
					state.cards[id]["pos"] = data.pos.duplicate()
					state.zones[str(action.id)].erase(id)
					state.zones[str(action.id)].append(id)
					ok = fire("move", {"actor": seat, "card": id, "from": action.id, "to": action.id, "depth": 0}).is_empty()
			elif kind == "manual_flip_top":
				var id := str(state.zones[str(action.id)].back())
				state.cards[id].face_up = not bool(state.cards[id].face_up)
				ok = true
			elif kind == "manual_roll":
				ok = Interp.run(self, [{"blocks": [{"op": "roll_player", "player": seat, "count": action.count, "visible": action.visible}], "index": 0, "context": {"actor": seat}}]).is_empty()
			elif kind == "manual_resource":
				var v := var_def(str(action.id))
				var owner := int(players[seat].get("team", 0)) if v.get("scope") == "team" else seat
				var old: Variant = get_var(str(action.id), owner)
				if Definition._number(old):
					set_var(str(action.id), owner, old + int(action.delta))
					ok = last_error.is_empty()
			elif kind == "manual_move":
				var id := str(action.get("card", ""))
				if id.is_empty():
					id = str(state.zones[str(action.id)].back())
				ok = move_card(id, str(action.to))
				if ok and zone_def(str(action.to)).get("view") == "free" and data.has("pos"):
					ok = _point(data.pos)
					if ok:
						state.cards[id]["pos"] = data.pos.duplicate()
				if ok:
					ok = fire("move", {"actor": seat, "card": id, "from": action.id, "to": action.to, "depth": 0}).is_empty()
			elif kind == "manual_flip":
				state.cards[str(action.card)].face_up = not bool(state.cards[str(action.card)].face_up)
				ok = true
			elif kind == "manual_shuffle":
				ok = Interp.run(self, [{"blocks": [{"op": "shuffle", "zone": action.id}], "index": 0, "context": {"actor": seat}}]).is_empty()
			else:
				var context := {"actor": seat, "id": data.get("id", ""), "card": data.get("card", ""), "depth": 0}
				ok = fire(kind, context).is_empty()
			break
	if not ok or not last_error.is_empty():
		state = before
		players = state.players
		rng.state = saved_rng
		return false
	state.revision += 1
	state.rng_state = str(rng.state)
	return true

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Definition._number(value[0]) and Definition._number(value[1]) and float(value[0]) >= 0 and float(value[0]) <= 1 and float(value[1]) >= 0 and float(value[1]) <= 1

func _same_action(action: Dictionary, kind: String, data: Dictionary) -> bool:
	if str(action.kind) != kind:
		return false
	for key: String in ["id", "card", "to", "delta"]:
		var fallback: Variant = 0 if key == "delta" else ""
		if not Interp._equal(action.get(key, fallback), data.get(key, fallback)):
			return false
	return true

func legal_actions(seat: int) -> Array:
	# Перечисление для UI/фазза не должно менять случайный поток и ошибку партии.
	var saved_rng := rng.state
	var saved_error := last_error
	last_error = ""
	var out := _legal_actions(seat)
	if not last_error.is_empty():
		out.clear()
	rng.state = saved_rng
	last_error = saved_error
	return out

func _legal_actions(seat: int) -> Array:
	var out: Array = []
	if state.is_empty() or phase == "game_over" or seat < 0 or seat >= players.size() or bool(players[seat].get("eliminated", false)):
		return out
	if not state.pending.is_empty():
		if int(state.pending.get("seat", -1)) == seat:
			out.append({"kind": "answer", "pending": state.pending.get("kind"), "options": state.pending.get("options", []).duplicate(true)})
		return out
	for chain: Dictionary in definition.rules.get("chains", []):
		var event: Dictionary = chain.get("event", {})
		var kind := str(event.get("type", ""))
		if kind not in ["button", "card"]:
			continue
		var context := {"actor": seat, "id": event.get("id", ""), "depth": 0}
		if kind == "card":
			var zone := str(Interp.value(self, event.get("zone", ""), context))
			if state.zones.has(zone) and owns_zone(zone, seat):
				for id: String in state.zones[zone]:
					context.card = id
					if card_visible(id, seat) and chain_allowed(chain, seat, context):
						out.append({"kind": kind, "id": event.get("id", ""), "card": id, "zone": zone})
		elif chain_allowed(chain, seat, context):
			out.append({"kind": kind, "id": event.get("id", "")})
	for source: String in state.zones:
		if not bool(zone_def(source).get("free", false)) or not owns_zone(source, seat):
			continue
		var cards: Array = state.zones[source]
		if not cards.is_empty() and not card_visible(str(cards.back()), seat) and state.cards[str(cards.back())].data.get("kind") != "token":
			out.append({"kind": "manual_flip_top", "id": source})
			if zone_def(source).get("view") == "free":
				out.append({"kind": "manual_place_top", "id": source, "pos": [0.5, 0.5]})
		if cards.size() > 1:
			out.append({"kind": "manual_shuffle", "id": source})
		for id: String in cards:
			if card_visible(id, seat):
				if zone_def(source).get("view") == "free":
					out.append({"kind": "manual_place", "id": source, "card": id, "pos": [0.5, 0.5]})
				if state.cards[id].data.get("kind") != "token":
					out.append({"kind": "manual_flip", "id": source, "card": id})
			elif id != str(cards.back()):
				continue
			for target: String in state.zones:
				if source == target or not bool(zone_def(target).get("free", false)) or not owns_zone(target, seat):
					continue
				out.append({"kind": "manual_move", "id": source, "card": id if card_visible(id, seat) else "", "to": target})
	for dice: Dictionary in definition.elements.get("dice", []):
		if dice.get("free", false):
			out.append({"kind": "manual_roll", "id": dice.id, "title": dice.get("title", "Бросить кубики"), "count": int(dice.get("count", 1)), "visible": dice.get("visible", "all")})
	for resource: Dictionary in definition.rules.get("vars", []):
		if resource.get("free", false) and resource.get("type", "number") == "number":
			for delta: int in [-1, 1]:
				out.append({"kind": "manual_resource", "id": resource.id, "title": resource.get("title", resource.id), "delta": delta})
	return out

func get_view(seat: int) -> Dictionary:
	var zones := {}
	for key: String in state.get("zones", {}):
		var zone := zone_def(key)
		var cards: Array = []
		for id: String in state.zones[key]:
			var card: Dictionary = state.cards[id]
			var visible := card_visible(id, seat)
			var display: Dictionary = card.duplicate(true) if visible else {"hidden": true}
			if not visible:
				if card.has("pos"):
					display["pos"] = card.pos.duplicate()
				for deck: Dictionary in definition.elements.get("decks", []):
					if deck.id == card.deck and not str(deck.get("back", "")).is_empty():
						# Рубашка видна физически. ID/строка/номинал закрытой карты не передаются.
						display["back"] = str(deck.back)
						display["size"] = int(deck.get("size", 3))
						break
			cards.append(display)
		zones[key] = cards
	var vars := {"shared": {}, "player": [], "team": {}}
	for s in players.size(): vars.player.append({})
	for v: Dictionary in definition.rules.get("vars", []):
		var visibility := str(v.get("visible", "all"))
		if visibility == "none": continue
		match str(v.get("scope", "shared")):
			"shared":
				if visibility == "all": vars.shared[v.id] = state.vars.shared.get(v.id)
			"player":
				for s in players.size():
					if visibility == "all" or seat == s: vars.player[s][v.id] = state.vars.player[s].get(v.id)
			"team":
				for team: String in state.vars.team:
					if visibility == "all" or seat >= 0 and str(players[seat].get("team", 0)) == team:
						if not vars.team.has(team):
							vars.team[team] = {}
						vars.team[team][v.id] = state.vars.team[team].get(v.id)
	var pending := {}
	if not state.get("pending", {}).is_empty() and int(state.pending.get("seat", -1)) == seat:
		pending = {"kind": state.pending.kind, "options": state.pending.get("options", []).duplicate(true), "min": state.pending.get("min", 0), "max": state.pending.get("max", 0)}
	var dice := {}
	for who: String in state.get("dice", {}):
		var roll: Dictionary = state.dice[who]
		dice[who] = roll.values.duplicate() if roll.get("visible", "all") == "all" or int(who) == seat else {"count": roll.values.size()}
	var hints: Array = []
	for hint: Dictionary in state.get("hints", []):
		if int(hint.seat) == -1 or int(hint.seat) == seat:
			hints.append(str(hint.text))
	var shown: Array = []
	for id: String in state.get("reveals", {}):
		var reveal: Dictionary = state.reveals[id]
		if int(reveal.seat) == -1 or int(reveal.seat) == seat:
			shown.append(id)
	return {"players": players.duplicate(true), "seat": seat, "zones": zones, "vars": vars, "dice": dice, "phase": phase,
		"hints": hints, "show_cards": shown, "sound_event": state.get("sound_event", {}).duplicate(true),
		"current": state.get("current", 0), "leader": state.get("leader", 0), "round": state.get("round", 1),
		"turn_no": turn_no, "revision": state.get("revision", 0), "pending": pending, "legal": legal_actions(seat),
		"log": state.get("log", []).duplicate(), "winners": state.get("winners", []).duplicate(), "clock": float(state.get("turn_seconds", 0)) > 0}

func save_state() -> Dictionary:
	state.players = players
	state.rng_state = str(rng.state)
	return {"definition": definition.duplicate(true), "state": state.duplicate(true)}

func tick(delta: float) -> bool:
	if delta < 0 or not is_finite(delta):
		return false
	if state.is_empty() or phase == "game_over":
		return false
	var changed := false
	if float(state.get("turn_seconds", 0)) > 0 and not bool(state.get("timed_out", false)):
		state.timer_left = maxf(0.0, float(state.timer_left) - delta)
		if float(state.timer_left) <= 0:
			var snapshot := state.duplicate(true)
			var saved_random := rng.state
			state.timed_out = true
			state.pending = {}
			last_error = ""
			steps = 0
			if not fire("timeout", {"actor": int(state.current), "depth": 0}).is_empty():
				state = snapshot
				players = state.players
				rng.state = saved_random
				state.timed_out = true
				return false
			changed = true
	for id: String in state.get("reveals", {}).keys():
		state.reveals[id].seconds = maxf(0.0, float(state.reveals[id].seconds) - delta)
		if float(state.reveals[id].seconds) <= 0:
			state.reveals.erase(id)
			changed = true
	if state.get("pending", {}).get("kind") != "wait":
		if changed:
			state.revision = int(state.revision) + 1
		return changed
	state.pending.seconds = maxf(0.0, float(state.pending.seconds) - delta)
	if float(state.pending.seconds) > 0:
		if changed:
			state.revision = int(state.revision) + 1
		return changed
	var before := state.duplicate(true)
	var saved_rng := rng.state
	var frames: Array = state.pending.frames.duplicate(true)
	state.pending = {}
	steps = 0
	last_error = ""
	if not Interp.run(self, frames).is_empty():
		state = before
		players = state.players
		rng.state = saved_rng
		return false
	state.revision = int(state.revision) + 1
	state.rng_state = str(rng.state)
	return true

func restore(data: Dictionary) -> String:
	if not data.get("definition") is Dictionary or not data.get("state") is Dictionary:
		return "Неверный снимок партии."
	var issues := Definition.validate(data.definition)
	if not issues.errors.is_empty(): return "Описание игры в снимке повреждено."
	var snapshot: Dictionary = data.state
	if not Definition._json_only(snapshot, 0, 96): return "Снимок содержит недопустимые данные."
	for key in ["zones", "cards", "vars", "pending"]:
		if not snapshot.get(key) is Dictionary: return "В снимке отсутствует %s." % key
	if not snapshot.get("players") is Array or snapshot.players.size() < 2 or snapshot.players.size() > 8:
		return "Неверный состав снимка."
	for player: Variant in snapshot.players:
		if not player is Dictionary or not player.get("name", "") is String or not player.get("eliminated", false) is bool:
			return "Повреждён игрок в снимке."
	for key: String in ["current", "leader"]:
		var value: Variant = snapshot.get(key)
		if not Definition._number(value) or value < 0 or value >= snapshot.players.size() or float(int(value)) != float(value):
			return "Неверный номер игрока в снимке."
	for key: String in ["turn_no", "round", "revision"]:
		if not Definition._number(snapshot.get(key)) or snapshot[key] < 0 or snapshot[key] > 1000000000000:
			return "Неверный счётчик снимка."
	for key: String in ["turn_seconds", "timer_left"]:
		if not Definition._number(snapshot.get(key)) or snapshot[key] < 0 or snapshot[key] > 3600:
			return "Неверное время снимка."
	if not snapshot.get("timed_out") is bool or not snapshot.get("rng_state") is String or not _int_string(snapshot.rng_state):
		return "Повреждён таймер или генератор случайных чисел."
	if not snapshot.get("phase") is String or snapshot.phase not in data.definition.rules.phases and snapshot.phase != "game_over":
		return "Неизвестная фаза снимка."
	if not snapshot.vars.get("shared") is Dictionary or not snapshot.vars.get("player") is Array or snapshot.vars.player.size() != snapshot.players.size() or not snapshot.vars.get("team") is Dictionary:
		return "Повреждены переменные снимка."
	for entry: Variant in snapshot.vars.player:
		if not entry is Dictionary:
			return "Неверные личные переменные снимка."
	for key: String in ["log", "trace", "winners", "hints"]:
		if not snapshot.get(key) is Array:
			return "Повреждён список снимка."
	for key: String in ["dice", "reveals", "skips"]:
		if not snapshot.get(key) is Dictionary:
			return "Повреждён словарь снимка."
	for key: String in ["log", "trace"]:
		for line: Variant in snapshot[key]:
			if not line is String:
				return "Повреждён текст журнала."
	if snapshot.has("sound_event"):
		var sound: Variant = snapshot.sound_event
		if not sound is Dictionary or not Definition._number(sound.get("id")) or sound.id < 1 or sound.id > 1000000000000 or float(int(sound.id)) != float(sound.id) or sound.get("name") not in Definition.Blocks.SOUNDS:
			return "Повреждено звуковое событие."
	var seat_keys: Array = []
	for seat in snapshot.players.size():
		seat_keys.append(str(seat))
	for key: String in snapshot.dice:
		if not seat_keys.has(key):
			return "Неверный владелец кубиков."
		var roll: Variant = snapshot.dice[key]
		if not roll is Dictionary or not roll.get("values") is Array or roll.values.size() > 30:
			return "Повреждён набор кубиков."
		for face: Variant in roll.values:
			if not Definition._number(face) or face < 1 or face > 6 or float(int(face)) != float(face):
				return "Неизвестная грань кубика."
	for hint: Variant in snapshot.hints:
		if not hint is Dictionary or not hint.get("text") is String or not Definition._number(hint.get("seat")):
			return "Повреждена подсказка."
	for reveal: Variant in snapshot.reveals.values():
		if not reveal is Dictionary or not Definition._number(reveal.get("seconds")) or not Definition._number(reveal.get("seat")):
			return "Повреждён временный показ."
	for who: Variant in snapshot.winners:
		if not Definition._number(who) or who < 0 or who >= snapshot.players.size():
			return "Неверный победитель снимка."
	var pending_error := _pending_error(snapshot.pending, data.definition.rules.phases, snapshot.players.size())
	if not pending_error.is_empty():
		return pending_error
	var seen := {}
	for zone: Variant in snapshot.zones.values():
		if not zone is Array: return "Неверная зона снимка."
		for id: Variant in zone:
			if not id is String or not snapshot.cards.has(id) or seen.has(id): return "Повтор или потеря карты в снимке."
			seen[id] = true
	if seen.size() != snapshot.cards.size(): return "Не все карты принадлежат зонам."
	for id: String in snapshot.cards:
		var card: Variant = snapshot.cards[id]
		if card is Dictionary and card.has("pos") and not _point(card.pos):
			return "Неверное положение компонента."
		if not card is Dictionary or not Interp._equal(card.get("id"), id) or not card.get("data") is Dictionary or not card.get("face_up") is bool or not card.get("visible_to") is Array:
			return "Повреждена карта снимка."
	definition = data.definition.duplicate(true)
	state = snapshot.duplicate(true)
	players = state.players
	rng.state = int(str(state.get("rng_state", "1")))
	last_error = ""
	return ""

static func _int_string(value: String) -> bool:
	var negative := value.begins_with("-")
	var digits := value.trim_prefix("-")
	if digits.is_empty() or digits.length() > 19:
		return false
	for c in digits:
		if c not in "0123456789":
			return false
	return digits.length() < 19 or digits <= ("9223372036854775808" if negative else "9223372036854775807")

static func _pending_error(pending: Dictionary, phases: Array, count: int) -> String:
	if pending.is_empty():
		return ""
	var kind := str(pending.get("kind", ""))
	if kind not in ["wait", "ask_number", "ask_card", "ask_player", "ask_option", "roll"]:
		return "Неизвестное ожидание снимка."
	var seat: Variant = pending.get("seat")
	if not Definition._number(seat) or seat < (-1 if kind == "wait" else 0) or seat >= count or float(int(seat)) != float(seat):
		return "Неверный адресат ожидания."
	if not pending.get("frames") is Array or pending.frames.size() > 2048 or not pending.get("context") is Dictionary:
		return "Повреждено продолжение ожидания."
	for frame: Variant in pending.frames:
		if not frame is Dictionary or not frame.get("context") is Dictionary:
			return "Повреждён кадр продолжения."
		var actor: Variant = frame.context.get("actor")
		var depth: Variant = frame.context.get("depth", 0)
		if not Definition._number(actor) or actor < 0 or actor >= count or not Definition._number(depth) or depth < 0 or depth > 16:
			return "Повреждён контекст продолжения."
		if frame.has("event"):
			if frame.event not in Definition.Blocks.EVENTS:
				return "Неизвестное событие продолжения."
		else:
			if not frame.get("blocks") is Array or not Definition._number(frame.get("index")) or frame.index < 0 or frame.index > frame.blocks.size() or float(int(frame.index)) != float(frame.index):
				return "Неверная позиция продолжения."
			var report := {"errors": [], "warnings": []}
			Definition._walk_blocks(frame.blocks, report, phases, 0)
			if not report.errors.is_empty():
				return "Повреждены блоки продолжения."
	if kind in ["ask_card", "ask_player", "ask_option"] and not pending.get("options") is Array:
		return "Повреждены варианты выбора."
	if kind == "ask_number" and (not Definition._number(pending.get("min")) or not Definition._number(pending.get("max"))):
		return "Повреждены границы выбора."
	if kind == "wait" and not Definition._number(pending.get("seconds")):
		return "Неверное время ожидания."
	if kind == "roll" and (not Definition._number(pending.get("count")) or pending.count < 1 or pending.count > 30):
		return "Повреждён ожидающий набор кубиков."
	return ""
