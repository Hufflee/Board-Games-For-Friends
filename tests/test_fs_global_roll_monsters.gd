extends "res://tests/test_fs_passive_fixes.gd"
## Триггеры открытых монстров от любого броска:440/445/439 и возврат ручного эффекта.
var observations: Array = []
func observe(id: int, action_text: String, expected, actual) -> void:
	observations.append({"id":id,"name":FSData.title(id),"action":action_text,"expected":expected,"actual":actual,"matches":expected == actual,"category":"global_roll"})
	check(expected == actual, action_text)
func fixture(id: int) -> FSRules:
	var g := make()
	g.hp = [5,5]
	g.max_hp = [5,5]
	g.monsters = [{"id":id,"hp":1,"dc":4,"at":1}]
	g.current = 0
	g.resolving = {"kind":"item","card":13,"owner":1}
	g._after_stack = "turn"
	g.coins = [3,3]
	g.bank = 94
	g.hands = [[475],[478,479]]
	return g
func roll(g: FSRules, value: int) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1,101):
		rng.seed = seed_value
		if rng.randi_range(1,6) == value:
			g._rng.seed = seed_value
			break
	check(g.action(1,"effect_roll"), "Настоящий бросок ручного эффекта объявлен")
	check(g.action(1,"effect_roll"), "Ответы на бросок разрешены")
func _initialize() -> void:
	var g := fixture(440)
	roll(g,2)
	observe(440, "Проклятый Хорф наносит2 именно бросившему, а не активному", [5,3], g.hp.duplicate())
	check(g.phase == "effect" and g.actor() == 1, "После Хорфа ручной эффект вернулся владельцу")
	g = fixture(445)
	roll(g,4)
	observe(445, "Святая голова даёт2 монеты именно бросившему4", [3,5], g.coins.duplicate())
	g = fixture(439)
	roll(g,5)
	observe(439, "Проклятый толстяк требует у бросившего5 сбросить карту", ["forced_discard",1], [g.phase,g.actor()])
	if g.phase == "forced_discard":
		check(g.action(1,"forced_discard",{"item":1}), "Бросивший выбирает карту сам")
		check(g.hands[1] == [478] and g.phase == "effect" and g.actor() == 1, "После сброса продолжается тот же ручной эффект")
	for id in [440,445,439]:
		g = fixture(id)
		roll(g,3)
		check(g.hp == [5,5] and g.coins == [3,3] and g.hands[1].size() == 2, "Контрольная3 не включает монстра " + str(id))
		g = fixture(id)
		g.monsters = [{"id":450,"hp":3,"dc":4,"at":1,"under":{"id":id,"hp":1,"dc":4,"at":1}}]
		roll(g,{440:2,445:4,439:5}[id])
		check(g.hp == [5,5] and g.coins == [3,3] and g.phase == "effect", "Накрытый монстр не срабатывает: " + str(id))
	g = fixture(439)
	g.phase = "priority"
	g.resolving = {}
	g.battle = 0
	g._after_stack = "battle_roll"
	g.stack = [{"kind":"roll","owner":0,"value":5}]
	g._finish_responses()
	check(g.phase == "forced_discard" and g.monsters[0].hp == 1, "Триггер пятёрки разрешается до боевого урона этого броска")
	g = fixture(440)
	g.hp[1] = 1
	roll(g,2)
	check(g.phase == "death" and g.actor() == 1, "Хорф с летальным уроном открывает обычный штраф бросившего")
	check(g.action(1,"death",{"loot":478,"item":-1}), "Бросивший оплачивает штраф до возврата способности")
	check(g.action(0,"end"), "После чужого штрафа активный закрывает оставшееся окно ответов")
	check(g.phase == "effect" and g.resolving.owner == 1 and g.current == 0, "Перед отложенным концом хода исходный эффект возвращён владельцу")
	check(g.action(1,"effect_done") and g.current == 1, "Завершение восстановленного эффекта выполняет ожидавший конец хода")
	g = fixture(445)
	g.monsters[0]["hp"] = 0
	g.monsters[0]["death_pending"] = true
	g.resolving = {"kind":"reward","card":445,"owner":1,"slot":0}
	roll(g,4)
	check(g.coins[1] == 5, "Открытая Голова действует на бросок собственной награды")
	g = fixture(439)
	g.hands[1].clear()
	roll(g,5)
	check(g.phase == "effect" and g.discard_choice.is_empty(), "Пустая рука Толстяка не запирает эффект")
	var output := FileAccess.open("res://build/fs_passive_audit/followup/runtime_global_roll.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"observations":observations,"mismatches":observations.filter(func(row): return not row.matches).size(),"setup_errors":0},"\t"))
	output.close()
	print("GLOBAL ROLL MONSTERS: ",checks," проверок, ",errors," ошибок")
	quit(1 if errors else 0)
