extends SceneTree
## Регрессии исправленных пассивов: получение, повторный пересчёт, уход, передача и старт DLC.
var checks := 0
var errors := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(message)

func make() -> FSRules:
	var g := FSRules.new()
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 26)
	preload("res://tests/fs_test_setup.gd").finish(g)
	g.current = 0
	g.phase = "effect"
	g.items = [[], []]
	g.attack = [1, 1]
	g.max_hp = [2, 2]
	g.hp = [2, 2]
	g.hands = [[], []]
	g.bonuses.clear()
	g.resolving = {"kind": "item", "card": 13, "owner": 0}
	return g

func _initialize() -> void:
	var g := make()
	g._gain_item(0, 16)
	g._finish_responses()
	check(g.attack == [2, 1], "Мамино кольцо добавляет атаку при получении")
	g._refresh_passive_stats()
	g._refresh_passive_stats()
	check(g.attack == [2, 1], "Повторный пересчёт не умножает бонус")
	g.resolving.card = 16
	check(not g.action(0, "effect", {"op": "attack", "amount": 1}), "Учтённый постоянный бонус нельзя применить вручную повторно")
	g.resolving.card = 13
	check(g.action(0, "effect", {"op": "give_item", "target": 1, "item": 0}), "Передача предмета")
	check(g.attack == [1, 2], "Бонус переносится вместе с предметом")
	check(g.action(0, "effect", {"op": "steal", "target": 1, "item": 0}), "Кража предмета обратно")
	check(g.attack == [2, 1], "Кража переносит бонус обратно")
	check(g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0}), "Уничтожение предмета")
	check(g.attack == [1, 1], "Уничтожение снимает бонус")
	g = make()
	g._gain_item(0, 79)
	check(g.max_hp[0] == 3 and g.hp[0] == 2, "Максимум здоровья растёт без бесплатного лечения")
	g.hp[0] = 3
	g.action(0, "effect", {"op": "destroy", "target": 0, "item": 0})
	check(g.max_hp[0] == 2 and g.hp[0] == 2, "Уход источника здоровья ограничивает текущее здоровье")
	g = make()
	g._gain_item(0, 16)
	g._finish_responses()
	g.action(0, "effect", {"op": "temporary_attack", "amount": 2})
	g.action(0, "effect", {"op": "destroy", "item": 0})
	check(g.attack[0] == 3, "Уход предмета сохраняет независимый временный бонус")
	g._end_turn()
	check(g.attack[0] == 1, "В конце хода снимается оставшийся временный бонус")
	check(FSData.characters(true).size() == 47, "С DLC доступны все 47 вариантов персонажей")
	check(FSData.characters(true).any(func(c): return c.card == 906 and c.item == 907), "Промо-Исаак получает Голову Гаппи")
	check(not FSData.characters(false).any(func(c): return c.card == 906), "Промо-вариант не попал в базовый набор")
	var seen := {}
	for seed_value in range(1, 501):
		g = FSRules.new()
		g.new_game([{"name": "А"}, {"name": "Б"}], true, seed_value)
		preload("res://tests/fs_test_setup.gd").finish(g)
		for seat in 2:
			var id: int = g.chars[seat]
			if id in [866, 884, 908] and not seen.has(id):
				seen[id] = true
				check(g.max_hp[seat] == (3 if id == 908 else 1), "Правильное здоровье DLC-персонажа " + str(id))
				if id == 908:
					check(g.hands[seat].size() >= 5 + (1 if g.current == seat else 0), "Первоуровневый Исаак начинает с дополнительным лутом")
		if seen.size() == 3:
			break
	check(seen.size() == 3, "Все три персонажа проверены настоящей раздачей")
	print("PASSIVE FIXES: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
