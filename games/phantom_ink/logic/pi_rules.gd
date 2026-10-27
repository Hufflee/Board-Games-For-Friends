class_name PIRules
extends RefCounted
## Правила «Призрачных чернил». Тайные слова остаются на картах духов;
## правильность буквы и слова подтверждает дух, как в настольной игре.
var players: Array = []
var roles: Array = []
var phase := "object"
var team := 0
var rows: Array = [[], []]
var hands: Array = [[], []]
var deck: Array = []
var discard: Array = []
var refreshed: Array = [false, false]
var votes: Array = [-1, -1]
var question_votes: Array = [{}, {}]  # команда → место → до двух выбранных вопросов
var object_card := 0
var object_slot := -1
var offered: Array = []
var winner := -1
var _rng := RandomNumberGenerator.new()
var _letter_time := 0.0
var revision := 0

func new_game(members: Array, chosen_roles: Array, seed_value: int = 0) -> void:
	players = members.duplicate(true)
	roles = chosen_roles.duplicate()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	phase = "object"
	team = 0
	rows = [[], []]
	hands = [[], []]
	discard = []
	refreshed = [false, false]
	votes = [-1, -1]
	question_votes = [{}, {}]
	offered = []
	winner = -1
	revision = 0
	deck = range(PIData.QUESTIONS)
	_shuffle(deck)
	object_card = _rng.randi_range(0, PIData.OBJECTS - 1)
	object_slot = -1
	_draw(0, 7)
	_draw(1, 7)

func _shuffle(cards: Array) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var temp: int = cards[i]
		cards[i] = cards[j]
		cards[j] = temp

func _draw(t: int, count: int) -> void:
	for i in count:
		if deck.is_empty():
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck)
		if not deck.is_empty():
			hands[t].append(deck.pop_back())

func actor() -> int:
	if phase == "object":
		return roles.find(1 if votes[0] < 0 else 3)
	var spirit := phase in ["question", "clue", "judge"]
	return roles.find(team * 2 + (1 if spirit else 0))

func can_act(seat: int) -> bool:
	if seat < 0 or seat >= roles.size() or phase == "game_over":
		return false
	var role: int = roles[seat]
	if phase == "object":
		return role % 2 == 1
	if int(role / 2) != team:
		return false
	return role % 2 == (1 if phase in ["question", "clue", "judge"] else 0)

func action(seat: int, kind: String, arg = null) -> bool:
	if not can_act(seat):
		return false
	var t: int = int(roles[seat] / 2)
	var ok := false
	match kind:
		"question_vote":
			if phase == "turn" and arg is int and hands[t].has(arg):
				var selected: Array = question_votes[t].get(seat, []).duplicate()
				if selected.has(arg):
					selected.erase(arg)
				elif selected.size() < 2:
					selected.append(arg)
				else:
					return false
				question_votes[t][seat] = selected
				ok = true
		"object":
			if phase == "object" and arg is int and arg >= 0 and arg < 6:
				votes[t] = arg
				if votes[0] == votes[1] and votes[0] >= 0:
					object_slot = votes[0]
					_begin_turn()
				ok = true
		"eye_skip":
			if phase == "eye":
				phase = "turn"
				ok = true
		"eye":
			if phase == "eye" and arg is Array and arg.size() == 2 and arg[0] is int and arg[1] is int:
				var et: int = arg[0]
				var ei: int = arg[1]
				if et in [0, 1] and ei >= 0 and ei < rows[et].size():
					var row: Dictionary = rows[et][ei]
					if row.kind == "clue" and not row.complete:
						_reveal(row)
						phase = "turn"
						ok = true
		"refresh":
			if phase in ["turn", "eye"] and not refreshed[t]:
				discard.append_array(hands[t])
				hands[t] = []
				question_votes[t] = {}
				_draw(t, 7)
				refreshed[t] = true
				ok = true
		"ask":
			if phase == "turn" and arg is Array and arg.size() == 2 and arg[0] != arg[1] and hands[t].has(arg[0]) and hands[t].has(arg[1]):
				offered = arg.duplicate()
				question_votes[t] = {}
				for q in offered:
					hands[t].erase(q)
				phase = "question"
				ok = true
		"question":
			if phase == "question" and arg is int and offered.has(arg):
				for q in offered:
					if q != arg:
						discard.append(q)
				rows[t].append({"kind": "clue", "text": "", "full": "", "question": arg, "complete": false, "wrong": false})
				offered.clear()
				phase = "clue"
				ok = true
		"clue":
			if phase == "clue" and arg is String and _letters(arg.strip_edges()) and arg.strip_edges().length() <= 48:
				rows[t].back()["full"] = arg.strip_edges().to_upper()
				phase = "writing"
				_letter_time = 0.0
				ok = true
		"silence":
			if phase == "writing" and not str(rows[t].back().text).is_empty():
				_draw(t, 2)
				_end_turn()
				ok = true
		"guess_begin":
			if phase == "turn":
				rows[t].append({"kind": "guess", "text": "", "complete": false, "wrong": false, "pending": ""})
				phase = "guess"
				ok = true
		"letter":
			if phase == "guess" and arg is String and (arg == "." or (arg.length() == 1 and _letters(arg))):
				if arg != "." or not str(rows[t].back().text).is_empty():
					rows[t].back()["pending"] = arg.to_upper()
					phase = "judge"
					ok = true
		"judge":
			if phase == "judge" and arg is bool:
				var row: Dictionary = rows[t].back()
				var pending: String = row.pending
				row.pending = ""
				if pending == "." and arg:
					row.complete = true
					winner = team
					phase = "game_over"
				elif arg:
					row.text += pending
					phase = "guess"
				else:
					row.text += pending
					row.wrong = true
					_end_turn()
				ok = true
	if ok:
		revision += 1
	return ok

