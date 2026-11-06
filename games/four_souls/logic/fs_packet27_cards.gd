extends RefCounted
## Последние стартовые предметы группы 27.
const ITEMS := [887, 889, 891, 893, 895, 897, 899, 901, 903, 905, 907, 910, 912, 56, 60, 832, 865]
const TAP := [887, 889, 891, 893, 895, 897, 899, 905, 907, 912, 60, 832, 865]

static func plan(id: int, context: String) -> Array:
	match id:
		887: return [{"op": "gello_heal27", "targets": "gello_target27"}]
		889: return [{"op": "bargain_start27"}]
		895:
			if context == "turn_end":
				return [{"op": "destroy", "targets": "own_destroy"}]
			return [{"op": "lemegeton_pending27"}, {"op": "treasure"}]
		897: return [{"op": "revenant_flip27"}]
		901: return [{"op": "tar_mode27", "targets": "tar_modes27"}]
		903: return [{"op": "auto_roll"}, {"op": "dna_result27"}]
		907:
			return [{"op": "give_loot_target21", "targets": "other_players", "required": true},
				{"op": "give_loot21", "targets": "give_loot21", "required": true},
				{"op": "peek_deck", "deck": "loot", "amount": 2}, {"op": "order_peek"}, {"op": "loot"}]
		910:
			if context == "squid_reward27":
				return [{"op": "squid_token27", "targets": "squid_items27"}]
			return [{"op": "squid_buff27", "targets": "squid_offer27", "optional": true}]
		912: return [{"op": "extra_loot"}]
		56: return [{"op": "recharge_all", "targets": "players"}]
		60: return [{"op": "rkey28"}]
		832:
			if context == "turn_start":
				return [{"op": "curse_mill28", "targets": "curse_decks28", "required": true}]
			return [{"op": "curse_return28", "targets": "curse_discards28"}]
		865:
			if context == "turn_end":
				return [{"op": "auto_roll"}, {"op": "spindown_recharge28"}]
			return [{"op": "spindown28", "targets": "spindown_items28", "required": true}, {"op": "spindown_shop28", "targets": "spindown_shop28", "optional": true}]
		891: return [{"op": "abyss_destroy28", "targets": "abyss_items28", "required": true}]
		893: return [{"op": "cancel_selected", "targets": "dead_weight28"}]
		899:
			return [{"op": "classic_pick28", "targets": "classic_rolls28", "required": true}, {"op": "auto_roll"}, {"op": "classic_collect28"},
				{"op": "auto_roll"}, {"op": "classic_collect28"}, {"op": "classic_judge28", "targets": "classic_judges28", "required": true},
				{"op": "classic_choose28", "targets": "classic_faces28", "required": true}]
		905:
			if context == "club_cancel28":
				return [{"op": "club_cancel28", "targets": "club_cancel28"}]
			return [{"op": "club_bottom28", "targets": "club_monsters28"}]
	return []
