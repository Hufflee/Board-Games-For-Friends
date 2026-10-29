extends SceneTree
## Кандидаты, ревизии, поддельные payload и приватность новой игры.
const Rules := preload("res://games/things_in_rings/logic/tr_rules.gd")
const Result := preload("res://hub/victory_result.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func send(game: Rules, seat: int, kind: String, payload: Dictionary = {}) -> bool:
	payload.revision = game.revision
	return game.action(seat, kind, payload)

func _init() -> void:
	for count: int in [1, 2, 3]:
		var game := Rules.new()
		var rings: Array = Rules.CATEGORIES.slice(0, count)
		var pools := {"Attribute": [100,101,102,103,104], "Word": [200,201,202,203], "Context": [300,301,302,303]}
		check(game.new_game([{}, {}, {}], range(100), pools, {"rings": rings}, 50 + count) == "", "Игра с разным количеством колец")
		var initial: Dictionary = game.get_view(0)
		check(game.phase == "choose_rules" and game.deck.size() == 100, "До выбора ничего не роздано")
		check(not send(game, 0, "begin_clues"), "Нельзя начать с неполным выбором")
		for category: String in rings:
			var candidates: Array = game.rule_choices[category]
			var unique := {}
			for id: int in candidates:
				unique[id] = true
			check(unique.size() == 3, "Ровно три разных кандидата")
			var excluded: int = -1
			for id: int in pools[category]:
				if not candidates.has(id):
					excluded = id
			check(not send(game, 0, "choose_rule", {"category": category, "card": excluded}), "Нельзя выбрать из остальной колоды")
			check(not send(game, 1, "choose_rule", {"category": category, "card": candidates[0]}), "Чужой выбор запрещён")
			check(send(game, 0, "choose_rule", {"category": category, "card": candidates[0]}), "Валидный выбор принят")
			check(game.get_view(0).rule_choices == initial.rule_choices, "Повторные view и выбор не меняют кандидатов")
		check(game.get_view(1).rule_choices.is_empty() and game.get_view(-1).secret_rules.is_empty(), "Искатель и зритель не получают тайны")
		check(send(game, 0, "begin_clues"), "Подтверждение раздаёт карты")
		check(not send(game, 0, "choose_rule", {"category": rings[0], "card": game.rule_choices[rings[0]][1]}), "После подтверждения неизменно")
		check(not game.action(0, "clue", null) and not game.action(0, "clue", {"revision": str(game.revision)}), "Неверный payload не падает")
		check(not send(game, 0, "clue", {"card": str(game.hands[0][0]), "mask": 0}), "Строка вместо ID запрещена")
		var stale: int = game.revision
		var card: int = game.hands[0][0]
		check(send(game, 0, "clue", {"card": card, "mask": 0}), "Подсказка принята")
		check(not game.action(0, "clue", {"revision": stale, "card": game.hands[0][0], "mask": 0}), "Старая ревизия не применяет следующую карту")
		for i: int in 2:
			check(send(game, 0, "clue", {"card": game.hands[0][0], "mask": 0}), "Оставшиеся подсказки")
		var private_view := game.get_view(-1)
		check(private_view.hand.is_empty() and private_view.secret_rules.is_empty() and private_view.rule_choices.is_empty(), "Снимок зрителя без закрытых карт")
		check(not send(game, -1, "place", {"card": game.hands[1][0], "mask": 0}), "Зритель не действует")
		check(send(game, 1, "place", {"card": game.hands[1][0], "mask": 0}), "Искатель предлагает")
		check(not send(game, 1, "judge", {"mask": 0}), "Искатель не судья")
		check(not send(game, 0, "judge", {"mask": 1 << count}), "Маска за полем запрещена")
		check(send(game, 0, "judge", {"mask": 1}), "Человеческая коррекция")
		check(game.hands[1].size() == 5 and game.current == 2, "Ошибка сохраняет пять карт и передаёт ход")
	var people := [{}, {}, {}]
	check(Result.resolve("things_in_rings", {"phase":"game_over", "players":people, "coop":true, "winners":[0,1,2]}).winners == [0,1,2], "Кооперативная победа для всех")
	check(Result.resolve("things_in_rings", {"phase":"game_over", "players":people, "coop":true, "winners":[], "reason":"no_clue"}).winners.is_empty(), "Проигрыш не создаёт победителей")
	print("TIR ACTIONS: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
