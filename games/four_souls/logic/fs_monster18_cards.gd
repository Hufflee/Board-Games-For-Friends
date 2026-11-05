extends RefCounted
## Сорок текстов367–408, кроме ранее разобранных369/395.
const IDS := [367, 368, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408]
static func plan(id: int, context: String) -> Array:
	match id:
		370:
			return [{"op": "other_damage18"}]
		371, 397:
			return [{"op": "roller_damage18"}]
		372:
			return [{"op": "auto_roll"}, {"op": "neighbor_result18"}]
		374:
			return [{"op": "nonactive_damage17"}]
		375:
			return [{"op": "peek_deck", "deck": "monster", "amount": 5}, {"op": "order_peek"}]
		376, 388:
			return [{"op": "damage_all18"}]
		377:
			return [{"op": "heal_all18"}]
		378:
			return [{"op": "expand16", "amount": 2}]
		379:
			return [{"op": "peek_deck", "targets": "decks", "amount": 3, "optional": true}, {"op": "order_peek"}]
		380:
			return [{"op": "expand16", "amount": 2}, {"op": "extra_attack", "targets": "accept17", "optional": true}]
		381:
			return [{"op": "winner_prepare18"}]
		382:
			return [{"op": "soul_giver18", "targets": "soul_owners18", "optional": true}]
		383:
			return [{"op": "lose_coins_all18", "amount": 4}]
		386:
			return [{"op": "extra_blind17", "targets": "accept17", "optional": true}]
		387:
			return [{"op": "player_damage18", "targets": "players", "amount": 3}]
		389:
			return [{"op": "soul_destroyer18", "targets": "players"}]
		390:
			return [{"op": "expand_shop"}]
		392:
			return [{"op": "auto_roll"}, {"op": "soul_damage16"}]
		393:
			return [{"op": "auto_roll"}, {"op": "death_result18"}]
		394:
			return [{"op": "lose_victim_coins18"}]
		396:
			return [{"op": "discard_target18", "targets": "players"}]
		399, 406:
			return [{"op": "mirror_damage18"}]
		403:
			return [{"op": "coins", "targets": "players", "amount": -7}]
		404, 405:
			return [{"op": "required_attack16"}]
	return []
