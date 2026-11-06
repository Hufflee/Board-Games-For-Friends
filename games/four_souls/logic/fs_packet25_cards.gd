extends RefCounted
## Комнаты и стартовые предметы группы25.
const ROOMS := [776, 778, 780, 783, 784, 785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 801, 805, 816, 819, 820]
const ITEMS := [824, 826, 830, 836, 841, 843]
const DICE_ROOMS := [786, 787, 788, 789, 790, 791]
static func plan(id: int, context: String) -> Array:
	if id in DICE_ROOMS:
		return [{"op": "discard_room25"}] if context == "room_end25" else [{"op": "dice_room25"}]
	match id:
		776, 785:
			return [{"op": "room_loot_cost25", "targets": "own_hand"}] if context == "room_cost24" else [{"op": "auto_roll"}, {"op": "room_table25"}]
		778: return [{"op": "auto_roll"}, {"op": "room_partner25"}]
		780, 784, 801, 805, 792, 820: return [{"op": "auto_roll"}, {"op": "room_table25"}]
		783: return [{"op": "mirror_pay25", "targets": "mirror_accept25", "optional": true}]
		824: return [{"op": "shield_event21", "targets": "shield_targets21"}]
		826: return [{"op": "peek_deck", "targets": "decks", "amount": 5}, {"op": "order_peek"}]
		830: return [{"op": "blue_modes25", "targets": "blue_modes25"}]
		836: return [{"op": "pit_cancel25"}]
		841: return [{"op": "incubus_modes25", "targets": "incubus_modes25"}]
		843:
			match context:
				"bone1": return [{"op": "bone_roll25", "targets": "rolls"}]
				"bone2": return [{"op": "damage", "targets": "damage_targets"}]
				"bone5": return [{"op": "bone_soul25"}]
			return [{"op": "source_counter20", "amount": 1}]
	return []
