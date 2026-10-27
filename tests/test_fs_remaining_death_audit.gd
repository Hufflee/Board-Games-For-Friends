extends "res://tests/test_fs_passive_fixes.gd"
## Отрицательный аудит оставшихся условий смерти. Exit1 означает сохранённые расхождения, не чистый прогон.
var observations: Array = []

func reward(id: int) -> FSRules:
	var g := make()
	g.phase = "battle_roll"
	g.resolving = {}
	g._after_stack = "battle_roll"
	g.battle = 0
	g.monsters = [{"id": id, "hp": 0, "dc": 4, "at": 1}, {"id": 450, "hp": 3, "dc": 4, "at": 1}]
	g.decks.monster = [451]
	g._continue_stack()
	g._finish_responses()
	check(g.phase == "effect" and int(g.resolving.card) == id, "Открыта настоящая награда умершей карты")
	return g

func roll_value(g: FSRules, value: int) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 101):
		rng.seed = seed_value
		if rng.randi_range(1, 6) == value:
			g._rng.seed = seed_value
			break
	check(g.action(0, "effect_roll"), "Подготовленный бросок запущен действием правил")
	g._finish_responses()
	check(g.last_roll == value and g.phase == "effect", "Бросок разрешился с заданной для воспроизведения гранью")

func record(id: int, action: String, expected, actual) -> void:
	observations.append({"id": id, "name": FSData.title(id), "action": action,
		"expected": expected, "actual": actual, "matches": expected == actual})

func _initialize() -> void:
	var g := reward(268)
	check(g.action(0, "effect_done"), "Завершена награда Завоевателя")
	record(268, "После подтверждённой смерти доступна обязательная PvP-атака другого игрока", true,
		g.action(0, "attack_player", {"target": 1}))
	for value in [6, 2]:
		g = reward(358)
		check(g.action(0, "effect", {"op": "loot", "amount": 1}), "Награда Тряпочника получена перед броском")
		roll_value(g, value)
		check(g.action(0, "effect_done"), "Завершена награда Тряпочника после броска")
		var returned: bool = g.decks.monster.has(358) or g.monsters.any(func(monster): return int(monster.id) == 358)
		record(358, "Возврат Тряпочника при броске%d после награды (с учётом заполнения освободившейся ячейки)" % value,
			value == 6, returned)
	var mismatches := observations.filter(func(row): return not row.matches).size()
	var file := FileAccess.open("res://build/fs_passive_audit/followup/remaining-death.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"observations": observations, "mismatches": mismatches, "setup_errors": errors}, "\t"))
	file.close()
	print("REMAINING DEATH AUDIT: ", observations.size(), " наблюдений, ", mismatches, " расхождений, ", errors, " ошибок подготовки")
	quit(2 if errors else (1 if mismatches else 0))
