extends "res://tests/test_fs_passive_fixes.gd"
## Засада и Пип: обязательные атаки верха, их учёт и законное размещение найденного Утопца.

func turn() -> FSRules:
	var g := make()
	g.phase = "turn"
	g.resolving = {}
	g.stack.clear()
	g.next_action = {}
	g._after_stack = "turn"
	g.monsters = [{"id": 450, "hp": 3, "dc": 4, "at": 1}, {"id": 451, "hp": 3, "dc": 4, "at": 1}]
	return g

func ambush(g: FSRules) -> void:
	g._push({"kind": "event", "card": 715, "owner": 0}, "turn")
	g._finish_responses()

func _initialize() -> void:
	var g := turn()
	ambush(g)
	check(g.phase == "turn" and int(g.get_view(0).get("forced_deck_attacks", 0)) == 2, "Засада сама требует две атаки верха колоды")
	check(not g.action(0, "end"), "Нельзя завершить живой ход раньше обязательных атак")
	check(not g.action(0, "attack", {"slot": 0}), "Обычная цель не заменяет обязательную атаку верха")
	g.decks.monster = [450, 451]
	check(g.action(0, "attack", {"slot": -1, "over": 0}), "Первая обязательная атака объявлена")
	check(int(g.get_view(0).get("forced_deck_attacks", -1)) == 1, "Считается объявление атаки, не бросок")
	# Отмена атаки не отменяет самого факта её объявления.
	g.stack.clear()
	g.phase = "turn"
	check(g.action(0, "attack", {"slot": -1, "over": 1}), "Вторая обязательная атака объявлена")
	check(int(g.get_view(0).get("forced_deck_attacks", -1)) == 0, "После двух атак требование выполнено")
	g = turn()
	g.decks.monster = [715]
	check(g.action(0, "attack", {"slot": -1, "over": 0}), "Засада открывается первой атакой верха")
	g._finish_responses()
	check(int(g.get_view(0).get("forced_deck_attacks", -1)) == 1, "Атака, открывшая Засаду, уже входит в две")
	g = turn()
	ambush(g)
	g.hp[0] = 0
	g._check_deaths()
	g._finish_responses()
	check(g.action(0, "death", {"loot": -1, "item": -1}), "Смерть не заставляет совершать оставшиеся атаки")
	check(g.current == 1 and int(g.get_view(1).get("forced_deck_attacks", -1)) == 0, "Требование не переходит на следующий ход")
	g = turn()
	ambush(g)
	g.decks.monster.clear()
	g.discards.monster.clear()
	check(int(g.get_view(0).forced_deck_attacks) == 0, "Полностью пустая колода и сброс не запирают ход")
	check(g.action(0, "end"), "Когда атаковать колоду невозможно, ход можно завершить")
	g = turn()
	ambush(g)
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 1)
	check(int(g.get_view(0).forced_deck_attacks) == 0 and g.deck_attacks == 0, "Новая партия очищает обязательство и счётчик прошлой")
	g = turn()
	g.monsters[0] = {"id": 429, "hp": 0, "dc": 4, "at": 1}
	g.battle = 0
	g.decks.monster = [450, 282, 451]
	g._continue_stack()
	g._finish_responses()
	check(g.phase == "effect" and int(g.resolving.get("spawn_card", -1)) == 282, "Подтверждённая смерть Пипа находит настоящего Утопца в колоде")
	check(not g.action(0, "effect_done"), "Нельзя пропустить обязательное размещение")
	check(not g.action(0, "effect_roll"), "Ручной бросок не обгоняет обязательное размещение")
	check(not g.action(0, "effect", {"op": "souls", "amount": 1}), "Награда не обгоняет размещение")
	check(not g.action(1, "place_bloat", {"slot": 1}), "Другой игрок не размещает карту за активного")
	check(not g.action(0, "place_bloat", {"slot": 0}), "Нельзя накрыть ячейку текущего боя")
	check(not g.action(0, "place_bloat", {"slot": 9}), "Несуществующая ячейка отклонена")
	check(g.action(0, "place_bloat", {"slot": 1}), "Утопец помещён в другую существующую ячейку")
	check(g.monsters.size() == 2 and int(g.monsters[1].id) == 282, "Новая ячейка не создаётся")
	check(int(g.monsters[1].get("under", {}).get("id", -1)) == 451, "Нижний монстр сохранён")
	check(not g.decks.monster.has(282), "Выложенная карта удалена из колоды")
	check(not bool(g.get_view(0).monsters[1].get("untargetable", true)), "Утопец остаётся обычной атакуемой картой")
	check(not g.action(0, "place_bloat", {"slot": 1}), "Повтор не создаёт второго Утопца")
	check(g.action(0, "effect", {"op": "treasure", "amount": 1}), "После размещения доступна обычная награда")
	g = turn()
	g.monsters[0] = {"id": 429, "hp": 0, "dc": 4, "at": 1}
	g.battle = 0
	g.decks.monster = [450, 451]
	g._continue_stack()
	g._finish_responses()
	check(g.phase == "effect" and not g.resolving.has("spawn_card"), "Отсутствие Утопца не блокирует награду и не создаёт карту из воздуха")
	g = turn()
	g.phase = "battle_roll"
	g._after_stack = "battle_roll"
	g.battle = 0
	g.monsters[1] = {"id": 429, "hp": 0, "dc": 4, "at": 1, "under": {"id": 451, "hp": 3, "dc": 4, "at": 1}}
	g.decks.monster = [282]
	g._continue_stack()
	g._finish_responses()
	check(g.get_view(0).spawn_slots == [1], "Пип погиб вне боя: его собственная ячейка доступна для Утопца")
	check(g.action(0, "place_bloat", {"slot": 1}), "Утопец занимает ячейку погибшего вне боя Пипа")
	g.next_action = {"seat": 0, "kind": "roll", "arg": null}
	check(g.action(0, "effect_done"), "Награда Пипа завершена после такого размещения")
	check(int(g.monsters[1].id) == 282 and int(g.monsters[1].under.id) == 451, "При уходе Пипа Утопец и живая нижняя карта сохранены")
	check(g.battle == 0 and int(g.monsters[0].id) == 450, "Исходный бой с другим монстром продолжается")
	check(g.roll_no == 1 and g.next_action.is_empty() and g.phase == "priority", "Ожидавший бросок исходного боя не теряется при завершении награды")
	print("AMBUSH PEEP: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
