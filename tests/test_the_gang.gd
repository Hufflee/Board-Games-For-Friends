## Авторские проверки покера, приватности и полного цикла The Gang на 3–10 мест.
## --headless --audio-driver Dummy --path . --script res://tests/test_the_gang.gd.
extends SceneTree

const Poker := preload("res://games/the_gang/logic/tg_poker.gd")
const Rules := preload("res://games/the_gang/logic/tg_rules.gd")
var checks: int = 0
var errors: int = 0
var completed_games: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func cards(ranks: Array, suits: Array = [0, 1, 2, 3, 0, 1, 2]) -> Array[int]:
	var result: Array[int] = []
	for index: int in ranks.size():
		result.append(int(suits[index]) * 13 + int(ranks[index]) - 2)
	return result

func members(count: int) -> Array:
	var result: Array = []
	for seat: int in count:
		result.append({"name": "Игрок %d" % seat, "peer": seat + 1, "bot": false})
	return result

func poker_examples() -> void:
	var examples: Array = [
		[cards([14, 11, 9, 5, 3]), [0, 14, 11, 9, 5, 3], "Старшая карта"],
		[cards([9, 9, 14, 7, 2]), [1, 9, 14, 7, 2], "Пара"],
		[cards([11, 11, 4, 4, 14], [0, 1, 0, 1, 2]), [2, 11, 4, 14], "Две пары"],
		[cards([7, 7, 7, 13, 2]), [3, 7, 13, 2], "Тройка"],
		[cards([9, 8, 7, 6, 5]), [4, 9], "Стрит"],
		[cards([14, 12, 9, 6, 2], [2, 2, 2, 2, 2]), [5, 14, 12, 9, 6, 2], "Флеш"],
		[cards([4, 4, 4, 12, 12], [0, 1, 2, 0, 1]), [6, 4, 12], "Фулл-хаус"],
		[cards([13, 13, 13, 13, 14]), [7, 13, 14], "Каре"],
		[cards([9, 8, 7, 6, 5], [1, 1, 1, 1, 1]), [8, 9], "Стрит-флеш"],
		[cards([14, 13, 12, 11, 10], [3, 3, 3, 3, 3]), [8, 14], "Роял-флеш"]
	]
	var previous: Dictionary = {}
	for example: Array in examples:
		var input: Array = example[0]
		var before: Array = input.duplicate()
		var got: Dictionary = Poker.evaluate(input)
		check(got.key == example[1] and got.category == example[1][0], "Категория и полный ключ: %s" % example[2])
		check(got.name == example[2] and got.best.size() == 5, "Русское имя и ровно пять карт: %s" % example[2])
		check(input == before, "Оценка не меняет вход: %s" % example[2])
		if not previous.is_empty():
			check(Poker.compare(got, previous) == 1 and Poker.compare(previous, got) == -1,
				"Порядок силы десяти названий: %s" % example[2])
		previous = got
	# Здесь у каждого примера ожидается полная лучшая пятёрка, не первые пять карт.
	var seven: Array = [
		[cards([10, 10, 10, 4, 4, 4, 14], [0, 1, 2, 0, 1, 2, 3]), [6, 10, 4]],
		[cards([14, 14, 13, 13, 12, 12, 2], [0, 1, 0, 1, 0, 1, 2]), [2, 14, 13, 12]],
		[cards([12, 12, 12, 12, 14, 13, 2]), [7, 12, 14]],
		[cards([14, 11, 9, 7, 4, 2, 13], [0, 0, 0, 0, 0, 0, 1]), [5, 14, 11, 9, 7, 4]],
		[cards([2, 3, 4, 5, 6, 7, 8], [2, 2, 2, 2, 2, 2, 2]), [8, 8]],
		[cards([14, 14, 5, 4, 3, 2, 13]), [4, 5]],
		[cards([9, 8, 7, 6, 4, 5, 2], [0, 0, 0, 0, 0, 1, 2]), [5, 9, 8, 7, 6, 4]],
		[cards([2, 3, 10, 11, 12, 13, 14]), [4, 14]]
	]
	for example: Array in seven:
		var input: Array = example[0]
		var got: Dictionary = Poker.evaluate(input)
		check(got.key == example[1], "Семь карт: ожидается %s, получено %s" % [example[1], got.key])
		check(Poker.evaluate(got.best).key == got.key, "Возвращённые best действительно образуют заявленную пятёрку")
		for card: int in got.best:
			check(input.has(card), "Best не создаёт карту вне исходных семи")
		input.reverse()
		check(Poker.compare(Poker.evaluate(input), got) == 0, "Перестановка семи карт не меняет силу")
	var wheel: Dictionary = Poker.evaluate(cards([14, 2, 3, 4, 5]))
	check(wheel.key == [4, 5], "Туз в колесе равен единице")
	check(Poker.compare(wheel, Poker.evaluate(cards([2, 3, 4, 5, 6]))) == -1, "Колесо слабее стрита до шестёрки")
	check(Poker.evaluate(cards([13, 14, 2, 3, 4])).category == 0, "K-A-2-3-4 не является стритом")
	check(Poker.evaluate(cards([14, 2, 3, 4, 5], [1, 1, 1, 1, 1])).key == [8, 5], "Одномастное колесо — стрит-флеш до5")
	check(Poker.evaluate(cards([2, 3, 4, 5, 6, 7])).key == [4, 7], "Оценка шести карт также выбирает лучшую пятёрку")
	for bad: Array in [[], [0, 1, 2, 3], [0, 0, 1, 2, 3], [0, 1, 2, 3, 52], [-1, 0, 1, 2, 3],
		[0, 1, 2, 3, "4"], [0, 1, 2, 3, 4.0], [0, 1, 2, 3, 4, 5, 6, 7]]:
		check(Poker.evaluate(bad).is_empty(), "Некорректные карты отклоняются: %s" % [bad])

