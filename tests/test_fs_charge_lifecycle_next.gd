## Зарядка22/44/60/84/822/824: ожидания с полных изображений и правил, не из FSData.
## Подготовленные состояния seed26; --headless --audio-driver Dummy --script res://tests/test_fs_charge_lifecycle_next.gd.
## Активные эффекты22/60 и полная семантика других активных способностей здесь не проверяются.
extends "res://tests/test_fs_mixed_next.gd"

var observations: Array = []

func record(id: int, scenario: String, expected: Variant, actual: Variant) -> void:
	var same: bool = expected == actual
	observations.append({"id": id, "scenario": scenario, "expected": expected, "actual": actual, "matches": same})
	print("ЗАРЯДКА ", id, ": ", scenario, " | ожидание=", expected, " | факт=", actual)
	check(same, "%d: %s" % [id, scenario])

func fixture(current: int = 0) -> FSRules:
	var g := clean()
	g.current = current
	g.monsters.clear()
	g.hands = [[], []]
	g.coins = [20, 20]
	g.bank = 60
	g.room = -1
	g.curses = [[], []]
	g.next_action = {}
	g._ending_turn = false
	g._end_discard_prepared = false
	return g

## Подготовленная ручная способность13 даёт доступ к штатным операциям получения/передачи.
func manual(g: FSRules, owner: int = 0, card: int = 13) -> void:
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": card, "owner": owner}
	g._after_stack = "turn"

func end(g: FSRules) -> bool:
	var accepted: bool = g.action(g.current, "end", {})
	check(accepted, "Подготовка: настоящий action end принят")
	if accepted:
		g._finish_responses()
	return accepted

func entry_paths(id: int) -> void:
	for method: String in ["purchase", "peek"]:
		var g := fixture()
		if method == "purchase":
			g.shop = [id]
			check(g.action(0, "buy", {"slot": 0}), "Подготовка: настоящая покупка%d" % id)
			g._finish_responses()
		else:
			manual(g)
			g.decks.treasure.erase(id)
			g.decks.treasure.append(id)
			check(g.action(0, "effect", {"op": "peek_treasure", "amount": 1}), "Подготовка: просмотр сокровища")
			check(g.action(0, "peek_take", {"card": id, "dest": "item"}), "Подготовка: предмет взят из просмотра")
			check(g.action(0, "effect_done", {}), "Подготовка: завершён просмотр")
		if g.items[0].size() != 1:
			check(false, "Подготовка: получен ровно один предмет")
			return
		var source: Dictionary = g.items[0][0]
		record(id, "Новая копия входит повёрнутой: " + method, true, source.tapped)
		record(id, "Входная зарядка передана в view: " + method, true, g.get_view(0).players[0].items[0].tapped)
		record(id, "Поворотная активация сразу после входа запрещена: " + method,
			false, g.action(0, "activate", {"item": 0}))
		if not end(g):
			return
		record(id, "Конец своего хода не даёт особой перезарядки: " + method, true, source.tapped)
		if not end(g):
			return
		record(id, "Обычный старт следующего собственного хода заряжает: " + method, false, source.tapped)
	# Смена контролирующего игрока не является новым входом в игровую зону.
	for tapped: bool in [false, true]:
		var g := fixture()
		g._gain_item(0, id)
		var source: Dictionary = g.items[0][0]
		source.tapped = tapped
		manual(g)
		check(g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Подготовка: передача%d" % id)
		check(g.action(0, "effect_done", {}), "Подготовка: передача завершена")
		record(id, "Передача сохраняет заряд, без повторного входа; tapped=%s" % tapped,
			[tapped, 0, 1], [g.items[1][0].tapped, g.items[0].size(), g.items[1].size()])
		end(g)
		record(id, "Начало хода нового владельца заряжает переданную копию", false, source.tapped)
	var g := fixture()
	g._gain_item(0, id)
	var gone: Dictionary = g.items[0][0]
	gone.tapped = false
	manual(g)
	check(g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "Подготовка: уничтожена старая копия")
	check(g.action(0, "effect_done", {}), "Подготовка: уничтожение завершено")
	g.shop = [id]
	check(g.action(0, "buy", {"slot": 0}), "Подготовка: куплена новая копия после ухода")
	g._finish_responses()
	if g.items[0].is_empty():
		check(false, "Подготовка: новая копия существует")
		return
	record(id, "Новый вход после уничтожения не наследует готовность старой копии",
		[false, true], [gone.tapped, g.items[0][0].tapped])

func turn_recharge(id: int) -> void:
	# Три игрока отделяют конец чужого хода от немедленного начала собственного.
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.chars = [839, 839, 839]
	g.items = [[], [], []]
	g.hands = [[], [], []]
	g.monsters.clear()
	g.room = -1
	g.curses = [[], [], []]
	g.bonuses.clear()
	g.stack.clear()
	g.resolving = {}
	g.next_action = {}
	g.phase = "turn"
	for owner in [0, 0, 2]:
		g._gain_item(owner, id)
	for source: Dictionary in g.items[0] + g.items[2]:
		source.tapped = true
	var own: Dictionary = g.items[0][0]
	var second: Dictionary = g.items[0][1]
	var foreign: Dictionary = g.items[2][0]
	if not end(g):
		return
	record(id, "Конец собственного хода заряжает обе копии, чужая копия не тронута",
		[false, false, true, 1], [own.tapped, second.tapped, foreign.tapped, g.current])
	# Подготовленная разрядка после собственного конца, в течение хода игрока1.
	own.tapped = true
	second.tapped = true
	if not end(g):
		return
	record(id, "Конец чужого хода1 не заряжает владельца0; обычный старт2 заряжает владельца2",
		[true, true, false, 2], [own.tapped, second.tapped, foreign.tapped, g.current])
	if not end(g):
		return
	record(id, "Старт собственного хода0 заряжает обе копии независимо от конца", [false, false], [own.tapped, second.tapped])
	var h := fixture()
	h._gain_item(0, id)
	var source: Dictionary = h.items[0][0]
	source.tapped = true
	manual(h)
	if id == 84:
		check(h.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Подготовка: передача84")
		check(h.action(0, "effect_done", {}), "Подготовка: передача84 завершена")
		# Третий игрок здесь не нужен: новый владелец ещё не начал ход в момент передачи.
		record(id, "Переданный источник остаётся повёрнутым до разрешённого шага нового владельца", true, source.tapped)
	else:
		record(id, "Обычная передача напечатанного вечного источника запрещена", false,
			h.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}))
		record(id, "Уничтожение вечного источника обычным эффектом запрещено", false,
			h.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}))
	if id == 84:
		var removal := fixture()
		removal._gain_item(0, id)
		var removed: Dictionary = removal.items[0][0]
		removed.tapped = true
		manual(removal)
		check(removal.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "Подготовка:84 ушла из игры")
		check(removal.action(0, "effect_done", {}), "Подготовка: удаление84 завершено")
		end(removal)
		record(id, "Ушедший источник84 не получает перезарядку в конце хода", true, removed.tapped)