func _letters(text: String) -> bool:
	if text.is_empty():
		return false
	for c in text:
		if c != " " and not (c.to_lower() >= "а" and c.to_lower() <= "я") and c.to_lower() != "ё" and not (c.to_lower() >= "a" and c.to_lower() <= "z"):
			return false
	return true

func _reveal(row: Dictionary) -> void:
	if str(row.text).length() < str(row.full).length():
		row.text = str(row.full).left(str(row.text).length() + 1)
	else:
		row.complete = true

func tick(delta: float) -> bool:
	if phase != "writing":
		return false
	_letter_time += maxf(0.0, delta)
	if _letter_time < 1.0:
		return false
	_letter_time = 0.0
	var row: Dictionary = rows[team].back()
	_reveal(row)
	if row.complete:
		_draw(team, 2)
		_end_turn()
	revision += 1
	return true

func _begin_turn() -> void:
	phase = "turn"
	question_votes[team] = {}
	if PIData.EYES[team].has(rows[team].size()):
		for group in rows:
			for row in group:
				if row.kind == "clue" and not row.complete:
					phase = "eye"

func _end_turn() -> void:
	if rows[0].size() >= 8 and rows[1].size() >= 8:
		phase = "game_over"
		return
	team = 1 - team
	if rows[team].size() >= 8:
		team = 1 - team
	_begin_turn()

func spectator_seat() -> int:
	return -1

func can_spectate() -> bool:
	return false

func get_view(seat: int, _show_all: bool = false) -> Dictionary:
	var role: int = roles[seat] if seat >= 0 and seat < roles.size() else -1
	var t: int = int(role / 2) if role >= 0 else -1
	var spirit := role >= 0 and role % 2 == 1
	var counts := {}
	var own_votes: Array = []
	if t >= 0 and not spirit:
		own_votes = question_votes[t].get(seat, []).duplicate()
		for selected: Array in question_votes[t].values():
			for q in selected:
				counts[q] = int(counts.get(q, 0)) + 1
	var visible_rows: Array = rows.duplicate(true)
	for rt in 2:
		for row in visible_rows[rt]:
			row.erase("full")
			if rt != t:
				row.erase("question")
	return {"phase": phase, "team": team, "seat": seat, "role": role, "roles": roles.duplicate(), "players": players.duplicate(true), "rows": visible_rows,
		"question_votes": counts, "own_question_votes": own_votes,
		"hand": hands[t].duplicate() if t >= 0 and not spirit else [], "offered": offered.duplicate() if t == team else [],
		"object_card": object_card if spirit or phase == "game_over" else -1, "object_slot": object_slot if spirit or phase == "game_over" else -1,
		"votes": votes.duplicate() if spirit else [], "discard": discard.duplicate(), "refreshed": refreshed.duplicate(),
		"winner": winner, "actor": actor(), "can_act": can_act(seat), "revision": revision}
