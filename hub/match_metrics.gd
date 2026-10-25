class_name MatchMetrics
extends RefCounted
## Хост собирает проверенные события, каждому клиенту передаётся только его накопительный снимок.
var uid := ""
var kind := ""
var rows: Array = []
var _seen: Dictionary = {}
var _owners: Array = []
var _enabled: Array = []
var _bindings: Array = []


static func empty_row() -> Dictionary:
	return {"decisions": 0, "errors": 0, "remarks": 0, "messages": 0, "emotes": 0, "dice": {}, "result": ""}


func _once(key: String) -> bool:
	if _seen.has(key):
		return false
	_seen[key] = true
	return true


func _row(seat: int) -> Dictionary:
	while rows.size() <= seat:
		rows.append(empty_row())
	return rows[seat]


func _dice(seat: int, faces: Array) -> void:
	if seat < 0 or seat >= _enabled.size() or not _enabled[seat]:
		return
	var row := _row(seat)
	for face in faces:
		if int(face) > 0:
			row.dice[str(face)] = int(row.dice.get(str(face), 0)) + 1


func _risk(seat: int, error: bool) -> void:
	if seat < 0 or seat >= _enabled.size() or not _enabled[seat]:
		return
	var row := _row(seat)
	row.decisions = int(row.decisions) + 1
	row.errors = int(row.errors) + (1 if error else 0)


func say(seat: int, message_kind: String) -> void:
	if seat < 0 or seat >= _enabled.size() or not _enabled[seat] or not message_kind in ["chat", "emote"]:
		return
	var row := _row(seat)
	row.remarks = int(row.remarks) + 1
	var key: String = "emotes" if message_kind == "emote" else "messages"
	row[key] = int(row[key]) + 1


## Наблюдаем хостовую логику: каждый эпизод учитывается один раз для текущего владельца места.
func observe(session: String, game: String, logic: Object, peers: Array = []) -> void:
	if session != uid:
		uid = session
		kind = game
		rows = []
		_seen = {}
		_owners = []
		_enabled = []
		_bindings = []
	if logic == null:
		return
	var players: Array = logic.get("players")
	for seat in players.size():
		_row(seat)
		var owner: int = int(peers[seat]) if seat < peers.size() else seat + 1
		if seat >= _owners.size():
			_owners.append(owner)
			_bindings.append(0)
			_enabled.append(false)
		elif int(_owners[seat]) != owner:
			rows[seat] = empty_row()
			_owners[seat] = owner
			_bindings[seat] = int(_bindings[seat]) + 1
		_enabled[seat] = owner != 0 and not bool(players[seat].get("bot", false))
	var rolls: Variant = logic.get("stats_rolls")
	if rolls is Array:
		for i in rolls.size():
			if _once("roll/%d" % i):
				_dice(int(rolls[i].seat), rolls[i].faces)
	var risks: Variant = logic.get("stats_risks")
	if risks is Array:
		for i in risks.size():
			if _once("risk/%d" % i):
				_risk(int(risks[i].seat), bool(risks[i].error))
	if game == "perudo":
		for seat in players.size():
			if logic.shaken[seat] and _once("shake/%d/%d" % [logic.round_no, seat]):
				_dice(seat, logic.dice[seat])
		for event: Dictionary in logic.history:
			if not _once("perudo/%d" % int(event.round)):
				continue
			var challenger: int = int(event.challenger)
			var loser: int = int(event.loser)
			_risk(challenger, loser == challenger)
			if not event.calza:
				_risk(int(event.bid.seat), loser == int(event.bid.seat))
	if game == "tip_top":
		for i in logic.log.size():
			var event: Dictionary = logic.log[i]
			if event.has("ok") and _once("tiptop/%d/%d" % [logic.round_no, i]):
				_risk(int(logic.captain), not event.ok)
	if game == "stillion":
		var event: Dictionary = logic.last
		if str(event.get("kind", "")) in ["ok", "boom"] and _once("stillion/%d" % int(event.no)):
			_risk(int(event.seat), event.kind == "boom")
	if str(logic.get("phase")) == "game_over":
		var view: Dictionary = logic.call("get_view", 0)
		for seat in players.size():
			if _enabled[seat]:
				_row(seat).result = (
					"unrated"
					if game == "wavelength" and bool(view.get("coop", false))
					else ("win" if _won(game, view, seat) else "loss")
				)


static func _won(game: String, view: Dictionary, seat: int) -> bool:
	if game == "tip_top":
		return bool(view.won)
	if game == "phantom_ink":
		return int(view.winner) == int(view.roles[seat]) / 2
	if game == "wavelength":
		return int(view.winner) == 0 if view.coop else int(view.winner) == int(view.players[seat].team)
	if game == "dangerous_words":
		return view.winners.has(int(view.players[seat].team))
	if game == "word_slam" and view.mode == "teams":
		return view.winners.has(int(view.players[seat].team))
	if view.has("winners"):
		return view.winners.has(seat)
	return int(view.get("winner", -1)) == seat


## Адресный снимок содержит только личные счётчики указанного игрока.
func snapshot(seat: int) -> Dictionary:
	if seat < 0 or seat >= rows.size() or not _enabled[seat]:
		return {}
	return {
		"id": uid + "@" + str(_bindings[seat]),
		"match_id": uid,
		"game": kind,
		"seat": seat,
		"time": int(Time.get_unix_time_from_system()),
		"totals": rows[seat].duplicate(true)
	}
