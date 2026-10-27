extends SceneTree
## Аудит: отдельно доступность ручной панели и соответствие напечатанным пассивам.
## Dummy + отдельный APPDATA. Известные несоответствия сохраняются, а не объявляются пройденными тестами.
var results: Array = []
var routes: Array = []
var setup_errors := 0

func make() -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.items = [[], []]
	g.hp = [2, 2]
	g.max_hp = [2, 2]
	g.attack = [1, 1]
	g.monsters.clear()
	g.bonuses.clear()
	return g

func entry(id: int) -> Dictionary:
	return {"id": id, "tapped": false, "eternal": FSData.card(id).kind == "eternal", "counters": 0}

func record(id: int, action: String, expected, actual, category: String = "text") -> void:
	results.append({"id": id, "name": FSData.title(id), "action": action,
		"expected": expected, "actual": actual, "matches": expected == actual, "category": category})

func obtain(id: int) -> FSRules:
	var g := make()
	if FSData.card(id).kind == "loot":
		g.hands[0].append(id)
		if not g.action(0, "loot", {"card": id}):
			setup_errors += 1
		g._finish_responses()
	else:
		g.phase = "effect"
		g.resolving = {"kind": "item", "card": 0, "owner": 0}
		g.decks.treasure.erase(id)
		g.decks.treasure.append(id)
		if not g.action(0, "effect", {"op": "treasure", "target": 0, "amount": 1}):
			setup_errors += 1
	g._finish_responses()
	return g

func combat(id: int, face: int, hit: bool = false) -> FSRules:
	var g := make()
	g.items[0].append(entry(id))
	g.hp = [5, 5]
	g.max_hp = [5, 5]
	# Защита 7 достижима модификаторами; шестёрка здесь тоже объявленный промах.
	g.monsters = [{"id": 450, "hp": 5, "dc": 1 if hit else 7, "at": 1}]
	g.battle = 0
	g.phase = "priority"
	g.stack = [{"kind": "roll", "owner": 0, "value": face}]
	g._after_stack = "battle_roll"
	g._finish_responses()
	return g

