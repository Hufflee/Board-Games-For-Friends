class_name RSBRules
extends RefCounted
## Движок «На старт, ставки!». Дом — программа: хост вызывает roll() по таймеру, игроки делают ставки
## в реальном времени (кто первый — того ячейка).
##
## Фазы: start (обратный отсчёт) → race (бросаем кубики, ставки) → results → vip (драфт после забегов 1–3)
##       → start … → game_over

var players: Array = []  # [{name, ...}]
var money: Array = []
var tokens: Array = []  # seat -> [{v, bonus: ""|"black"|"white", used}]
var vips: Array = []  # seat -> оставленные VIP-карты
var vip_hand: Array = []  # seat -> 2 карты на выбор (фаза vip)
var vip_deck: Array = []
var vip_discard: Array = []
var prop_deck: Array = []
var exotic_deck: Array = []
var props: Array = []  # 5 пари текущего забега (индексы RSBData.PROPS)
var exotics: Array = []  # открытые экзотические финиши (индексы RSBData.EXOTICS)

var race_no := 0
var phase := "setup"
var pos: Array = []
var prev_horse := -1
var pair_used := false
var last_roll := {}
var rolls: Array = []  # последние броски [{d1, d2, sum, horse, bonus}]
var roll_count := 0
var crossed: Array = []  # лошади в порядке пересечения красной линии
var no_more_bets := false
var bets := {}  # spot -> [{seat, tok, v, bonus, early}]
var piggy_used: Array = []
var late_used: Array = []
var snake_gain: Array = []  # +$ за 2 и 12 в этом забеге
var places := {}
var result := {}
var winners: Array = []
var rng := RandomNumberGenerator.new()


func new_game(player_list: Array, seed_value: int = 0) -> void:
	players = player_list.duplicate(true)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := players.size()
	money = []
	tokens = []
	vips = []
	vip_hand = []
	for s in n:
		money.append(0)
		var values := [2, 3, 3, 4, 5] if n <= 6 else [2, 3, 4, 5]
		var list := []
		for v in values:
			list.append({"v": v, "bonus": "", "used": false})
		tokens.append(list)
		vips.append([])
		vip_hand.append([])
	vip_deck = range(RSBData.VIP.size())
	_shuffle(vip_deck)
	vip_discard = []
	prop_deck = range(RSBData.PROPS.size())
	_shuffle(prop_deck)
	exotic_deck = range(RSBData.EXOTICS.size())
	_shuffle(exotic_deck)
	exotics = []
	race_no = 0
	winners = []
	_new_race()


func _new_race() -> void:
	race_no += 1
	pos = []
	pos.resize(9)
	pos.fill(0)
	prev_horse = -1
	pair_used = false
	last_roll = {}
	rolls = []
	roll_count = 0
	crossed = []
	no_more_bets = false
	bets = {}
	places = {}
	result = {}
	props = []
	for i in 5:
		if prop_deck.is_empty():
			prop_deck = range(RSBData.PROPS.size())
			_shuffle(prop_deck)
		props.append(prop_deck.pop_back())
	if not exotic_deck.is_empty():
		exotics.append(exotic_deck.pop_back())
	var n := players.size()
	piggy_used = []
	late_used = []
	snake_gain = []
	for s in n:
		piggy_used.append(false)
		late_used.append(false)
		snake_gain.append(0)
		for t in tokens[s]:
			t["used"] = false
	phase = "start"


func start_race() -> bool:
	if phase != "start":
		return false
	phase = "race"
	return true


func has_vip(seat: int, kind: String) -> Array:
	return vips[seat].filter(func(i): return RSBData.VIP[i]["kind"] == kind)


# --- Забег --------------------------------------------------------------------------

