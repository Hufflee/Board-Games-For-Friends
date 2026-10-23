class_name PerudoBot
extends RefCounted
## Бот для «Перудо»: оценивает, сколько костей номинала скорее всего на столе,
## и либо повышает ставку на самый выгодный номинал, либо говорит «Дудо!» или изредка «Калзак!».


## Ожидаемое число костей номинала face на столе с точки зрения игрока seat.
static func expected(r: PerudoRules, seat: int, face: int) -> float:
	var wild := face != 1 and not r.maputo
	var mine := 0
	for v in r.dice[seat]:
		if v == face or (wild and v == 1):
			mine += 1
	var unknown: int = r.total_dice() - r.dice[seat].size()
	var p := (1.0 / 3.0) if wild else (1.0 / 6.0)
	return mine + unknown * p


## Делает ход за бота (или за человека по таймеру). true — ход сделан.
static func act(r: PerudoRules, seat: int) -> bool:
	if r.phase != "bid" or r.turn != seat:
		return false
	if not r.bid.is_empty():
		var exp_now := expected(r, seat, r.bid["face"])
		# чем сильнее ставка превышает ожидание, тем охотнее не верим
		var excess: float = float(r.bid["q"]) - exp_now
		if excess > 1.2 or (excess > 0.4 and r.rng.randf() < 0.45):
			return r.challenge(seat)
		# ставка очень близка к ожиданию — иногда рискуем «Калзаком»
		if absf(excess) < 0.35 and r.rng.randf() < 0.12:
			return r.calza(seat)
	var best_face := -1
	var best_q := -1
	var best_score := -999.0
	for face in range(1, PerudoRules.FACES + 1):
		var q := r.min_quantity(face)
		if q < 0:
			continue
		var score := expected(r, seat, face) - q + r.rng.randf() * 0.6
		if score > best_score:
			best_score = score
			best_face = face
			best_q = q
	if best_face < 0:
		return r.challenge(seat)
	return r.place_bid(seat, best_q, best_face)
