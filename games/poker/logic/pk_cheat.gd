extends RefCounted
## Фазы жульничества на хосте. Закрытые заявки и результаты подсматривания выдаются только своему месту.

const Cards := preload("res://games/poker/logic/pk_cheat_cards.gd")
const PICK_TIME := 10.0
const REVEAL_TIME := 2.0
const EFFECT_TIME := 1.35

var hands: Array = []
var pending: Dictionary = {}
var revealed: Array = []
var peeks: Array = []
var known: Array = []
var reverse := false
var gap_straights: Array[int] = []
var color_flushes: Array[int] = []
var deck_replacements := 0
var window := 0
var cursor := 0


func new_session(game: RefCounted) -> void:
	var ids := Cards.CARDS.keys()
	if game.players.size() == 2:
		ids = ids.filter(func(id: int) -> bool: return id != 1 and not Cards.FOLDED.has(id))
	_shuffle(ids, game.rng)
	hands.clear()
	for _seat: int in game.players.size():
		hands.append(ids.slice(0, 7))


func new_hand(game: RefCounted) -> void:
	window += 1
	pending.clear()
	revealed.clear()
	peeks.clear()
	known.clear()
	reverse = false
	gap_straights.clear()
	color_flushes.clear()
	deck_replacements = 0
	for _seat: int in game.players.size():
		peeks.append([])
		known.append({})


func begin(game: RefCounted) -> void:
	window += 1
	pending.clear()
	revealed.clear()
	game.phase = "cheat_pick"
	game.time_left = PICK_TIME
	game.revision += 1
	for seat: int in game.players.size():
		if game.in_hand(seat) and bool(game.players[seat].get("bot", false)):
			bot_play(game, seat)


func bot_play(game: RefCounted, seat: int) -> void:
	if game.rng.randf() >= 0.42:
		return
	var available := choices(game, seat)
	if available.is_empty():
		return
	var ids := available.keys()
	var id: int = ids[game.rng.randi_range(0, ids.size() - 1)]
	var options: Array = available[id]
	submit(game, seat, {"id": id, "window": window, "args": options[game.rng.randi_range(0, options.size() - 1)].args})


func submit(game: RefCounted, seat: int, data: Dictionary) -> bool:
	if not _play_window(game) or data.get("window") != window:
		return false
	if seat < 0 or seat >= hands.size() or not game.in_hand(seat) or pending.has(seat):
		return false
	var id: Variant = data.get("id")
	var args: Variant = data.get("args")
	if not id is int or not args is Array or args.size() != 4:
		return false
	for index: Variant in args:
		if not index is int:
			return false
	for option: Dictionary in choices(game, seat).get(id, []):
		if option.args == args:
			if game.mode == "cheat_experimental":
				hands[seat].erase(id)
				var applied := _effect(game, seat, id, args)
				game._note("%s · %s%s" % [game.players[seat].name, Cards.title(id), "" if applied else " (нет эффекта)"])
			else:
				_play(seat, id, args)
			game.revision += 1
			return true
	return false


func _play_window(game: RefCounted) -> bool:
	if game.mode == "cheat_experimental":
		return game.phase == "hand" and game.to_act >= 0
	return game.phase == "cheat_pick" and game.time_left > 0.0


## Отсчитываем от верха колоды, пропуская ближайшую выкладку.
func _peek_deck(game: RefCounted, count: int) -> Array:
	var skip := 0
	match str(game.street):
		"preflop":
			skip = 3
		"flop", "turn":
			skip = 1
	var cards := []
	for offset: int in count:
		cards.append(game.deck[-1 - skip - offset])
	return cards


func _play(seat: int, id: int, args: Array) -> void:
	pending[seat] = {"id": id, "args": args.duplicate()}
	hands[seat].erase(id)


func tick(game: RefCounted, delta: float) -> bool:
	game.time_left -= delta
	if game.time_left > 0.0:
		return false
	if game.phase == "cheat_pick":
		_reveal(game)
	else:
		_resolve_next(game)
	game.revision += 1
	return true


func _reveal(game: RefCounted) -> void:
	if pending.is_empty():
		game._advance_street()
		return
	var counts := {}
	for play: Dictionary in pending.values():
		counts[play.id] = int(counts.get(play.id, 0)) + 1
	for step: int in range(1, game.players.size() + 1):
		var seat: int = (game.button + step) % game.players.size()
		if pending.has(seat):
			var id: int = pending[seat].id
			var status := "cancelled" if int(counts[id]) > 1 else "queued"
			revealed.append({"seat": seat, "id": id, "status": status})
			if status == "cancelled":
				game._note("%s · %s: отменено совпадением" % [game.players[seat].name, Cards.title(id)])
	cursor = 0
	game.phase = "cheat_reveal"
	game.time_left = REVEAL_TIME


