extends "res://tests/fs/core/core_automation_batch28.gd"
## Пакет правок 07.11 (просьбы владельца): проклятия, души боссов, Доп. жизнь, ответы и предметы
## в чужой ход, покупка вслепую, «Больше вариантов», аварийные действия хоста, «Рак».
## Довести стек и выборы до спокойного состояния (первый допустимый вариант).
func _settle29(s: RefCounted) -> void:
	for i in 12:
		if s.g.phase == "priority":
			s.close()
		elif s.g.phase == "effect" and not s.g._card_choices().is_empty():
			s.g.action(s.g.actor(), "card_choice", {"index": 0, "revision": s.g.revision})
		else:
			break

func run(t: Check) -> void:
	for curse in [729, 705, 736]:
		var s = _game(t, 40)
		s._take(curse)
		s.g._push({"kind": "event", "card": curse, "owner": 0}, "turn")
		s.close()
		t.equal(s.g.phase, "effect", "%d при выходе ждёт выбора, кому отдать" % curse)
		s.choose(0, "attach_curse28", {"target": 1})
		s.close()
		t.check(curse in s.g.curses[1] and s.g.phase == "turn", "%d привязано к выбранному игроку, партия продолжается" % curse)
	var tiny = _game(t, 40)
	tiny._take(729)
	tiny.g.curses[0].append(729)
	tiny.ok(0, "end")
	_settle29(tiny)
	t.equal(tiny.g.phase, "discard", "729 в конце хода — сброс до 2")
	while tiny.g.phase == "discard" and tiny.g.hands[0].size() > 2:
		tiny.ok(0, "discard", {"card": int(tiny.g.hands[0][0])})
	_settle29(tiny)
	t.equal(tiny.g.hands[0].size(), 2, "729 рука 2 карты, ход передан")

	for boss in [375, 396, 404, 422]:
		t.equal(int(tiny.g._printed_monster_reward(boss).get("souls", 0)), 1, "%d босс: в награде душа «+1» (изображение)" % boss)

	var life = _game(t, 142)
	life.g.hp[0] = 1
	life.g.monsters[0].at = 3
	life.ok(0, "attack", {"slot": 0})
	life.close()
	life.roll(1)
	life.ok(0, "roll")
	for i in 6:
		if life.g.phase == "priority":
			life.close()
	t.check(life.g.phase == "turn" and life.g.battle < 0 and not life.g.dead[0], "142 спасение: атака отменена, обычный ход")
	t.check(life.g.action(0, "attack", {"slot": 1}), "142 можно атаковать ещё раз")

	var strict = _game(t, 40)
	strict.g.strict_responses28 = true
	_item(strict, 1, 16)
	strict.g._push({"kind": "roll", "value": 3, "owner": 0}, "turn")
	strict.no(0, "end", null, "строгий режим: активный не закрывает окно ответов своим действием")
	strict.close()
	strict.g.phase = "turn"
	t.check(strict.g.off_turn_open(1, "activate"), "строгий режим: предмет в чужой ход — в любой момент")
	t.check(not strict.g.off_turn_open(1, "loot"), "строгий режим: добыча в чужой ход — только в ответ")

	var blind = _game(t, 40)
	_item(blind, 0, 229)
	t.equal(blind.g._purchase_cost(0, -1), 10, "вслепую без скидки — по тексту «предметы магазина» (решение владельца 07.11)")
	t.equal(blind.g._purchase_cost(0, 0), 5, "предмет магазина со скидкой 229")

	var options = _game(t, 40)
	options.g.bank -= 22
	options.g.coins[0] = 30
	options._take(105)
	options.g.discards.treasure.append(int(options.g.shop[0]))
	options.g.shop[0] = 105
	options.ok(0, "buy", {"slot": 0})
	for i in 3:
		if options.g.phase == "priority":
			options.close()
	t.check(options.g.action(0, "buy", {"slot": 1}), "105 куплена в свой ход — вторая покупка сразу")

	var stuck = _game(t, 40)
	stuck.g.phase = "effect"
	stuck.g.resolving = {}
	t.check(stuck.g.host_unstick28("recover") and stuck.g.phase == "turn", "хост снимает зависание «эффект без эффекта»")
	stuck._take(497)
	stuck.g._push({"kind": "loot", "card": 497, "owner": 0}, "turn")
	t.check(stuck.g.host_unstick28("end_turn"), "хост заканчивает ход принудительно")
	_settle29(stuck)
	t.check(497 in stuck.g.discards.loot and not stuck.g.stack.any(func(e): return int(e.get("card", -1)) == 497), "добыча из снятого стека в сбросе, не потеряна")
	t.check(stuck.g.current != 0 or stuck.g.phase == "discard", "ход передан (или идёт сброс до лимита)")

	var cancer = _game(t, 40)
	cancer._take(552)
	cancer.g._gain_item(0, 552)
	cancer.ok(0, "attack", {"slot": 0})
	cancer.close()
	cancer.roll(3)
	cancer.ok(0, "roll")
	var rolls: Array = cancer.g.stack.filter(func(e): return str(e.kind) == "roll")
	t.equal(int(rolls[0].value) if not rolls.is_empty() else -1, 4, "552 первый бросок хода +1 (3 → 4)")
	t.equal(int(cancer.g._last_raw_die20), 3, "552 выпавшая грань сохраняется отдельно для показа")

	var fix = _game(t, 40)
	var coins_fix: int = int(fix.g.coins[1])
	t.check(fix.g.resolving.is_empty(), "хост: эффекта нет")
	t.check(fix.g.host_apply28(0, {"op": "coins", "target": 1, "amount": 2}), "хост: операция без текущего эффекта принята")
	t.equal(int(fix.g.coins[1]), coins_fix + 2, "хост: монеты выданы")
	t.check(fix.g.resolving.is_empty() and fix.g.phase == "turn", "хост: временный эффект сразу завершён, ход продолжается")
