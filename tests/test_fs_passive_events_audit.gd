extends SceneTree
## Второй этап аудита: события, контрольные условия и ручное исполнение пассивов.
## Dummy + отдельный APPDATA. Код 1 означает реальные расхождения, код 2 — ошибку подготовки.
var observations: Array = []
var setup_errors: Array = []

func make(id: int, owner: int = 0) -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], true, 2610)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.phase = "turn"
	g.items = [[], []]
	g.items[owner] = [FSData.item_entry(id)]
	g.chars = [821, 823]
	g.hands = [[], []]
	g.hp = [6, 6]
	g.max_hp = [6, 6]
	g.attack = [1, 1]
	g.coins = [3, 3]
	g.bank = 94
	g.souls = [0, 0]
	g.soul_cards = [[], []]
	g.curses = [[], []]
	g.monsters = [{"id": 450, "hp": 6, "dc": 4, "at": 1}]
	g.bonuses.clear()
	g.room = -1
	return g

func record(id: int, action: String, expected, actual, category: String = "automatic_event") -> void:
	observations.append({"id": id, "name": FSData.title(id), "action": action,
		"expected": expected, "actual": actual, "matches": expected == actual, "category": category})

func require(ok: bool, message: String) -> void:
	if not ok:
		setup_errors.append(message)

func manual(g: FSRules, id: int, owner: int = 0) -> void:
	if g.phase == "effect":
		require(g.action(int(g.resolving.owner), "effect_done"), "Закрытие предыдущего эффекта " + str(id))
	require(g.action(owner, "activate", {"item": 0, "tap": false}), "Открытие пассива " + str(id))
	g._finish_responses()
	require(g.phase == "effect" and int(g.resolving.card) == id, "Источник ручного эффекта " + str(id))

func apply(g: FSRules, op: String, amount: int, target: int = 0, item: int = 0) -> void:
	require(g.action(int(g.resolving.owner), "effect", {
		"op": op, "amount": amount, "target": target, "item": item}), "Ручная операция " + op)
	g._finish_responses()

