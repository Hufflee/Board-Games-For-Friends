extends RefCounted
## Вторая половина пакета10 (сорок карт): яйца, отложенные эффекты и выбор бросков.
const IDS := [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 113, 115, 116, 117, 118, 119, 121, 123]
const ACTIVATED := [100, 101, 104, 106, 107, 109, 110, 111, 113, 119, 123]

static func plan(id: int, context: String) -> Array:
	match id:
		100: return [{"op": "white_egg", "targets": "other_players"}]
		101: return [{"op": "red_egg", "targets": "egg_entities"}]
		102: return [{"op": "black_egg", "targets": "empty_egg_entities", "optional": true}]
		103: return [{"op": "nine_recharge", "targets": "own_recharges", "optional": true, "remaining": 2}]
		104: return [{"op": "bible_mode", "targets": "bible_modes"}]
		105: return [{"op": "optional_treasure_peek", "targets": "peek_or_skip", "optional": true}, {"op": "read_peek"}]
		106: return [{"op": "ouija_peek"}, {"op": "ouija_choose", "targets": "ouija_events", "optional": true}, {"op": "ouija_bottom"}]
		107: return [{"op": "damage_monsters"}] if context == "lemon_roll" else [{"op": "lemon_enable"}]
		108: return [{"op": "knife_splash"}]
		109: return [{"op": "auto_roll"}, {"op": "bean_recharge"}]
		110: return [{"op": "dad_key_cost", "targets": "cost_hand", "required": true}, {"op": "key_cover", "targets": "dad_key_slots"}]
		111: return [{"op": "plan_c_kill_all"}] if context == "turn_end" else [{"op": "destroy_self"}, {"op": "plan_c_monster", "targets": "monsters"}]
		113: return [{"op": "crooked_target", "targets": "players"}, {"op": "auto_roll"}, {"op": "crooked_result"}]
		116: return [{"op": "reroll", "targets": "missing_roll", "optional": true}]
		119: return [{"op": "succubus_plays", "targets": "loot_play_counts"}]
		123: return [{"op": "roll", "targets": "attack_roll_bonuses"}]
	return []

static func event(id: int, owner: int, current: int, event_name: String, data: Dictionary) -> bool:
	match id:
		102: return owner == current and event_name in ["turn_start", "turn_end"]
		103: return owner == current and event_name == "turn_end"
		105: return owner == current and event_name == "turn_start"
		108: return event_name == "combat_monster_damage" and int(data.get("seat", -1)) == owner and int(data.get("value", 0)) == 6
	return false
