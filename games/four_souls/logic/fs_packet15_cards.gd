extends RefCounted
## Пакет15: оставшиеся базовые сокровища и первые монстры дополнений.
const IDS := [246, 247, 248, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286]
const ACTIVATED := [248, 251, 252, 253, 255, 257]
static func plan(id: int, context: String) -> Array:
	match id:
		246:
			return [{"op": "auto_roll"}, {"op": "bum_result15"}]
		247:
			return [{"op": "shadow_item15", "targets": "penalty_items15"}]
		248:
			return [{"op": "kill15", "targets": "kill_targets15"}] if context == "paid15" else [{"op": "source_counter15"}]
		251:
			return [{"op": "rotate_hands15", "direction": 1}]
		252:
			return [{"op": "crystal_face15", "targets": "faces15"}]
		253:
			return [{"op": "steal_coins", "targets": "other_players", "amount": 3}]
		255:
			return [{"op": "damage", "targets": "other_players"}] if context == "prevented" else [{"op": "reflect_shield15"}]
		257:
			return [{"op": "box_destroy15"}, {"op": "auto_roll"}, {"op": "box_result15"}]
		258:
			return [{"op": "min_prepare15"}]
		259:
			return [{"op": "auto_roll"}, {"op": "trapper_result15"}] if context == "turn_start" else [{"op": "damage", "target_current": true}]
		260:
			return [{"op": "random_tokens15"}]
		261:
			return [{"op": "spiders_prepare15"}]
		262:
			return [{"op": "monster_age15"}] if context == "turn_start" else [{"op": "damage_all", "amount": 2}]
		263:
			return [{"op": "random_attack_token15"}]
		265:
			return [{"op": "auto_roll"}, {"op": "switch_result15"}]
		266:
			return [{"op": "exchange_prepare15"}] if context == "attack_declared" else [{"op": "loot"}]
		267:
			return [{"op": "eternal_token15", "targets": "eternal_items15"}] if context == "monster_death" else [{"op": "discard_other15", "targets": "other_monsters15"}]
		269:
			return [{"op": "numbers_prepare15"}]
		270:
			return [{"op": "rotate_hands15", "direction": -1}]
		271:
			return [{"op": "vote_prepare15"}] if context == "turn_start" else [{"op": "other_monster_damage15"}]
		273:
			return [{"op": "neighbors_prepare15"}]
		274:
			return [{"op": "cancel_source_attack15"}, {"op": "loot"}, {"op": "move_monster15", "targets": "other_slots15"}]
		275:
			return [{"op": "other_monster_damage15"}]
		276:
			return [{"op": "hand_health15"}]
		277:
			return [{"op": "find_curse15"}]
		282:
			return [{"op": "other_monster_damage15"}, {"op": "damage_all"}]
		283:
			return [{"op": "item_health15", "targets": "other_player_items15"}]
		285:
			return [{"op": "winner_prepare18"}]
		284:
			return [{"op": "cancel_attack15"}, {"op": "random_damage15", "amount": 2}]
	return []
