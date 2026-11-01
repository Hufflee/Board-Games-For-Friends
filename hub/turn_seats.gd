class_name TurnSeats
extends RefCounted
## Места, от которых СЕЙЧАС ждут действия (для мерцающей рамки «твой ход» по краям экрана).
## Чистая функция по публичному view игры — ничего не меняет в правилах и Net.
## Использование: TurnSeats.is_mine(view) — ждут ли действия от моего места.


## Все места за столом (для одновременных фаз, где не видно, кто уже сходил).
static func _all(view: Dictionary) -> Array:
	return range((view.get("players", []) as Array).size())


static func _seat(v) -> Array:
	var n := _int(v)
	return [n] if n >= 0 else []


## Номер места из view; не число (null, словарь, строка) — -1, без ошибок скрипта.
static func _int(v, fallback: int = -1) -> int:
	if v is int or v is float:
		return int(v)
	return fallback


## Моё место: seat (большинство игр) или you; зритель — -1.
static func my_seat(view: Dictionary) -> int:
	return _int(view.get("seat", view.get("you", -1)))


static func is_mine(view: Dictionary) -> bool:
	var me := my_seat(view)
	if me < 0 or bool(view.get("spectator", false)):
		return false
	return acting(str(view.get("game", "")), view).has(me)


## game — id игры (у gloomier тот же набор ключей, что у gloom).
static func acting(game: String, view: Dictionary) -> Array:
	var phase := str(view.get("phase", ""))
	if phase == "" or phase == "game_over":
		return []
	var players: Array = view.get("players", [])
	var out: Array = []
	match game:
		"brodilka":
			var w := _int(view.get("waiting", -1))
			out = _seat(w if w >= 0 else view.get("turn", -1))
		"poker":
			if phase == "hand":
				out = _seat(view.get("to_act", -1))
		"khorom":
			if phase == "write":
				var books: Array = view.get("books", [])
				for s in books.size():
					if not bool(books[s].get("ready", true)):
						out.append(s)
			elif phase == "reveal":
				out = _seat(view.get("turn", -1))
		"dangerous_words":
			out = _dw(view, phase, players)
		"gloom", "gloomier":
			match phase:
				"trim":
					out = (view.get("trim_left", []) as Array).duplicate()
				"draft":
					var order: Array = view.get("draft_order", [])
					out = _seat(order[0]) if not order.is_empty() else []
				"play":
					out = _seat(view.get("current", -1))
				"prompt":
					out = _seat((view.get("prompt", {}) as Dictionary).get("seat", -1))
				"react":
					# кто отвечает, видно только самому игроку (react.can)
					out = ((view.get("react", {}) as Dictionary).get("can", []) as Array).duplicate()
		"hues_and_cues":
			if phase in ["prepare", "pick", "cue1", "cue2"]:
				out = _seat(view.get("giver", -1))
			elif phase in ["guess1", "guess2"]:
				out = _seat(view.get("guesser", -1))
		"not_a_hat":
			if phase == "give":
				out = _seat(view.get("giver", -1))
			elif phase == "respond":
				out = _seat(view.get("receiver", -1))
			elif phase == "memorize":
				out = _all(view)
		"tip_top", "tip_top_18":
			var captain := _int(view.get("captain", -1), -1)
			match phase:
				"theme", "order":
					out = _seat(captain)
				"answer":
					var done: Array = view.get("answered", [])
					for s in players.size():
						if s != captain and not done.has(s):
							out.append(s)
				"guess":
					for s in players.size():
						if s != captain:
							out.append(s)
		"wavelength":
			var psychic := _int(view.get("psychic", -1), -1)
			var team := _int(view.get("active_team", 0), 0)
			match phase:
				"card", "clue":
					out = _seat(psychic)
				"guess":
					for s in players.size():
						if int(players[s].get("team", 0)) == team and s != psychic:
							out.append(s)
				"side":
					for s in players.size():
						if int(players[s].get("team", 0)) != team:
							out.append(s)
		"word_slam":
			if phase == "word":
				var storytellers: Array = view.get("storytellers", [])
				var ready: Array = view.get("ready", [])
				for i in storytellers.size():
					if i >= ready.size() or not bool(ready[i]):
						out.append(storytellers[i])
			elif phase == "play":
				out = _all(view)
		"phantom_ink":
			var roles: Array = view.get("roles", [])
			var team_now := _int(view.get("team", 0), 0)
			for s in roles.size():
				var role := int(roles[s])
				if role < 0:
					continue
				if phase == "object":
					if role % 2 == 1:
						out.append(s)
				elif role / 2 == team_now and role % 2 == (1 if phase in ["question", "clue", "judge"] else 0):
					out.append(s)
		"ready_set_bet":
			if phase == "vip" or (phase == "race" and not bool(view.get("no_more_bets", false))):
				out = _all(view)
		"stillion":
			if phase == "fuse":
				out = _seat(view.get("target", -1))
		"the_mind":
			var members: Array = view.get("players", [])
			var ready: Array = view.get("ready", [])
			var votes: Array = view.get("votes", [])
			for s in members.size():
				if phase == "play" and int(members[s].get("count", 0)) > 0:
					out.append(s)
				elif phase == "focus" and s < ready.size() and not bool(ready[s]):
					out.append(s)
				elif phase == "vote" and s < votes.size() and not bool(votes[s]):
					out.append(s)
		"the_gang":
			if phase == "rank":
				var chips: Array = view.get("chips", [])
				for s in chips.size():
					if int(chips[s]) == 0:
						out.append(s)
		"things_in_rings":
			match phase:
				"blind":
					out = (view.get("blind_waiting", []) as Array).duplicate()
				"postgame":
					pass
				_:
					out = _seat(view.get("actor", -1))
		"perudo":
			if phase == "bid":
				out = _seat(view.get("turn", -1))
			elif phase == "roll":
				var shaken: Array = view.get("shaken", [])
				var counts: Array = view.get("counts", [])
				for s in counts.size():
					if int(counts[s]) > 0 and not (s < shaken.size() and bool(shaken[s])):
						out.append(s)
		"king_of_12":
			out = _k12(view, phase, players)
		"four_souls":
			out = _seat(view.get("actor", view.get("current", -1)))
	return out


