extends "res://tests/test_fs_passive_fixes.gd"
## Пассив от ручного урона не блокирует оставшуюся награду и не пропускает чужой ответ.

func pending() -> FSRules:
	var g := make()
	g.current = 1
	g.resolving = {"kind": "reward", "card": 387, "owner": 1, "slot": 0}
	g.items[0] = [FSData.item_entry(180)]
	g.items[1] = []
	g.battle = 0
	g.monsters[0].id = 387
	g.monsters[0].hp = 0
	g.monsters[0].death_pending = true
	check(g.action(1, "effect", {"op": "damage", "amount": 3, "target": 0}), "Урон Бомбанытика запустил пассив")
	check(g.get_view(1).effect_pending, "Осталась доступна ручная награда")
	return g

func _initialize() -> void:
	var g := pending()
	var money: int = g.coins[1]
	check(not g.action(0, "effect", {"op": "coins", "amount": 6}), "Другой игрок не продолжает чужую награду")
	check(g.items[0][0].counters == 0, "Чужая попытка не разрешает стек")
	check(g.action(1, "effect", {"op": "coins", "amount": 6}), "Следующая операция разрешает пассив перед наградой")
	check(g.phase == "effect" and g.items[0][0].counters == 1, "Пассив разрешён ровно один раз, исходная награда восстановлена")
	check(g.coins[1] == money + 6 and g.resolving.card == 387, "Монеты начислены исходному владельцу Бомбанытика")
	g = pending()
	check(g.action(1, "effect_done"), "Завершение эффекта также разрешает ожидающий пассив")
	check(g.items[0][0].counters == 1, "Завершение не теряет пассив")
	g = pending()
	check(g.action(1, "effect_roll"), "Ручной бросок разрешает предшествующие пассивы")
	check(g.roll_no == 1 and g.items[0][0].counters == 1, "Один результат броска и одно срабатывание")
	g = pending()
	g.stack.append({"kind": "loot", "card": 515, "owner": 0})
	check(not g.get_view(1).effect_pending, "Чужой ручной ответ исключает быстрый возврат")
	check(not g.action(1, "effect", {"op": "coins", "amount": 6}), "Нельзя пропустить чужой ручной ответ ради награды")
	g = pending()
	g.current = 0
	g.next_action = {"seat": 0, "kind": "roll", "arg": null}
	check(not g.action(0, "effect", {"op": "coins", "amount": 6, "target": 1}), "Активный игрок не становится владельцем чужого ручного эффекта")
	check(g.action(1, "effect", {"op": "coins", "amount": 6, "target": 1}), "Владелец продолжает эффект и вне своего хода")
	check(g.phase == "effect" and g.roll_no == 0 and not g.next_action.is_empty(), "Ожидающее основное действие не обгоняет оставшуюся ручную награду")
	print("MANUAL PASSIVE RESUME: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
