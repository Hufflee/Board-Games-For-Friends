extends RefCounted
## Пакет09: двадцать сокровищ по passive_treasure20.png и passive_health3.png.
const IDS := [16, 18, 24, 25, 26, 33, 36, 38, 39, 41, 45, 58, 62, 69, 76, 77, 79, 112, 174, 249]

static func plan(id: int, context: String) -> Array:
	match id:
		33: return [{"op": "damage", "targets": "damage_targets", "amount": 1, "optional": true}]
		38: return [{"op": "destroy_self"}, {"op": "coins", "amount": 25}]
		41: return [{"op": "damage", "targets": "brimstone_targets", "amount": 1}]
		69:
			if context == "turn_end":
				return [{"op": "sack_discard"}]
			return [{"op": "give_source", "targets": "other_players"}]
		77: return [{"op": "penny_counter"}, {"op": "give_source", "targets": "other_players"}]
	return []

static func event(id: int, owner: int, current: int, event_name: String, data: Dictionary) -> bool:
	match id:
		33: return event_name == "roll" and int(data.get("value", 0)) == 2
		41: return event_name == "roll" and int(data.get("seat", -1)) == owner and int(data.get("value", 0)) == 6
		69: return event_name == "turn_end" and owner == current
	return false
