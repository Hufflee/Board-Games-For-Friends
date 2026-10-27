## Независимые интеграции общего guard recharge со старыми пассивами6/830.
## Полные локальные карты просмотрены:6 — одна выплата≥3;830 — урон владельцу;830 вечный.
## Подготовленные состояния seed26; --headless --audio-driver Dummy --script res://tests/test_fs_charge_lifecycle_review.gd.
extends "res://tests/test_fs_charge_lifecycle_next.gd"

func setup(id: int) -> FSRules:
	var g := fixture()
	g.hp = [5, 5]
	g.max_hp = [5, 5]
	g._gain_item(0, id)
	g.items[0][0].tapped = true
	return g

func trigger(g: FSRules, id: int, owner: int = 0) -> void:
	# Настоящие серверные события, не прямая очередь операции recharge.
	if id == 6:
		g._gain_coins(owner, 3)
	else:
		g._damage_player(owner, 1)

func live_copies(id: int) -> void:
	var g := setup(id)
	g._gain_item(0, id)
	g._gain_item(1, id)
	g.items[0][1].tapped = true
	g.items[1][0].tapped = true
	trigger(g, id)
	check(g.items[0][0].tapped and g.items[0][1].tapped, "%d: зарядка ждёт настоящую очередь" % id)
	check(g.stack.filter(func(entry): return entry.kind == "passive" and int(entry.card) == id).size() == 2,
		"%d: только две собственные копии получили событие" % id)
	g._finish_responses()
	check(not g.items[0][0].tapped and not g.items[0][1].tapped and g.items[1][0].tapped,
		"%d: обе живые копии заряжены, чужая не затронута" % id)
	check(not g.get_view(1).players[0].items[0].tapped and g.get_view(0).players[1].items[0].tapped,
		"%d: view отражает независимую зарядку источников" % id)

func miner_transfer() -> void:
	var g := setup(6)
	g._gain_item(0, 13)
	var source: Dictionary = g.items[0][0]
	trigger(g, 6)
	check(g.action(0, "activate", {"item": 1}), "6: настоящий ответ на ожидающую зарядку")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "6: источник передан до зарядки")
	check(g.action(0, "effect_done", {}), "6: передача завершена")
	g._finish_responses()
	check(g.current == 0 and is_same(source, g.items[1][0]) and not source.tapped,
		"6: тот же источник у нового владельца заряжен без начала его хода")
	check(g.items[0].size() == 1 and int(g.items[0][0].id) == 13, "6: исходный инвентарь не сохранил копию")

func miner_replacement() -> void:
	var g := setup(6)
	g._gain_item(0, 13)
	var removed: Dictionary = g.items[0][0]
	trigger(g, 6)
	check(g.action(0, "activate", {"item": 1}), "6: настоящий ответ уничтожением")
	g._resolve_top()
	check(g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "6: источник старого триггера ушёл")
	# Новая копия получена реальной операцией treasure в том же ручном ответе.
	g.decks.treasure.erase(6)
	g.decks.treasure.append(6)
	check(g.action(0, "effect", {"op": "treasure", "target": 0, "amount": 1}), "6: получена новая копия того же ID")
	var replacement: Dictionary = g.items[0][1]
	# Подготовлено уже использованное состояние новой копии; активный бросок6 здесь не проверяется.
	replacement.tapped = true
	check(g.action(0, "effect_done", {}), "6: уничтоживший ответ завершён")
	g._finish_responses()
	check(removed.tapped and replacement.tapped, "6: старый триггер не заряжает ушедший объект или замену")
	check(not is_same(removed, replacement), "6: новая копия является другим объектом")
	check(not g._source_item_in_play(removed) and g._source_item_in_play(replacement),
		"6: guard различает уход и живую замену с тем же ID")

func eternal_source_stays() -> void:
	var g := setup(830)
	g._gain_item(0, 13)
	var source: Dictionary = g.items[0][0]
	trigger(g, 830)
	check(g.hp == [4, 5], "830: произошло реальное получение1 урона")
	check(g.action(0, "activate", {"item": 1}), "830: ответ над ожидающей зарядкой")
	g._resolve_top()
	check(not g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "830: вечный источник не переносится обычным give_item")
	check(not g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "830: вечный источник не уничтожается обычным destroy")
	check(g.action(0, "effect_done", {}), "830: ответ завершён")
	g._finish_responses()
	check(not source.tapped and is_same(source, g.items[0][0]), "830: неуспешное удаление не гасит законную зарядку")
	check(g.hp == [4, 5], "830: очередь зарядки не повторяет урон")

func negative_events() -> void:
	var g := setup(6)
	for amount in [2, 1]:
		g._gain_coins(0, amount)
		g._finish_responses()
	check(g.items[0][0].tapped, "6: выплаты2+1 не стали одной выплатой3")
	trigger(g, 6, 1)
	g._finish_responses()
	check(g.items[0][0].tapped, "6: чужая выплата3 не заряжает владельца0")
	g = setup(830)
	trigger(g, 830, 1)
	g._finish_responses()
	check(g.items[0][0].tapped and g.hp == [5, 4], "830: чужой урон не заряжает владельца0")

func _initialize() -> void:
	for id in [6, 830]:
		live_copies(id)
	miner_transfer()
	miner_replacement()
	eternal_source_stays()
	negative_events()
	print("CHARGE LIFECYCLE REVIEW: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