func roll_effect(g: FSRules, face: int, roller: int = 0) -> void:
	# Фиксируется грань, а не итог пассива: используется настоящий обработчик разрешения броска.
	g.stack = [{"kind": "effect_roll", "owner": roller, "value": face}]
	g.paused_effects = [{"effect": {"kind": "item", "card": 13, "owner": roller},
		"resume": "turn", "peek": {}, "roller": roller}]
	g.phase = "priority"
	g._resolve_top()
	g._finish_responses()
	require(g.last_roll == face, "Разрешена заданная грань")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Начало хода, пороги жетонов и обязательные награды.
	for counter in [0, 1, 3, 5]:
		var g := make(45)
		g.items[0][0].counters = counter
		g._begin_turn()
		g._finish_responses()
		record(45, "Начало хода: жетоны " + str(counter) + " → " + str(counter + 1), counter + 1, g.items[0][0].counters)
		if counter == 1:
			record(45, "Второй жетон даёт десять монет", 13, g.coins[0])
		if counter == 3:
			record(45, "Четвёртый жетон даёт четыре лута сверх обычного добора", 5, g.hands[0].size())
		if counter == 5:
			record(45, "Шестой жетон даёт два сокровища", 3, g.items[0].size())
	for gap in [0, 2]:
		var g := make(90)
		g.souls[1] = gap
		g._begin_turn()
		g._finish_responses()
		record(90, "Добор с отставанием по душам " + str(gap), 1 + gap, g.hands[0].size())
	var g := make(58)
	g.hands[0] = [475, 476, 477]
	g.items[0].clear()
	g.decks.treasure.erase(58)
	g.decks.treasure.append(58)
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	apply(g, "treasure", 1)
	record(58, "Получить Каменное дно с тремя картами в руке", 3, g.items[0][0].counters)
	# Обе стороны условий в конце хода: совпадение отрицательной ветки не подтверждает весь пассив.
	for value in [0, 1]:
		g = make(161)
		g.coins[0] = value
		g.bank = 97 - value
		g._end_turn()
		g._finish_responses()
		record(161, "Конец хода с монетами " + str(value), 6 if value == 0 else value, g.coins[0])
	for pair in [[240, 7], [240, 8], [250, 0], [250, 1], [58, 2], [58, 3]]:
		var id: int = pair[0]
		var count: int = pair[1]
		g = make(id)
		for i in count:
			g.hands[0].append(475 + i)
		if id == 58:
			g.items[0][0].counters = 3
		var draws: bool = (id == 240 and count >= 8) or (id == 250 and count == 0) or (id == 58 and count < 3)
		g._end_turn()
		g._finish_responses()
		record(id, "Конец хода с рукой " + str(count), count + (2 if draws else 0), g.hands[0].size())
	g = make(56)
	g._end_turn()
	g._finish_responses()
	record(56, "Запас батареек получает жетон в конце своего хода", 1, g.items[0][0].counters)
	# Результат любого игрока; отдельный контроль несовпадающей грани.
	for definition in [[165, 5, "coins", 3], [231, 1, "loot", 1], [857, 6, "coins", 2],
		[55, 1, "counter", 1], [85, 2, "counter", 1], [42, 3, "own_roll", 1]]:
		var id: int = definition[0]
		var face: int = definition[1]
		var kind: String = definition[2]
		var amount: int = definition[3]
		for roller in [0, 1]:
			for matching in [true, false]:
				# Слёзы Исаака срабатывают на любой собственный бросок, а не на чужой.
				if kind == "own_roll" and not matching:
					continue
				g = make(id)
				roll_effect(g, face if matching else (4 if face != 4 else 3), roller)
				var active: bool = matching and (kind != "own_roll" or roller == 0)
				var expected: int = (3 if kind == "coins" else 0) + (amount if active else 0)
				var actual: int = g.coins[0] if kind == "coins" else (g.hands[0].size() if kind == "loot" else g.items[0][0].counters)
				record(id, "Бросок игрока %d: %d" % [roller, g.last_roll], expected, actual)
	# Урон — одно событие, а не число потерянных единиц здоровья.
	for id in [180, 223, 677]:
		for amount in [1, 2]:
			g = make(id)
			g._damage_player(0, amount)
			g._finish_responses()
			var actual: int = g.items[0][0].counters if id == 180 else (g.hands[0].size() if id == 223 else g.coins[0])
			record(id, "Один источник наносит " + str(amount) + " урона", 4 if id == 677 else 1, actual)
		g = make(id)
		g._damage_player(1, 1)
		g._finish_responses()
		var actual: int = g.items[0][0].counters if id == 180 else (g.hands[0].size() if id == 223 else g.coins[0])
		record(id, "Урон другому игроку не активирует личный пассив", 3 if id == 677 else 0, actual)
	# Два однозначных модификатора получения монет/карт.
	for amount in [1, 3]:
		g = make(675)
		g._gain_coins(0, amount)
		g._finish_responses()
		record(675, "Получить " + str(amount) + " монет с Поддельным пенни", 4 + amount, g.coins[0])
		g = make(137)
		g._gain_coins(1, amount)
		g._finish_responses()
		record(137, "Другой игрок получает " + str(amount) + " монет: Магнит", [4, 2 + amount], g.coins)
	g = make(527)
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	apply(g, "loot", 2)
	record(527, "Взять два лута по эффекту вне шага добора", 3, g.hands[0].size())
	g = make(527)
	g._begin_turn()
	g._finish_responses()
	record(527, "Счастливый палец не увеличивает обычный шаг добора", 1, g.hands[0].size())
	g = make(237)
	g.items[0].append(FSData.item_entry(13))
	require(g.action(0, "activate", {"item": 1, "tap": true}), "Активация другого предмета")
	g._finish_responses()
	record(237, "Активация предмета даёт монету Сияющего камня", 4, g.coins[0])
	# Уничтожение и смерть — источник должен существовать в момент своего триггера.
	g = make(505)
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	apply(g, "destroy", 1)
	record(505, "Кость желаний заменяется сокровищем при уничтожении", 1, g.items[0].size())
	for id in [47, 184]:
		g = make(id)
		g.monsters[0].hp = 0
		g._continue_stack()
		g._finish_responses()
		require(g.phase == "effect" and g.resolving.kind == "reward", "Смерть монстра открывает награду")
		record(id, "Смерть монстра активирует пассив до завершения награды", 1 if id == 47 else 6,
			g.items[0][0].counters if id == 47 else g.coins[0])
	for id in [654, 857]:
		g = make(id, 1)
		g.hp[0] = 0
		g._check_deaths()
		g._finish_responses()
		require(g.phase == "death" and g.actor() == 0, "Открыт штраф смерти другого игрока")
		record(id, "Чужая смерть: взять лут до штрафа", 1, g.hands[1].size())
	# Подтверждение рабочих обходов: не только открытие панели, но изменение и откат состояния.
	for definition in [[165, "coins", 3], [231, "loot", 1], [55, "counter", 1],
		[180, "counter", 1], [223, "loot", 1], [677, "coins", 1], [45, "counter", 1]]:
		var id: int = definition[0]
		var op: String = definition[1]
		var amount: int = definition[2]
		g = make(id)
		g.current = 0 if id == 45 else 1
		manual(g, id)
		var repeated := g.action(0, "effect", {"op": op, "amount": amount})
		record(id, "Автоматический эффект нельзя повторить ручной операцией", false, repeated, "manual_workaround")
	g = make(97)
	manual(g, 97)
	apply(g, "temporary_attack", 1)
	record(97, "Вручную применить бонус Мёртвого глаза до конца хода", 2, g.attack[0], "manual_workaround")
	require(g.action(0, "effect_done"), "Закрытие Мёртвого глаза")
	require(g.action(0, "end"), "Завершение хода с временной атакой")
	record(97, "Временная атака снимается после хода", 1, g.attack[0], "manual_workaround")
	# Ручной постоянный бонус не связан с карточкой: проверяем уход источника.
	for method in ["destroy", "give_item", "steal"]:
		g = make(16)
		manual(g, 16)
		require(not g.action(0, "effect", {"op": "attack", "amount": 1}), "Защита от повторения постоянного бонуса")
		if method == "steal":
			g.resolving = {"kind": "item", "card": 13, "owner": 1}
			apply(g, method, 1, 0)
		else:
			apply(g, method, 1, 1 if method == "give_item" else 0)
		record(16, "Уход источника постоянного бонуса: " + method, [1, 1] if method == "destroy" else [1, 2], g.attack, "source_lifecycle")
	# Зарегистрированные персонажи: настоящая раздача с DLC и неизменёнными колодами.
	# Числа здоровья с изображений персонажей; свойства случайного стартового предмета Эдема — отдельный аудит.
	var seen: Dictionary = {}
	var registered: Array = FSData.characters(true)
	for card: Dictionary in FSData.data().cards:
		if card.kind == "character":
			var present: bool = registered.any(func(character): return int(character.card) == int(card.id))
			record(int(card.id), "Карта персонажа доступна в составе с DLC", true, present, "character_availability")
	for seed_value in range(1, 501):
		g = FSRules.new()
		g.new_game([{"name": "А"}, {"name": "Б"}], true, seed_value)
		preload("res://tests/fs_test_setup.gd").finish(g)
		g._finish_responses()
		for seat in g.players.size():
			var id: int = g.chars[seat]
			if seen.has(id):
				continue
			seen[id] = true
			var printed_health: int = 1 if id in [848, 866, 884] else (3 if id == 908 else 2)
			var starting_health_bonus := 0
			for item: Dictionary in g.items[seat]:
				starting_health_bonus += int(item.get("_health_bonus", 0))
			record(id, "Реальная раздача DLC: здоровье персонажа и стартового предмета", printed_health + starting_health_bonus, g.max_hp[seat], "character_setup")
			var turn_draw: int = (1 + g._has_item(seat, "guppystail")) if g.current == seat else 0
			record(id, "Реальная раздача DLC: начальная рука с учётом первого добора", (5 if id == 908 else 3) + turn_draw,
				g.hands[seat].size(), "character_setup")
		if seen.size() == registered.size():
			break
	require(seen.size() == registered.size(), "Все зарегистрированные персонажи реально встретились при раздаче")
	var mismatches := observations.filter(func(row): return not row.matches).size()
	var output := FileAccess.open("res://build/fs_passive_audit/followup/runtime_events.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"observations": observations, "mismatches": mismatches,
		"setup_errors": setup_errors}, "\t"))
	output.close()
	print("PASSIVE EVENTS: ", observations.size(), " сценариев, расхождений ", mismatches,
		", ошибок подготовки ", setup_errors.size())
	for error in setup_errors:
		push_error(error)
	quit(2 if not setup_errors.is_empty() else (1 if mismatches else 0))
