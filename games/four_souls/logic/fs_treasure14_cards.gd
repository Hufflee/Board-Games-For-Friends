extends RefCounted
## Пакет14:206–245,40полных текстов. Копирование — по официальному Extended Rulebook.
const IDS := [206,207,208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245]
const ACTIVATED := [208,211,216,217,218,219,220,224,227,233,238,239,241,244]
static func plan(id: int, context: String) -> Array:
	match id:
		206:
			return [{"op": "auto_roll"}, {"op": "spider_result14"}]
		208:
			return [{"op": "cancel_ability14", "targets": "activated_stack14"}]
		209:
			return [{"op": "recharge", "targets": "items", "optional": true}]
		210:
			return [{"op": "auto_roll"}, {"op": "collar_result14"}]
		211:
			return [{"op": "peek_deck", "targets": "decks"}, {"op": "bottom_top14", "targets": "bottom_options14"}]
		212:
			return [{"op": "swap_own14", "targets": "swap_own14", "optional": true}, {"op": "swap_other14", "targets": "roller_items14"}]
		213:
			return [{"op": "reroll", "targets": "pending_reroll14", "optional": true}]
		214:
			return [{"op": "haunt_give", "targets": "other_players"}]
		215:
			return [{"op": "replace_monster14", "targets": "nonattacked14", "optional": true}]
		216:
			return [{"op": "auto_roll"}, {"op": "slot_result14"}]
		217:
			if context == "activation_cost":
				return [{"op": "pay_loot_cost", "targets": "cost_hand12", "required": true}, {"op": "declare_paid12"}]
			return [{"op": "coins", "amount": 3}]
		218:
			return [{"op": "permanent_copy14", "targets": "copy_items14"}]
		219:
			return [{"op": "steal", "targets": "steal_any14"}]
		220:
			return [{"op": "copy_ability14", "targets": "tap_items14"}]
		222:
			return [{"op": "discard_shop14", "targets": "shop_items", "optional": true}]
		224:
			return [{"op": "swap_source14", "targets": "steal_players13"}]
		225:
			return [{"op": "auto_roll"}, {"op": "fart_result14"}]
		226:
			return [{"op": "ready_character", "targets": "yes13", "optional": true}]
		227:
			return [{"op": "blank_arm14"}]
		230:
			return [{"op": "damage_others14"}]
		232:
			return [{"op": "sacred_six14", "targets": "yes13", "optional": true}]
		233:
			return [{"op": "roll", "targets": "plus_roll14"}]
		234:
			return [{"op": "damage", "targets": "other_players"}]
		236:
			return [{"op": "peek_deck", "deck": "treasure", "amount": 4}, {"op": "order_peek"}]
		238:
			return [{"op": "flush_mode14", "targets": "flush_modes14"}]
		239:
			return [{"op": "force_monster14", "targets": "forced_monsters14"}]
		241:
			return [{"op": "glass_destroy14", "targets": "other_destroy14", "required": true}, {"op": "auto_roll"}, {"op": "glass_result14"}]
		242:
			return [{"op": "roller_give14"}, {"op": "gift_only13", "targets": "giver_hand12"}]
		244:
			return [{"op": "roll", "targets": "nonattack_plus14"}]
		245:
			return [{"op": "peek_deck", "targets": "decks"}, {"op": "reveal_top14"}, {"op": "fly_top", "targets": "fly_top_options"}]
	return []
