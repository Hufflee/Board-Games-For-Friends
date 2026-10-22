extends SceneTree
## Автотесты «Алольского атлета». Запуск: godot --headless --script res://tests/test_alola_athlete.gd

var failures := 0
var checks := 0


func _init() -> void:
	test_setup()
	test_tracks()
	test_random_games()
	print("Алольский атлет — проверок: %d, ошибок: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: " + msg)


func make(n: int, seed_value: int, bots: bool = true) -> AARules:
	var players := []
	for i in n:
		players.append({"name": "И%d" % i, "bot": bots})
	var r := AARules.new()
	r.new_game(players, seed_value)
	return r


func test_setup() -> void:
	check(AAData.RACERS.size() == 70, "70 гонщиков")
	var r := make(4, 3)
	check(r.phase == "draft" and r.line.size() == 8 and r.draft_seq.size() == 16, "драфт: 8 в ряд, 16 выборов")
	while r.phase == "draft":
		r.auto_draft()
	check(r.teams.all(func(t): return t.size() == 4), "у каждого по 4 гонщика")
	check(r.phase == "pick", "затем выбор на гонку")


func test_tracks() -> void:
	for t in AAData.TRACK_ORDER:
		var r := make(2, 5)
		r.track = t
		r._load_track()
		check(r.dist(-1) >= 15 and r.dist(-1) <= 31, "трасса %s: до финиша %d" % [t, r.dist(-1)])


func test_random_games() -> void:
	var done := 0
	for g in 80:
		var n := 2 + g % 5
		var r := make(n, 100 + g)
		var steps := 0
		while r.phase != "game_over" and steps < 20000:
			steps += 1
			match r.phase:
				"draft":
					r.auto_draft()
				"pick":
					for s in n:
						if r.picks[s] == "":
							r.auto_pick(s)
				"race":
					if not r.prompt.is_empty():
						r.auto_answer()
					elif r.stage == "roll":
						r.do_roll(r.current)
					elif not r.step():
						print("  застряли: этап ", r.stage)
						break
				"race_result":
					r.advance()
		if r.phase == "game_over":
			done += 1
		else:
			print("  не закончилась: игра %d, фаза %s, гонка %d, шаг %d, %s" % [g, r.phase, r.race_no, steps, r.log.slice(-3).map(func(e): return e["text"])])
	check(done == 80, "все 80 партий доиграны (%d)" % done)
