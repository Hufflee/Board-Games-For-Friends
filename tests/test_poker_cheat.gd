extends SceneTree
## Cheat Poker: фазы, приватность, совпадения и эффекты.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_poker_cheat.gd

const Rules := preload("res://games/poker/logic/pk_rules.gd")
const Cards := preload("res://games/poker/logic/pk_cheat_cards.gd")
const SEATS := [{"name": "А"}, {"name": "Б"}, {"name": "В"}, {"name": "Г"}]
var checks := 0
var errors := 0


func _init() -> void:
	_windows()
	_order()
	_all_in()
	_effects()
	_rank_cards()
	_portraits()
	_hand_modifiers()
	_forecast()
	_experimental()
	_fresh_deck()
	_reverse()
	print("ИТОГ: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", message)


func _game() -> PKRules:
	var game := Rules.new()
	game.new_game(SEATS, {"mode": "cheat", "seed": 7})
	return game


func _trade(game: PKRules) -> void:
	for _move: int in 8:
		if game.phase != "hand":
			return
		game.check_call(game.to_act)


func _submit(game: PKRules, seat: int, id: int) -> bool:
	var options: Array = game.get_view(seat).cheat.options.get(id, [])
	if options.is_empty():
		return false
	return game.action(seat, "cheat_play", {"id": id, "args": options[0].args, "window": game.cheat.window})


func _windows() -> void:
	var game := _game()
	var first: Array = game.cheat.hands[0].duplicate()
	check(first.size() == 7 and game.cheat.hands.all(func(hand: Array) -> bool: return hand == first), "один набор из семи на всех")
	check(first.all(func(id: int) -> bool: return first.count(id) == 1), "в руке семь разных карт")
	game.cheat.hands[0] = [0, 3]
	game.cheat.hands[1] = [0, 3]
	_trade(game)
	check(game.phase == "cheat_pick" and game.time_left == 10.0, "окно префлопа — 10 секунд")
	check(not game.action(0, "call", {}) and not game.action(-1, "cheat_play", {"window": game.cheat.window}), "торговля и зритель не участвуют в фазе")
	check(not game.action(0, "cheat_play", {"id": 0, "window": game.cheat.window - 1, "args": [-1, -1, -1, -1]}), "заявка из предыдущего окна отвергается")
	check(not game.action(0, "cheat_play", {"id": 0, "window": game.cheat.window, "args": [0, 1, 0, 0]}), "подставленная цель отвергается")
	check(_submit(game, 0, 0) and not _submit(game, 0, 3), "ровно одна заявка")
	check(game.get_view(0).cheat.played == 0 and game.get_view(1).cheat.played == -1, "выбор виден только автору")
	check(game.get_view(-1).cheat.hand.is_empty() and game.get_view(-1).cheat.revealed.is_empty(), "зрителю не выдают заявки")
	check(_submit(game, 1, 0), "вторая закрытая карта")
	game.tick(9.95)
	check(game.phase == "cheat_pick", "до истечения таймера карты скрыты")
	game.tick(0.1)
	check(game.cheat.revealed.size() == 2 and game.cheat.revealed.all(func(entry: Dictionary) -> bool: return entry.status == "cancelled"), "совпадение отменяет обе карты")
	game.tick(2.0)
	check(game.street == "flop" and game.hole[0].size() == 2 and game.cheat.hands[0] == [3], "отменённая карта расходуется без эффекта")
	for street: String in ["flop", "turn"]:
		_trade(game)
		check(game.street == street and game.phase == "cheat_pick", "есть фаза после улицы %s" % street)
		game.tick(10.0)
	_trade(game)
	check(game.street == "river" and game.phase == "showdown", "ривер сразу переходит к вскрытию")
	game.hand_no = 12
	game.tick(20.0)
	check(game.phase == "session_end", "после двенадцатой раздачи считаются очки")
	game.tick(20.0)
	check(game.session_no == 2 and game.hand_no == 1 and game.cheat.hands[0].size() == 7, "в новой сессии руки пополняются")
	check(game.cheat.hands[0] == game.cheat.hands[1] and game.cheat.hands[0] != first, "новый случайный набор опять общий")


func _order() -> void:
	var game := _game()
	var first: int = (game.button + 1) % SEATS.size()
	game.cheat.hands[first] = [15]
	game.cheat.hands[game.button] = [0]
	var top: int = game.deck[-1]
	var second: int = game.deck[-2]
	_trade(game)
	_submit(game, game.button, 0)
	_submit(game, first, 15)
	game.tick(10.0)
	check(game.cheat.revealed[0].seat == first and game.cheat.revealed[-1].seat == game.button, "баттон срабатывает последним")
	check(game.hole[game.button].size() == 2, "эффект ждёт показа карт")
	game.tick(2.0)
	check(game.deck[-2] == top and game.deck[-1] == second and game.cheat.revealed[0].status == "applied", "две верхние карты поменялись местами")
	game.tick(2.0)
	check(game.hole[game.button][-1] == second and game.get_view(first).hole[game.button] == [-1, -1, -1], "третья карта взята после предыдущего эффекта и скрыта")
	check(not game.evaluate(game.hole[game.button] + game.deck.slice(0, 5)).is_empty(), "оценка восьми карт")
	game.tick(2.0)
	check(game.phase == "hand" and game.street == "flop", "следующая улица после применения эффектов")