func _resolve_next(game: RefCounted) -> void:
	while cursor < revealed.size():
		var entry: Dictionary = revealed[cursor]
		cursor += 1
		if entry.status != "queued":
			continue
		var seat: int = entry.seat
		var id: int = entry.id
		var applied := _effect(game, seat, id, pending[seat].args)
		entry.status = "applied" if applied else "unavailable"
		game._note("%s · %s%s" % [game.players[seat].name, Cards.title(id), "" if applied else " (нет эффекта)"])
		game.time_left = EFFECT_TIME
		return
	pending.clear()
	game._advance_street()


func choices(game: RefCounted, seat: int) -> Dictionary:
	var result := {}
	for id: int in hands[seat]:
		var list := _options(game, seat, id)
		if not list.is_empty():
			result[id] = list
	return result


func _options(game: RefCounted, seat: int, id: int) -> Array:
	if not Cards.CARDS.has(id):
		return []
	if id == 23:
		var ranks := []
		for rank: int in range(2, 15):
			ranks.append({"args": [-1, -1, -1, rank], "label": "Номинал: %s" % game.rank_name(rank)})
		return ranks
	if id == 0 and game.hole[seat].size() >= 3 or id == 3 and reverse:
		return []
	if id == 1 and not _has_folded(game):
		return []
	if id == 19 and game.board.size() < 3:
		return []
	var own: Array = range(game.hole[seat].size()) if Cards.OWN.has(id) else [-1]
	var board: Array = range(game.board.size()) if Cards.BOARD.has(id) else [-1]
	var others := [-1]
	if Cards.OTHER.has(id):
		others.clear()
		for other: int in game.players.size():
			if seat == other or game.hole[other].is_empty():
				continue
			if bool(game.folded[other]) == Cards.FOLDED.has(id):
				others.append(other)
	var options := []
	for other: int in others:
		var slots: Array = range(game.hole[other].size()) if Cards.SLOT.has(id) else [-1]
		for slot: int in slots:
			if id == 20 and game.shown[other][slot]:
				continue
			for mine: int in own:
				for shared: int in board:
					var labels := PackedStringArray()
					if mine >= 0:
						labels.append("Ваша %d: %s" % [mine + 1, game.card_name(game.hole[seat][mine])])
					if other >= 0:
						var label: String = game.players[other].name
						if slot >= 0:
							var card: int = game.hole[other][slot]
							label += " · карта %d" % (slot + 1)
							if game.shown[other][slot] or knows(seat, other, slot, card):
								label += " (%s)" % game.card_name(card)
						labels.append(label)
					if shared >= 0:
						labels.append("Стол %d: %s" % [shared + 1, game.card_name(game.board[shared])])
					options.append({"args": [mine, other, slot, shared], "label": " → ".join(labels)})
	return options


func _has_folded(game: RefCounted) -> bool:
	for seat: int in game.players.size():
		if not game.in_hand(seat) and not game.hole[seat].is_empty():
			return true
	return false


func _effect(game: RefCounted, seat: int, id: int, args: Array) -> bool:
	var mine: int = args[0]
	var other: int = args[1]
	var slot: int = args[2]
	var shared: int = args[3]
	var deck: Array = game.deck
	match id:
		0:
			game.hole[seat].append(deck.pop_back())
			game.shown[seat].append(false)
		1:
			for target: int in game.players.size():
				if not game.in_hand(target) and not game.hole[target].is_empty():
					var cards: Array = game.hole[target]
					for index: int in cards.size():
						_remember(seat, target, index, cards[index])
					_report(game, seat, str(game.players[target].name), cards)
		2, 20:
			if id == 20 and game.shown[other][slot]:
				return false
			var card: int = game.hole[seat][mine]
			var mine_open: bool = game.shown[seat][mine]
			game.hole[seat][mine] = game.hole[other][slot]
			game.shown[seat][mine] = id == 20 or game.shown[other][slot]
			game.hole[other][slot] = card
			game.shown[other][slot] = id == 20 or mine_open
		3:
			reverse = true
		4:
			var card: int = game.hole[other][slot]
			_remember(seat, other, slot, card)
			_report(game, seat, str(game.players[other].name), [card])
		5:
			_report(game, seat, Cards.title(id), _peek_deck(game, 1))
		6, 12:
			if id == 12:
				game.shown[seat][mine] = true
			var top := _peek_deck(game, 3)
			if id == 6:
				_shuffle(top, game.rng)
			_report(game, seat, Cards.title(id), top)
		7, 9, 13, 24, 25:
			var index := deck.size() - 1
			match id:
				9:
					index = _random_ten(deck, game.rng)
				13:
					index = game.rng.randi_range(0, deck.size() - 1)
				24, 25:
					while index >= 0 and _red(deck[index]) != (id == 25):
						index -= 1
			if index < 0:
				return false
			var card: int = deck.pop_at(index)
			game.hole[seat][mine] = card
			game.shown[seat][mine] = false
		10:
			game.board[shared] = deck.pop_back()
		11:
			game.shown[other][slot] = true
		14:
			deck.assign(range(52))
			_shuffle(deck, game.rng)
			deck_replacements += 1
		15:
			var card: int = deck[-1]
			deck[-1] = deck[-2]
			deck[-2] = card
		16:
			var index := _find_rank(deck, 11, 13)
			if index < 0:
				return false
			game.board[shared] = deck.pop_at(index)
		18:
			var colors := PackedStringArray()
			for card: int in game.hole[other]:
				colors.append("красная" if _red(card) else "чёрная")
			peeks[seat].append("%s · %s" % [game.players[other].name, ", ".join(colors)])
		19:
			peeks[seat].append("%s · %s" % [game.players[other].name, evaluate(game.hole[other] + game.board, other).name])
		21:
			game._note("Карта после ближайшей выкладки: %s" % game.card_name(_peek_deck(game, 1)[0]))
		22:
			var card: int = game.board[shared]
			game.board[shared] = game.hole[seat][mine]
			game.hole[seat][mine] = card
			game.shown[seat][mine] = true
		23:
			_report_rank(game, seat, shared)
		27:
			game.shown[other].fill(true)
		28:
			for target: int in game.players.size():
				if not game.in_hand(target):
					continue
				for index: int in game.hole[target].size():
					var rank := int(game.hole[target][index]) % 13 + 2
					if rank >= 11 and rank <= 13:
						game.shown[target][index] = true
		Cards.GAPPED_STRAIGHT:
			gap_straights.append(seat)
		Cards.COLOR_FLUSH:
			color_flushes.append(seat)
		_:
			return false
	return true


