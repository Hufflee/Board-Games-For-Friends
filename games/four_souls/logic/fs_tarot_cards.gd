extends RefCounted
## Таро621–640: планы по полным изображениям BaseV2, сверенным04.11.
const IDS := [621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640]

static func op(name: String, amount: int = 1) -> Dictionary:
	return {"op": name, "amount": amount}

static func choice(name: String, targets: String) -> Dictionary:
	return {"op": name, "targets": targets, "amount": 1}

static func plan(id: int) -> Array:
	match id:
		621: return [choice("set_selected_roll", "set_roll_faces")]
		622: return [choice("priestess_target", "damage_targets"), op("auto_roll"), op("priestess_damage")]
		623: return [choice("empress", "players")]
		624: return [{"op": "peek_deck", "deck": "monster", "amount": 5}, choice("peek_keep_top", "peek_cards")]
		625: return [{"op": "peek_deck", "deck": "treasure", "amount": 5}, choice("peek_keep_top", "peek_cards")]
		626: return [op("fool_end")]
		627: return [choice("next_hit_shield", "damage_targets")]
		628: return [choice("lovers", "players")]
		629: return [choice("chariot", "players")]
		630: return [choice("justice", "players")]
		631: return [op("auto_roll"), op("wheel_result")]
		632: return [choice("strength", "players")]
		633: return [op("peek_decks"), choice("peek_bottom", "peek_groups"), op("loot", 2)]
		634: return [choice("kill_player", "living_players")]
		635: return [choice("temperance", "temperance_options")]
		636: return [op("self_underdeck"), op("extra_turn")]
		637: return [choice("devil_destroy", "own_destroy")]
		638: return [op("auto_roll"), op("tower_result")]
		639: return [op("treasure")]
		640: return [{"op": "peek_deck", "deck": "loot", "amount": 5}, choice("peek_keep_top", "peek_cards")]
	return []
