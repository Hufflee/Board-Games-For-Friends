extends SceneTree
## Автотесты «Это не шляпа!». Запуск: godot --headless --script res://tests/test_not_a_hat.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_flow()
	test_random_games()
	print("Это не шляпа — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int = 4, each: int = 1) -> NHRules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i})
	var r := NHRules.new()
	r.new_game(players, each, 7)
	return r


func test_flow() -> void:
	var r := make()
	check(r.phase == "memorize", "сначала — запоминание")
	check(r.get_view(1)["hands"][0][0]["g"] >= 0, "в запоминании подарки видны")
	r.start_play()
	check(r.phase == "give" and r.from_shop, "первый подарок — из магазина")
	check(r.get_view(1)["hands"][0][0]["g"] == -1, "потом подарки рубашкой вверх")
	var g := r.giver
	var recv := r.receiver
	check(recv == posmod(g + int(r.card["dir"]), 4), "получатель — по стрелке")
	check(not r.give(recv, 0), "дарит только даритель")
	var real: int = r.card["g"]
	check(r.give(g, real) and r.phase == "respond", "назвал подарок")
	var old_card: Dictionary = r.hands[recv][0]
	check(r.respond(recv, true), "принял")
	check(r.giver == recv and r.card == old_card and r.hands[recv].size() == 1, "дарит свой старый подарок, новый остаётся")
	var g2 := r.giver
	var lie := (int(r.card["g"]) + 1) % NHData.GIFTS.size()
	r.give(g2, lie)
	var recv2 := r.receiver
	check(r.respond(recv2, false) and r.phase == "reveal", "отказ — вскрытие")
	check(r.reveal["loser"] == g2 and r.penalties[g2].size() == 1, "соврал — штраф дарителю")
	r.advance()
	check(r.phase == "give" and r.giver == g2 and r.from_shop, "проигравший дарит новый подарок из магазина")
	r.give(r.giver, r.card["g"])
	var recv3 := r.receiver
	r.respond(recv3, false)
	check(r.reveal["loser"] == recv3, "правда — штраф отказавшемуся")


func test_random_games() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var over := 0
	for k in 40:
		var r := make(rng.randi_range(2, 8), 1 + k % 2)
		r.start_play()
		var steps := 0
		while r.phase != "game_over" and steps < 5000:
			steps += 1
			match r.phase:
				"give":
					r.give(r.giver, r.card["g"] if rng.randf() < 0.7 else rng.randi_range(0, NHData.GIFTS.size() - 1))
				"respond":
					r.respond(r.receiver, rng.randf() < 0.7)
				"reveal":
					r.advance()
			var total := 0
			for h in r.hands:
				total += h.size()
				if h.size() < 1:
					check(false, "у игрока не осталось подарков")
			check(total == r.players.size() * r.start_cards + (0 if r.phase != "respond" and r.phase != "give" else 0), "число подарков на столе постоянно") if steps % 50 == 0 else null
		if r.phase == "game_over":
			over += 1
			var mx := 0
			for p in r.penalties:
				mx = maxi(mx, p.size())
			check(mx == NHRules.MAX_PENALTY, "конец — у кого-то 3 штрафа")
			check(not r.winners().is_empty(), "есть победитель")
	check(over == 40, "все партии доиграны")
