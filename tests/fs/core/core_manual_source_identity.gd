extends RefCounted
## Жест старой панели закрывает её ответы, но не выполняет вновь открывшуюся Карму того же владельца.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	for kind: String in ["effect", "effect_done"]:
		var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).no_items(0).no_items(1).no_items(2) \
			.item(0, 13).item(0, 8).item(1, 243).build()
		s.g._begin_resolving({"kind": "item", "card": 13, "owner": 0})
		var chest := -1
		for index in s.g.items[1].size():
			if int(s.g.items[1][index].id) == 243:
				chest = index
		s.effect(0, "item_to_soul", {"target": 1, "item": chest})
		var coins: Array = s.g.coins.duplicate()
		s.ok(0, kind, {"op": "coins", "target": 0, "amount": 9}, "Следующий жест старой панели закрывает ответы")
		t.equal(s.g.resolving.get("card"), 8, "Новая Карма того же владельца остаётся открыта: " + kind)
		t.equal(s.g.coins, coins, "Старое применение не выполнилось по новой карте")
		if s.g.resolving.get("card") == 8:
			s.ok(0, "effect_done", null, "Явное завершение вложенной панели")
			t.equal(s.g.resolving.get("card"), 13, "Внешняя карта продолжилась после вложенной")
			s.ok(0, "effect_done", null, "Отдельное завершение исходной панели")
		s.inv("Вложенный эффект с тем же владельцем")
