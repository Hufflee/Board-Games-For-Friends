extends RefCounted
## Преобразование публичных итогов всех игр в места победителей. Без изменения правил и Net.

static func resolve(game: String, view: Dictionary) -> Dictionary:
	var result := {"finished": false, "winners": [], "others": [], "title": "Партия завершена", "team": false}
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
		"things_in_rings":
			winners = view.get("winners", []).duplicate()
			result.team = bool(view.get("coop", false))
			if winners.is_empty() and view.get("reason", "") == "no_clue":
				result.title = "Подсказки закончились"
		"dangerous_words":
			teams = view.get("winners", [])
			result.team = true
		"wavelength":
			result.team = true
			if bool(view.get("coop", false)):
				# Кооператив завершается даже ниже цели: winner=0 сам по себе не означает победу.
				if int(view.get("scores", [0])[0]) >= preload("res://games/wavelength/logic/wl_rules.gd").COOP_GOAL:
					winners = range(players.size())
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
		"gloom", "gloomier", "not_a_hat", "ready_set_bet", "hues_and_cues":
			winners = view.get("winners", []).duplicate()
			result.team = game == "hues_and_cues" and bool(view.get("coop", false))
	if not teams.is_empty():
		for seat: int in players.size():
			if teams.has(int(players[seat].get("team", -1))):
				winners.append(seat)
	for seat: int in players.size():
		if winners.has(seat):
			result.winners.append(seat)
		else:
			result.others.append(seat)
	if not result.winners.is_empty():
		result.title = "Командная победа!" if result.team else "Победа!" if result.winners.size() == 1 else "Общая победа!"
	elif not bool(view.get("coop", false)) and not game in ["the_gang", "tip_top", "tip_top_18"]:
		result.title = "Партия завершена · без победителя"
	return result
