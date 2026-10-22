extends SceneTree
## Автотесты Gloom. Запуск: godot --headless --script res://tests/test_gloom.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_data()
	test_setup()
	test_scores()
	test_plays()
	test_expansions()
	test_random_games()
	print("Gloom — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int = 3, seed_value: int = 11, sets: Array = ["base"]) -> GLRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := GLRules.new()
	r.new_game(players, seed_value, sets)
	return r


var DECK := 88


func count(t: String, set_name: String = "base") -> int:
	var k := 0
	for c in GLData.CARDS:
		if c["t"] == t and c["set"] == set_name:
			k += 1
	return k


func total_cards(r: GLRules) -> int:
	var k: int = r.deck.size() + r.discard.size() + r.removed.size()
	for h in r.hands:
		k += h.size()
	for ch in r.chars:
		k += ch["stack"].size()
	if not r.react.is_empty():
		k += 1
	return k


func mine(r: GLRules, s: int) -> Array:
	var out := []
	for c in r.chars.size():
		if r.owner(c) == s and r.alive(c):
			out.append(c)
	return out


func find_card(pred: Callable) -> int:
	for i in GLData.CARDS.size():
		if pred.call(GLData.CARDS[i]):
			return i
	return -1


func test_data() -> void:
	check(count("M", "ug") == 26 and count("D", "ug") == 8 and count("E", "ug") == 6, "«Незваные гости»: 40 карт")
	check(count("M", "ud") == 36 and count("D", "ud") == 5 and count("E", "ud") == 7, "«Неспокойные мертвецы»: 48 карт")
	check(GLData.CARDS.size() == 264 and GLData.GUESTS.size() == 19 and GLData.STORIES.size() == 11, "264 карты, 19 гостей, 11 историй")
	check(count("M") == 57 and count("E") == 11 and count("D") == 20, "88 карт: 57 модификаторов, 11 событий, 20 смертей")
	check(GLData.CHARS.size() == 40, "40 персонажей")
	for f in 4:
		check(GLData.CHARS.filter(func(c): return c["family"] == f).size() == 5, "в семье %d — 5 персонажей" % f)
	check(GLData.card_name(GLData.SECOND_CHANCE) == "Второй шанс" and GLData.card_name(GLData.CANCEL_EVENT) == "Напустить туману", "ответные карты на месте")


func test_setup() -> void:
	var r := make(3)
	check(r.phase == "play" and r.chars.size() == 15, "трое — сразу игра, по 5 персонажей")
	check(r.hands.all(func(h): return h.size() == 5), "по 5 карт в руке")
	check(total_cards(r) == DECK, "все карты на месте")
	var r4 := make(4)
	check(r4.phase == "trim" and r4.trim_left.size() == 4, "четверо — сначала откладывают персонажа")
	r4.trim(0, mine(r4, 0)[0])
	check(not r4.trim(0, mine(r4, 0)[0]), "откладывают одного")
	r4.auto_trim()
	check(r4.phase == "play" and mine(r4, 0).size() == 4 and mine(r4, 3).size() == 4, "после — по 4 персонажа")
	var r5 := make(5)
	r5.auto_trim()
	check(r5.phase == "play" and mine(r5, 4).size() == 4, "пятый играет сборной семьёй из отложенных")


func test_scores() -> void:
	var r := make(2)
	var c: int = mine(r, 0)[0]
	var picnic := find_card(func(d): return d["name"] == "Устроил пикник в парке")  # +10 / +5
	var ghosts := find_card(func(d): return d["name"] == "Встретил привидений")  # −10 / — / −20
	r.chars[c]["stack"] = [picnic]
	check(r.worth(c) == 15 and r.icons(c) == ["goblet"], "пикник: +15 и кубок")
	r.chars[c]["stack"] = [picnic, ghosts]
	check(r.worth(c) == -10 + 5 - 20 and r.icons(c) == ["skull"], "сверху привидения: −25, видна середина пикника")
	var bears := find_card(func(d): return d["name"] == "Съеден медведями")
	var bees := find_card(func(d): return d["name"] == "Покусан пчёлами")  # зверь
	r.chars[c]["stack"] = [bees, bears]
	r.chars[c]["dead"] = true
	check(r.final_worth(c) == -15 - 10, "медведи: −10 за зверя")
	var calm := find_card(func(d): return d["name"] == "Умер без забот")
	r.chars[c]["stack"] = [bees, calm]
	check(r.final_worth(c) == 0, "«Умер без забот» закрывает все очки")


func test_expansions() -> void:
	DECK = 176
	var r := make(3, 21, ["base", "ug", "ud"])
	var guests := r.chars.filter(func(ch): return ch["kind"] == "guest")
	check(guests.size() == 2 and guests.all(func(g): return g["owner"] == -1), "2 гостя без хозяина в центре")
	check(r.stories.size() == 2, "2 истории в центре")
	check(total_cards(r) == 176, "колода с дополнениями — 176 карт")
	# нежить: модификатор на мёртвого снимает смерть, персонаж приносит очки
	var s := r.current
	var c: int = mine(r, s)[0]
	var bees := find_card(func(d): return d["name"] == "Покусан пчёлами")
	var bears := find_card(func(d): return d["name"] == "Съеден медведями")
	var ghoul := find_card(func(d): return d["name"] == "Предпочёл стать гулем")
	r.chars[c]["stack"] = [bees, bears]
	r.chars[c]["dead"] = true
	_put_in_hand(r, s, ghoul)
	r.chars[c]["stack"] = [bees, bears]
	check(r.play(s, ghoul, c) and r.is_undead(c) and r.alive(c) and r.scores(c), "нежить: и жив, и приносит очки")
	# гость следует за смертью
	var g := -1
	for i in r.chars.size():
		if r.chars[i]["kind"] == "guest":
			g = i
	r.chars[g]["id"] = 1  # Несчастный Холмс — следует за смертью
	var o := (s + 1) % 3
	var victim: int = mine(r, o)[0]
	r.chars[victim]["stack"] = [bees]
	r.end_turn(s)
	while r.phase == "prompt":
		r.auto_choose()
	var cur := r.current
	_put_in_hand(r, cur, bears)
	r.plays_used = 0
	r.play(cur, bears, victim)
	if r.phase == "react":
		r.finish_react()
	check(r.chars[victim]["dead"] and r.owner(g) == o, "гость переехал в семью убитого")
	# история
	var st: int = r.stories[0]["id"]
	var req: String = GLData.STORIES[st]["req"][0]
	var with_icon := find_card(func(d): return d["t"] == "M" and req in d["icons"] and d["set"] == "base")
	var mine_now: Array = mine(r, r.current)
	if with_icon >= 0 and mine_now.size() >= 2:
		for h in r.hands:
			h.erase(with_icon)
		r.deck.erase(with_icon)
		r.discard.erase(with_icon)
		for ch in r.chars:
			ch["stack"].erase(with_icon)
		r.chars[mine_now[0]]["stack"].append(with_icon)
		var other := find_card(func(d): return d["t"] == "M" and req in d["icons"] and d["set"] != "base")
		if other < 0:
			other = with_icon
		r.chars[mine_now[1]]["stack"].append(with_icon if other == with_icon else other)
		check(r.can_claim(r.current, st), "история: 2 персонажа с иконкой — можно забрать")
	DECK = 88


func test_plays() -> void:
	var r := make(2, 5)
	var s := r.current
	var c: int = mine(r, s)[0]
	var bees := find_card(func(d): return d["name"] == "Покусан пчёлами")
	var bears := find_card(func(d): return d["name"] == "Съеден медведями")
	_put_in_hand(r, s, bees)
	_put_in_hand(r, s, bears)
	check(not r.play(s, bears, c), "смерть только на отрицательного")
	check(r.play(s, bees, c) and r.worth(c) == -15, "модификатор лёг")
	check(r.plays_left == 1 and not r.ud_allowed(), "смерть — только первым действием")
	check(not r.play(s, bears, c), "вторым действием смерть нельзя")
	r.end_turn(s)
	check(r.current != s and r.hands[s].size() >= r.hand_limit(s), "добор до лимита и переход хода")
	var o := r.current
	_put_in_hand(r, o, bears)
	check(r.play(o, bears, c) and r.phase == "react", "смерть на чужого — окно ответа")
	r.finish_react()
	check(r.chars[c]["dead"] and r.phase == "play", "персонаж умер")
	check(total_cards(r) == DECK, "карты не теряются")


func _put_in_hand(r: GLRules, s: int, card: int) -> void:
	for h in r.hands:
		h.erase(card)
	r.deck.erase(card)
	r.discard.erase(card)
	for ch in r.chars:
		ch["stack"].erase(card)
	r.hands[s].append(card)


## Случайный, но «разумный» игрок: минусы — себе, плюсы — соперникам, смерти — своим.
func _legal(r: GLRules) -> Array:
	var s := r.current
	var out := []
	for card in r.hands[s]:
		var cd: Dictionary = GLData.CARDS[card]
		for t in range(-1, r.chars.size()):
			var extras := [{}]
			if cd["t"] == "E":
				for w in r.hands[s]:
					extras.append({"with": w})
				for t2 in r.chars.size():
					extras.append({"t2": t2})
				for pick in r.discard:
					extras.append({"pick": pick})
			if cd["t"] == "E":
				for st in r.stories:
					extras.append({"st": st["id"]})
			for ex in extras:
				if r.can_play(s, card, t, ex):
					var good := 1
					if cd["t"] == "M":
						var sum := 0
						for p in cd["pts"]:
							sum += int(p) if p != null else 0
						good = 3 if (sum < 0) == (r.owner(t) == s) else 0
					elif cd["t"] == "D":
						good = 6 if r.owner(t) == s else 0
					out.append([card, t, ex, good])
	return out


func test_random_games() -> void:
	var ended := 0
	for g in 100:
		var n := 2 + g % 4
		var mode: Array = [["base"], ["base", "ug", "ud"], ["gm"], ["base", "ug", "ud", "gm"]][g / 25]
		DECK = 0
		for c in GLData.CARDS:
			if c["set"] in mode:
				DECK += 1
		var r := make(n, 1000 + g, mode)
		var steps := 0
		var ok := true
		while r.phase != "game_over" and steps < 6000:
			steps += 1
			match r.phase:
				"trim":
					r.auto_trim()
				"draft":
					r.auto_draft()
				"prompt":
					r.auto_choose()
				"react":
					var e: Array = r.react["eligible"]
					var acted := false
					for s in e:
						if not s in r.react["passed"]:
							r.respond(s, r.rng.randf() < 0.3)
							acted = true
							break
					if not acted:
						r.finish_react()
				"play":
					for st in r.stories:
						if r.can_claim(r.current, int(st["id"])) and r.rng.randf() < 0.5:
							r.claim(r.current, int(st["id"]))
					if r.phase != "play":
						continue
					var moves := _legal(r)
					for c in r.hands[r.current]:
						if r._fx0(c) == "dramatic" and r.can_play(r.current, c, -1, {"mode": "free"}):
							moves.append([c, -1, {"mode": ["free", "chaos"][r.rng.randi() % 2]}, 1])
					moves = moves.filter(func(m): return m[3] > 0)
					if moves.is_empty() or r.rng.randf() < 0.08:
						if r.rng.randf() < 0.1 and r.plays_left > 0:
							r.discard_hand(r.current)
						else:
							r.end_turn(r.current)
					else:
						var m: Array = moves[r.rng.randi_range(0, moves.size() - 1)]
						if not r.play(r.current, m[0], m[1], m[2]):
							ok = false
							print("  незаконный ход: ", GLData.card_name(m[0]), " → ", m[1], " ", m[2])
			if total_cards(r) != DECK:
				ok = false
				print("карты: %d, фаза %s, шаг %d" % [total_cards(r), r.phase, steps])
				var all := r.deck + r.discard + r.removed
				for h in r.hands:
					all += h
				for ch in r.chars:
					all += ch["stack"]
				for c in all:
					if all.count(c) > 1:
						print("  дубль: ", c, " ", GLData.card_name(c))
						break
				print("  ", r.log.slice(-4).map(func(e): return e["text"]))
				break
		if steps >= 6000:
			print("  не закончилась: фаза ", r.phase, " ", r.log.slice(-3).map(func(e): return e["text"]))
		check(ok, "партия %d (%d игроков): карты целы, ходы законны" % [g, n])
		if r.phase == "game_over":
			ended += 1
			check(r.winners.size() >= 1 and r.finals.size() == n, "партия %d: есть победитель" % g)
	DECK = 88
	check(ended == 100, "все случайные партии закончились (%d из 100)" % ended)
