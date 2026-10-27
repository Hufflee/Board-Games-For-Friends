extends SceneTree
## Напечатанная вечность предметов при реальном получении и пассивная классификация Глюка.
var checks := 0
var errors := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func make() -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.items = [[], []]
	g.monsters.clear()
	g.bonuses.clear()
	return g

func effect(g: FSRules, id: int = 0, owner: int = 0) -> void:
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": id, "owner": owner}
	g._after_stack = "turn"

func _initialize() -> void:
	check(FSData.response_kind(883) == "passive", "Глюк — пассив, без поворотной/платной способности")
	check(FSData.response_kind(843) == "hybrid", "Кость сохраняет обе активируемые способности")
	for id in [44, 50, 248]:
		check(FSData.response_kind(id) == "hybrid", "Доступны поворотная и платная способности: " + str(id))
	check(FSData.item_entry(69).eternal, "Мошна Хранителя напечатана вечной")
	check(FSData.item_entry(503).eternal, "Клещ напечатан вечным")
	check(not FSData.item_entry(121).eternal, "Обычный Хвост Гаппи не становится вечным")
	check(FSData.item_entry(121, true).eternal, "Стартовый предмет Эдема остаётся вечным")
	var g := make()
	g.hands[0] = [503]
	check(g.action(0, "loot", {"card": 503}), "Клещ разыгран обычным лутом")
	g._finish_responses()
	check(g.items[0].size() == 1 and g.items[0][0].eternal, "Клещ после разрешения сохраняет вечность")
	effect(g)
	check(not g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "Клеща нельзя уничтожить")
	check(not g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Клеща нельзя передать обычным эффектом")
	effect(g, 0, 1)
	check(not g.action(1, "effect", {"op": "steal", "target": 0, "item": 0}), "Клеща нельзя украсть")
	g.current = 1
	g.hp[0] = 0
	g.resolving = {}
	g.phase = "turn"
	g._check_deaths()
	g._finish_responses()
	check(g.action(0, "death", {"loot": -1, "item": -1}), "Штраф смерти разрешается без уничтожения вечного Клеща")
	check(g.items[0].size() == 1 and g.items[0][0].id == 503, "Клещ пережил штраф смерти")
	for method in ["treasure", "purchase", "peek"]:
		g = make()
		g.decks.treasure.erase(69)
		g.decks.treasure.append(69)
		if method == "treasure":
			effect(g)
			check(g.action(0, "effect", {"op": "treasure", "target": 0, "amount": 1}), "Получение сокровища")
		elif method == "purchase":
			g.shop = [69]
			g.coins[0] = 10
			check(g.action(0, "buy", {"slot": 0}), "Покупка Мошны")
			g._finish_responses()
		else:
			effect(g)
			g.action(0, "effect", {"op": "peek_treasure", "target": 0, "amount": 1})
			check(g.action(0, "peek_take", {"card": 69, "dest": "item"}), "Получение Мошны из просмотра")
		check(g.items[0].size() == 1 and g.items[0][0].id == 69 and g.items[0][0].eternal, "Мошна вечная: " + method)
	effect(g)
	check(not g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Обычная передача Мошны запрещена")
	check(not g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "Обычное уничтожение Мошны запрещено")
	effect(g, 69)
	check(g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Собственная способность Мошны разрешает её передачу")
	check(g.items[1][0].eternal and g.items[0].is_empty(), "Переданная Мошна остаётся вечной, без копии")
	g.items[0] = [FSData.item_entry(822)]
	check(not g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Исключение Мошны не позволяет передать другой вечный предмет")
	for id in [22, 60, 199]:
		g = make()
		effect(g)
		g.decks.treasure.erase(id)
		g.decks.treasure.append(id)
		g.action(0, "effect", {"op": "treasure", "target": 0, "amount": 1})
		check(g.items[0][0].tapped, "Предмет входит в игру деактивированным: " + str(id))
	for pair in [[5, 3], [202, 9]]:
		g = make()
		effect(g)
		g.decks.treasure.erase(int(pair[0]))
		g.decks.treasure.append(int(pair[0]))
		g.action(0, "effect", {"op": "treasure", "target": 0, "amount": 1})
		check(g.items[0][0].counters == pair[1], "Напечатанные начальные жетоны: " + str(pair[0]))
	for id in [84, 822, 824, 828, 834, 849, 893, 899]:
		g = make()
		var source := FSData.item_entry(id)
		source.tapped = true
		g.items[0] = [source]
		g._end_turn()
		g._finish_responses()
		check(not g.items[0][0].tapped, "Обязательная перезарядка в конце своего хода: " + str(id))
	g = make()
	var battery := FSData.item_entry(44)
	battery.tapped = true
	g.items[0] = [battery]
	g._begin_turn()
	check(g.items[0][0].tapped, "Аккумулятор не перезаряжается обычным шагом")
	effect(g, 159)
	check(not g.action(0, "effect", {"op": "recharge", "target": 0, "item": 0}), "Чужая способность не перезаряжает Аккумулятор")
	effect(g, 44)
	check(g.action(0, "effect", {"op": "recharge", "target": 0, "item": 0}), "Собственная способность перезаряжает Аккумулятор")
	check(not g.items[0][0].tapped, "После собственной перезарядки Аккумулятор готов")
	g = make()
	g.monsters = [{"id": 272, "hp": 1, "dc": 1, "at": 1}]
	check(not g.action(0, "attack", {"slot": 0}), "Лавочника нельзя атаковать напрямую")
	g.decks.monster = [272]
	g.monsters = [{"id": 450, "hp": 1, "dc": 1, "at": 1}]
	g._start_attack({"slot": -1, "over": 0})
	check(g.battle == -1 and g.phase != "battle_roll", "Лавочник сверху колоды не начинает бой")
	g = make()
	g.monsters = [
		{"id": 450, "hp": 0, "dc": 1, "at": 1},
		{"id": 272, "hp": 1, "dc": 1, "at": 1},
		{"id": 346, "hp": 1, "dc": 1, "at": 1},
		{"id": 408, "hp": 1, "dc": 1, "at": 1}]
	g.stack = [{"kind": "monster_death", "card": 450, "owner": 0, "slot": 0}]
	g._resolve_top()
	check(g.monsters[1].hp == 1, "Лавочник не гибнет от смерти другого монстра")
	check(g.monsters[2].hp == 0 and g.monsters[3].hp == 0, "Связанная гибель Головы смерти и Каменюки сохраняется")
	print("PRINTED TRAITS: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