func battery() -> void:
	var g := fixture()
	g._gain_item(0, 44)
	g._gain_item(0, 44)
	var first: Dictionary = g.items[0][0]
	var second: Dictionary = g.items[0][1]
	record(44, "Новые Аккумуляторы входят готовыми, запрет зарядки не означает повёрнутый вход",
		[false, false], [first.tapped, second.tapped])
	first.tapped = true
	second.tapped = true
	end(g)
	record(44, "Конец собственного хода не заряжает ни одну копию", [true, true], [first.tapped, second.tapped])
	end(g)
	record(44, "Обычный старт собственного хода не обходит запрет обеих копий", [true, true], [first.tapped, second.tapped])
	manual(g)
	record(44, "Чужой источник13 не заряжает первую копию", false,
		g.action(0, "effect", {"op": "recharge", "target": 0, "item": 0}))
	record(44, "Отказ не меняет заряд второй копии", [true, true], [first.tapped, second.tapped])
	check(g.action(0, "effect_done", {}), "Подготовка: ручной источник завершён")
	# Разрешённый платный путь явно отделён от автоматической зарядки и от поворотной способности.
	check(g.action(0, "activate", {"item": 0, "tap": false}), "Подготовка: платная способность44 открыта без поворота")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "pay_coins", "amount": 7}), "Собственная способность44: оплачены7 монет")
	check(g.action(0, "effect", {"op": "recharge", "target": 0, "item": 0}), "Собственная способность44 зарядила источник")
	record(44, "Оплаченная собственная зарядка затрагивает выбранную копию, не вторую",
		[false, true, 13, 67], [first.tapped, second.tapped, g.coins[0], g.bank])
	check(g.action(0, "effect_done", {}), "Подготовка: платная способность завершена")
	# Проверяем доступную законную часть поворотной способности: другой предмет, не сам44.
	g._gain_item(0, 84)
	g.items[0][2].tapped = true
	check(g.action(0, "activate", {"item": 0}), "Подготовка: готовый44 повёрнут")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "recharge", "target": 0, "item": 2}), "44 заряжает другой предмет84")
	record(44, "Поворотная способность зарядила другой предмет и оставила сам44 повёрнутым",
		[true, true, false], [first.tapped, second.tapped, g.items[0][2].tapped])
	check(g.action(0, "effect_done", {}), "Подготовка: поворотная способность завершена")
	manual(g)
	check(g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Подготовка: повёрнутый44 передан")
	check(g.action(0, "effect_done", {}), "Подготовка: передача44 завершена")
	end(g)
	record(44, "Смена владельца и его обычный старт не обходят запрет зарядки", true, first.tapped)
	record(44, "View нового владельца показывает фактическое состояние44", true, g.get_view(1).players[1].items[0].tapped)

## Официальный порядок конца: триггеры конца → сброс лишних карт, а не наоборот.
func recharge_before_discard() -> void:
	var g := fixture()
	g._gain_item(0, 84)
	var source: Dictionary = g.items[0][0]
	source.tapped = true
	g.hands[0].resize(11)
	g.hands[0].fill(475)
	if not end(g):
		return
	record(84, "Собственная перезарядка конца хода уже разрешена при ожидании обязательного сброса11→10",
		["discard", 0, false, false],
		[g.phase, g.current, source.tapped, g.get_view(0).players[0].items[0].tapped])

func _initialize() -> void:
	for id in [22, 60]:
		entry_paths(id)
		if errors:
			break
	if not errors:
		for id in [84, 822, 824]:
			turn_recharge(id)
			if errors:
				break
	if not errors:
		battery()
	if not errors:
		recharge_before_discard()
	var output := FileAccess.open("res://build/fs_passive_registry/runtime_charge_lifecycle.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"observations": observations, "checks": checks, "errors": errors,
		"scope": "Только описанные свойства зарядки и жизненного цикла, не полные активные способности"}, "\t"))
	output.close()
	print("CHARGE LIFECYCLE NEXT: ", observations.size(), " наблюдений, ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)

