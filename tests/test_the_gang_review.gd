## Независимое ревью базовой The Gang по английскому руководству, страницы5–13.
## --headless --audio-driver Dummy --script res://tests/test_the_gang_review.gd.
## Диапазон3..10 и timeout — решение владельца; печатная база3..6, расширенные режимы вне scope.
extends SceneTree

var checks := 0
var errors := 0
var poker: GDScript
var rules: GDScript
var sections: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func card(rank: int, suit: int) -> int:
	return suit * 13 + rank - 2

func cards(pairs: Array) -> Array:
	var result: Array = []
	for pair: Array in pairs:
		result.append(card(pair[0], pair[1]))
	return result

func evaluate(ids: Array) -> Dictionary:
	return poker.call("evaluate", ids)

func compare(left: Dictionary, right: Dictionary) -> int:
	return poker.call("compare", left, right)

func expected_hand(label: String, pairs: Array, expected_key: Array) -> Dictionary:
	var ids := cards(pairs)
	var before := ids.duplicate()
	var got := evaluate(ids)
	check(ids == before, label + ": оценка не меняет исходные карты")
	check(not got.is_empty(), label + ": получена оценка")
	if got.is_empty():
		return got
	check(got.category == expected_key[0] and got.key == expected_key,
		"%s: ожидание=%s факт=%s" % [label, expected_key, got])
	check(str(got.name).contains("а") or str(got.name).contains("е") or str(got.name).contains("и"),
		label + ": русское название комбинации")
	check(got.best.size() == 5, label + ": лучшая комбинация ровно из пяти карт")
	var seen := {}
	for id: int in got.best:
		check(ids.has(id) and not seen.has(id), label + ": лучшая пятёрка состоит из разных исходных карт")
		seen[id] = true
	# Это дополнительный инвариант; ожидаемый ключ выше задан независимо вручную по правилам.
	check(evaluate(got.best).key == expected_key, label + ": выбранная пятёрка действительно имеет ожидаемую силу")
	ids.reverse()
	check(evaluate(ids).key == expected_key, label + ": порядок исходных карт не влияет")
	var rotated: Array = []
	for id: int in ids:
		rotated.append((id + 13) % 52)
	check(evaluate(rotated).key == expected_key, label + ": масти не дают старшинства")
	return got