func _all_in() -> void:
	var game := Rules.new()
	game.new_game(SEATS.slice(0, 2), {"mode": "cheat", "seed": 7})
	game.cheat.hands[0] = [0]
	game.all_in_action(game.to_act)
	game.check_call(game.to_act)
	check(game.all_in(0) and game.phase == "cheat_pick" and _submit(game, 0, 0), "ва-банк не отнимает возможность разыграть карту")
	game.tick(10.0)
	game.tick(2.0)
	game.tick(2.0)
	check(game.phase == "cheat_pick" and game.street == "flop", "ва-банк сохраняет фазу флопа")
	game.tick(10.0)
	check(game.phase == "cheat_pick" and game.street == "turn", "ва-банк сохраняет фазу тёрна")
	game.tick(10.0)
	check(game.phase == "showdown" and game.get_view(1).hole[0].size() == 3 and game.get_view(1).open[0] == [true, true, true], "после последнего окна раскрываются все три карты")


func _effects() -> void:
	check(Cards.CARDS.size() == 28, "в каталоге 28 карт")
	for id: int in Cards.CARDS:
		var game := _game()
		game.fold(game.to_act)
		_trade(game)
		game.tick(10.0)
		_trade(game)
		var seat: int = game.folded.find(false)
		var folded: int = game.folded.find(true)
		var observer: int = (seat + 1) % SEATS.size()
		if observer == folded:
			observer = (observer + 1) % SEATS.size()
		if id == 9 and not game.deck.any(func(card: int) -> bool: return card % 13 == 8):
			check(false, "в тестовой колоде нужна десятка")
			continue
		game.cheat.hands[seat] = [id]
		check(_submit(game, seat, id), "можно сыграть «%s»" % Cards.title(id))
		game.tick(10.0)
		game.tick(2.0)
		check(not game.cheat.revealed.is_empty() and game.cheat.revealed[0].status == "applied", "сработала «%s»" % Cards.title(id))
		var pool: Array = game.board + game.deck
		for hand: Array in game.hole:
			pool.append_array(hand)
		var distinct := {}
		for card: int in pool:
			distinct[card] = true
		if id == 14:
			check(game.deck.size() == 52 and distinct.size() == 52, "новая колода содержит копии карт из игры")
		else:
			check(distinct.size() == pool.size(), "без дубликатов после «%s»" % Cards.title(id))
		if id == 1:
			check(game.get_view(seat).hole[folded] == game.hole[folded] and game.get_view(observer).hole[folded].is_empty(), "пас видит только разыгравший карту")
		if id in [5, 6, 12, 18, 19, 23]:
			check(not game.get_view(seat).cheat.peeks.is_empty() and game.get_view(observer).cheat.peeks.is_empty(), "подсказка приватна")
		if id == 2:
			check(game.get_view(seat).hole[folded].is_empty(), "обмен вслепую не открывает оставшиеся карты")


func _rank_cards() -> void:
	var game := _game()
	var tens := {}
	for seed: int in 12:
		game.deck = [8, 25, 2, 37, 49, 21, 5]
		game.rng.seed = seed
		check(game.cheat._effect(game, 0, 9, [1, -1, -1, -1]) and int(game.hole[0][1]) % 13 == 8,
			"выбранная карта заменяется десяткой")
		tens[game.hole[0][1]] = true
		check(game.deck.size() == 6 and not game.deck.has(game.hole[0][1]), "в колоде остаются все карты кроме взятой десятки")
	check(tens.size() == 2, "может выпасть любая из десяток")
	game.board = [0, 9, 1]
	check(game.cheat._effect(game, 0, 16, [-1, -1, -1, 1]) and game.board == [0, 49, 1],
		"званые гости берут ближайшую картинку и меняют только выбранное место")
	game.deck = [0, 3, 7]
	var hand: Array = game.hole[0].duplicate()
	check(not game.cheat._effect(game, 0, 9, [1, -1, -1, -1]) and game.hole[0] == hand,
		"если десятки нет, рука не меняется")
	check(not game.cheat._effect(game, 0, 16, [-1, -1, -1, 0]) and game.board == [0, 49, 1],
		"если картинок нет, стол не меняется")
	game.hole = [[4, 12], [12, 25], [38, 3], [51, 10]]
	game.folded[3] = true
	game.cheat.hands[0] = [23]
	game.cheat.begin(game)
	var ranks: Array = game.get_view(0).cheat.options[23]
	check(ranks.size() == 13, "розыск предлагает все номиналы")
	check(not game.action(0, "cheat_play", {"id": 23, "args": [-1, -1, -1, 15], "window": game.cheat.window}),
		"несуществующий номинал нельзя заявить")
	check(game.action(0, "cheat_play", {"id": 23, "args": ranks[-1].args, "window": game.cheat.window}),
		"розыск принимает туза")
	game.tick(10.0)
	game.tick(2.0)
	check(game.get_view(0).cheat.peeks == ["Розыск · Т · Б ×2, В ×1"], "розыск считает карты и пропускает пас")
	check(game.get_view(1).cheat.peeks.is_empty() and game.get_view(0).hole[1] == [-1, -1], "розыск приватен и не открывает масти")


