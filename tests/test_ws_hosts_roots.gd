extends SceneTree
## Ворд Слэм 08.11: однокоренные подсказки, смена рассказчиков без повторов в круге, смена слова голосованием.
## godot --headless --audio-driver Dummy --path . --script res://tests/test_ws_hosts_roots.gd
var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ОШИБКА: ", msg)


func _initialize() -> void:
	check(WSData.same_root("суп", "суп") and WSData.same_root("суп", "супы"), "суп ~ суп, супы")
	check(WSData.same_root("волшебник", "волшебный"), "волшебник ~ волшебный")
	check(WSData.same_root("железная дорога", "дорогой"), "многословное слово — по каждому слову")
	check(not WSData.same_root("суп", "сон") and not WSData.same_root("время", "вред"), "разные корни не путаются")
	var players := []
	for i in 6:
		players.append({"name": "И%d" % i, "team": i % 2})
	for seed_value in [3, 17, 91]:
		for catalog in ["basic", "simplified"]:
			var w := WSRules.new()
			w.new_game(players, false, 25, false, true, seed_value, catalog)
			var told := [{}, {}]
			for round_i in 3:  # 3 участника в команде — круг из 3 раундов, без повторов
				for t in 2:
					var s: int = w.storytellers[t]
					check(not told[t].has(s), "рассказчик команды %d не повторяется в круге (%s)" % [t, catalog])
					told[t][s] = true
				for cat in WSData.CATEGORIES:
					for id: String in w.catalog_order[cat]:
						if WSData.same_root(w.word, WSRules.card_word(id)):
							check(false, "однокоренная подсказка «%s» к слову «%s»" % [WSRules.card_word(id), w.word])
				for s2 in w.storytellers:
					w.set_ready(s2)
				w.time_up()
				w.advance()
			check(told[0].size() == 3 and told[1].size() == 3, "за круг рассказали все")
	var w2 := WSRules.new()
	w2.new_game(players, false, 25, false, true, 5, "basic")
	var first := w2.word
	var no := w2.word_no
	check(w2.vote_skip(w2.storytellers[0]) and w2.word == first, "один голос — слово не меняется")
	check(not w2.vote_skip(w2.storytellers[0]), "второй голос того же рассказчика не считается")
	check(not w2.vote_skip((w2.storytellers[0] + 2) % 6) or w2.storytellers.has((w2.storytellers[0] + 2) % 6), "не рассказчик не голосует")
	w2.vote_skip(w2.storytellers[1])
	check(w2.word_no == no + 1 and w2.skip_votes.is_empty(), "все рассказчики «за» — новое слово, голоса сброшены")
	for cat in WSData.CATEGORIES:
		for id: String in w2.catalog_order[cat]:
			if WSData.same_root(w2.word, WSRules.card_word(id)):
				check(false, "после смены слова однокоренная «%s»" % WSRules.card_word(id))
	print("ВОРД СЛЭМ 08.11: ", checks, " проверок, ", fails, " ошибок")
	quit(1 if fails > 0 else 0)
