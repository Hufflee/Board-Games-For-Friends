class_name K12Bot
extends RefCounted
## Простой бот: играет по правилам, но без глубокой стратегии.


static func choose_card(rules: K12Rules, seat: int) -> String:
	var hand: Array = rules.hands[seat]
	return hand[rules.rng.randi_range(0, hand.size() - 1)]


static func choose_face(rules: K12Rules, seat: int) -> int:
	var options: Array = rules.pending["options"]
	var knight := false
	for s in rules.player_count():
		if rules.selected[s] == K12Cards.KNIGHT and s != seat:
			knight = true
	return options.min() if knight else options.max()


static func choose_under(rules: K12Rules, seat: int) -> String:
	var hand: Array = rules.hands[seat]
	return hand[rules.rng.randi_range(0, hand.size() - 1)]


## Делает все ходы ботов, которые сейчас возможны. Возвращает true, если что-то сделал.
## everyone — ходить и за людей (у них вышло время на ход).
static func act_all(rules: K12Rules, everyone: bool = false) -> bool:
	var acted := false
	match rules.phase:
		"roll":
			for s in rules.player_count():
				if (everyone or rules.players[s].get("bot", false)) and not rules.rolled[s] and rules.phase == "roll":
					var dir := Vector2.from_angle(rules.rng.randf() * TAU)
					rules.roll_die(s, dir.x * 900.0, dir.y * 900.0)
					acted = true
					if not everyone:
						break  # боты бросают по одному — так броски видно
		"select":
			for s in rules.player_count():
				if (everyone or rules.players[s].get("bot", false)) and rules.active[s] and rules.selected[s] == "" and rules.phase == "select":
					rules.select_card(s, choose_card(rules, s))
					acted = true
		"sorcerer":
			var s: int = rules.pending["seat"]
			if (everyone or rules.players[s].get("bot", false)):
				rules.choose_face(s, choose_face(rules, s))
				acted = true
		"oracle":
			var s: int = rules.pending["seat"]
			if (everyone or rules.players[s].get("bot", false)):
				var dir := Vector2.from_angle(rules.rng.randf() * TAU)
				rules.roll_oracle(s, dir.x * 900.0, dir.y * 900.0)
				acted = true
		"pick_under":
			for s in rules.pending.get("seats", []).duplicate():
				if (everyone or rules.players[s].get("bot", false)) and rules.phase == "pick_under":
					rules.pick_under(s, choose_under(rules, s))
					acted = true
	return acted
