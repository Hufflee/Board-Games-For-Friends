extends RefCounted
## 20 физических карт добычи: урон, заряды, отмена выбранной карты, переброс, щиты и отложенный урон.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_card_automation.gd")

func _game(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 908) \
		.no_items(0).no_items(1).no_items(2).hand(0, [id]).hand(1, [477, 478]).hand(2, []) \
		.item(1, 40, {"tapped": true}).coins(0, 3).coins(1, 6).monster(0, 423).monster(1, 427).build()
	s.g.bonuses.clear()
	return s

func _choose(s: RefCounted, t: Check, op: String, target: int = -1) -> void:
	var choices: Array = s.g._card_choices()
	for i in choices.size():
		if str(choices[i].arg.op) == op and (target < 0 or int(choices[i].arg.get("target", -1)) == target):
			s.ok(0, "card_choice", {"index": i, "revision": s.g.revision})
			s.close()
			return
	t.check(false, "Нет выбора " + op)

func run(t: Check) -> void:
	t.equal(Cards.BATCH_03.size(), 20, "Пакет20физическихкарт")
	for id in Cards.BATCH_03:
		var s = _game(t, id)
		if id in [509, 510, 511]:
			s.no(0, "loot", {"card": id}, "Боб нельзя потратить без допустимой цели")
			s._take(549)
			s.g._push({"kind": "loot", "card": 549, "owner": 1}, "turn")
		if id in [515, 516, 517]:
			s.no(0, "loot", {"card": id}, "Осколок нельзя потратить без броска")
			s.g._push({"kind": "roll", "owner": 1, "value": 3}, "turn")
		s.ok(0, "loot", {"card": id})
		s.close()
		s.no(0, "effect", {"op": "coins", "amount": 99}, "Произвольная операция не заменяет текст карты")
		if id in [497, 498, 499, 541, 512]:
			_choose(s, t, "damage", 1)
			t.equal(s.g.hp[1], 0 if id == 512 else 1, "Бомба%d наносит напечатанный урон" % id)
			t.equal(s.g.hp[0], 2, "Бомба не меняет здоровье невыбранного игрока")
		elif id in [507, 508]:
			var choices: Array = s.g._card_choices()
			for i in choices.size():
				if choices[i].label.contains("G Fuel"):
					s.ok(0, "card_choice", {"index": i, "revision": s.g.revision})
					break
			t.check(not s.g.items[1].filter(func(item): return int(item.id) == 40)[0].tapped, "Батарейка%d заряжает чужой предмет" % id)
		elif id in [509, 510, 511]:
			_choose(s, t, "cancel_selected")
			t.equal(s.zone_of(549), "discard:loot", "Боб отменяет выбранную физическую добычу")
			t.equal(s.g.coins[1], 6, "Отменённая монета не начисляется")
		elif id in [515, 516, 517]:
			_choose(s, t, "reroll")
			t.equal(s.g.actor(), 1, "Осколок возвращает кубик его контроллеру")
			s.no(0, "effect_roll", null, "Автор карты не бросает вместо другого игрока")
			s.roll(5)
			s.ok(1, "effect_roll")
			s.close()
			t.equal(s.g.last_roll, 5, "Переброс%d использовал настоящий источник" % id)
		elif id in [524, 525, 554]:
			_choose(s, t, "prevent_damage", 1)
			s.g._damage_player(1, 1)
			t.equal(s.g.hp[1], 2, "Сердце%d предотвратило1урон" % id)
			s.g._damage_player(1, 1)
			t.equal(s.g.hp[1], 1, "Сердце не предотвращает второй урон")
		elif id in [531, 532]:
			_choose(s, t, "black_heart", 1)
			s.g._damage_player(1, 1)
			t.equal(s.g.hp[1], 2, "Чёрное сердце тоже предотвращает1урон")
			s.g._emit_passives("death", {"seat": 1})
			s.close()
			t.equal(s.g.hp[0], 2, "Отложенный урон исключает автора сердца")
			t.equal(s.g.hp[2], 1, "Отложенный урон2третьемуигроку")
			t.equal(s.g.hp[1], 2, "Отложенный урон исключает выбранного игрока")
			s.g._card_delayed.clear()
			s.g._emit_passives("death", {"seat": 1})
			s.close()
			t.equal(s.g.hp[2], 1, "После истечения отложенный эффект не повторяется")
		elif id == 542:
			_choose(s, t, "double_coins", 1)
			t.equal(s.g.coins[1], 12, "Двойка бубен даёт выбранному столько же монет")
			t.equal(s.g.coins[0], 3, "Двойка бубен не платит автору вместо цели")
		elif id == 501:
			t.check(not s.g._card_choices().any(func(c): return int(c.arg.get("target", -1)) == 0), "Двойка пик требует другого игрока")
			_choose(s, t, "spades_loot", 1)
			t.equal(s.g.hands[0].size(), 2, "Автор берёт столько лута, сколько у выбранного соперника")
			t.equal(s.g.hands[1].size(), 2, "Двойка пик не забирает чужую руку")
		t.check(s.zone_of(id) == "discard:loot", "Карта%d после эффекта в сбросе ровно одна" % id)
		s.inv("Автоматическая добыча%d" % id)
