extends RefCounted
## 20 физических копий: сверка с отдельными изображениями и Золотая бомба / Мегабатарейка.
const Check := preload("res://tests/fs/fs_check.gd")
const Fixture := preload("res://tests/fs/core/core_automation_batch03.gd")
const Cards := preload("res://games/four_souls/logic/fs_card_automation.gd")

func run(t: Check) -> void:
	t.equal(Cards.BATCH_04.size(), 20, "Четвёртый пакет20карт")
	var fixture := Fixture.new()
	for id in Cards.BATCH_04:
		var s = fixture._game(t, id)
		if id in Cards.CANCEL_LOOT:
			s._take(549)
			s.g._push({"kind": "loot", "card": 549, "owner": 1}, "turn")
		if id in Cards.REROLL_LOOT:
			s.g._push({"kind": "roll", "owner": 1, "value": 3}, "turn")
		s.ok(0, "loot", {"card": id})
		s.close()
		if id in [567, 643, 644, 645, 646, 650]:
			s.choose(0, "damage", {"target": 2})
			t.equal(s.g.hp[2], 0 if id == 650 else 2, "Бомба%d наносит1или3урона" % id)
		elif id in [572, 655, 656, 657, 658]:
			s.choose(0, "recharge", {"target": 1, "item": 1})
			t.check(not s.g.items[1][1].tapped, "Батарейка%d перезарядила выбранный предмет" % id)
		elif id == 662:
			for item: Dictionary in s.g.items[1]:
				item.tapped = true
			s.choose(0, "recharge_all", {"target": 1})
			t.check(s.g.items[1].all(func(item): return not bool(item.tapped)), "Мегабатарейка перезарядила все предметы выбранного игрока")
		elif id in Cards.CANCEL_LOOT:
			s.choose(0, "cancel_selected")
			t.equal(s.zone_of(549), "discard:loot", "Отменённая карта в сбросе")
			t.equal(s.g.coins[1], 6, "Отмена не пропускает выплату монеты")
		elif id in Cards.REROLL_LOOT:
			s.choose(0, "reroll")
			s.roll(6)
			s.ok(1, "effect_roll")
			s.close()
			t.equal(s.g.last_roll, 6, "Осколок%d оставляет бросок контроллеру" % id)
		s.close()
		t.equal(s.zone_of(id), "discard:loot", "Карта%d не потеряна и не продублирована" % id)
		s.inv("Копия%d" % id)
