## Бот «Большой бродилки»: один шаг за вызов (бросок, ответ на prompt, карта Лавки или конец хода).
class_name BRBot
extends RefCounted

## Вес клетки для выбора кубика.
const CELL_VALUE := {
	"chest_good": 3, "shop": 2, "bike": 4, "lucky": 4, "luck_die": 3, "mine": 3, "tadam": 1, "tribute": 2,
	"chest_bad": -3, "nooo": -3, "tornado": -1, "gum": 2, "finish": 5,
}


## Сделать ход за место seat, если от него что-то ждут. true — что-то сделал.
static func act(r: BRRules, seat: int) -> bool:
	if r.phase == "game_over":
		return false
	if not r.prompt.is_empty():
		return int(r.prompt.seat) == seat and r.answer(seat, choose(r, seat))
	if seat != r.turn:
		return false
	if r.phase == "roll":
		return r.roll(seat)
	if r.phase == "free":
		for i in r.shop[seat].size():
			if r.can_use(seat, i):
				var id: String = BRData.SHOP[r.shop[seat][i]].id
				var tg := r.use_targets(seat, id)
				if id == "hook" or id == "rocket" or r.coins[seat] >= 6:
					return r.use_card(seat, i, tg[tg.size() - 1] if not tg.is_empty() else -1)
		return r.end_turn(seat)
	return false


static func choose(r: BRRules, seat: int) -> int:
	var p: Dictionary = r.prompt
	var opts: Array = p.options
	var d: Dictionary = p.get("data", {})
	match p.kind:
		"boost":
			return opts.size() - 1 if r.coins[seat] >= 15 else (1 if r.coins[seat] >= 8 else 0)
		"die":
			var best := 0
			var best_v := -99
			for i in opts.size():
				var c := BRBoard.cell(r.pos[seat] + int(opts[i]))
				var v: int = CELL_VALUE.get(c.t, 0) * 10 + int(opts[i])
				if v > best_v:
					best_v = v; best = i
			return best
		"buy":
			return 1 if opts.size() > 1 and (d.get("free", false) or r.coins[seat] >= 8) else 0
		"tornado":
			return 1 if d.get("free", false) or r.coins[seat] >= 20 else 0
		"pay":
			return mini(opts.size() - 1, 3)
		"yesno":
			return 1 if d.get("fx", "") == "pay_extra_turn" else 0
		"target", "duel_target", "steal", "burn":
			var seats: Array = d.get("seats", [])
			var best := 0
			for i in seats.size():
				if r.pos[seats[i]] > r.pos[seats[best]]:
					best = i
			if d.get("fx", "") in ["give_to", "target_gain", "target_double"]:
				best = 0
				for i in seats.size():
					if r.pos[seats[i]] < r.pos[seats[best]]:
						best = i
			return best
		"trap":
			# на 3–6 клеток перед лидером среди соперников
			var cells: Array = d.get("cells", [])
			var lead := -1
			for o in r.others(seat):
				if lead < 0 or r.pos[o] > r.pos[lead]:
					lead = o
			if lead >= 0:
				var want: int = r.pos[lead] + 3 + r.rng.randi_range(0, 3)
				var k := cells.find(want)
				if k >= 0:
					return k + 1
			return 0
		"duel_prize":
			return 0 if r.coins[int(d.loser)] >= 10 else 1
	return 0
