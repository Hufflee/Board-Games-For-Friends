extends RefCounted
## Сорок полных текстов409–451 без ранее разобранных414/417/424.
const IDS := [409, 410, 411, 412, 413, 415, 416, 418, 419, 420, 421, 422, 423, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451]
static func plan(id: int, _context: String) -> Array:
	match id:
		410:
			return [{"op": "random_loot19", "targets": "other_hands19"}]
		416:
			return [{"op": "expand16"}]
		418:
			return [{"op": "steal", "targets": "steal_players13", "optional": true}]
		419, 436:
			return [{"op": "end_unresolved17"}]
		429:
			return [{"op": "bloat_prepare19"}]
		432:
			return [{"op": "required_attack16"}]
		433, 438, 440, 443:
			return [{"op": "roller_damage19", "amount": 2 if id == 440 else 1}]
		435:
			return [{"op": "roller_coins19", "amount": -2}]
		439:
			return [{"op": "discard_victim16"}]
		442:
			return [{"op": "recharge_all", "target": -1}]
		444:
			return [{"op": "kill_player16", "targets": "living_players16"}]
		445, 447:
			return [{"op": "roller_coins19", "amount": 2 if id == 445 else 1}]
		446:
			return [{"op": "roller_heal19"}]
		448:
			return [{"op": "recharge", "targets": "items", "optional": true}]
		449:
			return [{"op": "loot"}]
	return []
