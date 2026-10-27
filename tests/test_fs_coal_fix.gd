extends "res://tests/test_fs_mixed_next.gd"
## Узкие регрессии карты 18: --headless --audio-driver Dummy --script res://tests/test_fs_coal_fix.gd.
## Подготовленные состояния seed 26; не естественная партия и не независимое ревью.

func coal(copies: int = 1) -> FSRules:
	var g := clean()
	for i in copies:
		g._gain_item(0, 18)
	g.battle = 0
	g.monsters = [{"id": 462, "hp": 100, "dc": 3, "at": 1}]
	return g

func third_pending(g: FSRules) -> void:
	roll(g)
	roll(g)
	g._push({"kind": "roll", "value": 6, "owner": 0}, "battle_roll")
	g._resolve_top()
	check(g.attack[0] == 1, "Бонус не применяется до разрешения триггера")
	check(g.stack.size() == 2 and g.stack[0].kind == "combat" and g.stack[1].kind == "passive",
		"Триггер угля находится над боевым уроном")
	check(g.stack[0].damage == 1, "Третий бросок уже определил количество урона 1")

func manual_roll(g: FSRules, seat: int) -> void:
	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 13, "owner": seat}
	check(g.action(seat, "effect_roll", {}), "Обычный ручной бросок доступен владельцу эффекта")
	g._finish_responses()
	check(g.phase == "effect", "Небоевой бросок вернулся в ручной эффект")
	g.resolving = {}
	g.phase = "battle_roll"

