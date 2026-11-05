extends RefCounted
## Пакет10: двадцать сокровищ с бросками, приватным просмотром и обязательными событиями.
const IDS := [0, 6, 14, 15, 21, 84, 85, 86, 87, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99]
const ACTIVATED := [0, 6, 21, 84, 85, 91, 94, 95, 96, 99]

static func plan(id: int, context: String) -> Array:
	match id:
		0: return [{"op": "destroy_self"}, {"op": "gift_player", "targets": "gift_players", "optional": true}, {"op": "gift_peek"}, {"op": "gift_arrange", "targets": "gift_cards"}, {"op": "gift_award"}]
		6: return [{"op": "auto_roll"}, {"op": "tnt_result"}]
		14: return [{"op": "destroy_self"}, {"op": "peek_deck", "deck": "treasure", "amount": 10}, {"op": "pumpkin_pick", "targets": "pumpkin_cards"}]
		15: return [{"op": "auto_roll"}, {"op": "dad_ring_result"}]
		21: return [{"op": "destroy_self"}, {"op": "dollar_shop"}]
		84: return [{"op": "peek_hand", "targets": "players"}, {"op": "read_peek"}, {"op": "peek_deck", "targets": "decks", "amount": 1}, {"op": "xray_discard", "targets": "xray_card", "optional": true}]
		85: return [{"op": "hallowed_take"}]
		86: return [{"op": "auto_roll"}, {"op": "chest_result"}]
		87: return [{"op": "shadow_reward"}]
		91: return [{"op": "peek_deck", "deck": "treasure", "amount": 3}, {"op": "order_peek"}, {"op": "discard_shop", "targets": "shop_items"}]
		93: return [{"op": "milk_counter"}]
		94, 95: return [{"op": "destroy_self"}, {"op": "auto_roll"}, {"op": "treatment_result" if id == 94 else "pageant_result"}]
		96: return [{"op": "gish_lock", "targets": "tapped_items"}]
		98: return [{"op": "marked_set", "targets": "marked_faces", "optional": true}]
		99: return [{"op": "monster_damage", "targets": "monsters", "amount": 1}, {"op": "damage", "targets": "players", "amount": 1}, {"op": "damage", "amount": 1}]
	return []

static func event(id: int, owner: int, current: int, event_name: String, data: Dictionary) -> bool:
	match id:
		15: return event_name == "attack_start" and int(data.get("seat", -1)) == owner
		86: return event_name == "monster_death" and int(data.get("seat", -1)) == owner
		93: return event_name == "turn_start" and owner == current
	return false
