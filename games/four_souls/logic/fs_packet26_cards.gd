extends RefCounted
## Стартовые предметы группы 26 и выбор способности персонажа 882.
const ITEMS := [845, 847, 849, 851, 853, 855, 857, 859, 861, 863, 869, 871, 873, 875, 877, 879, 881, 883, 885]
const TAP := [845, 847, 849, 851, 859, 863, 871, 879]
const PAID := {
	853: {"trash_loot26": [3, 0, 0, "Разыграть дополнительную добычу"], "trash_draw26": [4, 0, 0, "Взять 1 добычу"], "trash_damage26": [6, 0, 0, "Нанести 1 урона"]},
	869: {"craft_store26": [0, 0, 1, "Положить жетон"], "craft_get26": [0, 4, 0, "Получить сокровище"]},
	873: {"ibs_small26": [0, 0, 1, "Отменить свою атаку или получить 3¢"], "ibs_cancel26": [0, 0, 2, "Отменить способность или добычу"]},
	875: {"clot26": [0, 2, 0, "Уменьшить защиту монстра на 1"]},
	879: {"blood_at26": [0, 1, 0, "Установить атаку монстра на 1"], "blood_damage26": [0, 2, 0, "Нанести урон двум целям"]},
	901: {"tar_paid27": [0, 0, 1, "Применить Шар смолы"]},
	56: {"battery28": [0, 2, 0, "Перезарядить все предметы игрока"]},
	905: {"club_cancel28": [0, 0, 0, "Отменить способность или добычу"]},
}

static func plan(id: int, context: String) -> Array:
	if context.begins_with("loot_cost26/"):
		return [{"op": "loot_cost26", "targets": "own_hand", "required": true}, {"op": "paid_effect26"}]
	match id:
		845: return [{"op": "nickel_target26", "targets": "players", "required": true}, {"op": "auto_roll"}, {"op": "nickel_coins26"}]
		847: return [{"op": "void_mode26", "targets": "void_modes26"}]
		848: return [{"op": "ready_character", "targets": "ready_chars26", "optional": true}]
		849: return [{"op": "holy_save26", "targets": "players"}]
		851: return [{"op": "loot", "amount": 2}, {"op": "discard_loot", "targets": "own_hand"}]
		853:
			match context:
				"trash_loot26": return [{"op": "extra_loot"}]
				"trash_draw26": return [{"op": "loot"}]
				"trash_damage26": return [{"op": "damage", "targets": "damage_targets"}]
		855: return [{"op": "gimpy26", "targets": "gimpy26"}]
		859: return [{"op": "pink_egg26", "targets": "pink_eggs26"}]
		861:
			if context == "book_damage26":
				return [{"op": "auto_roll"}, {"op": "book_damage26"}]
			return [{"op": "book_loot26", "targets": "other_players"}]
		863: return [{"op": "sibling26", "targets": "nonactive26"}]
		869: return [{"op": "source_counter20", "amount": 1}] if context == "craft_store26" else [{"op": "treasure"}]
		871:
			match context:
				"turn_end": return [{"op": "loot"}, {"op": "discard_loot", "targets": "own_hand"}]
				"monster_death": return [{"op": "loot"}]
			return [{"op": "extra_loot"}]
		873:
			if context == "ibs_cancel26":
				return [{"op": "cancel_selected", "targets": "cancel_ibs26"}]
			return [{"op": "ibs_small26", "targets": "ibs_modes26"}]
		875: return [{"op": "temporary_monster_dc", "targets": "monsters", "amount": -1}]
		877: return [{"op": "self_health"}]
		879:
			match context:
				"blood_at26": return [{"op": "blood_at26", "targets": "monsters"}]
				"blood_damage26": return [{"op": "blood_damage26", "targets": "blood_targets26", "optional": true}]
			return [{"op": "source_counter20", "amount": 1}]
		881: return [{"op": "flip26"}]
		882: return [{"op": "capricious26", "targets": "capricious_modes26"}]
		883: return [{"op": "glitch_copy26", "targets": "glitch_shop26"}, {"op": "glitch_recharge26"}]
		885: return [{"op": "soulbond26", "targets": "other_players"}]
	return []
