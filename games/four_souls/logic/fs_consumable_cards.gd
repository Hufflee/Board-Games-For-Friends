extends RefCounted
## Пакет07: двадцать одноразовых карт по полным изображениям, прочитанным04.11.
const IDS := [469, 472, 504, 513, 519, 533, 543, 545, 547, 548, 552, 553, 568, 569, 641, 642, 679, 685, 686, 688]

static func plan(id: int) -> Array:
	match id:
		469: return [{"op": "bean_return", "targets": "pending_loot"}]
		472: return [{"op": "auto_roll"}, {"op": "era_walk"}]
		504: return [{"op": "key_mode", "targets": "key_modes"}]
		513, 548: return [{"op": "loot", "amount": 3}]
		519: return [{"op": "note_monster", "targets": "discarded_monsters", "optional": true, "remaining": 3}]
		533: return [{"op": "emergency_contact"}]
		543: return [{"op": "joker_player", "targets": "players"}, {"op": "joker_take", "targets": "joker_hand", "optional": true}]
		545: return [{"op": "jera"}]
		547: return [{"op": "credit_card"}]
		553: return [{"op": "holy_card", "targets": "players"}]
		568: return [{"op": "gold_key"}]
		569: return [{"op": "jail_card"}]
		641: return [{"op": "judgement_player", "targets": "most_souls"}, {"op": "judgement_soul", "targets": "chosen_souls"}]
		642: return [{"op": "peek_hands"}, {"op": "read_peek"}, {"op": "loot", "amount": 2}]
		679: return [{"op": "auto_roll"}, {"op": "blank_rune"}]
		685, 686: return [{"op": "prevent_damage", "targets": "players", "amount": 1}]
		688: return [{"op": "ehwaz"}]
	return []
