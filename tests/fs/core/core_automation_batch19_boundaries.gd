extends "res://tests/fs/core/core_automation_batch19.gd"
## Общие границы запрета урона, защиты от сброса и реального броска без дубля.
func run(t: Check) -> void:
	var room = _monster(t, 266)
	room._take(817)
	room.g.room = 817
	_trigger(room, "monster_damage", {"seat": -1, "card": 266, "amount": 1})
	t.equal(room.g.hp, [2, 2, 2], "817 урон монстра не считается уроном игрока")
	t.equal(room.g.hands[0].size(), 3, "266 урон монстра не даёт добычу игроку")
	t.check(room.g.resolving.is_empty(), "266/817 не создают исполнителя−1")
	var safe = _monster(t, 439)
	_item(safe, 1, 523)
	_trigger(safe, "roll", {"seat": 1, "value": 5})
	t.equal(safe.g.hands[1].size(), 2, "523 блокирует обязательный сброс439")
	t.check(not safe.g._card_automation_active(), "523 не оставляет чужой выбор без допустимых карт")
	for id in [440, 445]:
		var actual = _monster(t, id)
		actual.g.phase = "turn"
		actual.g._roll_passives(2 if id == 440 else 4, 1)
		actual.close()
		if id == 440:
			t.equal(actual.g.hp[1], 0, "440 настоящий бросок наносит только2урона")
		else:
			t.equal(actual.g.coins[1], 11, "445 настоящий бросок не дублирует2монеты")
	var immune = _monster(t, 364, {"hp": 5})
	_item(immune, 0, 144)
	_attack_roll17(immune, 6)
	t.equal(int(immune.g.monsters[0].hp), 5, "364 общий запрет не обходится бонусом Проклятого глаза")
	var peep = _monster(t, 429, {"hp": 0})
	peep.g._continue_stack()
	peep.close()
	t.check(not peep.g.resolving.has("spawn_card"), "429 отсутствует старое ручное окно поверх автоматического выбора")
	peep.choose(0, "bloat_place19", {"item": 1})
	peep.close()
	t.check(peep.g.soul_cards[0].any(func(soul): return int(soul.id) == 429), "429 награда продолжается после размещения Утопца")
