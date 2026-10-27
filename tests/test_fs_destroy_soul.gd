extends "res://tests/test_fs_passive_fixes.gd"
## Уничтожение выбранной души целиком: счётчик, исходная карта, цена2 и запрет частичного списания.

func _initialize() -> void:
	var g := make()
	g.resolving = {"kind": "reward", "card": 389, "owner": 0}
	g.souls = [0, 3]
	g.soul_cards = [[], [{"id": 428, "value": 1}, {"id": 454, "value": 2}]]
	check(not g.action(0, "effect", {"op": "souls", "amount": -1, "target": 1}), "Счётчик нельзя уменьшить, оставив карты души")
	check(g.souls[1] == 3 and g.soul_cards[1].size() == 2, "Отказ атомарен")
	check(not g.action(0, "effect", {"op": "destroy_soul", "item": -1, "target": 1}), "Отрицательный индекс отклонён")
	check(not g.action(0, "effect", {"op": "destroy_soul", "item": 2, "target": 1}), "Несуществующая душа отклонена")
	check(not g.action(1, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Соперник не применяет эффект за владельца")
	check(g.action(0, "effect", {"op": "destroy_soul", "item": 1, "target": 1}), "Выбрана вторая карта, стоящая две души")
	check(g.souls[1] == 1 and g.soul_cards[1].size() == 1 and g.soul_cards[1][0].id == 428, "Уничтожена вся выбранная карта с её стоимостью")
	check(g.discards.monster.has(454), "Монстр-душа попал в сброс монстров")
	check(g.action(0, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Уничтожена оставшаяся карта")
	check(g.souls[1] == 0 and g.soul_cards[1].is_empty(), "Счётчик и список опустели вместе")
	check(not g.action(0, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Одна и та же душа не уничтожается дважды")
	g.souls[1] = 1
	g.soul_cards[1] = [{"id": 689, "value": 1}]
	g.claimed = [689]
	check(g.action(0, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Бонусная душа покидает контроль игрока")
	check(g.claimed.has(689) and not g.discards.monster.has(689), "Бонусная душа не возвращается в условия получения или колоду монстров")
	g.souls[1] = 1
	g.soul_cards[1] = [{"id": 848, "value": 1}]
	check(not g.action(0, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Душа персонажа не уничтожается этим действием")
	g.soul_cards[1] = [{"id": 843, "value": 1}]
	check(g.action(0, "effect", {"op": "destroy_soul", "item": 0, "target": 1}), "Кость, уже ставшая душой, потеряла прежнюю вечность")
	check(g.souls[1] == 0 and not g.discards.treasure.has(843), "Уничтоженная Кость не возвращается в колоду сокровищ")
	print("DESTROY SOUL: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
