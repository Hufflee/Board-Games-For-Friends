extends "res://tests/test_fs_passive_fixes.gd"
## Подготовленные регрессии пассивов 6/18. Запуск: --headless --audio-driver Dummy --script res://tests/test_fs_mixed_next.gd.
## Seed 26 из make(); стек атаки задаётся явно, это не естественная партия.

func observe(ok: bool, label: String, actual: Variant) -> void:
	print("СЦЕНАРИЙ: ", label, " | факт: ", actual, " | ", "СОВПАЛО" if ok else "РАСХОЖДЕНИЕ")
	check(ok, label)

func clean() -> FSRules:
	var g := make()
	g.chars = [839, 839]
	g.room = -1
	g._refresh_passive_stats()
	g.attack = [1, 1]
	g.stack.clear()
	g.resolving = {}
	g.phase = "turn"
	return g

func miner(amounts: Array, recipient: int, bank: int, expected: bool) -> void:
	var g := clean()
	g._gain_item(0, 6)
	g.items[0][0].tapped = true
	g.bank = bank
	var before: int = g.coins[recipient]
	for amount: int in amounts:
		g._gain_coins(recipient, amount)
		g._finish_responses()
	var ready: bool = not g.items[0][0].tapped
	observe(ready == expected, "6: выплаты %s получателю %d банк %d → готов=%s" % [amounts, recipient, bank, expected],
		{"готов": ready, "получено": int(g.coins[recipient]) - before})

func roll(g: FSRules) -> int:
	g.phase = "battle_roll"
	g._push({"kind": "roll", "value": 6, "owner": g.current}, "battle_roll")
	g._finish_responses()
	return int(g.monsters[0].hp)

func _initialize() -> void:
	miner([2], 0, 20, false)
	miner([3], 0, 20, true)
	miner([2, 1], 0, 20, false)
	miner([3], 1, 20, false)
	miner([3], 0, 2, false)
	miner([4], 0, 3, true)
	miner([3], 0, 0, false)
	var g := clean()
	g._gain_item(0, 6)
	var source: Dictionary = g._remove_item(0, 0)
	source.tapped = true
	g._gain_coins(0, 3)
	g._finish_responses()
	observe(source.tapped, "6: источник ушёл → не перезаряжается", source.tapped)
	g.items[1].append(source)
	g._gain_coins(0, 3)
	g._finish_responses()
	observe(source.tapped, "6: передача → старый владелец не перезаряжает", source.tapped)
	g._gain_coins(1, 3)
	g._finish_responses()
	observe(not source.tapped, "6: передача → новый владелец перезаряжает", source.tapped)
	g = clean()
	g._gain_item(0, 18)
	g.battle = 0
	g.monsters = [{"id": 462, "hp": 100, "dc": 3, "at": 1}]
	# Обычные броски и чужие события не должны приближать собственный третий бросок атаки.
	for i in 3:
		g._roll_passives(6, 1)
		g._roll_passives(6, 0)
		g._finish_responses()
	observe(g.attack[0] == 1, "18: чужие/обычные броски → ATK=1", g.attack[0])
	for i in range(1, 5):
		var before: int = g.monsters[0].hp
		roll(g)
		var expected_atk := 1 if i < 3 else 2
		var expected_damage := 1 if i <= 3 else 2
		observe(g.attack[0] == expected_atk, "18: после броска атаки %d → ATK=%d" % [i, expected_atk], g.attack[0])
		observe(before - int(g.monsters[0].hp) == expected_damage,
			"18: бросок %d → урон=%d (фиксируется до триггеров)" % [i, expected_damage], before - int(g.monsters[0].hp))
	g.battle = -1
	g._end_turn()
	g._finish_responses()
	observe(g.attack[0] == 1, "18: конец хода → ATK=1", g.attack[0])
	g._end_turn()
	g._finish_responses()
	g.battle = 0
	g.monsters[0].hp = 100
	for i in range(1, 4):
		roll(g)
		var expected := 1 if i < 3 else 2
		observe(g.attack[0] == expected, "18: новый ход бросок %d → ATK=%d" % [i, expected], g.attack[0])
	print("MIXED NEXT: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
