extends "res://tests/test_fs_mixed_next.gd"
## Завершение боя удаляет броски и урон, сохраняя ответы; спасение сохраняет бой.
## Запуск: --headless --audio-driver Dummy --script res://tests/test_fs_coal_battle_end.gd.

func duel() -> FSRules:
	var g := clean()
	g.hp = [10, 10]
	g.max_hp = [10, 10]
	g.required_player_attacks = 1
	g.monsters = [{"id": 445, "hp": 10, "dc": 4, "at": 1}]
	g._gain_item(0, 18)
	g._gain_item(0, 42)
	g.hands = [[497], []]
	check(g.action(0, "attack_player", {"target": 1}), "Объявление допустимого PvP")
	g._finish_responses()
	return g

func pending(g: FSRules) -> void:
	g._push({"kind": "roll", "owner": 0, "value": 4}, "battle_roll")
	check(g.action(0, "loot", {"card": 497}), "Ответ Бомбой над броском")
	g._resolve_top()
	check(g.phase == "effect" and g.resolving.card == 497, "Бомба доступна для исполнения")

func _initialize() -> void:
	var g := duel()
	pending(g)
	var coins_before: int = g.coins[0]
	check(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 10}), "Ответ убивает цель")
	check(g.action(0, "effect", {"op": "coins", "amount": 1}), "Остальная часть убившего ответа не пропущена")
	check(g.resolving.card == 497 and g.stack[0].kind == "roll", "До завершения способности ожидающий бросок сохранён")
	check(g.action(0, "effect_done", {}), "Способность завершена штатно")
	check(g.stack.back().kind == "death" and g.battle_player == 1, "Объявление смерти ещё сохраняет бой")
	g._finish_responses()
	check(g.phase == "death" and g.battle_player == -1 and g.stack.is_empty(), "Подтверждённая смерть удалила бросок")
	check(g.discards.loot.count(497) == 1, "Бомба завершена и сброшена ровно один раз")
	check(g.action(1, "death", {}), "Обычный штраф цели")
	g._finish_responses()
	check(g.items[0][1].counters == 0, "Удалённый бросок не вызывает пассив жетонов42")
	check(g.coins[0] == coins_before + 1, "Удалённый бросок не вызывает глобальный пассив445")
	check(g._turn_attack_rolls.is_empty(), "Удалённый бросок не попал в счёт")

	g = duel()
	pending(g)
	check(g.action(0, "effect", {"op": "damage", "target": 1, "amount": 10}), "Летальный ответ перед спасением")
	check(g.action(0, "effect_done", {}), "Ответ завершён, смерть ещё в стеке")
	g._push({"kind": "item", "card": 13, "owner": 1}, "battle_roll")
	g._resolve_top()
	check(g.action(1, "effect", {"op": "prevent_death", "target": 1}), "Спасение до разрешения смерти")
	check(g.action(1, "effect", {"op": "heal", "target": 1, "amount": 4}), "Спасённая цель переживёт ожидающую атаку")
	check(g.action(1, "effect_done", {}), "Спасение завершено")
	g._finish_responses()
	check(g.battle_player == 1 and g.phase == "battle_roll", "Спасение сохранило бой")
	check(int(g._turn_attack_rolls.get(0, 0)) == 1 and g.items[0][1].counters == 1,
		"Сохранённый бросок разрешён и вызывает пассивы ровно один раз")
	check(g.hp[1] == 4, "После спасения сохранённая атака нанесла урон1")

	g = duel()
	g._push({"kind": "roll", "owner": 0, "value": 6}, "battle_roll")
	g._resolve_top()
	check(g.stack[0].kind == "player_combat", "Боевой урон ожидает разрешения")
	g._push({"kind": "item", "card": 13, "owner": 1}, "battle_roll")
	g._resolve_top()
	check(g.action(1, "effect", {"op": "cancel_attack"}), "Явная отмена боя")
	check(g.stack.all(func(e): return e.kind not in ["roll", "combat", "player_combat"]), "Отмена удаляет также ожидающий боевой урон")
	check(g.action(1, "effect_done", {}), "Отменившая бой способность завершается")
	g._finish_responses()
	check(g.hp[1] == 10 and g.phase == "turn", "Отменённый урон не нанесён")

	g = duel()
	pending(g)
	check(g.action(0, "effect", {"op": "damage", "target": 0, "amount": 10}), "Ответ убивает атакующего")
	check(g.action(0, "effect_done", {}), "Убившая атакующего способность завершена")
	g._finish_responses()
	check(g.actor() == 0 and g.phase == "death" and g.stack.is_empty(), "Смерть атакующего тоже удаляет ожидающий бросок")

	print("COAL BATTLE END: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
