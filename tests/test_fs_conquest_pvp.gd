extends "res://tests/test_fs_remaining_death_audit.gd"
## Завоеватель: обязательный выбор PvP, 4+, урон обеим сторонам, штрафы, спасение и отмена.

func duel() -> FSRules:
	var g := reward(268)
	check(g.action(0, "effect_done"), "Награда Завоевателя завершена")
	g.hp = [4, 3]
	g.max_hp = [4, 3]
	g.attack = [2, 1]
	return g

func start(g: FSRules) -> void:
	check(g.action(0, "attack_player", {"target": 1}), "Атака другого игрока объявлена")
	check(g.phase == "priority", "До атаки открыто окно ответов")
	g._finish_responses()
	check(g.phase == "battle_roll" and g.battle_player == 1, "После ответов начинается бой с выбранным игроком")

func resolve_roll(g: FSRules, value: int) -> void:
	g._push({"kind": "roll", "owner": 0, "value": value}, "battle_roll")
	g._resolve_top()
	check(g.stack.back().kind == "player_combat", "Результат создал ответный этап PvP-урона")
	g._resolve_top()

func _initialize() -> void:
	var g := duel()
	check(int(g.get_view(0).required_player_attacks) == 1, "Смерть Завоевателя требует одну дополнительную PvP-атаку")
	check(not g.action(0, "end"), "Нельзя пропустить обязательную PvP-атаку концом хода")
	check(not g.action(0, "attack", {"slot": 0}), "Атака монстра не заменяет PvP")
	check(not g.action(1, "attack_player", {"target": 0}), "Другой игрок не объявляет атаку за активного")
	check(not g.action(0, "attack_player", {"target": 0}), "Нельзя атаковать самого себя")
	check(not g.action(0, "attack_player", {"target": 9}), "Несуществующая цель отклонена")
	start(g)
	check(not g.action(0, "attack_player", {"target": 1}), "Второе объявление не дублирует атаку")
	resolve_roll(g, 4)
	check(g.hp == [4, 1], "4 попадает и наносит атакованному силу атаки активного игрока")
	resolve_roll(g, 3)
	check(g.hp == [3, 1], "3 промахивается и ранит активного силой атаки защищающегося")
	g.attack[0] = 5
	resolve_roll(g, 4)
	check(g.hp[1] == 0, "Избыточный урон не уводит HP ниже0")
	g._finish_responses()
	check(g.phase == "death" and g.actor() == 1 and g.battle_player == -1, "Смерть защищавшегося завершает PvP и открывает его штраф")
	check(g.action(1, "death", {"loot": -1, "item": -1}), "Защищавшийся платит обычный штраф смерти")
	check(g.current == 0 and g.phase == "turn", "После чужой смерти ход активного игрока продолжается")
	check(not g.action(0, "attack_player", {"target": 1}), "Одно обязательство не даёт повторный PvP")
	g = duel()
	g.hp[0] = 1
	g.attack[1] = 4
	start(g)
	resolve_roll(g, 2)
	g._finish_responses()
	check(g.phase == "death" and g.actor() == 0, "При промахе может погибнуть атакующий")
	check(g.action(0, "death", {"loot": -1, "item": -1}), "Атакующий платит обычный штраф")
	check(g.current == 1 and g.battle_player == -1, "Смерть активного игрока передаёт ход")
	g = duel()
	start(g)
	g.hp[1] = 1
	resolve_roll(g, 4)
	g._push({"kind": "item", "card": 13, "owner": 1}, "battle_roll")
	g._finish_responses()
	check(g.action(1, "effect", {"op": "prevent_death", "target": 1}), "Ответ спасает защищающегося до подтверждения смерти")
	check(g.action(1, "effect_done"), "Спасающий ответ завершён")
	g._finish_responses()
	check(g.hp[1] == 1 and g.battle_player == 1 and g.phase == "battle_roll", "Спасение сохраняет текущий PvP-бой")
	g = duel()
	start(g)
	g._push({"kind": "item", "card": 13, "owner": 1}, "battle_roll")
	g._finish_responses()
	check(g.action(1, "effect", {"op": "cancel_attack"}), "Обычная отмена атаки работает и в PvP")
	check(g.action(1, "effect_done") and g.phase == "turn" and g.battle_player == -1, "После отмены нет зависшего боя")
	g = duel()
	g.dead[1] = true
	check(g.get_view(0).player_attack_targets.is_empty() and g.get_view(0).required_player_attacks == 0, "При отсутствии живых целей невозможно запереть ход")
	check(g.action(0, "end"), "Если цели нет, ход можно завершить")
	print("CONQUEST PVP: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