func poker_cases() -> void:
	# Числа ключей — независимые ожидаемые категория/ранги/кикеры из правил, не из helpers medium.
	var golden: Array = [
		["Старшая карта", [[14,0],[13,1],[11,2],[9,3],[3,0]], [0,14,13,11,9,3]],
		["Пара и три кикера", [[14,0],[14,1],[13,2],[12,3],[9,0],[5,1],[2,2]], [1,14,13,12,9]],
		["Две пары", [[13,0],[13,1],[12,2],[12,3],[14,0],[3,1],[2,2]], [2,13,12,14]],
		["Три пары: только две старшие", [[14,0],[14,1],[13,2],[13,3],[12,0],[12,1],[11,2]], [2,14,13,12]],
		["Тройка с двумя кикерами", [[9,0],[9,1],[9,2],[14,3],[13,0],[8,1],[2,2]], [3,9,14,13]],
		["Колесо A2345", [[14,0],[2,1],[3,2],[4,3],[5,0],[9,1],[12,2]], [4,5]],
		["Стрит с повтором ранга", [[2,0],[3,1],[4,2],[5,3],[6,0],[6,1],[14,2]], [4,6]],
		["Туз не в середине K A 2 3 4", [[13,0],[14,1],[2,2],[3,3],[4,0],[8,1],[11,2]], [0,14,13,11,8,4]],
		["Флеш: лучшие пять из шести", [[14,3],[13,3],[10,3],[8,3],[4,3],[2,3],[14,0]], [5,14,13,10,8,4]],
		["Две тройки: старшая становится тройкой фулл-хауса", [[14,0],[14,1],[14,2],[13,0],[13,1],[13,2],[2,3]], [6,14,13]],
		["Фулл-хаус: лучшая пара из двух", [[8,0],[8,1],[8,2],[14,0],[14,1],[13,2],[13,3]], [6,8,14]],
		["Каре с тузом-кикером", [[9,0],[9,1],[9,2],[9,3],[14,0],[13,1],[2,2]], [7,9,14]],
		["Стрит-флеш до короля", [[9,0],[10,0],[11,0],[12,0],[13,0],[2,1],[14,2]], [8,13]],
		["Роял-флеш", [[10,1],[11,1],[12,1],[13,1],[14,1],[2,2],[3,3]], [8,14]],
		["Стрит-флеш колесом", [[14,2],[2,2],[3,2],[4,2],[5,2],[13,0],[12,1]], [8,5]],
		["Стрит и флеш не образуют стрит-флеш разными картами", [[9,0],[10,0],[11,0],[12,0],[13,1],[2,0],[14,1]], [5,12,11,10,9,2]]
	]
	for entry: Array in golden:
		expected_hand(entry[0], entry[1], entry[2])
	# В каждом сравнении различается значимый более поздний кикер, а не только категория.
	var comparisons: Array = [
		[[[14,0],[13,1],[11,2],[9,3],[4,0]], [[14,1],[13,2],[11,3],[9,0],[3,1]]],
		[[[14,0],[14,1],[13,2],[12,3],[9,0]], [[14,2],[14,3],[13,0],[12,1],[8,2]]],
		[[[13,0],[13,1],[8,2],[8,3],[14,0]], [[13,2],[13,3],[7,0],[7,1],[14,2]]],
		[[[13,0],[13,1],[8,2],[8,3],[14,0]], [[13,2],[13,3],[8,0],[8,1],[12,2]]],
		[[[9,0],[9,1],[9,2],[14,3],[13,0]], [[9,0],[9,1],[9,3],[14,2],[12,1]]],
		[[[14,0],[13,0],[11,0],[8,0],[4,0]], [[14,1],[13,1],[11,1],[8,1],[3,1]]],
		[[[10,0],[10,1],[10,2],[2,0],[2,1]], [[9,0],[9,1],[9,2],[14,0],[14,1]]],
		[[[10,0],[10,1],[10,2],[14,0],[14,1]], [[10,0],[10,1],[10,2],[13,0],[13,1]]],
		[[[9,0],[9,1],[9,2],[9,3],[14,0]], [[9,0],[9,1],[9,2],[9,3],[13,0]]],
		[[[2,0],[3,1],[4,2],[5,3],[6,0]], [[14,0],[2,1],[3,2],[4,3],[5,0]]]
	]
	for index in comparisons.size():
		var left := evaluate(cards(comparisons[index][0]))
		var right := evaluate(cards(comparisons[index][1]))
		var old_left := left.duplicate(true)
		var old_right := right.duplicate(true)
		check(compare(left, right) > 0 and compare(right, left) < 0, "Сравнение кикеров/старшинства №%d" % index)
		check(compare(left, left) == 0, "Рефлексивная ничья №%d" % index)
		check(left == old_left and right == old_right, "compare не меняет аргументы №%d" % index)
	var invalid: Array = [[], [0,1,2,3], [0,1,2,3,4,5,6,7], [0,1,2,3,52], [-1,1,2,3,4], [0,0,1,2,3], [0,1,2,3,"4"], [0,1,2,3,4.0], [0,1,2,3,true]]
	for ids: Array in invalid:
		var old := ids.duplicate(true)
		check(evaluate(ids).is_empty() and ids == old, "Некорректные карты отвергнуты без мутации: %s" % [ids])
	var ids := cards([[14,0],[14,1],[13,2],[12,3],[9,0]])
	var first := evaluate(ids)
	var second := evaluate(ids)
	first.best[0] = -100
	first.key.append(100)
	check(second == evaluate(ids), "Возвращаемые key/best разных оценок независимы")

func members(count: int) -> Array:
	var result: Array = []
	for seat in count:
		result.append({"name": "Игрок%d" % seat, "peer": seat + 1, "color": {"id": seat}})
	return result

func make(count: int = 3, seed_value: int = 26) -> RefCounted:
	var g: RefCounted = rules.new()
	g.call("new_game", members(count), seed_value)
	return g

func view(g: RefCounted, seat: int = 0, show_all: bool = false) -> Dictionary:
	return g.call("get_view", seat, show_all)

func send(g: RefCounted, seat: int, kind: String, arg: Dictionary = {}) -> bool:
	var request := arg.duplicate(true)
	request["revision"] = g.revision
	return g.call("action", seat, kind, request)