func kicker_examples() -> void:
	var pairs: Array = [
		[cards([14, 12, 9, 6, 4]), cards([14, 12, 9, 6, 3])],
		[cards([8, 8, 14, 12, 5]), cards([8, 8, 14, 12, 4])],
		[cards([9, 9, 6, 4, 2]), cards([8, 8, 14, 13, 12])],
		[cards([12, 12, 7, 7, 3], [0, 1, 0, 1, 2]), cards([12, 12, 6, 6, 14], [0, 1, 0, 1, 2])],
		[cards([12, 12, 7, 7, 14], [0, 1, 0, 1, 2]), cards([12, 12, 7, 7, 4], [0, 1, 0, 1, 2])],
		[cards([9, 9, 9, 14, 3]), cards([9, 9, 9, 14, 2])],
		[cards([9, 9, 9, 2, 2], [0, 1, 2, 0, 1]), cards([8, 8, 8, 14, 14], [0, 1, 2, 0, 1])],
		[cards([9, 9, 9, 7, 7], [0, 1, 2, 0, 1]), cards([9, 9, 9, 6, 6], [0, 1, 2, 0, 1])],
		[cards([12, 12, 12, 12, 14]), cards([12, 12, 12, 12, 13])],
		[cards([14, 12, 9, 6, 4], [0, 0, 0, 0, 0]), cards([14, 12, 9, 6, 3], [2, 2, 2, 2, 2])]
	]
	for pair: Array in pairs:
		var a: Dictionary = Poker.evaluate(pair[0])
		var b: Dictionary = Poker.evaluate(pair[1])
		check(Poker.compare(a, b) == 1 and Poker.compare(b, a) == -1, "Полные кикеры/группы: %s сильнее %s" % [a.key, b.key])
	var same_a: Dictionary = Poker.evaluate(cards([14, 12, 9, 6, 4], [0, 0, 0, 0, 0]))
	var same_b: Dictionary = Poker.evaluate(cards([14, 12, 9, 6, 4], [3, 3, 3, 3, 3]))
	check(Poker.compare(same_a, same_b) == 0, "Разные масти не разрешают равенство флешей")
	# Все позиции кикеров сравниваются лексикографически, не суммой значений.
	for prefix: int in range(1, 6):
		var left: Array = [0, 14, 12, 10, 8, 6]
		var right: Array = left.duplicate()
		right[prefix] -= 1
		check(Poker.compare({"key": left}, {"key": right}) == 1, "Сравнение позиции%d полного ключа" % prefix)

func snapshot(g: RefCounted) -> Dictionary:
	return {"view": g.get_view(0), "hands": g.hands.duplicate(true), "deck": g.deck.duplicate(), "rng": g._rng.state}