static func _dw(view: Dictionary, phase: String, players: Array) -> Array:
	var out: Array = []
	match phase:
		"traps":
			var ready: Array = view.get("ready", [false, false])
			var votes: Array = view.get("ready_votes", [[], []])
			for s in players.size():
				var t := int(players[s].get("team", 0))
				if not bool(ready[t]) and not (t < votes.size() and (votes[t] as Array).has(s)):
					out.append(s)
		"defuse":
			# выбирает команда-соперник проклятой «обезвреживанием», пока строка не вычеркнута
			var curses: Array = view.get("active_curses", [[], []])
			var crossed: Array = view.get("crossed", [-1, -1])
			for t in 2:
				if (curses[t] as Array).any(func(c): return str(c) == "defuse") and int(crossed[t]) < 0:
					for s in players.size():
						if int(players[s].get("team", 0)) == 1 - t and not out.has(s):
							out.append(s)
		"turn_ready", "turn":
			var explainers: Array = view.get("explainers", [])
			if explainers.size() == 2:
				out = _seat(explainers[_int(view.get("turn_team", 0), 0)])
	return out


static func _k12(view: Dictionary, phase: String, players: Array) -> Array:
	var out: Array = []
	var active: Array = view.get("active", [])
	match phase:
		"roll":
			var rolled: Array = view.get("rolled", [])
			for s in players.size():
				if (active.is_empty() or bool(active[s])) and not (s < rolled.size() and bool(rolled[s])):
					out.append(s)
		"select":
			var chosen: Array = view.get("chosen", [])
			for s in players.size():
				if (active.is_empty() or bool(active[s])) and not (s < chosen.size() and bool(chosen[s])):
					out.append(s)
		"sorcerer", "oracle", "pick_under":
			var pending: Dictionary = view.get("pending", {})
			if pending.has("seats"):
				out = (pending["seats"] as Array).duplicate()
			elif pending.has("seat"):
				out = _seat(pending["seat"])
	return out