## Включаем RNG/закрытые поля: отклонённое действие не должно тайком менять будущую раздачу.
func snapshot(g: RefCounted) -> Dictionary:
	var result := {}
	for property: Dictionary in g.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = g.get(property.name)
		if value is RandomNumberGenerator:
			result[property.name] = [value.seed, value.state]
		elif value is Array or value is Dictionary:
			result[property.name] = value.duplicate(true)
		else:
			result[property.name] = value
	return result

func rejected(g: RefCounted, seat: int, kind: String, arg: Dictionary, label: String) -> void:
	var before := snapshot(g)
	check(not g.call("action", seat, kind, arg), label + ": отказ")
	check(snapshot(g) == before, label + ": всё состояние и RNG сохранены")

func contains_hand(value: Variant, secret: Array) -> bool:
	if value is Array:
		if value == secret:
			return true
		for child: Variant in value:
			if contains_hand(child, secret):
				return true
	elif value is Dictionary:
		for child: Variant in value.values():
			if contains_hand(child, secret):
				return true
	return false

func privacy(g: RefCounted) -> void:
	for seat in range(-1, g.players.size() + 1):
		for show_all: bool in [false, true]:
			var got := view(g, seat, show_all)
			var expected: Array = g.hands[seat] if seat >= 0 and seat < g.hands.size() else []
			check(got.hand == expected, "В rank видна только собственная рука, место%d all=%s" % [seat, show_all])
			for other in g.hands.size():
				if other != seat:
					check(not contains_hand(got, g.hands[other]), "Вложенные поля view не раскрывают руку%d месту%d" % [other, seat])

func deal_unique(g: RefCounted) -> void:
	var seen := {}
	for hand: Array in g.hands:
		check(hand.size() == 2, "У каждого игрока две закрытые карты")
		for id: int in hand:
			check(id >= 0 and id < 52 and not seen.has(id), "Раздача без повторов и джокеров")
			seen[id] = true
	for id: int in g.community:
		check(not seen.has(id), "Общая карта не повторяет закрытую")
		seen[id] = true
	for id: int in g.deck:
		check(not seen.has(id), "Остаток колоды не повторяет стол/руки")
		seen[id] = true
	check(seen.size() == 52, "Руки, стол и остаток составляют ровно52 карты")

func fill(g: RefCounted, assignment: Array) -> void:
	for seat in assignment.size():
		var before: int = g.revision
		check(send(g, seat, "take", {"value": assignment[seat]}), "Взять чип: место%d значение%d" % [seat, assignment[seat]])
		check(g.revision > before, "Принятое действие увеличило revision")

func round_and_timeout() -> void:
	for count in range(3, 11):
		var g := make(count)
		check(g.phase == "rank" and g.round_no == 1 and g.heist_no == 1 and g.community.is_empty(), "Старт партии%d мест" % count)
		deal_unique(g)
		privacy(g)
		var pocket: Array = g.hands.duplicate(true)
		for round_index in range(1, 5):
			check(g.round_no == round_index and g.phase == "rank", "Начало ранжирования%d" % round_index)
			check(g.community.size() == [0,3,4,5][round_index - 1], "Префлоп/флоп/тёрн/ривер: число общих карт")
			var old_turn: int = g.turn_no
			# timeout заполняет только пропуски: уже выбранные чипы нельзя отбирать/переоценивать.
			check(send(g, 0, "take", {"value": count}), "До timeout сохранён выбор игрока0")
			check(send(g, 2, "take", {"value": 1}), "До timeout сохранён выбор игрока2")
			check(g.call("timeout"), "Timeout дополнил недостающие чипы")
			var row: Array = g.history[round_index - 1]
			check(row[0] == count and row[2] == 1, "Timeout не меняет уже выбранные значения")
			var sorted := row.duplicate()
			sorted.sort()
			var expected: Array = []
			for value in range(1, count + 1):
				expected.append(value)
			check(sorted == expected, "Все чипы распределены единожды")
			check(g.turn_no > old_turn and g.hands == pocket, "Раунд завершился, pocket не заменены")
			if round_index < 4:
				check(not g.chips.any(func(value): return value != 0), "Новый цвет начинается без выбранных чипов")
				privacy(g)
			deal_unique(g)
		check(g.phase == "showdown" and g.round_no == 4 and g.history.size() == 4, "После четвёртого цвета ровно одно вскрытие")
		check(g.vaults + g.alarms == 1, "Вскрытие начислило ровно один исход")
		var before := snapshot(g)
		check(not g.call("timeout") and snapshot(g) == before, "Timeout не меняет уже открытое вскрытие")
		for seat in [-1, 0, count - 1]:
			check(view(g, seat).result.hands == pocket, "На вскрытии публичны все pocket")

