extends "res://tests/test_fs_passive_fixes.gd"
## Расширение поля монстров: ёмкость сохраняется, награда не теряется при событиях заполнения.

func _initialize() -> void:
	var g := make()
	g.resolving = {"kind": "reward", "card": 360, "owner": 0, "slot": 0}
	g.battle = 0
	g.monsters = [{"id": 360, "hp": 0, "dc": 4, "at": 1}, {"id": 450, "hp": 3, "dc": 4, "at": 1}]
	g.decks.monster = [451, 450, 451, 450]
	check(not g.action(1, "effect", {"op": "expand_monsters", "amount": 2}), "Чужой игрок не расширяет поле чужой наградой")
	check(not g.action(0, "effect", {"op": "expand_monsters", "amount": 0}), "Нулевое расширение отклонено")
	check(g.action(0, "effect", {"op": "expand_monsters", "amount": 2}), "Бластоциста расширяет поле на2")
	check(g.monster_slots == 4 and g.monsters.size() == 2, "Ёмкость увеличена без пропуска оставшейся награды")
	check(g.action(0, "effect", {"op": "loot", "amount": 1}), "Обычная награда всё ещё доступна")
	check(g.action(0, "effect_done"), "Награда завершена")
	check(g.monsters.size() == 4 and g.monster_slots == 4, "Все четыре ячейки заполнены после разрешения эффекта")
	g.hands[0].clear()
	g.phase = "turn"
	g._after_stack = "turn"
	g._end_turn()
	g._finish_responses()
	check(g.monster_slots == 4, "Расширение сохраняется на следующий ход")
	g.new_game([{"name": "А"}, {"name": "Б"}], false, 1)
	check(g.monster_slots == 2, "Новая партия возвращает базовое число ячеек")
	g = make()
	g.resolving = {"kind":"reward","card":360,"owner":0,"slot":0}
	g.battle = 0
	g.monsters = [{"id":360,"hp":0,"dc":4,"at":1},{"id":450,"hp":3,"dc":4,"at":1}]
	g.decks.monster = [450,451,450,715]
	check(g.action(0,"effect",{"op":"expand_monsters","amount":2}), "Расширение перед событием заполнения")
	check(g.action(0,"effect_done"), "Исходная награда не теряется перед Засадой")
	g._finish_responses()
	check(g.monsters.size() == 4 and g.required_deck_attacks == 2, "Событие заполнения разрешено, все дополнительные ячейки заполнены")
	print("MONSTER EXPANSION: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