## Бросок кубиков Домом. d1, d2 > 0 — заданный результат (для тестов).
func roll(d1: int = 0, d2: int = 0) -> bool:
	if phase != "race":
		return false
	if d1 <= 0:
		d1 = rng.randi_range(1, 6)
		d2 = rng.randi_range(1, 6)
	var sum := d1 + d2
	var h := RSBData.horse_for_roll(sum)
	var move := 1
	var bonus := false
	if h == prev_horse and not pair_used:
		move += RSBData.BONUS[h]
		bonus = RSBData.BONUS[h] > 0
		pair_used = true
	else:
		pair_used = false
	prev_horse = h
	var before: int = pos[h]
	pos[h] = mini(RSBData.FINISH, before + move)
	roll_count += 1
	var crossed_now := false
	if before <= RSBData.RED_LINE and pos[h] > RSBData.RED_LINE and not crossed.has(h):
		crossed.append(h)
		crossed_now = true
	var closed_now := false
	if crossed.size() >= 3 and not no_more_bets:
		no_more_bets = true
		closed_now = true
	if sum == 2 or sum == 12:
		for s in players.size():
			var k := has_vip(s, "snake").size()
			if k > 0:
				money[s] += k
				snake_gain[s] += k
	last_roll = {"d1": d1, "d2": d2, "sum": sum, "horse": h, "move": move, "bonus": bonus, "crossed": crossed_now, "closed": closed_now, "n": roll_count}
	rolls.append(last_roll)
	if rolls.size() > 14:
		rolls.pop_front()
	if pos[h] >= RSBData.FINISH:
		no_more_bets = true
		_resolve()
	return true


# --- Ставки -------------------------------------------------------------------------

func spot_valid(spot: String) -> bool:
	return not spot_info(spot).is_empty()


## {mult, loss, title} ячейки или {} — нет такой ячейки в этом забеге.
func spot_info(spot: String) -> Dictionary:
	var parts := spot.split("_")
	match parts[0]:
		"s", "p", "w":
			if parts.size() != 3:
				return {}
			var h := int(parts[1])
			var k := int(parts[2])
			var table: Array = {"s": RSBData.SHOW, "p": RSBData.PLACE, "w": RSBData.WIN}[parts[0]]
			if h < 0 or h > 8 or k < 0 or k >= table[h].size():
				return {}
			var name: String = {"s": "в тройке", "p": "в двойке", "w": "победит"}[parts[0]]
			return {"mult": table[h][k][0], "loss": table[h][k][1], "title": "%s — %s" % [RSBData.HORSES[h], name]}
		"color", "seven":
			if not RSBData.COLOR_BETS.has(spot):
				return {}
			var c: Dictionary = RSBData.COLOR_BETS[spot]
			return {"mult": c["mult"], "loss": c["loss"], "title": c["name"]}
		"prop":
			var i := int(parts[1])
			if i < 0 or i >= props.size():
				return {}
			var pr: Dictionary = RSBData.PROPS[props[i]]
			return {"mult": pr["mult"], "loss": pr["loss"], "title": prop_title(pr)}
		"ex":
			if parts.size() != 3:
				return {}
			var j := int(parts[1])
			var k := int(parts[2])
			if j < 0 or j >= exotics.size() or k < 0 or k > 2:
				return {}
			var ex: Dictionary = RSBData.EXOTICS[exotics[j]]
			return {"mult": ex["mult"], "loss": ex["loss"], "title": ex["name"]}
	return {}


static func prop_title(pr: Dictionary) -> String:
	if pr.has("group"):
		return "%s обгонит всех: %s" % [RSBData.HORSES[pr["a"]], RSBData.COLOR_NAMES[pr["group"]]]
	return "%s обгонит %s" % [RSBData.HORSES[pr["a"]], RSBData.HORSES[pr["b"]]]


## Почему нельзя поставить ("" — можно).
func can_place(seat: int, tok: int, spot: String) -> String:
	if phase != "race":
		return "Ставки принимаются только во время забега."
	if tok < 0 or tok >= tokens[seat].size() or tokens[seat][tok]["used"]:
		return "Этот жетон уже на поле."
	if not spot_valid(spot):
		return "Нет такой ячейки."
	if no_more_bets and (has_vip(seat, "late").is_empty() or late_used[seat]):
		return "Ставок больше нет!"
	if spot.begins_with("ex_"):
		var card := spot.substr(0, spot.rfind("_"))
		for k in 3:
			for b in bets.get("%s_%d" % [card, k], []):
				if b["seat"] == seat:
					return "На одну карту экзотики — только один ваш жетон."
	var here: Array = bets.get(spot, [])
	if here.is_empty():
		return ""
	if here.size() == 1 and here[0]["seat"] != seat and _piggy_ok(seat, int(tokens[seat][tok]["v"])):
		return ""
	return "Ячейка занята."


func _piggy_ok(seat: int, v: int) -> bool:
	if piggy_used[seat]:
		return false
	for i in has_vip(seat, "piggy"):
		if RSBData.VIP[i]["value"] == v:
			return true
	return false


