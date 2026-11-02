extends RefCounted
## Награда завершает свою физическую карту, а не устаревший индекс: сдвиг ряда и накрытые источники.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var shifted := Scenario.new(t).players(2).dlc().current(0) \
		.monster(0, 344, {"hp": 0, "death_pending": true}) \
		.monster(1, 345, {"hp": 0, "death_pending": true}).build()
	shifted.g._begin_resolving({"kind": "reward", "card": 345, "owner": 0, "slot": 1})
	shifted.g._begin_resolving({"kind": "reward", "card": 344, "owner": 0, "slot": 0})
	shifted.ok(0, "effect_done", null)
	t.equal(shifted.g.monsters[0].id, 345, "После внутренней награды ряд сдвинулся")
	t.equal(shifted.g.resolving.slot, 1, "У внешней награды сохранился прежний индекс")
	shifted.ok(0, "effect_done", null)
	t.equal(shifted.g.discards.monster.count(345), 1, "Внешняя карта сброшена ровно один раз")
	shifted.inv("После завершения сдвинутой награды")
	var covered := Scenario.new(t).players(2).dlc().current(0).monster(0, 450).monster(1, 344)
	covered.setup(func(g: FSRules) -> void:
		g.decks.monster.erase(368)
		g.decks.monster.erase(345)
		g.monsters[0]["under"] = {"id": 368, "hp": 0, "dc": 3, "at": 1,
			"under": {"id": 345, "hp": 4, "dc": 5, "at": 1}})
	covered.build()
	covered.g._begin_resolving({"kind": "reward", "card": 368, "owner": 0, "slot": 1})
	covered.ok(0, "effect_done", null)
	t.equal(covered.g.monsters[0].id, 450, "Живая карта над умершим источником сохранена")
	t.equal(covered.g.monsters[0].under.id, 345, "Карта под умершим источником сохранена")
	t.equal(covered.g.monsters[1].id, 344, "Чужая карта по устаревшему индексу не снята")
	t.equal(covered.g.discards.monster.count(368), 1, "Накрытый источник в сбросе один раз")
	covered.g._finish_monster_reward({"kind": "reward", "card": 368, "owner": 0, "slot": 1})
	t.equal(covered.g.discards.monster.count(368), 1, "Повторный cleanup не дублирует карту")
	covered.inv("Накрытый источник после повторного завершения")
