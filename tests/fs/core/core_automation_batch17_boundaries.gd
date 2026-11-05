extends "res://tests/fs/core/core_automation_batch17.gd"
## Общие границы группы17: двусторонний боевой урон, яйца и отдельная добавочная атака.
func run(t: Check) -> void:
	var skull = _monster(t, 355, {"hp": 1})
	_attack_roll17(skull, 1)
	skull.close()
	t.check(355 in skull.g.discards.monster, "355 единица убивает монстра с1HP")
	t.equal(skull.g.hp[0], 1, "355 смерть монстра сохраняет уже назначенный урон промаха")
	skull.inv("355 два боевых результата")
	var egg = _monster(t, 343)
	_trigger(egg, "monster_death", {"seat": 0, "card": 343})
	egg.g.discards.monster.append(int(egg.g.monsters.pop_at(0).id))
	egg.g.battle = 0
	_trigger(egg, "death", {"seat": 0})
	t.check(egg.g._card_choices().all(func(choice): return int(choice.arg.item) < egg.g.monster_slots and int(choice.arg.item) != egg.g.battle), "343 нельзя создать лишний слот или накрыть атакуемый")
	var extra = _monster(t, 360)
	extra.g.attack_left = 0
	extra.g.attacked = true
	_trigger(extra, "monster_death", {"seat": 0, "card": 360})
	extra.choose(0, "extra_blind17")
	extra.no(0, "attack_familiar15", {"index": 0})
	extra.g.decks.monster.erase(423)
	extra._take(427)
	extra.g.decks.monster.append(427)
	extra.ok(0, "attack", {"slot": -1, "over": 0})
	t.equal(extra.g._optional_blind17, 0, "360 бонус расходуется объявлением атаки колоды")
	t.check(extra.g.attacked, "360 обычные атаки после расхода закрыты")
	var counter = _monster(t, 342, {"counters": 6})
	_trigger(counter, "turn_start", {"seat": 0})
	t.equal(counter.g.hp[0], 0, "342 шесть жетонов убивают активного в начале хода")
