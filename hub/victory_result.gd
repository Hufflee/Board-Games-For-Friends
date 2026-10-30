extends RefCounted
## Преобразование публичных итогов всех игр в места победителей. Без изменения правил и Net.

static func resolve(game: String, view: Dictionary) -> Dictionary:
	var result := {"finished": false, "winners": [], "others": [], "title": "Партия завершена", "team": false, "leader": -1, "summary": ""}
	if str(view.get("phase", "")) != "game_over":
		return result
	result.finished = true
	var players: Array = view.get("players", [])
	var winners: Array = []
	var teams: Array = []
	match game:
		"the_gang", "tip_top", "tip_top_18":
			result.team = true
			if bool(view.get("won", false)):
				winners = range(players.size())
			else:
				result.title = "Попробуем ещё раз!"
			if game == "the_gang":
				result.summary = "Сейфов вскрыто: %d из 3 · тревог: %d из 3" % [int(view.get("vaults", 0)), int(view.get("alarms", 0))]
			else:
				result.summary = "Единорогов осталось: %d · какашек: %d" % [int(view.get("unicorns", 0)), int(view.get("poops", 0))]
		"things_in_rings":
			winners = view.get("winners", []).duplicate()
			result.team = bool(view.get("coop", false))
			# В обычной игре знающий не может победить: он ведущий, а не проигравший.
			if not result.team:
				result.leader = int(view.get("knower", -1))
			if winners.is_empty() and view.get("reason", "") == "no_clue":
				result.title = "Подсказки закончились"
			# Кооператив TIR явно объявляет общий проигрыш (у знающего кончились подсказки).
			if result.team:
				result.summary = "Вещей на поле: %d" % view.get("board", []).size()
		"dangerous_words":
			teams = view.get("winners", [])
			result.team = true
		"wavelength":
			result.team = true
			if bool(view.get("coop", false)):
				# Кооператив завершается даже ниже цели: winner=0 сам по себе не означает победу.
				var goal: int = preload("res://games/wavelength/logic/wl_rules.gd").COOP_GOAL
				var score := int(view.get("scores", [0])[0])
				# Цель объявлена в самой игре («Не хватило N очк. до цели») — это явный исход.
				if score >= goal:
					winners = range(players.size())
				result.summary = "Очков команды: %d · %s" % [score, "цель взята!" if score >= goal else "цель — %d" % goal]
			else:
				teams = [view.get("winner", -1)]
		"phantom_ink":
			result.team = true
			var roles: Array = view.get("roles", [])
			var winner := int(view.get("winner", -1))
			for seat: int in mini(players.size(), roles.size()):
				if winner >= 0 and int(int(roles[seat]) / 2) == winner:
					winners.append(seat)
		"word_slam":
			if str(view.get("mode", "teams")) == "teams":
				teams = view.get("winners", [])
				result.team = true
			else:
				winners = view.get("winners", []).duplicate()
		"king_of_12", "perudo", "brodilka", "stillion", "four_souls":
			winners = [view.get("winner", -1)]
		"poker":
			winners = view.get("winners", []).duplicate()
			var scores: Array = view.get("scores", [])
			if str(view.get("mode", "classic")) == "sport" and not winners.is_empty():
				result.summary = "Победные очки: %d из %d" % [int(scores[winners[0]]), int(view.get("target", 0))]
			elif not winners.is_empty():
				result.summary = "Итог: %+d фишек" % int(view.get("profits", [0])[winners[0]])
		"gloom", "gloomier", "not_a_hat", "ready_set_bet", "hues_and_cues", "khorom":
			winners = view.get("winners", []).duplicate()
			result.team = game == "hues_and_cues" and bool(view.get("coop", false))
			if result.team:
				# Общий счёт записан каждому месту одинаково; цель объявлена в лобби, победителей даёт сама игра.
				result.summary = "Очков команды: %d" % int(view.get("scores", [0])[0])
	if not teams.is_empty():
		for seat: int in players.size():
			if teams.has(int(players[seat].get("team", -1))):
				winners.append(seat)
	if winners.has(result.leader):
		result.leader = -1
	for seat: int in players.size():
		if seat == result.leader and not winners.has(seat):
			continue
		if winners.has(seat):
			result.winners.append(seat)
		else:
			result.others.append(seat)
	if not result.winners.is_empty():
		result.title = "Командная победа!" if result.team else "Победа!" if result.winners.size() == 1 else "Общая победа!"
	elif not bool(view.get("coop", false)) and not game in ["the_gang", "tip_top", "tip_top_18"]:
		result.title = "Партия завершена · без победителя"
	return result
