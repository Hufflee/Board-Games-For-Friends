extends RefCounted
## Пакет08: двадцать брелоков. Пассивные события содержат собственный контекст и источник.
const IDS := [471, 473, 474, 505, 523, 526, 527, 546, 566, 570, 571, 582, 647, 651, 652, 653, 654, 677, 678, 687]

static func plan(id: int, context: String) -> Array:
	match id:
		471: return [{"op": "found_soul_give", "targets": "other_players"}]
		474: return [{"op": "damage", "targets": "damage_targets", "amount": 2}]
		526: return [{"op": "hagalaz_discard", "targets": "hagalaz_targets", "optional": true}]
		546: return [{"op": "pink_eye_damage"}]
		566: return [{"op": "auto_roll"}, {"op": "aaa_result"}]
		570: return [{"op": "recharge", "targets": "items", "optional": true}]
		571: return [{"op": "damage", "targets": "other_players", "amount": 1}]
		582: return [{"op": "auto_roll"}, {"op": "poker_result"}]
		647, 651, 678: return [{"op": "peek_deck", "deck": "loot" if id == 647 else "treasure" if id == 651 else "monster", "amount": 1}, {"op": "trinket_peek", "targets": "trinket_peek"}]
		653: return [{"op": "auto_roll"}, {"op": "hairball_result"}]
		687: return [{"op": "auto_roll"}, {"op": "ankh_result"}] if context == "would_die" else []
	return []

static func event(id: int, owner: int, current: int, event_name: String, data: Dictionary) -> bool:
	var subject: int = int(data.get("seat", -1))
	match id:
		471: return event_name == "soul_control" and subject == owner
		526: return event_name == "activate" and subject == owner
		546: return event_name == "damage" and subject == owner and bool(data.get("combat", false)) and int(data.get("value", 0)) == 1
		566: return event_name == "turn_end" and owner == current
		570: return event_name == "death" and subject != owner
		571: return event_name == "attack_miss" and subject == owner
		647, 651, 678: return event_name == "turn_start" and owner == current
	return false