func _portraits() -> void:
	var game := _game()
	game.hole = [[9, 12], [23, 37, 3], [49, 5], [7, 8]]
	game.shown[1].append(false)
	game.folded[2] = true
	game.cheat.hands[0] = [28, 8, 17, 26]
	game.cheat.begin(game)
	check(game.get_view(0).cheat.hand == [28] and game.get_view(0).cheat.options.size() == 1,
		"убранные карты скрыты и не разыгрываются")
	check(_submit(game, 0, 28), "галерею можно разыграть без цели")
	game.tick(10.0)
	game.tick(2.0)
	var view := game.get_view(-1)
	check(view.hole[0] == [9, -1] and view.hole[1] == [23, 37, -1],
		"валет, дама и король видны всем, а туз и числовая карта закрыты")
	check(view.hole[2].is_empty() and view.hole[3] == [-1, -1],
		"галерея пропускает пас и сохраняет рубашки остальных карт")


func _hand_modifiers() -> void:
	var game := _game()
	var gapped := Cards.GAPPED_STRAIGHT
	var colored := Cards.COLOR_FLUSH
	game.cheat.hands[0] = [gapped, colored]
	_trade(game)
	check(_submit(game, 0, gapped), "стрит с пропусками разыгрывается без цели")
	game.tick(10.0)
	game.tick(2.0)
	var example := [12, 24, 35, 46, 6]
	check(game.evaluate(example, 0).key == [4, 14], "Т–К–В–9–8 — стрит до туза")
	check(game.evaluate(example, 1).category == 0 and TGPoker.evaluate(example).category == 0, "эффект действует только для автора")
	check(game.evaluate([12, 23, 34, 45, 4], 0).key == [4, 14], "можно пропустить по одному номиналу в каждом промежутке")
	check(game.evaluate([12, 24, 35, 45, 5], 0).category == 0, "два соседних пропуска ломают стрит")
	check(game.evaluate([12, 19, 30, 41, 0], 0).key == [4, 8], "туз может быть младшим")
	check(game.evaluate([11, 25, 26, 40, 2], 0).category == 0, "через туза нельзя замкнуть стрит")
	check(game.evaluate([12, 25, 35, 46, 6], 0).category == 1, "повтор номинала не засчитывается в стрит")
	game.tick(2.0)
	_trade(game)
	check(_submit(game, 0, colored), "цветной флеш разыгрывается на следующей улице")
	game.tick(10.0)
	game.tick(2.0)
	var red := [26, 42, 32, 47, 38]
	var black := [0, 16, 6, 21, 12]
	check(game.evaluate(red, 0).category == 5 and game.evaluate(black, 0).category == 5,
		"флеш собирается из двух красных или двух чёрных мастей")
	check(game.evaluate(red, 1).category == 0 and game.evaluate([26, 42, 32, 47, 12], 0).category == 0,
		"чужой эффект и смесь цветов не дают флеш")
	var both := game.evaluate([38, 50, 35, 46, 32], 0)
	check(both.key == [8, 14] and both.name == "Стрит-флеш", "оба эффекта совместимы, это стрит-флеш с пропусками")
	check(game.evaluate([8, 9, 10, 11, 12], 0).name == "Роял-флеш", "название обычного роял-флеша сохраняется")
	check(game.get_view(0).cheat.effects.size() == 2 and game.get_view(1).cheat.effects.is_empty(), "стол показывает только свои активные эффекты")
	game.cheat.reverse = true
	check(game.evaluate(red, 0).category == 0, "при гипнозе игрок может обойтись без послабления")
	game.cheat.reverse = false
	game.board = [26, 42, 32, 13, 5]
	game.hole = [[47, 38], [17, 3], [], []]
	game.folded = [false, false, true, true]
	game.totals = [2, 2, 0, 0]
	game._showdown()
	check(game.result.hands[0] == "Флеш" and game.result.pots[0].winners == [0], "цветной флеш учитывается при выплате")
	game._start_hand()
	check(game.get_view(0).cheat.effects.is_empty() and game.evaluate(example, 0).category == 0, "новая раздача снимает оба эффекта")


