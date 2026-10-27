extends "res://tests/test_fs_remaining_death_audit.gd"
## Тряпочник: обязательный бросок после награды, возврат при1/6 и отсутствие дублирования карты.

func _initialize() -> void:
	for value in [1, 6, 2]:
		var g := reward(358)
		check(not g.action(0, "effect_done"), "Нельзя завершить награду, пропустив обязательный бросок")
		check(not g.action(1, "effect_roll"), "Соперник не бросает за владельца награды")
		check(g.action(0, "effect", {"op": "loot", "amount": 1}), "Сначала получена напечатанная награда")
		roll_value(g, value)
		check(int(g.resolving.reward_roll) == value, "Результат сохранён у исходной награды")
		check(g.action(0, "effect_done"), "Награда завершена после броска")
		var returned: bool = g.decks.monster.has(358) or g.monsters.any(func(monster): return int(monster.id) == 358)
		check(returned == (value in [1, 6]), "Правильная зона Тряпочника при грани%d" % value)
		check(g.discards.monster.has(358) == (value not in [1, 6]), "Возврат не оставляет копию в сбросе")
		var total: int = g.decks.monster.count(358) + g.discards.monster.count(358)
		total += g.monsters.filter(func(monster): return int(monster.id) == 358).size()
		check(total == 1, "В игре ровно один экземпляр карты")
		check(not g.action(0, "effect_done"), "Повторное завершение не выдаёт ещё одну награду")
	print("RAGLING: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
