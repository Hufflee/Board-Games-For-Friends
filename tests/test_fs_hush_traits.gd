extends "res://tests/test_fs_passive_fixes.gd"
## Тишина: только возрастающие броски в одном ходу, ограничение урона и сброс истории хода.

func hush() -> FSRules:
	var g := make()
	g.phase = "battle_roll"
	g.resolving = {}
	g.battle = 0
	g.monsters = [{"id": 281, "hp": 6, "dc": 1, "at": 1}]
	g.attack[0] = 3
	return g

func attack_roll(g: FSRules, value: int) -> Dictionary:
	g.phase = "priority"
	g.stack = [{"kind": "roll", "owner": 0, "value": value}]
	g._resolve_top()
	return g.stack.back().duplicate(true)

func _initialize() -> void:
	var g := hush()
	var effect := attack_roll(g, 3)
	check(effect.hit, "Первый бросок Тишины не сравнивается с предыдущим ходом")
	g._apply_combat(effect)
	check(g.monsters[0].hp == 5, "Боевые3 урона уменьшены до1")
	g.hp[0] = 2
	effect = attack_roll(g, 3)
	check(not effect.hit and effect.damage == 1, "Повтор той же грани — промах с уроном монстра")
	g._apply_combat(effect)
	check(g.hp[0] == 1 and g.monsters[0].hp == 5, "Повтор ранит игрока, а не монстра")
	g.hp[0] = 2
	check(not attack_roll(g, 2).hit, "Меньший бросок тоже промах")
	check(attack_roll(g, 3).hit, "Сравнение с непосредственно предыдущим броском, не с максимумом")
	g._expire_monster_modifiers(g.monsters[0])
	check(attack_roll(g, 1).hit, "После границы хода история бросков очищена")
	g = hush()
	g.phase = "effect"
	g.resolving = {"kind": "loot", "card": 13, "owner": 0}
	check(g.action(0, "effect", {"op": "monster_damage", "amount": 3, "item": 0}), "Небоевой урон по Тишине разрешён")
	check(g.monsters[0].hp == 5, "Небоевые3 урона также уменьшены до1")
	g.monsters[0]["under"] = {"id": 281, "hp": 6, "dc": 1, "at": 1, "last_attack_roll": 6}
	g._expire_monster_modifiers(g.monsters[0])
	check(not g.monsters[0].under.has("last_attack_roll"), "История очищается и у накрытой карты")
	print("HUSH TRAITS: ", checks, " проверок, ", errors, " ошибок")
	quit(1 if errors else 0)