func invalid_and_chips() -> void:
	var g := Rules.new()
	for count: int in [0, 1, 2, 11]:
		g.new_game(members(count), 91)
		check(g.phase == "setup" and g.players.is_empty() and g.hands.is_empty(), "Неверное количество%d безопасно отклонено" % count)
		check(not g.timeout() and not g.action(0, "take", {"value": 1}), "В setup нет действий")
	g.new_game([{}, 0, {}], 91)
	check(g.phase == "setup", "Неверные данные участника не приводят к падению")
	g.new_game(members(3), 91)
	check(g.phase == "rank" and g.round_no == 1 and g.heist_no == 1, "Начальное состояние контракта")
	check(g.action(0, "take", {"value": 1}), "Игрок0 взял1")
	check(g.action(1, "take", {"value": 2}), "Игрок1 взял2")
	check(g.action(1, "take", {"value": 1}) and g.chips == [0, 1, 0], "Кража чужой фишки возвращает свою прежнюю в центр")
	check(g.history[0] == [0, 1, 0], "История текущего раунда отражает кражу")
	check(g.action(1, "return") and g.chips == [0, 0, 0], "Свою фишку можно вернуть")
	var bad: Array = [
		[-1, "take", {"value": 1}], [3, "take", {"value": 1}], [0, "take", {"value": 0}],
		[0, "take", {"value": 4}], [0, "take", {}], [0, "take", {"value": 1.0}],
		[0, "take", {"value": "1"}], [0, "take", {"value": true}], [0, "return", {}],
		[0, "next", {}], [0, "неизвестное", {}], [0, "take", {"value": 1, "seat": 2}],
		[0, "take", {"value": 1, "target": 2}], [0, "take", {"value": 1, "revision": -1}],
		[0, "take", {"value": 1, "revision": "1"}]
	]
	for attempt: Array in bad:
		var before: Dictionary = snapshot(g)
		check(not g.action(attempt[0], attempt[1], attempt[2]), "Неверное действие отклонено: %s" % [attempt])
		check(snapshot(g) == before, "Отказ не меняет состояние, журнал, ревизию или RNG")
	var rev: int = g.revision
	check(g.action(0, "take", {"value": 3, "revision": rev}), "Первая сериализованная заявка принята")
	check(not g.action(1, "take", {"value": 3, "revision": rev}) and g.chips == [3, 0, 0],
		"Вторая заявка той же старой ревизии отклонена")
	check(g.action(1, "take", {"value": 3, "revision": g.revision}) and g.chips == [0, 3, 0],
		"Новая сериализованная заявка законно забирает занятую фишку")
	var turn: int = g.turn_no
	check(g.action(0, "take", {"value": 1}) and g.turn_no == turn, "Обычный выбор не перезапускает часы раунда")
	var rank_revision: int = g.revision
	check(g.action(2, "take", {"value": 2}) and g.round_no == 2 and g.turn_no == turn + 1,
		"Последняя фишка немедленно завершает раунд без подтверждения")
	check(g.history[0] == [1, 3, 2] and g.chips == [0, 0, 0] and g.community.size() == 3,
		"История сохранена, новые фишки пусты, открыты три карты")
	var rank_snapshot: Dictionary = snapshot(g)
	check(not g.action(0, "take", {"value": 2, "revision": rank_revision}) and snapshot(g) == rank_snapshot,
		"Запоздалая заявка прошлого раунда не назначает новую фишку")
	var old_revision: int = g.revision
	var old_turn: int = g.turn_no
	g.new_game(members(3), 91)
	check(g.revision > old_revision and g.turn_no > old_turn, "Новая партия не переиспользует старые ревизии и часы")
	check(not g.action(0, "take", {"value": 1, "revision": old_revision}), "Заявка старой партии не применится к новой")
	g.new_game(g.players, 91)
	check(g.phase == "rank" and g.players.size() == 3, "Повторный запуск с собственными метаданными не очищает вход до проверки")
	var metadata: Array = members(3)
	metadata[0]["hands"] = [[0, 1], [2, 3]]
	g.new_game(metadata, 91)
	metadata[0].name = "Подмена входа"
	check(g.players[0].name != "Подмена входа" and not g.get_view(0).players[0].has("hands"),
		"Входные метаданные скопированы, неожиданный контейнер рук не публикуется")
	var other := Rules.new()
	other.new_game(members(3), 91)
	other.hands.reverse()
	g.timeout()
	other.timeout()
	check(g.history[0] == other.history[0], "Fallback не ранжирует фишки по скрытым рукам")
	var seen: Dictionary = {}
	for seed_value: int in range(1, 20):
		other.new_game(members(3), seed_value)
		other.timeout()
		seen[str(other.history[0])] = true
	check(seen.size() > 1, "Разные seeds дают разные перестановки свободных фишек")