func place(seat: int, tok: int, spot: String) -> bool:
	if can_place(seat, tok, spot) != "":
		return false
	var t: Dictionary = tokens[seat][tok]
	if not bets.get(spot, []).is_empty():
		piggy_used[seat] = true
	if no_more_bets:
		late_used[seat] = true
	t["used"] = true
	if not bets.has(spot):
		bets[spot] = []
	bets[spot].append({"seat": seat, "tok": tok, "v": t["v"], "bonus": t["bonus"], "early": crossed.is_empty()})
	return true


# --- Итоги забега -------------------------------------------------------------------

## Места: first (одна лошадь), second, third (с учётом ничьих).
static func compute_places(p: Array) -> Dictionary:
	var first := p.find(RSBData.FINISH)
	var rest := []
	for h in 9:
		if h != first:
			rest.append(h)
	var second_pos := -1
	for h in rest:
		second_pos = maxi(second_pos, p[h])
	var second := rest.filter(func(h): return p[h] == second_pos)
	var third := []
	if second.size() >= 2:
		third = second.duplicate()
	else:
		var others := rest.filter(func(h): return p[h] != second_pos)
		var third_pos := -1
		for h in others:
			third_pos = maxi(third_pos, p[h])
		third = others.filter(func(h): return p[h] == third_pos)
	return {"first": first, "second": second, "third": third}


func spot_wins(spot: String) -> bool:
	var parts := spot.split("_")
	var first: int = places["first"]
	match parts[0]:
		"s":
			var h := int(parts[1])
			return h == first or places["second"].has(h) or places["third"].has(h)
		"p":
			var h := int(parts[1])
			return h == first or places["second"].has(h)
		"w":
			return int(parts[1]) == first
		"color":
			return RSBData.HORSE_COLOR[first] == parts[1]
		"seven":
			var ahead := 0
			for h in 9:
				if pos[h] > pos[4]:
					ahead += 1
			return ahead >= 4
		"prop":
			var pr: Dictionary = RSBData.PROPS[props[int(parts[1])]]
			var a: int = pr["a"]
			if pr.has("group"):
				for h in 9:
					if h != a and RSBData.HORSE_COLOR[h] == pr["group"] and pos[h] >= pos[a]:
						return false
				return true
			return pos[a] > pos[pr["b"]]
		"ex":
			return exotic_wins(RSBData.EXOTICS[exotics[int(parts[1])]]["id"])
	return false


func exotic_wins(id: String) -> bool:
	var second_pos: int = pos[places["second"][0]]
	var third_pos: int = pos[places["third"][0]] if not places["third"].is_empty() else 0
	match id:
		"tight":
			return pos.min() >= 6
		"late":
			return pos.filter(func(x): return x <= 3).size() >= 2
		"photo":
			return RSBData.FINISH - third_pos <= 3
		"nose":
			return second_pos == RSBData.FINISH - 1
		"blowout":
			return RSBData.FINISH - second_pos > 5
	return false


func _resolve() -> void:
	places = compute_places(pos)
	var n := players.size()
	var lines := []
	for s in n:
		lines.append([])
	var won := []
	var lost := []
	won.resize(n)
	won.fill(0)
	lost.resize(n)
	lost.fill(0)
	var insured := []
	insured.resize(n)
	insured.fill(false)
	var spots := bets.keys()
	spots.sort()
	for spot in spots:
		var info := spot_info(spot)
		var ok := spot_wins(spot)
		for b in bets[spot]:
			var s: int = b["seat"]
			var v: int = b["v"]
			if ok:
				var gain: int = v * int(info["mult"])
				var extra := 2 * has_vip(s, "risky").size()
				if v == 5:
					extra += 5 * has_vip(s, "highroller").size()
				if b["early"]:
					extra += 2 * has_vip(s, "early").size()
				won[s] += gain + extra
				lines[s].append({"spot": spot, "title": info["title"], "v": v, "bonus": b["bonus"], "win": true, "delta": gain + extra})
			else:
				var loss: int = info["loss"]
				if b["bonus"] != "":
					var bl: int = RSBData.BONUS_TOKEN_LOSS[v]
					loss = 0 if bl < 0 else loss + bl
				loss += has_vip(s, "risky").size()
				if loss > 0 and not insured[s] and not has_vip(s, "insure").is_empty():
					insured[s] = true
					loss = 0
				lost[s] += loss
				lines[s].append({"spot": spot, "title": info["title"], "v": v, "bonus": b["bonus"], "win": false, "delta": -loss})
	var color: String = RSBData.HORSE_COLOR[places["first"]]
	for s in n:
		for i in has_vip(s, "fan"):
			if RSBData.VIP[i]["color"] == color:
				won[s] += int(RSBData.VIP[i]["value"])
		var before: int = money[s]
		money[s] += won[s]
		money[s] = maxi(0, money[s] - lost[s])
		lines[s].sort_custom(func(a, b): return a["delta"] > b["delta"])
		result[s] = {"won": won[s], "lost": lost[s], "before": before, "lines": lines[s], "snake": snake_gain[s]}
	var low: int = money.min()
	for s in n:
		if money[s] == low and not has_vip(s, "comeback").is_empty():
			money[s] += 6 * has_vip(s, "comeback").size()
			result[s]["comeback"] = true
	for s in n:
		result[s]["net"] = money[s] - int(result[s]["before"]) + snake_gain[s]
	phase = "results"


