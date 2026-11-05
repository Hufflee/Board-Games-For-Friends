extends RefCounted
## Регресс46067: ожидание штатных часов не является зависанием после исчерпания ответов.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Legal := preload("res://games/four_souls/logic/fs_legal.gd")
const Fuzz := preload("res://tests/fs/fs_fuzz.gd")

func run(t: Check) -> void:
	var s := Scenario.new(t).players(2).no_items(0).no_items(1).hand(0, []).hand(1, []).build()
	s._take(550)
	s.g._push({"kind": "loot", "card": 550, "owner": 0}, "turn")
	s.g.next_action = {"seat": 0, "kind": "end", "arg": null}
	s.g.character_ready.fill(false)
	for inventory: Array in s.g.items:
		for item: Dictionary in inventory:
			item.tapped = true
	t.check(Legal.anyone_can_act(s.g), "Штатные часы предотвращают ложное зависание")
	var candidate: Dictionary = Fuzz._pick(s.g, RandomNumberGenerator.new())
	t.equal(candidate.get("kind"), "_clock", "Фаззер умеет дождаться тихого окна при отсутствии действий")
	t.check(not s.g.action(0, "_clock"), "Сетевой action не принимает часы стенда")
	var before: int = int(s.g.coins[0])
	t.check(Fuzz.perform(s.g, 0, "_clock", null), "Хостовые часы действительно продвинули стек")
	t.equal(s.g.coins[0], before + 1, "Штатное ожидание выдало ресурс ровно один раз")
	t.check(not Legal.advance_clock(s.g), "Повторное ожидание без стека не дублирует ресурс")