func check_cards_and_privacy(g: RefCounted) -> void:
	var all: Array = g.deck.duplicate()
	all.append_array(g.community)
	for hand: Array in g.hands:
		check(hand.size() == 2, "Каждому выданы две карты")
		all.append_array(hand)
	var unique: Dictionary = {}
	for card: int in all:
		unique[card] = true
	check(all.size() == 52 and unique.size() == 52 and all.min() == 0 and all.max() == 51,
		"Руки, стол и оставшаяся колода — ровно52 уникальные карты")
	for seat: int in range(-1, g.players.size()):
		var view: Dictionary = g.get_view(seat, true)
		check(not view.has("hands") and not view.has("deck") and view.result.is_empty(), "Даже show_all не раскрывает руки/колоду до вскрытия")
		check(view.hand == (g.hands[seat] if seat >= 0 else []), "Только собственная рука, зрителю пусто")
		check(view.history.size() == 4 and view.history[g.round_no - 1] == g.chips, "Четыре строки истории и текущая строка согласованы")
	var view: Dictionary = g.get_view(0)
	view.hand.clear()
	view.community.clear()
	view.chips[0] = 99
	view.history[0][0] = 99
	view.players[0].name = "Подмена"
	check(g.hands[0].size() == 2 and g.chips[0] != 99 and g.history[0][0] != 99 and g.players[0].name != "Подмена",
		"Изменение выданного view не меняет движок")

func distributions_and_timeouts() -> void:
	for count: int in range(3, 11):
		for seed_value: int in range(1, 9):
			var g := Rules.new()
			g.new_game(members(count), seed_value)
			var same := Rules.new()
			same.new_game(members(count), seed_value)
			check(g.hands == same.hands and g.deck == same.deck, "Повторяемая раздача собственного RNG")
			for round_index: int in 4:
				check(g.phase == "rank" and g.round_no == round_index + 1, "Четыре раунда в правильном порядке")
				check(g.community.size() == [0, 3, 4, 5][round_index], "Общие карты0/3/4/5")
				check_cards_and_privacy(g)
				check(g.action(0, "take", {"value": count}), "Перед timeout назначена максимальная фишка")
				check(g.action(1, "take", {"value": 1}), "Перед timeout назначена минимальная фишка")
				var rev: int = g.revision
				var turn: int = g.turn_no
				check(g.timeout(), "Истечение таймера заполняет только недостающие места")
				check(g.revision == rev + 1 and g.turn_no == turn + 1, "Один timeout — одна ревизия и один переход")
				check(g.history[round_index][0] == count and g.history[round_index][1] == 1,
					"Timeout не отбирает уже выбранные фишки")
				var sorted: Array = g.history[round_index].duplicate()
				sorted.sort()
				check(sorted == range(1, count + 1), "Свободные фишки распределены без дублей и нулей")
				for earlier: int in round_index:
					check(not g.history[earlier].has(0), "Предыдущие строки истории не потеряны")
			check(g.phase == "showdown" and g.result.hands == g.hands, "После четвёртого раунда руки публичны только в result")
			check(g.result.order[0] == 1 and g.result.order[count - 1] == 0, "Order содержит места по возрастанию фишек")
			for seat: int in count:
				var seven: Array = g.hands[seat].duplicate()
				seven.append_array(g.community)
				check(g.result.ranks[seat].key == Poker.evaluate(seven).key, "Ranks индексируются по месту игрока")
			check(g.vaults + g.alarms == 1 and not g.timeout(), "Вскрытие засчитано один раз, timeout там ничего не делает")
			var old: Dictionary = snapshot(g)
			check(not g.action(0, "take", {"value": 1}) and snapshot(g) == old, "Нельзя менять фишки после вскрытия")
			check(g.get_view(-1).result.hands == g.hands and g.get_view(-1).hand.is_empty(), "На вскрытии зритель видит публичный result")
			var rev: int = g.revision
			check(g.action(count - 1, "next", {"revision": rev}), "Любой участник переходит к следующему ограблению")
			check(not g.action(0, "next", {"revision": rev}), "Повторный next старой ревизии отклонён")
			check(g.heist_no == 2 and g.round_no == 1 and g.result.is_empty(), "Новый heist убирает прежнее вскрытие")
			check_cards_and_privacy(g)

