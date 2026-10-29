class_name TRRules
extends RefCounted
## Чистые правила Things in Rings: смысловую правильность размещения определяет живой знающий.
## Проверка: Godot --headless --audio-driver Dummy --path . --script res://tests/test_things_in_rings.gd

const CATEGORIES := ["Attribute", "Word", "Context"]
var players: Array = []
var rings: Array = []
var knower := 0
var coop := false
var phase := "setup"
var hands: Array = []
var deck: Array = []
var discarded: Array = []
var board: Array = []
var secret_rules := {}
var pending := {}
var current := -1
var round_no := 1
var turn_no := 0
var winners: Array = []
var reason := ""
var revealed := false
var revealed_conditions: Array = []
var feedback := {}
var _feedback_id := 0
var _initial_clues := 0
var _round_left: Array = []
var _rule_pools := {}
var rule_choices := {}
var revision := 0
var rng := RandomNumberGenerator.new()


func new_game(persons: Array, things: Array, pools: Dictionary, options: Dictionary = {}, seed_value: int = 0) -> String:
	var chosen: Array = options.get("rings", ["Attribute", "Word"])
	var knowing: int = int(options.get("knower", 0))
	var cooperative: bool = bool(options.get("coop", false)) or persons.size() == 2
	if persons.size() < 2 or persons.size() > 6 or knowing < 0 or knowing >= persons.size():
		return "Нужно 2–6 игроков и существующее место знающего."
	if cooperative and persons.size() > 4:
		return "Кооператив рассчитан на 2–4 игроков."
	if chosen.is_empty() or chosen.size() > 3:
		return "Выберите от одного до трёх колец."
	var seen := {}
	for category: String in chosen:
		if category not in CATEGORIES or seen.has(category) or not pools.get(category, []) is Array or pools.get(category, []).size() < 3:
			return "У каждого кольца должно быть минимум три разных правила."
		var unique := {}
		for card in pools[category]:
			if not card is int or unique.has(card):
				return "Правила должны иметь разные целочисленные ID."
			unique[card] = true
		seen[category] = true
	seen.clear()
	for id in things:
		if not id is int or id < 0 or seen.has(id):
			return "Колода предметов содержит неправильные или повторные ID."
		seen[id] = true
	var needed := (persons.size() - 1) * 5 + (10 if cooperative else 5)
	if things.size() < needed:
		return "Недостаточно предметов для начальной раздачи."
	players = persons.duplicate(true)
	rings = chosen.duplicate()
	knower = knowing
	coop = cooperative
	rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	deck = things.duplicate()
	for i: int in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temporary: int = deck[i]
		deck[i] = deck[j]
		deck[j] = temporary
	hands = []
	for seat: int in players.size():
		hands.append([])
	secret_rules = {}
	_rule_pools = pools.duplicate(true)
	rule_choices = {}
	for category: String in rings:
		var pool: Array = pools[category].duplicate()
		var choices := []
		for _i: int in 3:
			var index := rng.randi_range(0, pool.size() - 1)
			choices.append(pool.pop_at(index))
		rule_choices[category] = choices
	board = []
	discarded = []
	pending = {}
	winners = []
	reason = ""
	revealed = false
	revealed_conditions = []
	for _category: String in rings:
		revealed_conditions.append(false)
	feedback = {}
	_feedback_id = 0
	current = -1
	round_no = 1
	turn_no = 0
	_initial_clues = players.size() if coop else 3
	_round_left = []
	phase = "choose_rules"
	revision = 0
	return ""


func actor() -> int:
	return knower if phase in ["choose_rules", "setup_clues", "judge", "knower_clue"] else (current if phase == "place" else -1)


func choose_rule(seat: int, category: String, card: int) -> bool:
	if phase != "choose_rules" or seat != knower or category not in rings or not rule_choices.get(category, []).has(card):
		return false
	secret_rules[category] = card
	return true


func begin_clues(seat: int) -> bool:
	if phase != "choose_rules" or seat != knower or secret_rules.size() != rings.size():
		return false
	for seat_index: int in players.size():
		for _i: int in (10 if coop and seat_index == knower else 5):
			hands[seat_index].append(deck.pop_back())
	phase = "setup_clues"
	return true


func _valid_mask(mask: int) -> bool:
	return mask >= 0 and mask < (1 << rings.size())


func clue(seat: int, card: int, mask: int) -> bool:
	if seat != knower or phase not in ["setup_clues", "knower_clue"] or not _valid_mask(mask) or not hands[knower].has(card):
		return false
	hands[knower].erase(card)
	board.append({"card": card, "mask": mask, "by": knower, "clue": true})
	turn_no += 1
	if phase == "setup_clues":
		_initial_clues -= 1
		if _initial_clues > 0:
			return true
		if not coop:
			discarded = hands[knower].duplicate()
			hands[knower].clear()
	else:
		round_no += 1
	_begin_round()
	return true


func _begin_round() -> void:
	_round_left = []
	for offset: int in range(1, players.size()):
		var seat := (knower + offset) % players.size()
		if not hands[seat].is_empty():
			_round_left.append(seat)
	if _round_left.is_empty():
		_finish(range(players.size()) if coop else [], "all_found")
		return
	current = int(_round_left[0])
	phase = "place"