func manual_probe(id: int, op: String, target: int = 0, index: int = 0) -> void:
	var g := make()
	g.items[0].append(entry(id))
	g.monsters = [{"id": 450, "hp": 2, "dc": 3, "at": 1}]
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": id, "owner": 0}
	if op in ["give_loot", "swap_items"]:
		target = 1
		g.items[1] = [entry(16)]
	if op == "set_roll":
		g.stack = [{"kind": "roll", "owner": 0, "value": 2}]
	var accepted := g.action(0, "effect", {"op": op, "target": target, "item": index, "amount": 1})
	record(id, "Ручная операция " + op, true, accepted, "manual_operation")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/response_catalog.json")).cards
	for card: Dictionary in FSData.data().cards:
		var id: int = card.id
		if catalog[id].response_kind != "passive" and not (card.kind == "loot" and card.lua.get("type", "") == "trinkets"):
			continue
		var g := make()
		g.current = 1
		g.items[0].append(entry(id))
		var hand_before: Array = g.hands[0].duplicate()
		var ready_before: bool = g.character_ready[0]
		var free_before := g.free_loot
		var accepted := g.action(0, "activate", {"item": 0, "tap": false})
		g._finish_responses()
		var accessible := accepted and g.phase == "effect" and int(g.resolving.card) == id and g.actor() == 0
		var no_cost: bool = not g.items[0][0].tapped and g.hands[0] == hand_before and g.character_ready[0] == ready_before and g.free_loot == free_before
		routes.append({"id": id, "manual_access": accessible, "without_activation_cost": no_cost})
		if not accessible or not no_cost:
			setup_errors += 1
	# Постоянные характеристики проверяются через настоящее получение сокровища/брелока.
	for pair in [[39, 1], [79, 1], [88, 2], [112, 1], [147, 2], [174, 1], [249, 1]]:
		var g := obtain(int(pair[0]))
		record(int(pair[0]), "Получить предмет: максимальное здоровье", 2 + int(pair[1]), g.max_hp[0])
	for pair in [[16, 1], [28, 1], [41, 1], [108, 1], [124, 3], [143, 2], [230, 1], [234, 1], [254, 1], [471, 1], [652, 1]]:
		var g := obtain(int(pair[0]))
		record(int(pair[0]), "Получить предмет: постоянная атака", 1 + int(pair[1]), g.attack[0])
	for id in [24, 25, 26, 117, 254, 877]:
		var g := make()
		g.items[0].append(entry(id))
		g._begin_turn()
		g._finish_responses()
		record(id, "Начать ход с дополнительными атаками", 99 if id == 117 else 2, g.attack_left)
	for id in [105, 173]:
		var g := make()
		g.items[0].append(entry(id))
		g._begin_turn()
		g._finish_responses()
		record(id, "Начать ход с дополнительной покупкой", 2, g.buy_left)
	for id in [221, 226]:
		var g := make()
		g.items[0].append(entry(id))
		g._begin_turn()
		g._finish_responses()
		record(id, "Начать ход с дополнительным розыгрышем лута", 2, g.free_loot)
	for id in [121, 196, 200]:
		var g := make()
		g.items[0].append(entry(id))
		g.hands[0].clear()
		g._begin_turn()
		g._finish_responses()
		record(id, "Дополнительный лут в шаге добора", 2, g.hands[0].size())
	for id in [76, 229, 473]:
		var g := make()
		g.items[0].append(entry(id))
		g.coins[0] = 5 if id == 229 else 9
		record(id, "Купить предмет по напечатанной скидке", true, g.action(0, "buy", {"slot": 0}))
	for pair in [[30, 1], [31, 2], [32, 3], [71, 1], [71, 6], [92, 3], [112, 4], [115, 1]]:
		var g := combat(int(pair[0]), int(pair[1]))
		record(int(pair[0]), "Не получить боевой урон на " + str(pair[1]), 5, g.hp[0])
	var g := combat(74, 6, true)
	record(74, "Шестёрка удваивает наносимый боевой урон", 3, g.monsters[0].hp)
	g = combat(74, 1)
	record(74, "Единица удваивает получаемый боевой урон", 3, g.hp[0])
	for pair in [[164, 3, 1], [514, 2, 0], [214, 1, 2]]:
		g = make()
		g.hp[0] = 5
		g.max_hp[0] = 5
		g.items[0].append(entry(int(pair[0])))
		g._damage_player(0, int(pair[1]))
		record(int(pair[0]), "Изменение входящего небоевого урона", 5 - int(pair[2]), g.hp[0])
	g = make()
	g.items[0].append(entry(72))
	g.current = 1
	g._damage_player(0, 1)
	record(72, "Не получить урон вне своего хода", 2, g.hp[0])
	g = make()
	g.items[0].append(entry(128))
	var v := g.get_view(0)
	record(128, "Видеть открытую чужую руку по Глазу Гаппи", true, v.players[1].has("hand"))
	g = make()
	g.items[0].append(entry(138))
	g.character_ready[0] = false
	g._begin_turn()
	g._finish_responses()
	record(138, "Мама-преследователь запрещает перезарядку персонажа", false, g.character_ready[0])
	g = make()
	g.items[0].append(entry(256))
	g.hands[1] = [475]
	record(256, "Щит триединства запрещает чужой лут", false, g.action(1, "loot", {"card": 475}))
	g = make()
	g.items[0].append(entry(256))
	g.items[1].append(entry(16))
	record(256, "Щит триединства запрещает чужую активацию", false, g.action(1, "activate", {"item": 0, "tap": false}))
	for pair in [[141, "deactivate"], [243, "item_to_soul"], [57, "give_loot"], [186, "discard_loot"], [62, "expand_shop"], [15, "temporary_monster_dc"], [98, "set_roll"], [128, "reveal_hand"], [212, "swap_items"], [215, "discard_monster"], [222, "discard_shop"]]:
		manual_probe(int(pair[0]), str(pair[1]))
	for id in [69, 503]:
		g = obtain(id)
		record(id, "Напечатанный вечный предмет сохраняет признак вечности", true, g.items[0].back().eternal)
		g.phase = "effect"
		g.resolving = {"kind": "item", "card": 0, "owner": 0}
		record(id, "Вечный предмет нельзя уничтожить обычной операцией", false, g.action(0, "effect", {"op": "destroy", "target": 0, "item": g.items[0].size() - 1}))
	# Предмет остаётся у владельца: защита не зависит от спорного порядка его уничтожения.
	g = make()
	g.current = 1
	g.items[0] = [entry(523), entry(16)]
	g.hp[0] = 0
	g._check_deaths()
	g._finish_responses()
	var coins_before: int = g.coins[0]
	var cards_before: int = g.hands[0].size()
	g.action(0, "death", {"loot": g.hands[0][0], "item": 1})
	record(523, "Ребро алчности сохраняет монеты при штрафе смерти", coins_before, g.coins[0])
	record(523, "Ребро алчности сохраняет лут при штрафе смерти", cards_before, g.hands[0].size())
	g = make()
	g.current = 1
	g.items[0] = [entry(838)]
	g.hp[0] = 0
	g._check_deaths()
	g._finish_responses()
	g.action(0, "death", {"loot": g.hands[0][0], "item": -1})
	g._finish_responses()
	record(838, "Лохмотья Лазаря автоматически выдают сокровище после штрафа", 2, g.items[0].size())
	# Комнаты и проклятия: те же обычные игровые переходы, без ручных поправок.
	for id in [707, 705, 737]:
		g = make()
		g.curses[0] = [id]
		g.monsters = [{"id": 450, "hp": 2, "dc": 3, "at": 1}]
		g._begin_turn()
		g._finish_responses()
		var observed: int = g.hp[0] if id == 707 else int(g.get_view(0).monsters[0].get("dc" if id == 705 else "at"))
		record(id, "Начало хода под проклятием", 1 if id == 707 else (4 if id == 705 else 2), observed, "curse")
	g = make()
	g.curses[0] = [709]
	g.coins[0] = 10
	g._end_turn()
	g._finish_responses()
	record(709, "Проклятие алчности: потерять четыре монеты в конце хода", 6, g.coins[0], "curse")
	g = make()
	g.curses[0] = [729]
	g.hands[0] = [475, 476, 477]
	g._end_turn()
	g._finish_responses()
	record(729, "Маленькие руки: сбросить до двух карт", "discard", g.phase, "curse")
	for id in [766, 769, 770, 772]:
		g = make()
		g.room = id
		g.hands[0].clear()
		g.coins[0] = 3
		g._begin_turn()
		g._finish_responses()
		var observed: int = g.coins[0] if id == 766 else (g.max_hp[0] if id == 769 else (g.attack[0] if id == 770 else g.hands[0].size()))
		record(id, "Начать ход с благословением комнаты", 6 if id == 766 else (3 if id == 769 else 2), observed, "room")
	for id in [744, 779]:
		g = make()
		if id == 744:
			g.curses[0] = [id]
		else:
			g.room = id
		g.bonuses = [689]
		g.coins[0] = 25
		g._check_bonuses()
		record(id, "Запрет получения души действует на бонусную душу", 0, g.souls[0], "curse" if id == 744 else "room")
	for id in [692, 693, 694, 695, 696]:
		g = make()
		g.bonuses = [id]
		record(id, "Нельзя забрать бонусную душу до выполнения условия", false, g.action(0, "claim", {"card": id}), "bonus")
	g = make()
	g.dlc = true
	g.room = -1
	g.decks.room = [769]
	if not g.action(0, "room") or g.room != 769:
		setup_errors += 1
	record(769, "Вход Мэгги немедленно меняет максимум здоровья", 3, g.max_hp[0], "room")
	g = make()
	g.monsters = [{"id": 272, "hp": 1, "dc": 0, "at": 0}]
	record(272, "Нельзя объявить атаку на Лавочника", false, g.action(0, "attack", {"slot": 0}), "monster")
	var tag := OS.get_environment("FS_AUDIT_TAG")
	if tag not in ["before", "after"]:
		tag = "after"
	var output := FileAccess.open("res://build/fs_passive_audit/runtime_%s.json" % tag, FileAccess.WRITE)
	var mismatches := results.filter(func(row): return not row.matches).size()
	output.store_string(JSON.stringify({"routes": routes, "observations": results,
		"setup_errors": setup_errors, "mismatches": mismatches}, "\t"))
	output.close()
	print("PASSIVE AUDIT: routes=", routes.size(), " observations=", results.size(),
		" mismatches=", mismatches, " setup_errors=", setup_errors)
	quit(2 if setup_errors else (1 if mismatches else 0))