func _forecast() -> void:
	var game := _game()
	var deck: Array = game.deck.duplicate()
	var expected: Array = [deck[-4], deck[-5], deck[-6]]
	var reports := {}
	for seed: int in 12:
		game.rng.seed = seed
		game.cheat._effect(game, 0, 6, [-1, -1, -1, -1])
		var report: String = game.cheat.peeks[0][-1]
		var all_seen := expected.all(func(id: int) -> bool: return report.contains(game.card_name(id)))
		check(all_seen and game.deck == deck, "прогноз пропускает флоп и не двигает колоду")
		reports[report] = true
	check(reports.size() > 1, "порядок показа меняется")
	check(game.get_view(1).cheat.peeks.is_empty(), "прогноз видит только автор")


func _experimental() -> void:
	var game := Rules.new()
	game.new_game(SEATS.slice(0, 2), {"mode": "cheat_experimental", "seed": 21})
	for seed: int in 30:
		game.rng.seed = seed
		game.cheat.new_session(game)
		check(not game.cheat.hands[0].any(func(id: int) -> bool: return id in [1, 2, 27]), "на двоих нет эффектов по пасу")
	var other := 1 - game.to_act
	game.cheat.hands[other] = [5, 0, 3]
	check(_submit(game, other, 5) and _submit(game, other, 0), "в чужой ход можно применить две карты сразу")
	check(game.hole[other].size() == 3 and game.phase == "hand", "эффект сразу меняет руку и не прерывает торговлю")
	var stale: int = game.cheat.window
	for step: int in 6:
		game.check_call(game.to_act)
	check(game.street == "river" and game.phase == "hand", "экспериментальная торговля дошла до ривера без окон")
	var data := {"id": 3, "args": [-1, -1, -1, -1], "window": stale}
	check(not game.action(other, "cheat_play", data), "заявка с прошлой улицы не принимается")
	game.raise_to(game.to_act, game.min_raise_to(game.to_act))
	game.check_call(game.to_act)
	data.window = game.cheat.window
	check(game.phase == "showdown" and not game.action(other, "cheat_play", data), "после последнего колла карта не меняет раздачу")


func _fresh_deck() -> void:
	var game := _game()
	game.fold(game.to_act)
	_trade(game)
	game.tick(10.0)
	_trade(game)
	var seat: int = game.folded.find(false)
	var before_hole: Array = game.hole.duplicate(true)
	var before_board: Array = game.board.duplicate()
	game.cheat.hands[seat] = [14]
	check(_submit(game, seat, 14), "новую колоду можно разыграть на флопе")
	game.tick(10.0)
	game.tick(2.0)
	var sorted: Array = game.deck.duplicate()
	sorted.sort()
	check(sorted == range(52) and game.deck != sorted, "новая перемешанная колода содержит все 52 карты")
	check(game.board == before_board and game.hole == before_hole, "замена сохраняет открытые карты и все руки")
	check(game.cheat.deck_replacements == 1, "замена учитывается при оценке шансов ботом")
	var copies := [0, 0, 13, 26, 39]
	var five := game.evaluate(copies)
	var royal := game.evaluate([8, 9, 10, 11, 12])
	check(five.name == "Пять одного номинала" and game.compare(five, royal) > 0, "пять двоек старше роял-флеша")
	check(TGPoker.evaluate(copies).is_empty(), "обычная оценка по-прежнему отвергает дубли")
	check(not game.evaluate([12, 12, 0, 1, 2]).is_empty(), "две одинаковые карты не ломают оценку")
	game.cheat.reverse = true
	check(game.compare(five, royal) < 0, "гипноз переворачивает и новую комбинацию")
	game.cheat.reverse = false
	game.board = [0, 13, 26, 39, 4]
	game.hole = [[0, 17], [1, 2], [], []]
	game.folded = [false, false, true, true]
	game.totals = [2, 2, 0, 0]
	game._showdown()
	check(game.result.pots[0].winners == [0] and game.result.hands[0] == five.name, "пять одного номинала забирают банк")


func _reverse() -> void:
	var game := _game()
	game.cheat.reverse = true
	var two := game.evaluate([0, 13, 2, 16, 30])
	var ace := game.evaluate([12, 25, 2, 16, 30])
	var high := game.evaluate([0, 14, 2, 16, 31])
	check(game.compare(two, ace) > 0 and game.compare(high, two) > 0, "гипноз переворачивает категорию и кикеры")
	var weakest := game.evaluate([0, 13, 2, 16, 30, 31, 33, 37])
	check(weakest.category == 0 and weakest.best.size() == 5, "выбирается самая слабая пятёрка из восьми")