func prepared_outcomes() -> void:
	for pattern: Array in [[true, true, true], [false, false, false], [true, false, true, false, true], [false, true, false, true, false]]:
		var g := Rules.new()
		g.new_game(members(3), 51)
		for index: int in pattern.size():
			for round_index: int in 3:
				check(g.timeout(), "Подготовленный полный раунд до известного вскрытия")
			# Различающиеся пары на нейтральном столе — ожидаемый порядок известен независимо от оценщика.
			g.hands = [cards([14, 14], [0, 1]), cards([13, 13], [0, 1]), cards([12, 12], [0, 1])]
			g.community = cards([2, 4, 6, 8, 10])
			var assignments: Array = [3, 2, 1] if pattern[index] else [1, 2, 3]
			for seat: int in 3:
				check(g.action(seat, "take", {"value": assignments[seat]}), "Подготовленное присвоение финальных фишек")
			check(g.result.success == pattern[index], "Пары AA/KK/QQ дают заранее известный исход")
			check(g.vaults + g.alarms == index + 1, "Счётчик ограблений растёт ровно на1")
			if index < pattern.size() - 1:
				check(g.phase == "showdown" and g.action(0, "next"), "Переход между ограблениями без раннего конца")
		check(g.phase == "game_over" and g.won == pattern.back(), "Финал по третьему сейфу или третьей тревоге")
		var before: Dictionary = snapshot(g)
		check(not g.action(0, "next") and not g.timeout() and snapshot(g) == before,
			"Конец игры сохраняет result и не принимает повторный next/timeout")
		completed_games += 1
	# Истинное равенство на общем роял-флеше допускает любой порядок, без сравнения карманных кикеров.
	var g := Rules.new()
	g.new_game(members(3), 87)
	for index: int in 3:
		g.timeout()
	g.community = cards([10, 11, 12, 13, 14], [0, 0, 0, 0, 0])
	g.hands = [cards([2, 3], [1, 1]), cards([4, 5], [1, 1]), cards([6, 7], [2, 2])]
	for seat: int in 3:
		g.action(seat, "take", {"value": [2, 3, 1][seat]})
	check(g.result.success and g.vaults == 1 and g.result.ranks[0].key == [8, 14], "Любой порядок истинно равных рук принимается")
	var view: Dictionary = g.get_view(-1)
	view.result.hands[0].clear()
	view.result.ranks[0].key.clear()
	check(g.result.hands[0].size() == 2 and not g.result.ranks[0].key.is_empty(), "Публичный result выдан независимой глубокой копией")

func random_full_games() -> void:
	for count: int in range(3, 11):
		for seed_value: int in range(1, 7):
			var g := Rules.new()
			g.new_game(members(count), 1000 + seed_value)
			var steps: int = 0
			var previous_turn: int = g.turn_no
			while g.phase != "game_over" and steps < 30:
				if g.phase == "rank":
					check(g.timeout(), "Полная партия: таймер завершает раунд без ботов")
				else:
					check(g.action(0, "next"), "Полная партия: переход после вскрытия")
				check(g.turn_no > previous_turn, "Часы монотонны при каждом переходе партии")
				previous_turn = g.turn_no
				steps += 1
			check(g.phase == "game_over" and g.heist_no >= 3 and g.heist_no <= 5, "Полная случайная партия завершается за3–5 ограблений")
			check((g.vaults == 3) != (g.alarms == 3), "Ровно один терминальный счётчик достиг3")
			check(g.won == (g.vaults == 3) and not g.result.is_empty(), "Итог победы/поражения и финальное вскрытие сохранены")
			completed_games += 1

func _initialize() -> void:
	poker_examples()
	kicker_examples()
	invalid_and_chips()
	distributions_and_timeouts()
	prepared_outcomes()
	random_full_games()
	print("THE GANG: ", checks, " проверок, ", errors, " ошибок, полных партий ", completed_games)
	quit(1 if errors else 0)
