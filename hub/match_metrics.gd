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
var _titles := {}
var _gift_runs := {}
var _rings_errors := {}

const TITLES := {
	"bluff": ["Убедительный блеф", "Больше всего принятых подарков под неверным названием — %d."],
	"caught": ["Память на подарки", "Больше всего правильных вызовов на проверку — %d."],
	"gifts": ["Без единой ошибки", "Больше всего передач с верным названием подряд — %d."],
	"rings_run": ["Без промаха", "Больше всего верно размещённых карт подряд — %d."],
	"rings_cross": ["Угадал пересечение", "Больше всего верных попаданий в пересечения — %d."],
	"rings_recovery": ["Второе дыхание", "Больше всего верных размещений подряд после ошибки — %d."],
	"calza": ["Кость в кость", "Больше всего точных «Кальса» — %d."],
	"dudo": ["Поймал на слове", "Больше всего успешных оспариваний — %d."],
	"answer_run": ["Серия без осечки", "Больше всего правильных ответов подряд — %d."],
	"answers": ["Знаток", "Больше всего правильных ответов — %d."]
}


func _title_point(key: String, seat: int, record: int = 0) -> void:
	if key.is_empty() or seat < 0 or seat >= _enabled.size() or not _enabled[seat]:
		return
	if not _titles.has(key):
		_titles[key] = {}
	var scores: Dictionary = _titles[key]
	scores[seat] = maxi(record, int(scores.get(seat, 0))) if record > 0 else int(scores.get(seat, 0)) + 1


func award() -> Dictionary:
	for key in TITLES:
		var scores: Dictionary = _titles.get(key, {})
		var seat := -1
		var best := 1
		for candidate: int in scores:
			if candidate >= _enabled.size() or not _enabled[candidate]:
				continue
			var value: int = scores[candidate]
			if value > best:
				best = value
				seat = candidate
			elif value == best:
				seat = -1
		if seat >= 0:
			return {"seat": seat, "title": TITLES[key][0], "description": TITLES[key][1] % best}
	return {}


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
		_titles.clear()
		_gift_runs.clear()
		_rings_errors.clear()
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
			for scores: Dictionary in _titles.values():
				scores.erase(seat)
			_gift_runs.erase(seat)
			_rings_errors.erase(seat)
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
				var event: Dictionary = risks[i]
				var seat := int(event.seat)
				if not bool(event.get("award_only", false)):
					_risk(seat, bool(event.error))
				_title_point(str(event.get("award", "")), seat)
				if event.has("truthful_gift"):
					var run := int(_gift_runs.get(seat, 0)) + 1 if event.truthful_gift else 0
					_gift_runs[seat] = run
					if run > 0:
						_title_point("gifts", seat, run)
	if game == "things_in_rings":
		for i in logic.board.size():
			var placement: Dictionary = logic.board[i]
			if not placement.has("correct") or not _once("rings/%d" % i):
				continue
			var finder := int(placement.by)
			if not placement.correct:
				_rings_errors[finder] = true
				_gift_runs[finder] = 0
				continue
			var run := int(_gift_runs.get(finder, 0)) + 1
			_gift_runs[finder] = run
			_title_point("rings_run", finder, run)
			if _rings_errors.has(finder):
				_title_point("rings_recovery", finder, run)
			var mask := int(placement.mask)
			if (mask & (mask - 1)) != 0:
				_title_point("rings_cross", finder)
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
			if loser != challenger:
				_title_point("calza" if event.calza else "dudo", challenger)
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
			var seat := int(event.seat)
			if event.kind == "ok":
				_title_point("answers", seat)
				var run := int(_gift_runs.get(seat, 0)) + 1
				_gift_runs[seat] = run
				_title_point("answer_run", seat, run)
			else:
				_gift_runs.erase(seat)
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
	if game in ["tip_top", "the_gang", "the_mind"]:
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