func advance() -> void:
	if phase != "results":
		return
	if race_no >= RSBData.RACES:
		var best: int = money.max()
		winners = []
		for s in players.size():
			if money[s] == best:
				winners.append(s)
		phase = "game_over"
		return
	for s in players.size():
		vip_hand[s] = []
		for k in 2:
			if vip_deck.is_empty():
				vip_deck = vip_discard.duplicate()
				vip_discard = []
				_shuffle(vip_deck)
			if not vip_deck.is_empty():
				vip_hand[s].append(vip_deck.pop_back())
	phase = "vip"


## Игрок оставляет одну из двух VIP-карт (i — индекс в руке).
func pick_vip(seat: int, i: int) -> bool:
	if phase != "vip" or i < 0 or i >= vip_hand[seat].size():
		return false
	var card: int = vip_hand[seat][i]
	for k in vip_hand[seat].size():
		if k != i:
			vip_discard.append(vip_hand[seat][k])
	vip_hand[seat] = []
	vips[seat].append(card)
	var v: Dictionary = RSBData.VIP[card]
	match v["kind"]:
		"bonus":
			tokens[seat].append({"v": v["value"], "bonus": v["color"], "used": false})
		"comp":
			money[seat] += RSBData.COMP_CHIPS[mini(vips[seat].size(), 3) - 1]
	if vip_hand.all(func(h): return h.is_empty()):
		_new_race()
	return true


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func get_view(seat: int, show_all: bool = false) -> Dictionary:
	var hands := []
	for s in players.size():
		hands.append(vip_hand[s].duplicate() if show_all or s == seat else vip_hand[s].map(func(_c): return -1))
	return {
		"you": seat,
		"players": players.duplicate(true),
		"money": money.duplicate(),
		"tokens": tokens.duplicate(true),
		"vips": vips.duplicate(true),
		"vip_hand": hands,
		"props": props.duplicate(),
		"exotics": exotics.duplicate(),
		"race_no": race_no,
		"phase": phase,
		"pos": pos.duplicate(),
		"last_roll": last_roll.duplicate(),
		"rolls": rolls.duplicate(true),
		"crossed": crossed.duplicate(),
		"no_more_bets": no_more_bets,
		"bets": bets.duplicate(true),
		"piggy_used": piggy_used.duplicate(),
		"late_used": late_used.duplicate(),
		"places": places.duplicate(true),
		"result": result.duplicate(true),
		"winners": winners.duplicate(),
		"hotseat": show_all,
	}


# --- Новый игрок посреди партии ------------------------------------------------------

## Перед забегом: новичок с $0 и обычным набором жетонов.
func can_add_player() -> bool:
	return phase == "start" and players.size() < 8


func add_player(p: Dictionary) -> bool:
	if not can_add_player():
		return false
	players.append(p.duplicate())
	money.append(0)
	var list := []
	for v in ([2, 3, 3, 4, 5] if players.size() <= 6 else [2, 3, 4, 5]):
		list.append({"v": v, "bonus": "", "used": false})
	tokens.append(list)
	vips.append([])
	vip_hand.append([])
	piggy_used.append(false)
	late_used.append(false)
	snake_gain.append(0)
	return true
