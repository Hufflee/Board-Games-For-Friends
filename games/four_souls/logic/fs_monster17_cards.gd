extends RefCounted
## Сорок текстов327–366: командные атаки, два кубика и одноразовые модификаторы.
const IDS := [327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366]
static func plan(id: int, context: String) -> Array:
	match id:
		327:
			return [{"op": "nonactive_damage17"}]
		328:
			return [{"op": "double_prepare17"}, {"op": "auto_roll"}, {"op": "double_collect17"}, {"op": "double_choose17", "targets": "double_faces17"}]
		329:
			return [{"op": "expand16"}]
		330:
			return [{"op": "random_damage15", "amount": 1}]
		331:
			return [{"op": "coins", "targets": "accept17", "amount": 3, "optional": true}]
		333:
			return [{"op": "extra_attack", "targets": "accept17", "optional": true}]
		334:
			return [{"op": "loot"}]
		335:
			return [{"op": "partner_gift17"}] if context == "monster_death" else [{"op": "partner17", "targets": "living_others17"}]
		337:
			return [{"op": "auto_roll"}, {"op": "neighbor_damage17"}]
		338:
			return [{"op": "peek_deck", "deck": "loot", "amount": 5}, {"op": "order_peek"}]
		339:
			return [{"op": "exchange_prepare15"}]
		340:
			return [{"op": "auto_roll"}, {"op": "declaration_damage17"}]
		341:
			return [{"op": "skip_turn", "targets": "players"}]
		342:
			return [{"op": "kill_knots17"}]
		343:
			return [{"op": "egg_spawn17", "targets": "spawn_slots17"}] if context == "respawn17" else [{"op": "egg_counter17"}]
		347:
			return [{"op": "force_deck_attack"}]
		356:
			return [{"op": "damage", "target_roller17": true, "amount": 2}] if context == "two17" else [{"op": "end_unresolved17"}]
		360:
			return [{"op": "expand16", "amount": 2}, {"op": "extra_blind17", "targets": "accept17", "optional": true}]
		363:
			return [{"op": "auto_roll"}, {"op": "one_health17"}]
		365:
			return [{"op": "damage", "targets": "living_players16"}]
		366:
			return [{"op": "auto_roll"}, {"op": "brown_result17"}]
	return []
