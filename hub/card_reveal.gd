extends RefCounted
## Временный показ карты. Место -1 означает публичный показ.

static func show(reveals: Dictionary, cards: Array, seat: int, seconds: float) -> void:
	if seat < -1 or seconds <= 0.0:
		return
	for card: Variant in cards:
		reveals[card] = {"seat": seat, "seconds": seconds}


static func visible_to(reveal: Dictionary, viewer: int) -> bool:
	var audience := int(reveal.get("seat", -2))
	return audience == -1 or (audience >= 0 and audience == viewer)


static func tick(reveals: Dictionary, delta: float) -> bool:
	var expired := false
	for card: Variant in reveals.keys():
		var grant_data: Dictionary = reveals[card]
		grant_data.seconds = maxf(0.0, float(grant_data.seconds) - delta)
		if float(grant_data.seconds) <= 0.0:
			reveals.erase(card)
			expired = true
	return expired