func chip_actions_and_revisions() -> void:
	var g := make(4)
	check(send(g, 0, "take", {"value": 1}), "Первый чип взят")
	check(send(g, 1, "take", {"value": 2}), "Другой чип взят")
	check(send(g, 0, "take", {"value": 2}), "Разрешён перехват занятого чипа")
	check(g.chips == [2,0,0,0], "Старый1 вернулся в центр; прежний владелец2 остался без чипа")
	check(send(g, 1, "take", {"value": 1}), "Освободившийся старый чип доступен другому")
	check(send(g, 0, "return"), "Чип можно вернуть в центр")
	check(g.chips == [0,1,0,0], "Return не назначает чип другому игроку")
	for seat in [-1, 4, 100]:
		rejected(g, seat, "take", {"value": 3}, "Неверное место%d" % seat)
	for value: Variant in [-1, 0, 5, "2", 2.0, true, null, [], {}]:
		rejected(g, 0, "take", {"value": value}, "Неверный тип/значение чипа %s" % [value])
	rejected(g, 0, "take", {}, "Нет номера чипа")
	rejected(g, 0, "take", {"value": 3, "seat": 2}, "Подмена отправителя в arg запрещена")
	rejected(g, 0, "next", {}, "Нельзя пропустить ранжирование")
	rejected(g, 0, "неизвестное", {}, "Неизвестное действие")
	rejected(g, 0, "return", {}, "Return отсутствующего чипа")
	for revision: Variant in [g.revision - 1, g.revision + 1, str(g.revision), float(g.revision), true]:
		rejected(g, 0, "take", {"value": 3, "revision": revision}, "Неверная/устаревшая revision %s" % revision)
	var request: Dictionary = {"value": 3, "revision": g.revision}
	check(g.call("action", 0, "take", request), "Запрос с текущей revision принят")
	rejected(g, 0, "take", request, "Повтор пакета не применяется")
	request.value = 4
	rejected(g, 0, "take", request, "Устаревший пакет с иным доступным чипом не применяется")
	var round_request := {"value": 4, "revision": g.revision}
	check(send(g, 2, "take", {"value": 2}), "Третье место выбрало свободный чип")
	check(send(g, 3, "take", {"value": 4}), "Последнее место автоматически закрыло первый цвет")
	check(g.round_no == 2 and g.history[0] == [3,1,2,4], "История хранит реальные места/чипы завершённого цвета")
	rejected(g, 0, "take", round_request, "Пакет предыдущего раунда не применяется к новому цвету")

## Подготовка только pocket/community, все переходы четырёх раундов выполняют настоящие action.
func final_fixture(g: RefCounted, mode: String = "ordered") -> bool:
	for round_index in 3:
		fill(g, [3,2,1])
	check(g.phase == "rank" and g.round_no == 4, "Первые три оценки могут быть любыми, впереди ривер")
	if g.phase != "rank" or g.round_no != 4:
		return false
	if mode == "board":
		g.community.assign([8,9,10,11,12])
		g.hands = [[13,14],[26,27],[39,40]]
	else:
		g.community.assign(cards([[2,0],[5,1],[9,2],[11,3],[13,0]]))
		g.hands = [cards([[3,0],[7,1]]), cards([[4,0],[8,1]]), cards([[14,2],[12,3]])]
		if mode == "tie":
			g.hands[1] = cards([[4,1],[7,3]])
	return true

func showdown_rules() -> void:
	for entry: Array in [["ordered", [1,2,3], true], ["ordered", [3,2,1], false],
		["tie", [2,1,3], true], ["tie", [3,1,2], false], ["board", [3,1,2], true]]:
		var g := make()
		if not final_fixture(g, entry[0]):
			return
		fill(g, entry[1])
		check(g.phase == "showdown" and g.result.success == entry[2], "Вскрытие%s чипы%s → успех%s" % entry)
		check(g.vaults == (1 if entry[2] else 0) and g.alarms == (0 if entry[2] else 1), "Один исход вскрытия, прежние цвета не оцениваются")
		check(g.result.ranks.size() == 3 and g.result.hands == g.hands and g.result.order.size() == 3, "Полный публичный результат вскрытия")
		if entry[0] == "board":
			for rank: Dictionary in g.result.ranks:
				check(rank.category == 8 and rank.key == [8,14], "На общей роял-доске все играют доску, порядок любой")
		var frozen := snapshot(g)
		var exposed := view(g, -1)
		exposed.result.hands[0][0] = -999
		exposed.result.ranks[0].key.append(999)
		exposed.result.order.clear()
		check(snapshot(g) == frozen, "Глубокая копия публичного результата не связана с сервером")
		rejected(g, 0, "take", {"value": 1}, "Вскрытые чипы нельзя менять")
		check(send(g, 2, "next"), "Любой участник может начать следующее ограбление после вскрытия")
		check(g.heist_no == 2 and g.round_no == 1 and g.phase == "rank" and g.result.is_empty(), "Новый heist очистил публичные руки предыдущего")
		privacy(g)

