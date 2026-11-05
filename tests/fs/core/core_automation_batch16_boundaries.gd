extends "res://tests/fs/core/core_automation_batch16.gd"
## Общие границы пакета16: замещения урона и отсутствовавшая в импорте карта Догмы.
func run(t: Check) -> void:
	var soul = _monster(t, 423)
	soul._take(293)
	soul.g._gain_soul_card(0, {"id": 293, "value": 1})
	soul.operation_panel()
	soul.effect(0, "monster_damage", {"item": 0, "amount": 1})
	_die(soul, 2)
	soul.ok(0, "effect_done")
	soul.close()
	t.equal(int(soul.g.monsters[0].hp), 1, "293 результат2разрешает ровно исходный урон")
	t.equal(soul.g.phase, "turn", "293 вложенная проверка не оставляет пустой эффект")
	var vote = _monster(t, 324)
	vote.operation_panel()
	vote.effect(0, "monster_damage", {"item": 0, "amount": 1})
	for seat in 3:
		vote.choose(seat, "whip_vote16", {"whip": false})
	vote.ok(0, "effect_done")
	vote.close()
	t.equal(int(vote.g.monsters[0].hp), 2, "324 Свист пропускает исходный урон")
	t.equal(vote.g.hands[0].size(), 4, "324 Свист даёт активному1добычу")
	t.equal(vote.g.phase, "turn", "324 голосование возвращается к исходной фазе")
	var dogma = _monster(t, 306)
	_trigger(dogma, "monster_death", {"seat": 0, "card": 306})
	t.check(dogma.g.monsters.any(func(monster): return int(monster.id) == 913), "306 из-за пределов колоды пришли Всадники")
	var slot: int = dogma.g.monsters.size() - 1
	dogma.g.monsters[slot].counters = 3
	dogma.g.monsters[slot].hp = 0
	t.check(dogma.g._replace_monster_death(slot), "913 четвёртая смерть предотвращается")
	dogma.close()
	t.equal(int(dogma.g.monsters[slot].id), 914, "913 четвёртый жетон переворачивает на Зверя")
	for face in [4, 1, 1]:
		for waiting in 8:
			if dogma.g.phase != "priority":
				break
			dogma.close()
		_die(dogma, face)
	for waiting in 8:
		if dogma.g.phase != "priority":
			break
		dogma.close()
	t.equal(dogma.g.hp, [2, 0, 0], "914 все игроки с наименьшим броском умирают")
	t.equal(dogma.g.battle, -1, "913 атака отменена перед превращением")
	t.equal(dogma.g.items[0].size(), 2, "913 предотвращение выдало сокровище")
	var throws = _monster(t, 314, {"hp": 5})
	throws.g.battle = 0
	_trigger(throws, "attack_roll", {"seat": 0, "value": 1})
	_trigger(throws, "attack_roll", {"seat": 0, "value": 6})
	throws.g._apply_combat({"kind": "combat", "owner": 0, "card": 314, "hit": true, "damage": 1, "value": 6})
	t.equal(int(throws.g.monsters[0].hp), 5, "314 промах тоже считается первым броском")

	var moved = _monster(t, 423)
	moved._take(320)
	moved.g._gain_soul_card(0, {"id": 320, "value": 1}, false)
	moved.inv("320 душа ожидает выбора вне награды")
	moved.choose(0, "give_soul16", {"target": 2})
	t.equal(moved.g.souls, [0, 0, 1], "320 активный не получает контроль даже при переносе чужой души")
	moved.inv("320 душа перешла другому")
	var attack = _monster(t, 423)
	attack._take(306)
	attack.g.discards.monster.append(int(attack.g.monsters[1].id))
	attack.g.monsters[1] = {"id": 306, "hp": 4, "dc": 3, "at": 3}
	attack.ok(0, "attack", {"slot": 1})
	attack.close()
	attack.close()
	t.check(attack.g.battle >= 0 and int(attack.g.monsters[attack.g.battle].id) == 306, "306 сдвиг ряда не меняет цель объявленной атаки")
