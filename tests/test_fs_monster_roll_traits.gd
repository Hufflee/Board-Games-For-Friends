extends "res://tests/test_fs_passive_fixes.gd"
## Напечатанные боевые условия Прыгуна, Пина и Чаба; подготовленные броски без подмены ожиданий.

func _initialize() -> void:
	for id: int in [428, 441]:
		var g := make()
		g.phase = "battle_roll"
		g.resolving = {}
		g.battle = 0
		g.monsters = [{"id": id, "hp": 2, "dc": 3, "at": 1}]
		g._apply_combat({"kind": "combat", "owner": 0, "card": id, "value": 6, "hit": true, "damage": 1})
		check(g.monsters[0].hp == 2, "Шестёрка не наносит боевой урон: " + FSData.title(id))
		g.monsters[0].hp = 2
		g._apply_combat({"kind": "combat", "owner": 0, "card": id, "value": 5, "hit": true, "damage": 1})
		check(g.monsters[0].hp == 1, "Пятёрка наносит обычный урон: " + FSData.title(id))
		g._apply_combat({"kind": "combat", "owner": 0, "card": id, "value": 6, "hit": false, "damage": 1})
		check(g.hp[0] == 1, "Иммунитет монстра не защищает игрока от промаха на6: " + FSData.title(id))
	var g := make()
	g.phase = "battle_roll"
	g.resolving = {}
	g.battle = 0
	g.monsters = [{"id": 462, "hp": 1, "dc": 3, "at": 1}]
	g._apply_combat({"kind": "combat", "owner": 0, "card": 462, "value": 1, "hit": false, "damage": 1})
	check(g.monsters[0].hp == 3, "Чаб лечится на2 при единице атаки")
	g.hp[0] = 2
	g.monsters[0].hp = 3
	g._apply_combat({"kind": "combat", "owner": 0, "card": 462, "value": 1, "hit": false, "damage": 1})
	check(g.monsters[0].hp == 4, "Лечение Чаба ограничено напечатанным максимумом4")
	print("MONSTER ROLL TRAITS: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
