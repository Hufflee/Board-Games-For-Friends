extends SceneTree
## Узкие дополнительные границы ядра; запуск --headless --audio-driver Dummy --script res://tests/test_things_in_rings_review.gd.
const Rules = preload("res://games/things_in_rings/logic/tr_rules.gd")
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func setup(game: Rules) -> void:
	for category: String in game.rings:
		check(game.choose_rule(game.knower, category, game.rule_choices[category][0]), "Выбор из тройки")
	check(game.begin_clues(game.knower), "Подтверждение правил")
	var n: int = game.players.size() if game.coop else 3
	for i: int in n:
		check(game.clue(game.knower, game.hands[game.knower][0], 0), "Начальная подсказка")

func _init() -> void:
	for ring_count: int in [1, 3]:
		var game := Rules.new()
		var rings: Array = ["Attribute", "Word", "Context"].slice(0, ring_count)
		check(game.new_game([{}, {}, {}, {}], range(270), {"Attribute": [10,11,12], "Word": [20,21,22], "Context": [30,31,32]}, {"rings": rings, "knower": 2}, 29) == "", "Старт с одним/тремя кольцами и внешней колодой270")
		setup(game)
		check(game.actor() == 3 and game.discarded.size() == 2, "Ход после непервого знающего")
		check(not game.place(3, game.hands[3][0], 1 << ring_count), "Маска за границей запрещена")
		var highest := (1 << ring_count) - 1
		check(game.place(3, game.hands[3][0], highest) and game.judge(2, 0), "Крайняя область допустима и исправляется в None")
		check(game.actor() == 0, "Переход через конец массива мест")
		var before: String = var_to_str([game.players, game.hands, game.board, game.pending, game.secret_rules, game.rings])
		var view: Dictionary = game.get_view(2)
		view.players.append({})
		view.hand.clear()
		view.board[0].mask = 123
		view.secret_rules.clear()
		view.rings.clear()
		check(before == var_to_str([game.players, game.hands, game.board, game.pending, game.secret_rules, game.rings]), "Изменение снимка не изменяет движок")
	var coop := Rules.new()
	check(coop.new_game([{}, {}, {}, {}], range(240), {"Word": [20,21,22]}, {"rings": ["Word"], "knower": 2, "coop": true}, 29) == "", "Кооператив4 с непервым знающим")
	setup(coop)
	for i: int in 5:
		check(coop.place(3, coop.hands[3][0], 0) and coop.judge(2, 0), "Первый искатель опустошает руку")
	check(coop.actor() == 0, "Пустой искатель завершил ход")
	for seat: int in [0, 1]:
		check(coop.place(seat, coop.hands[seat][0], 0) and coop.judge(2, 1), "Остальные завершают ход ошибкой")
	check(coop.phase == "knower_clue" and coop.actor() == 2, "После полного круга ровно одна подсказка")
	check(coop.clue(2, coop.hands[2][0], 1) and coop.actor() == 0 and coop.round_no == 2, "Новый круг пропускает пустого искателя3")
	var empty := Rules.new()
	check(empty.new_game([{}, {}, {}], range(15), {"Word": [20,21,22]}, {"rings": ["Word"]}, 29) == "", "Минимальная колода полностью роздана")
	setup(empty)
	check(empty.place(1, empty.hands[1][0], 0) and empty.judge(0, 1), "Ошибка при пустой колоде обработана")
	check(empty.phase == "game_over" and empty.reason == "deck_empty" and empty.winners.is_empty(), "Техническое завершение без выдуманного победителя")
	check(empty.board.size() == 4 and empty.pending.is_empty(), "Исправленная карта сохранена при завершении")
	print("TIR LOW BOUNDARIES: %d проверок, %d ошибок" % [checks, errors])
	quit(1 if errors else 0)
