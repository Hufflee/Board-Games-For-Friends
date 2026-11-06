extends RefCounted
## Ручные операции Кармы/Сундука: физическая карта, магазин без покупки и запрет неверного индекса.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var s := Scenario.new(t).players(3).dlc().current(0).item(0, 8).build()
	s.g.phase = "effect"
	s.g.resolving = {"kind": "item", "card": 8, "owner": 0}
	var first: int = s.g.shop[0]
	var second: int = s.g.shop[1]
	var coins: Array = s.g.coins.duplicate()
	var buys: int = s.g.buy_left
	s.effect(0, "take_shop", {"target": 1, "item": 0})
	s.effect(0, "loot", {"target": 1, "amount": 1})
	s.effect(0, "take_shop", {"target": 2, "item": 1})
	s.effect(0, "loot", {"target": 2, "amount": 1})
	t.check(s.g.items[1].any(func(item): return item.id == first), "Первый выбранный игрок получил карту магазина")
	t.check(s.g.items[2].any(func(item): return item.id == second), "Второй выбранный игрок получил другую карту магазина")
	t.equal(s.g.coins, coins, "Кража магазина не платит и не создаёт монеты")
	t.equal(s.g.buy_left, buys, "Кража магазина не расходует покупку")
	t.equal(s.g.shop.size(), 2, "Магазин добран без расширения")
	s.no(0, "effect", {"op": "take_shop", "target": 1, "item": -1}, "Отрицательный индекс магазина")
	s.no(0, "effect", {"op": "take_shop", "target": 1, "item": 99}, "Индекс вне магазина")
	s.no(1, "effect", {"op": "take_shop", "target": 1, "item": 0}, "Чужой игрок не управляет ручным эффектом Кармы")
	var chest := Scenario.new(t).players(2).dlc().current(0).item(0, 243).build()
	chest.g._begin_resolving({"kind": "item", "card": 243, "owner": 0})
	var index: int = chest.g.items[0].find(chest.g.items[0].filter(func(item): return item.id == 243)[0])
	chest.effect(0, "item_to_soul", {"target": 0, "item": index})
	t.equal(chest.g.soul_cards[0].filter(func(card): return card.id == 243).size(), 1, "Сундук превращается в физическую карту души")
	t.check(not chest.g.items[0].any(func(item): return item.id == 243), "Сундук больше не предмет и не сохраняет способности")
	chest.inv("После превращения Сундука")
	# Общая операция уже существовала, но старые строки реестра70/222 считали её отсутствующей.
	for card: int in [70, 222]:
		var discard := Scenario.new(t).players(2).dlc().current(0).item(0, card).shop(0, 243).shop(1, 91).build()
		discard.operation_panel()
		var old_coins: Array = discard.g.coins.duplicate()
		var old_buys: int = discard.g.buy_left
		discard.effect(0, "discard_shop", {"item": 0})
		t.equal(discard.zone_of(243), "discard:treasure", "Обычный сброс магазина не уничтожает Сундук и не превращает его")
		t.check(int(discard.g.shop[0]) >= 0 and int(discard.g.shop[0]) != 243, "Освобождённая ячейка добрана")
		if card == 222:
			discard.effect(0, "discard_shop", {"item": 1})
			t.equal(discard.zone_of(91), "discard:treasure", "Пополнение позволяет выбрать также второй прежний предмет")
		t.equal(discard.g.coins, old_coins, "Сброс не расходует и не создаёт монеты")
		t.equal(discard.g.buy_left, old_buys, "Сброс не расходует покупку")
		discard.no(0, "effect", {"op": "discard_shop", "item": -1}, "Отрицательный индекс отклонён")
		discard.no(0, "effect", {"op": "discard_shop", "item": 99}, "Индекс за магазином отклонён")
		discard.inv("Ручной сброс магазина")
	var empty := Scenario.new(t).players(2).dlc().current(0).item(0, 222).shop(0, -1).build()
	empty.g._begin_resolving({"kind": "item", "card": 222, "owner": 0})
	empty.no(0, "effect", {"op": "discard_shop", "item": 0}, "Пустую ячейку нельзя сбросить как физическую карту")
