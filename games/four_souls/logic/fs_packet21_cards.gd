extends RefCounted
## Группа21: полные40текстов; подключение незавершённых ветвей отложено до их реализации.
const ALL_IDS := [35, 37, 42, 43, 44, 46, 47, 48, 50, 51, 52, 53, 54, 55, 57, 59, 61, 63, 64, 66, 68, 70, 71, 72, 73, 74, 78, 80, 81, 82, 83, 114, 122, 470, 475, 480, 481, 482, 483, 484]
const IDS := [35, 37, 42, 43, 44, 46, 47, 48, 50, 51, 52, 53, 54, 55, 57, 59, 61, 63, 64, 66, 70, 71, 73, 74, 78, 80, 81, 82, 122, 475]
const ACTIVATED := [35, 42, 44, 46, 47, 48, 50, 51, 53, 54, 55, 61, 63, 66, 70, 73, 80, 122]
static func plan(id: int, context: String) -> Array:
	match id:
		35: return [{"op": "shield_event21", "targets": "shield_monsters21"}]
		37: return [{"op": "auto_roll"}, {"op": "bill_result21"}]
		42: return [{"op": "splash21", "amount": 1, "exclude_owner": true}]
		43: return [{"op": "auto_roll"}, {"op": "abel_result21"}]
		44:
			return [{"op": "battery_self21"}] if context == "paid21" else [{"op": "battery_prepare21"}]
		46: return [{"op": "auction_prepare21", "targets": "auction_shop21"}]
		47: return [{"op": "bag_spend21", "targets": "bag_counters21"}]
		48: return [{"op": "shield_one21", "targets": "shield_targets21"}]
		50: return [{"op": "low_rolls21"}] if context == "paid21" else [{"op": "source_counter20", "amount": 1}]
		51:
			return [{"op": "auto_roll"}, {"op": "pandora_result21"}] if context == "turn_start" else [{"op": "treasure"}, {"op": "source_counter20", "amount": 1}, {"op": "give_source21", "targets": "other_players"}]
		52: return [{"op": "destroy_self"}]
		53: return [{"op": "peek_deck", "deck": "loot", "amount": 3}, {"op": "loot_three21", "targets": "loot_three21"}]
		54: return [{"op": "held_mode21"}]
		55: return [{"op": "damage", "targets": "damage_targets"}]
		57:
			return [{"op": "give_source21", "targets": "other_players"}] if context == "death" else [{"op": "give_loot_prepare21"}]
		59: return [{"op": "peek_deck", "targets": "decks", "amount": 3, "optional": true}, {"op": "order_peek"}]
		61: return [{"op": "raise_monster21", "targets": "discard_monsters21"}]
		63: return [{"op": "peek_deck", "deck": "monster", "amount": 3}, {"op": "peek_monster21", "targets": "peek_monsters21", "optional": true}, {"op": "order_peek"}]
		64: return [{"op": "level_start21"}]
		66: return [{"op": "destroy_self"}, {"op": "splash21", "amount": 3}]
		70: return [{"op": "discard_shop", "targets": "shop_items", "optional": true}] if context == "turn_start" else [{"op": "copy_shop21", "targets": "copy_shop21"}]
		73: return [{"op": "offer_loot_accept21", "targets": "offer_loot21", "optional": true}] if context == "offer21" else [{"op": "offer_loot_prepare21"}]
		78: return [{"op": "counter_item21", "targets": "counter_items21"}]
		81: return [{"op": "loot"}]
		80: return [{"op": "copy_eternal21", "targets": "copy_eternal21"}]
		82:
			return [{"op": "give_source21", "targets": "other_players"}] if context == "turn_end" else [{"op": "damage"}, {"op": "source_counter20", "amount": 1}, {"op": "six_soul21"}]
		122: return [{"op": "extra_loot"}]
		475: return [{"op": "treasure", "amount": 2}, {"op": "gift_soul21", "targets": "other_players"}]
	return []
