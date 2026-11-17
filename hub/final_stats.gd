extends RefCounted
## Итоговая таблица хоста. Передаются только числовые итоги, без скрытых состояний игроков.

const Result := preload("res://hub/victory_result.gd")
const UNIVERSAL := {"decisions": "Рискованные решения", "errors": "Ошибки в решениях", "messages": "Сообщения", "emotes": "Быстрые реплики", "rolls": "Кубиков брошено"}
const COOP := ["the_gang", "the_mind", "tip_top", "tip_top_18", "strokes_game"]


static func make(game: String, view: Dictionary, players: Array, collected: Array, logic: Object) -> Dictionary:
	var phase := str(view.get("phase", ""))
	if phase != "game_over" and not (phase == "end" and game in ["colt", "green_team", "strokes_game", "first_contact"]):
		return {}
	var columns := UNIVERSAL.duplicate()
	var rows := []
	var outcome := Result.resolve(game, view)
	var scores: Array = view.get("scores", []) if view.get("scores") is Array else []
	if game in ["gloom", "gloomier"]:
		scores = view.get("finals", [])
	if game == "machi_koro":
		scores = (view.get("built", []) as Array).map(func(item): return item.size() if item is Array else 0)
	if game == "poker" and str(view.get("mode", "classic")) == "classic":
		scores = view.get("profits", [])
	var ranks := {}
	for seat in players.size():
		var values := {}
		if seat < collected.size() and not bool(players[seat].get("bot", false)):
			for key in ["decisions", "errors", "messages", "emotes"]:
				values[key] = int(collected[seat].get(key, 0))
			var rolls := 0
			for count in collected[seat].get("dice", {}).values():
				rolls += int(count)
			values.rolls = rolls
		if logic != null and logic.has_method("host_stats"):
			for metric: Dictionary in logic.call("host_stats", seat):
				if not metric.get("value") is int and not metric.get("value") is float:
					continue
				var key := "game_" + str(metric.key)
				if not columns.has(key):
					columns[key] = str(metric.label)
				values[key] = metric.value
		if scores.size() == players.size() and (scores[seat] is int or scores[seat] is float):
			columns.score = "Итоговый счёт"
			values.score = scores[seat]
			ranks[seat] = -float(scores[seat]) if game in ["gloom", "gloomier"] else scores[seat]
		elif game in ["king_of_12", "brodilka", "not_a_hat", "ready_set_bet"] and values.has(_rank_key(game)):
			var score: float = values[_rank_key(game)]
			ranks[seat] = -score if game == "not_a_hat" else score
		var public_players: Array = view.get("players", [])
		if game == "four_souls" and seat < public_players.size():
			var public: Dictionary = public_players[seat]
			var soul_labels := {"souls": "Души", "coins": "Монеты", "attack": "Атака"}
			for key in soul_labels:
				if public.get(key) is int:
					columns[key] = soul_labels[key]
					values[key] = public[key]
			if values.has("souls") and not bool(public.get("withdrawn", false)):
				ranks[seat] = values.souls
		if game == "strokes_game":
			columns.team_score = "Угадано командой"
			values.team_score = int(view.get("score", 0))
		rows.append({"seat": seat, "name": str(players[seat].get("name", "Игрок")), "values": values})
	if game == "colt":
		for result: Dictionary in view.get("results", []):
			var seat := int(result.get("seat", -1))
			if seat >= 0 and seat < rows.size() and bool(result.get("eligible", false)):
				columns.score = "Итоговый счёт"
				rows[seat].values.score = int(result.get("score", 0))
				ranks[seat] = int(result.get("score", 0))
	if game == "first_contact":
		for metric in ["knowledge", "favor"]:
			var values: Array = view.get(metric, [])
			for seat in mini(values.size(), rows.size()):
				if values[seat] is int or values[seat] is float:
					columns[metric] = "Знание языка" if metric == "knowledge" else "Благосклонность"
					rows[seat].values[metric] = values[seat]
	var winners: Array = outcome.winners
	if game == "first_contact" and int(view.get("winner", -1)) >= 0:
		winners = [view.winner]
	if winners.is_empty() and not ranks.is_empty() and game in ["colt", "green_team"]:
		var best: float = ranks.values().max()
		winners = ranks.keys().filter(func(seat): return float(ranks[seat]) == best)
	var team: bool = outcome.team or game == "blood_on_the_clocktower" or (game == "colt" and bool(view.get("teams", false)))
	var coop := game in COOP or bool(view.get("coop", false))
	var ratings := {}
	for row: Dictionary in rows:
		var seat: int = row.seat
		if seat == outcome.leader:
			continue
		if coop:
			if game != "strokes_game":
				ratings[seat] = {"kind": "coop", "rating": 100 if winners.has(seat) else 0}
		elif team and not winners.is_empty():
			ratings[seat] = {"kind": "team", "rating": 100 if winners.has(seat) else 0}
		elif not team:
			var games_played := rows.size() - 1 - int(outcome.leader >= 0)
			if games_played <= 0:
				continue
			if ranks.size() >= rows.size() - int(outcome.leader >= 0) and ranks.has(seat):
				var beaten := 0
				for rival: int in ranks:
					if rival != seat and rival != outcome.leader and (winners.has(seat) and not winners.has(rival) or winners.has(seat) == winners.has(rival) and ranks[seat] > ranks[rival]):
						beaten += 1
				ratings[seat] = {"kind": "rank", "rating": roundi(100.0 * beaten / games_played)}
			elif not winners.is_empty() and (winners.has(seat) or games_played == 1):
				ratings[seat] = {"kind": "rank", "rating": roundi(100.0 * (rows.size() - winners.size() - int(outcome.leader >= 0)) / games_played) if winners.has(seat) else 0}
		if ratings.has(seat) and (coop or not winners.is_empty()):
			ratings[seat].result = "win" if winners.has(seat) else "loss"
		if ratings.has(seat) and ratings[seat].kind == "rank":
			columns.beaten = "Соперников обошли, %"
			row.values.beaten = ratings[seat].rating
	return {"columns": columns, "rows": rows, "ratings": ratings}


static func _rank_key(game: String) -> String:
	return {"king_of_12": "game_points", "perudo": "game_dice", "brodilka": "game_coins", "not_a_hat": "game_penalties", "ready_set_bet": "game_money"}.get(game, "")
