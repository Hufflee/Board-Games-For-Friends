extends RefCounted
## Пакет13:40полных текстов164–205, кроме ранее разобранных174/199.
const IDS := [164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 200, 201, 202, 203, 204, 205]
const ACTIVATED := [167, 168, 169, 170, 171, 172, 175, 178, 180, 181, 183, 185, 188, 189, 191, 192, 193, 195, 203, 204, 205]
static func plan(id: int, context: String) -> Array:
	match id:
		166:
			return [{"op":"coins", "amount":8}]
		167:
			return [{"op":"admiration_target", "targets":"gift_players13"}, {"op":"gift_only13", "targets":"giver_hand12"}]
		168:
			return [{"op":"double_draw13", "targets":"players"}]
		169:
			return [{"op":"copy_passive13", "targets":"passive_items13"}]
		170:
			return [{"op":"vote_prepare13"}]
		171:
			return [{"op":"destroy_cost13", "targets":"cost_destroy13", "required":true}, {"op":"destroy_cost13", "targets":"cost_destroy13", "required":true}, {"op":"declare_paid12"}] if context == "activation_cost" else [{"op":"steal", "targets":"steal_players13"}]
		172:
			return [{"op":"loot"}, {"op":"hand_top", "targets":"own_hand_top"}]
		173:
			return [{"op":"peek_deck", "deck":"treasure", "amount":1}, {"op":"read_peek"}]
		175, 185:
			return [{"op":"auto_roll"}, {"op":"bag_result13"}]
		176:
			return [{"op":"recharge", "targets":"items", "optional":true}]
		177:
			return [{"op":"piggy_reward13"}]
		178:
			return [{"op":"damage", "targets":"damage_targets"}]
		179:
			return [{"op":"random_destroy13"}]
		180:
			return [{"op":"counter", "amount":1}] if context == "damage" else [{"op":"self_shield13"}]
		181:
			return [{"op":"destroy_self"}, {"op":"chaos_mode13", "targets":"chaos_modes13"}]
		182, 187:
			return [{"op":"peek_deck", "deck":"monster" if id == 182 else "loot", "amount":4}, {"op":"order_peek"}]
		183:
			return [{"op":"discard_tops13"}]
		186:
			return [{"op":"recycle_hand13", "targets":"recycle_hand13", "optional":true}, {"op":"recycle_draw13"}]
		188:
			return [{"op":"compost_arm13"}]
		189:
			return [{"op":"destroy_self"}, {"op":"unlimited_loot13"}]
		190:
			return [{"op":"loot", "amount":3}]
		191:
			return [{"op":"pay_health13"}, {"op":"next_hit_shield", "targets":"shield_players13", "amount":2}]
		192:
			return [{"op":"damage", "targets":"players"}]
		193:
			return [{"op":"monster_top13", "targets":"discard_monsters13"}]
		194:
			return [{"op":"haunt_give", "targets":"other_players"}]
		195:
			return [{"op":"damage_cap13", "targets":"damage_caps13"}]
		197:
			return [{"op":"roller_damage13", "targets":"yes13", "optional":true}]
		198:
			return [{"op":"optional_loot13", "targets":"yes13", "optional":true}, {"op":"discard_if_drew13"}]
		201:
			return [{"op":"crow_reveal13", "targets":"yes13", "optional":true}]
		203:
			return [{"op":"fly_recharge", "targets":"fly_yes", "optional":true}] if context == "roll" else [{"op":"coins"}]
		204:
			return [{"op":"roll", "targets":"subtract_roll13"}]
		205:
			return [{"op":"monster_damage", "targets":"monsters"}]
	return []
