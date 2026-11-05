extends RefCounted
## Пакет06:20полных текстов пилюль/рун, сверенных по изображениям04.11.
const IDS := [477, 478, 479, 495, 496, 520, 521, 551, 565, 578, 579, 580, 581, 584, 648, 672, 673, 674, 529, 530]

static func op(name: String, amount: int = 1) -> Dictionary:
	return {"op": name, "amount": amount}

static func choose(name: String, targets: String, amount: int = 1) -> Dictionary:
	return {"op": name, "targets": targets, "amount": amount}

static func plan(id: int) -> Array:
	match id:
		477: return [op("random_gift"), choose("gift_item", "gift_items")]
		495: return [choose("grant_eternal", "players")]
		496: return [choose("berkano_destroy", "all_destroyable")]
		565: return [choose("peek_deck", "decks", 4), op("order_peek")]
		578: return [choose("reroll_item", "all_destroyable")]
		648: return [choose("dagaz_mode", "dagaz_modes")]
		529: return [op("ace_diamonds")]
		530: return [choose("peek_deck", "monster_room_decks", 5), op("order_peek"), choose("hagalaz_discard", "hagalaz_targets")]
		521:
			var steps: Array = []
			for i in 3:
				steps.append_array([op("start_roll"), op("auto_roll"), op("rune_result")])
			return steps
	return [op("auto_roll"), op("rune_result")]