func _report_rank(game: RefCounted, seat: int, rank: int) -> void:
	var matches := PackedStringArray()
	for other: int in game.players.size():
		if other == seat or not game.in_hand(other):
			continue
		var count := 0
		for card: int in game.hole[other]:
			if card % 13 + 2 == rank:
				count += 1
		if count > 0:
			matches.append("%s ×%d" % [game.players[other].name, count])
	var info := ", ".join(matches) if not matches.is_empty() else "у соперников нет"
	peeks[seat].append("%s · %s · %s" % [Cards.title(23), game.rank_name(rank), info])


func _remember(seat: int, other: int, slot: int, card: int) -> void:
	known[seat][Vector2i(other, slot)] = card


func knows(seat: int, other: int, slot: int, card: int) -> bool:
	return seat >= 0 and seat < known.size() and int(known[seat].get(Vector2i(other, slot), -1)) == card


func _report(game: RefCounted, seat: int, title: String, cards: Array) -> void:
	var names := PackedStringArray()
	for card: int in cards:
		names.append(game.card_name(card))
	peeks[seat].append("%s · %s" % [title, ", ".join(names)])


func view_for(game: RefCounted, seat: int) -> Dictionary:
	var own := seat >= 0 and seat < hands.size()
	var can_pick: bool = own and _play_window(game) and game.in_hand(seat) and not pending.has(seat)
	var effects := PackedStringArray()
	if gap_straights.has(seat):
		effects.append(Cards.title(Cards.GAPPED_STRAIGHT))
	if color_flushes.has(seat):
		effects.append(Cards.title(Cards.COLOR_FLUSH))
	return {
		"hand": hands[seat].filter(func(id: int) -> bool: return Cards.CARDS.has(id)) if own else [],
		"played": pending.get(seat, {}).get("id", -1),
		"options": choices(game, seat) if can_pick else {},
		"revealed": revealed.duplicate(true),
		"peeks": peeks[seat].duplicate() if own else [],
		"reverse": reverse,
		"effects": effects,
		"window": window,
	}


func evaluate(cards: Array, seat: int = -1) -> Dictionary:
	# При «Гипнозе» выгоднее пользоваться обычной оценкой: оба послабления
	# могут только повысить обычную силу пятёрки.
	var gapped := not reverse and gap_straights.has(seat)
	var colors := not reverse and color_flushes.has(seat)
	return TGPoker.evaluate(cards, reverse, 8, deck_replacements > 0, gapped, colors)


func compare(a: Dictionary, b: Dictionary) -> int:
	return TGPoker.compare(a, b) * (-1 if reverse else 1)


static func _random_ten(deck: Array, rng: RandomNumberGenerator) -> int:
	var positions := []
	for index: int in deck.size():
		if int(deck[index]) % 13 == 8:
			positions.append(index)
	if positions.is_empty():
		return -1
	return positions[rng.randi_range(0, positions.size() - 1)]


static func _find_rank(deck: Array, lowest: int, highest: int) -> int:
	for index: int in range(deck.size() - 1, -1, -1):
		var rank := int(deck[index]) % 13 + 2
		if rank >= lowest and rank <= highest:
			return index
	return -1


static func _red(card: int) -> bool:
	return card >= 26


static func _shuffle(cards: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var card: int = cards[i]
		cards[i] = cards[j]
		cards[j] = card