func terminal_games() -> void:
	for outcomes: Array in [[true,true,true], [false,false,false], [true,false,true,false,true], [false,true,false,true,false]]:
		var g := make()
		var expected_vaults := 0
		var expected_alarms := 0
		var old_turn: int = g.turn_no
		for index in outcomes.size():
			if not final_fixture(g):
				return
			fill(g, [1,2,3] if outcomes[index] else [3,2,1])
			expected_vaults += 1 if outcomes[index] else 0
			expected_alarms += 0 if outcomes[index] else 1
			check(g.vaults == expected_vaults and g.alarms == expected_alarms and g.heist_no == index + 1, "Счёт ограблений и исходов не теряется")
			check(g.turn_no > old_turn, "turn_no монотонно проходит новые ограбления")
			old_turn = g.turn_no
			if index < outcomes.size() - 1:
				check(g.phase == "showdown" and send(g, 0, "next"), "До третьего исхода игра продолжается")
		check(g.phase == "game_over" and g.won == (expected_vaults == 3), "Три сейфа/три тревоги завершают игру, включая пятое ограбление")
		for kind: String in ["next", "take", "return"]:
			rejected(g, 0, kind, {"value": 1} if kind == "take" else {}, "После конца игры %s отклонено" % kind)
		var frozen := snapshot(g)
		check(not g.call("timeout") and snapshot(g) == frozen, "Timeout не возобновляет завершённую игру")

func copies_and_determinism() -> void:
	var g := make(5, 714)
	var other := make(5, 714)
	check(g.hands == other.hands and g.deck == other.deck, "Одинаковый seed воспроизводит раздачу")
	var exposed := view(g, 0, true)
	var before := snapshot(g)
	exposed.hand[0] = -999
	exposed.chips[0] = 999
	exposed.community.append(999)
	exposed.history[0][0] = 999
	exposed.players[0].color.id = -999
	exposed.log.clear()
	check(snapshot(g) == before, "Все вложенные поля view — независимые глубокие копии")
	var input := members(3)
	g.call("new_game", input, 555)
	input[0].name = "Изменено снаружи"
	input[0].color.id = -999
	check(g.players[0].name == "Игрок0" and g.players[0].color.id == 0, "Метаданные входных игроков не связаны с состоянием")
	var old_revision: int = g.revision
	var old_turn: int = g.turn_no
	g.call("new_game", members(3), 555)
	check(g.revision > old_revision and g.turn_no > old_turn, "Перезапуск того же экземпляра не возвращает revision/turn_no назад")
	rejected(g, 0, "take", {"value": 1, "revision": old_revision}, "Пакет предыдущей партии не действует после new_game")
	for count in [0, 2, 11]:
		g.call("new_game", members(count), 55)
		check(g.phase != "rank" and g.hands.is_empty(), "Неверное число игроков%d не создаёт активную раздачу" % count)

func _initialize() -> void:
	poker = load("res://games/the_gang/logic/tg_poker.gd")
	rules = load("res://games/the_gang/logic/tg_rules.gd")
	if poker == null or rules == null:
		check(false, "Production-файлы medium отсутствуют/не загружены; это не успешный прогон")
		quit(1)
		return
	for method: String in ["poker_cases", "round_and_timeout", "chip_actions_and_revisions", "showdown_rules", "terminal_games", "copies_and_determinism"]:
		var before_checks := checks
		var before_errors := errors
		call(method)
		sections[method] = {"checks": checks - before_checks, "errors": errors - before_errors}
		print("THE GANG REVIEW РАЗДЕЛ ", method, ": ", sections[method])
		if errors:
			break
	print("THE GANG REVIEW: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