func _initialize() -> void:
	var g := coal()
	for i in range(1, 5):
		var before: int = g.monsters[0].hp
		roll(g)
		check(g.attack[0] == (1 if i < 3 else 2), "Порог ATK на броске %d" % i)
		check(before - int(g.monsters[0].hp) == (1 if i <= 3 else 2), "Урон броска %d" % i)
	check(g.temporary_attack == [[0, 1]], "Четвёртый бросок не добавил второй временный бонус")
	g._refresh_passive_stats()
	g._refresh_passive_stats()
	check(g.attack[0] == 2, "Пересчёт постоянных характеристик не удваивает бонус угля")
	g.battle = -1
	g._end_turn()
	g._finish_responses()
	check(g.attack[0] == 1 and g.temporary_attack.is_empty(), "Настоящий бонус снят в конце хода")
	g._end_turn()
	g._finish_responses()
	g.battle = 0
	g.monsters[0].hp = 100
	for i in range(1, 4):
		roll(g)
		check(g.attack[0] == (2 if i == 3 else 1), "Счёт заново на следующем своём ходу: %d" % i)

	g = coal()
	third_pending(g)
	g._resolve_top()
	check(g.attack[0] == 2 and g.monsters[0].hp == 98, "Бонус разрешён до нанесения третьего урона")
	g._finish_responses()
	check(g.monsters[0].hp == 97, "Третий урон остался равным 1 после бонуса")

	g = coal(2)
	for i in 3:
		roll(g)
	check(g.attack[0] == 3 and g.temporary_attack.size() == 2, "Две копии создают два независимых +1")
	roll(g)
	check(g.attack[0] == 3 and g.monsters[0].hp == 94, "Четвёртая атака с двумя копиями наносит 3")

	g = coal(0)
	roll(g)
	roll(g)
	g._gain_item(0, 18)
	roll(g)
	check(g.attack[0] == 2, "Получение карты после двух бросков учитывает историю игрока")
	var source: Dictionary = g._remove_item(0, 0)
	g.items[0].append(source)
	g._refresh_passive_stats()
	roll(g)
	check(g.attack[0] == 2, "Повторное получение не повторяет третий бросок")
	g._gain_item(0, 18)
	roll(g)
	check(g.attack[0] == 2, "Новая копия после третьего броска не срабатывает задним числом")

	g = coal()
	third_pending(g)
	source = g._remove_item(0, 0)
	g.items[1].append(source)
	g._finish_responses()
	check(g.attack == [2, 1], "Переданный источник не меняет владельца уже созданного триггера")
	check(g.temporary_attack == [[0, 1]], "Временный бонус привязан к получателю, а не источнику")
	g._remove_item(1, 0)
	check(g.attack == [2, 1], "Уничтожение источника не снимает уже полученный бонус")

	g = coal()
	third_pending(g)
	g.stack.pop_back()
	g._finish_responses()
	roll(g)
	check(g.attack[0] == 1, "Отменённый триггер не возникает снова на четвёртом броске")

	g = coal()
	roll(g)
	roll(g)
	source = g._remove_item(0, 0)
	g.items[1].append(source)
	roll(g)
	check(g.attack == [1, 1], "Передача до третьего броска лишает прежнего владельца триггера")
	g.current = 1
	for i in range(1, 4):
		roll(g)
		check(g.attack[1] == (2 if i == 3 else 1), "Новый владелец считает свои броски: %d" % i)

	g = coal()
	for i in 3:
		manual_roll(g, 0)
		manual_roll(g, 1)
	# Настоящий путь action roll другого игрока, без начала нового хода.
	g.current = 1
	for i in 3:
		check(g.action(1, "roll", {}), "Чужой бросок атаки проходит через action")
		g.stack.back().value = 6
		g._finish_responses()
	g.current = 0
	check(g.attack[0] == 1, "Чужие атаки и ручные броски не усилили владельца")
	for i in range(1, 4):
		roll(g)
		check(g.attack[0] == (2 if i == 3 else 1), "Отрицательные события не приблизили порог: %d" % i)

	g = coal()
	for i in 3:
		g._push({"kind": "roll", "value": 2, "owner": 0}, "battle_roll")
		g._resolve_top()
		# Проверяем результат промаха до урона, не подменяя смерть/штраф этой узкой проверкой.
		check(not g.stack[0].hit, "Промах остаётся промахом")
		if i == 2:
			g._resolve_top()
		g.stack.clear()
		g.phase = "battle_roll"
	check(g.attack[0] == 2, "Три промаха тоже являются тремя бросками атаки")

	g = coal()
	roll(g)
	roll(g)
	g._push({"kind": "roll", "value": 1, "owner": 0}, "battle_roll")
	g.resolving = {"kind": "item", "card": 13, "owner": 0, "reroll_request": {"owner": 0, "index": 0}}
	g.phase = "effect"
	check(g.action(0, "effect_roll", {}), "Переброс ожидающей атаки создаётся обычным действием")
	g.stack.back().value = 6
	g._resolve_top()
	check(g.attack[0] == 1 and int(g._turn_attack_rolls[0]) == 2, "Промежуточный effect_roll не считает атаку дважды")
	g.resolving = {}
	g.phase = "priority"
	g._finish_responses()
	check(g.attack[0] == 2 and int(g._turn_attack_rolls[0]) == 3, "Итог переброшенной атаки считается один раз при passives_done")
	check(g.monsters[0].hp == 97, "Переброшенная третья атака наносит прежний урон 1")

	g.phase = "effect"
	g.resolving = {"kind": "item", "card": 18, "owner": 0}
	check(not g.action(0, "effect", {"op": "temporary_attack", "amount": 1}), "Нельзя дублировать автоматический бонус вручную")
	check(not g.action(0, "effect", {"op": "attack", "amount": 1}), "Нельзя вручную превратить бонус угля в постоянную атаку")
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	check(g._turn_attack_rolls.is_empty() and g.temporary_attack.is_empty(), "Новая партия очистила счёт и временные бонусы")
	g.items = [[], []]
	g.chars = [839, 839]
	g.room = -1
	g._refresh_passive_stats()
	g.attack = [1, 1]
	g.stack.clear()
	g.resolving = {}
	g._gain_item(0, 18)
	g.current = 0
	g.battle = 0
	g.monsters = [{"id": 462, "hp": 100, "dc": 3, "at": 1}]
	for i in range(1, 4):
		roll(g)
		check(g.attack[0] == (2 if i == 3 else 1), "Новая партия считает с первого броска: %d" % i)
	print("COAL FIX: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
