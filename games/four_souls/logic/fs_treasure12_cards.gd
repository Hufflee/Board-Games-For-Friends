extends RefCounted
## Пакет12:124–163. Полные тексты — card_texts.json, исходные области texts12_0..9.png.
const IDS := [124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163]
const ACTIVATED := [125, 126, 129, 133, 134, 136, 140, 145, 148, 150, 151, 154, 155, 156, 157, 159, 160, 162, 163]

static func plan(id: int, context: String) -> Array:
	match id:
		124:
			return [{"op": "abaddon_die"}]
		125:
			return [{"op": "pay_loot_cost", "targets": "cost_hand12", "required": true}, {"op": "declare_paid12"}] if context == "activation_cost" else [{"op": "athame_discard", "targets": "players"}]
		126, 162:
			return [{"op": "set_roll12", "targets": "fixed_roll_faces"}]
		127:
			return [{"op": "damage", "targets": "wiz_targets"}]
		129:
			return [{"op": "auto_roll"}, {"op": "krampus_result"}]
		130:
			return [{"op": "coins", "amount": 1 if context in ["damage", "monster_damage"] else 2}]
		131:
			return [{"op": "damage", "targets": "damage_targets"}]
		132:
			return [{"op": "phd_adjust", "targets": "phd_adjustments"}]
		133:
			return [{"op": "destroy_self"}, {"op": "divorce_target", "targets": "other_players"}, {"op": "divorce_halves"}, {"op": "divorce_item", "targets": "giver_item12"}]
		134:
			return [{"op": "destroy_self"}, {"op": "forget_souls"}]
		135:
			return [{"op": "reroll_item", "targets": "bug_items", "optional": true}]
		136:
			return [{"op": "damage", "targets": "damage_targets"}] if context == "candle_roll" else [{"op": "candle_face", "targets": "candle_faces"}]
		138:
			return [{"op": "haunt_give", "targets": "other_players"}]
		139:
			return [{"op": "redirect_attack", "targets": "declared_monsters", "optional": true}]
		140:
			if context == "multi_roll":
				return [{"op": "multi_prepare"}, {"op": "auto_roll"}, {"op": "multi_collect"}]
			return [{"op": "multi_arm"}]
		141:
			return [{"op": "deactivate", "targets": "items", "optional": true}]
		142:
			return [{"op": "destroy_self"}, {"op": "one_up_save"}]
		144:
			return [{"op": "pitfall"}]
		145:
			return [{"op": "rainbow_mode", "targets": "rainbow_modes"}]
		146:
			return [{"op": "auto_roll"}, {"op": "cement_result"}]
		147:
			return [{"op": "discard_loot", "targets": "own_hand"}]
		148:
			return [{"op": "admiration_target", "targets": "other_players"}, {"op": "admiration_gift", "targets": "giver_hand12"}, {"op": "read_peek"}, {"op": "admiration_play"}]
		149:
			return [{"op": "telepathy_use", "targets": "telepathy_options"}] if context == "next_roll" else [{"op": "auto_roll"}, {"op": "telepathy_store"}]
		150:
			return [{"op": "fly_recharge", "targets": "fly_yes", "optional": true}] if context == "damage" else [{"op": "peek_deck", "targets": "decks"}, {"op": "fly_top", "targets": "fly_top_options"}]
		151:
			return [{"op": "candle_reveal"}, {"op": "candle_curse", "targets": "revealed_curses12", "optional": true}, {"op": "candle_bottom", "targets": "candle_bottom_cards"}]
		152:
			return [{"op": "euthanasia_kill"}]
		153:
			return [{"op": "key_cover", "targets": "dad_key_slots", "optional": true}]
		154:
			return [{"op": "auto_roll"}, {"op": "d100_result"}]
		155:
			return [{"op": "reroll_item", "targets": "all_destroyable"}]
		156:
			return [{"op": "destroy_self"}, {"op": "d4_inventory", "targets": "players"}]
		157:
			return [{"op": "donation_item", "targets": "donation_items12", "required": true}, {"op": "donation_give", "targets": "other_players", "required": true}, {"op": "declare_paid12"}] if context == "activation_cost" else [{"op": "coins", "amount": 8}]
		159:
			return [{"op": "recharge", "targets": "other_items12"}]
		160:
			return [{"op": "recharge", "targets": "items"}]
		163:
			return [{"op": "boomerang_take", "targets": "other_players"}]
	return []
