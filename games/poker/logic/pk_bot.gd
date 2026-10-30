class_name PKBot
extends RefCounted
## «Покер»: бот. Префлоп — сила стартовой руки, дальше — шансы перебором (Монте-Карло против живых соперников)
## и шансы банка. Иногда блефует и иногда разыгрывает сильную руку медленно.
## Возвращает {kind: "fold" | "call" | "raise", amount}.

const SAMPLES := 90
const MAX_OPPONENTS := 3  # дальше шансы почти не меняются, а считать дольше


static func decide(rules: RefCounted, seat: int, rng: RandomNumberGenerator) -> Dictionary:
	var need: int = rules.to_call(seat)
	var pot: int = rules.pot()
	var strength: float = preflop_strength(rules.hole[seat]) if rules.board.is_empty() else equity(rules, seat, rng)
	var pot_odds := float(need) / float(pot + need) if need > 0 else 0.0
	var bluff := rng.randf() < 0.07
	var bb: int = rules.BB
	if rules.can_raise(seat) and (strength > 0.72 or bluff) and rng.randf() < 0.85:
		var size: float = pot * (0.5 if strength < 0.85 else 0.8)
		if rules.board.is_empty():
			size = float(bb * rng.randi_range(2, 4))
		var amount: int = rules.current_bet + maxi(int(size), rules.min_raise)
		if strength > 0.93 and rng.randf() < 0.25:
			amount = rules.max_raise_to(seat)  # монстр — иногда сразу ва-банк
		return {"kind": "raise", "amount": clampi(amount, rules.min_raise_to(seat), rules.max_raise_to(seat))}
	if need == 0:
		return {"kind": "call"}
	# уравниваем, если шансы выше шансов банка (с запасом на неточность); дешёвый колл — почаще
	var cheap := need <= bb * 2
	if strength >= pot_odds + 0.05 or (cheap and strength > 0.35):
		return {"kind": "call"}
	return {"kind": "fold"}


## Сила двух карт 0..1: пары, старшие карты, одномастные и связанные.
static func preflop_strength(cards: Array) -> float:
	if cards.size() < 2:
		return 0.0
	var a: int = int(cards[0]) % 13 + 2
	var b: int = int(cards[1]) % 13 + 2
	var high := maxi(a, b)
	var low := mini(a, b)
	var score := 0.0
	if a == b:
		score = 0.5 + float(a - 2) / 12.0 * 0.5
	else:
		score = float(high - 2) / 12.0 * 0.45 + float(low - 2) / 12.0 * 0.2
		if int(cards[0]) / 13 == int(cards[1]) / 13:
			score += 0.08
		var gap := high - low
		if gap == 1:
			score += 0.06
		elif gap == 2:
			score += 0.03
	return clampf(score, 0.0, 1.0)


## Доля выигранных розыгрышей до ривера против случайных рук живых соперников.
static func equity(rules: RefCounted, seat: int, rng: RandomNumberGenerator) -> float:
	var opponents := 0
	for other: int in rules.players.size():
		if other != seat and rules.in_hand(other):
			opponents += 1
	opponents = mini(opponents, MAX_OPPONENTS)
	var known: Array = rules.hole[seat] + rules.board
	var pool := []
	for card: int in 52:
		if not known.has(card):
			pool.append(card)
	var wins := 0.0
	for _i: int in SAMPLES:
		var deck := pool.duplicate()
		var draw := func() -> int:
			var k := rng.randi_range(0, deck.size() - 1)
			var c: int = deck[k]
			deck[k] = deck[-1]
			deck.pop_back()
			return c
		var table: Array = rules.board.duplicate()
		while table.size() < 5:
			table.append(draw.call())
		var mine: Dictionary = TGPoker.evaluate(rules.hole[seat] + table)
		var result := 1.0
		for _o: int in opponents:
			var theirs: Dictionary = TGPoker.evaluate([draw.call(), draw.call()] + table)
			var cmp := TGPoker.compare(mine, theirs)
			if cmp < 0:
				result = 0.0
				break
			if cmp == 0:
				result = minf(result, 0.5)
		wins += result
	return wins / SAMPLES