func place(seat: int, card: int, mask: int) -> bool:
	if phase != "place" or seat != current or not _valid_mask(mask) or not hands[seat].has(card):
		return false
	hands[seat].erase(card)
	pending = {"card": card, "proposed": mask, "by": seat}
	phase = "judge"
	return true


func judge(seat: int, actual_mask: int) -> bool:
	if phase != "judge" or seat != knower or not _valid_mask(actual_mask):
		return false
	var finder: int = pending.by
	var correct: bool = actual_mask == int(pending.proposed)
	_feedback_id += 1
	feedback = {"id": _feedback_id, "correct": correct, "card": pending.card, "seat": finder}
	board.append({"card": pending.card, "mask": actual_mask, "by": finder, "clue": false, "correct": correct})
	pending = {}
	turn_no += 1
	if correct:
		if hands[finder].is_empty():
			if not coop:
				_finish([finder], "first_found")
				return true
			var all_empty := true
			for other: int in players.size():
				if other != knower and not hands[other].is_empty():
					all_empty = false
			if all_empty:
				_finish(range(players.size()), "all_found")
				return true
		else:
			phase = "place"
			return true
	else:
		if deck.is_empty():
			# PDF не определяет этот край: сообщаем об исчерпании, не выдумываем победителя.
			_finish([], "deck_empty")
			return true
		hands[finder].append(deck.pop_back())
	_end_turn()
	return true


func _end_turn() -> void:
	_round_left.erase(current)
	if not _round_left.is_empty():
		current = int(_round_left[0])
		phase = "place"
	elif coop:
		if hands[knower].is_empty():
			_finish([], "no_clue")
		else:
			phase = "knower_clue"
	else:
		round_no += 1
		_begin_round()


func _finish(victors: Array, why: String) -> void:
	winners = victors.duplicate()
	reason = why
	phase = "postgame"
	current = -1


func reveal_rules(seat: int) -> bool:
	# Старое массовое раскрытие отключено: каждую карту открывают отдельно.
	return false


func flip_condition(seat: int, ring: int) -> bool:
	if phase != "postgame" or seat != knower or ring < 0 or ring >= rings.size() or revealed_conditions[ring]:
		return false
	revealed_conditions[ring] = true
	revealed = not revealed_conditions.has(false)
	return true


func show_victory(host_authorized: bool) -> bool:
	if phase != "postgame" or not host_authorized:
		return false
	phase = "game_over"
	return true


## Ревизия защищает от повторного сетевого решения и действий со старого экрана.
func action(seat: int, kind: String, payload: Variant, host_authorized: bool = false) -> bool:
	if not payload is Dictionary or not payload.get("revision") is int or payload.revision != revision:
		return false
	for key: String in ["card", "mask", "ring"]:
		if payload.has(key) and not payload[key] is int:
			return false
	var accepted := false
	match kind:
		"choose_rule":
			if payload.get("category") is String:
				accepted = choose_rule(seat, payload.category, payload.get("card", -1))
		"begin_clues":
			accepted = begin_clues(seat)
		"clue":
			accepted = clue(seat, payload.get("card", -1), payload.get("mask", -1))
		"place":
			accepted = place(seat, payload.get("card", -1), payload.get("mask", -1))
		"judge":
			accepted = judge(seat, payload.get("mask", -1))
		"reveal_rules":
			accepted = reveal_rules(seat)
		"flip_condition":
			accepted = flip_condition(seat, payload.get("ring", -1))
		"show_victory":
			accepted = show_victory(host_authorized)
	if accepted:
		revision += 1
	return accepted


func can_spectate() -> bool:
	return false  # В этой игре место нельзя передать семантическому боту.


func get_view(seat: int) -> Dictionary:
	var counts := []
	for hand: Array in hands:
		counts.append(hand.size())
	var public_rules := {}
	var condition_faces := []
	for ring: int in rings.size():
		var opened: bool = ring < revealed_conditions.size() and revealed_conditions[ring]
		condition_faces.append(secret_rules.get(rings[ring], -1) if opened else -1)
		if opened:
			public_rules[rings[ring]] = secret_rules[rings[ring]]
	return {"players": players.duplicate(true), "rings": rings.duplicate(), "knower": knower,
		"coop": coop, "phase": phase, "you": seat, "current": current, "actor": actor(),
		"round_no": round_no, "turn_no": turn_no, "counts": counts, "deck_left": deck.size(),
		"hand": hands[seat].duplicate() if seat >= 0 and seat < hands.size() else [],
		"secret_rules": secret_rules.duplicate() if seat == knower else public_rules,
		"rule_choices": rule_choices.duplicate(true) if seat == knower and phase == "choose_rules" else {},
		"board": board.duplicate(true), "pending": pending.duplicate(),
		"feedback": feedback.duplicate(), "revealed_conditions": revealed_conditions.duplicate(),
		"condition_faces": condition_faces, "winners": winners.duplicate() if phase == "game_over" else [],
		"reason": reason, "initial_clues_left": _initial_clues, "revealed": revealed, "revision": revision}
