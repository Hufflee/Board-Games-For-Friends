extends RefCounted
## Полные тексты287–326: события монстров и действия после напечатанной награды.
const IDS := [287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326]
static func plan(id: int, context: String) -> Array:
	match id:
		913:
			return [{"op": "rider_death16"}]
		914:
			return [{"op": "beast_rolls16"}]
		287, 308, 319:
			if context == "post_reward16":
				return [{"op": "coins", "amount": 5, "targets": "other_players"}]
			return [{"op": "damage", "targets": "other_players" if id == 308 else "players"}]
		288, 309:
			return [{"op": "random_nonactive16", "amount": 2}]
		289:
			return [{"op": "bottom_source16"}]
		290:
			return [{"op": "kill_other16", "targets": "other_monsters16"}, {"op": "kill_player16", "targets": "living_players16"}, {"op": "expand16", "amount": 2}]
		291:
			return [{"op": "random_damage15", "amount": 1}]
		292:
			return [{"op": "auto_roll"}, {"op": "gut_result16"}]
		293:
			return [{"op": "auto_roll"}, {"op": "soul_damage16"}]
		295:
			return [{"op": "kill_others16"}] if context == "monster_death" else [{"op": "kill_players16"}]
		296:
			return [{"op": "auto_roll"}, {"op": "portal_result16"}]
		298:
			return [{"op": "expand16"}]
		300:
			return [{"op": "spider_split_prepare16"}]
		301:
			return [{"op": "auto_roll"}, {"op": "expand_roll16"}]
		303:
			return [{"op": "expand16"}, {"op": "required_attack16"}]
		305:
			return [{"op": "hurt_other_players16"}]
		306:
			return [{"op": "rider16"}] if context == "monster_death" else [{"op": "discard_others16"}]
		307:
			return [{"op": "rotate_hands15", "direction": 1}]
		311:
			return [{"op": "expand16", "amount": 2}]
		312:
			return [{"op": "last_alive16"}]
		313:
			return [{"op": "kill_three_prepare16"}] if context == "monster_death" else [{"op": "discard_victim16"}] if context == "discard16" else [{"op": "discard_others_hands16"}]
		315:
			return [{"op": "treasure", "targets": "other_players"}]
		316:
			return [{"op": "recharge_owner16", "targets": "other_players"}]
		317, 321, 322:
			if context == "damaged_player16":
				return [{"op": "discard_victim16"}]
			return [{"op": "loot", "targets": "other_players", "amount": 3 if id == 317 else 1 if id == 321 else 2}]
		318:
			return [{"op": "coins", "targets": "other_players", "amount": 10}]
		320:
			return [{"op": "give_soul16", "targets": "other_players"}]
		323:
			return [{"op": "roll_gift16", "targets": "other_players"}, {"op": "auto_roll"}, {"op": "coins_result16"}]
		324:
			return [{"op": "whip_prepare16"}]
		325:
			return [{"op": "curse_slot16"}] if context == "monster_death" else [{"op": "loot"}]
		326:
			return [{"op": "random_damage15", "amount": 3}]
	return []
