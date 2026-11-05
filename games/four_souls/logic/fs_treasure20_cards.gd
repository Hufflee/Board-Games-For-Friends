extends RefCounted
## Реализованная часть сокровищ пакета20; остальные карты подключаются после реализации.
const IDS := [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 17, 19, 20, 22, 23, 27, 28, 29, 30, 31, 32]
const ACTIVATED := [1, 2, 4, 5, 9, 10, 11, 12, 13, 19, 20, 22, 29]
static func plan(id: int, context: String) -> Array:
	match id:
		1:
			if context == "gain_item":
				return [{"op": "prototype_column20", "targets": "prototype_column0_20"}, {"op": "prototype_column20", "targets": "prototype_column1_20"}, {"op": "prototype_column20", "targets": "prototype_column2_20"}, {"op": "prototype_commit20"}]
			return [{"op": "prototype_run20"}] if context == "generated20" else [{"op": "prototype_run20", "targets": "prototype_paid20"}]
		2:
			return [{"op": "auto_roll"}, {"op": "dataminer20"}]
		3:
			return [{"op": "familiar_reward20"}] if context == "destroyed20" else [{"op": "coop_partner20", "targets": "other_players"}]
		4:
			return [{"op": "destroy_self"}, {"op": "booster_reveal20"}, {"op": "booster_play20", "targets": "booster_loot20", "optional": true}, {"op": "booster_done20"}]
		5:
			return [{"op": "mushroom_counter20", "targets": "mushrooms20"}] if context == "character20" else [{"op": "mushroom_mode20", "targets": "mushroom_modes20"}]
		8:
			return [{"op": "take_shop", "targets": "karma_shop20"}, {"op": "loot"}] if context == "gift20" else [{"op": "karma_first20", "targets": "players"}]
		9:
			return [{"op": "own_cancel20"}, {"op": "full_heal20"}]
		10:
			if context == "death":
				return [{"op": "source_counter20", "amount": 3}]
			if context == "saved20":
				return [{"op": "own_cancel20", "targets": "accept17", "optional": true}]
			return [{"op": "tumor_save20", "targets": "players"}]
		11:
			return [{"op": "coins", "amount": 2}, {"op": "will_store20"}] if context == "after_death" else [{"op": "will_mode20", "targets": "will_modes20"}]
		12:
			return [{"op": "recharge_source20"}] if context == "roll" else [{"op": "next_d8_20", "targets": "players"}]
		13:
			return [{"op": "peek_deck", "targets": "decks", "amount": 2, "optional": true}, {"op": "peek_discard_prepare20"}] if context == "turn_start" else [{"op": "force_activate20", "targets": "forced_items20"}]
		17:
			return [{"op": "pyro_search20"}]
		19:
			return [{"op": "top_loot20"}]
		20:
			return [{"op": "loot"}] if context == "death" else [{"op": "nail20"}]
		22:
			return [{"op": "destroy_self"}, {"op": "peek_deck", "deck": "treasure", "amount": 7}, {"op": "deck_take_prepare20"}]
		23:
			return [{"op": "stairway_prepare20"}]
		27:
			return [{"op": "peek_deck", "deck": "treasure", "amount": 3}, {"op": "delirium_copy20", "targets": "private_treasures20"}]
		29:
			return [{"op": "end_unresolved17"}] if context == "roll" else [{"op": "unicorn20"}]
	return []
