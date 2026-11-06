extends RefCounted
## Получение контроля над душой: Друг7, ручной выбор Кармы8, перенос и вложенное продолжение после10с.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _manual(s, owner: int, card: int) -> void:
	s.g._begin_resolving({"kind": "item", "card": card, "owner": owner})

func _index(s, seat: int, card: int) -> int:
	for index in s.g.items[seat].size():
		if int(s.g.items[seat][index].id) == card:
			return index
	return -1

func run(t: Check) -> void:
	var friend := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(1).item(0, 7).hand(1, [475]).build()
	friend.ok(1, "loot", {"card": 475})
	friend.close()
	t.equal(friend.g.items[0][_index(friend, 0, 7)].counters, 1, "Чужая Потерянная душа добавляет жетон Другу")
	t.equal(friend.zone_of(475), "soul:1", "Карта лута физически стала чужой душой")
	_manual(friend, 0, 7)
	friend.no(0, "effect", {"op": "counter", "target": 0, "item": _index(friend, 0, 7), "amount": 1}, "Автоматический жетон нельзя повторить вручную")
	friend.no(0, "effect", {"op": "item_to_soul", "target": 0, "item": _index(friend, 0, 7)}, "Автоматическое превращение нельзя повторить вручную")
	var own := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(0).item(0, 7).hand(0, [475]).build()
	own.ok(0, "loot", {"card": 475})
	own.close()
	t.equal(own.g.items[0][_index(own, 0, 7)].counters, 0, "Собственная душа не добавляет жетон")
	var third := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(1).item(0, 7, {"counters": 2}).hand(1, [475]).build()
	third.ok(1, "loot", {"card": 475})
	third.close()
	t.equal(third.zone_of(7), "soul:0", "Третий жетон переносит самого Друга в души")
	t.equal(third.g.souls[0], 1, "Друг дал одну душу")
	t.equal(_index(third, 0, 7), -1, "Превратившийся Друг перестал быть предметом")
	third.inv("После автоматического превращения")
	var moved := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(3).dlc().current(2).item(0, 7).item(2, 13).soul(1, 475).build()
	_manual(moved, 2, 13)
	moved.effect(2, "steal_soul", {"target": 1, "item": 0})
	moved.close()
	t.equal(moved.g.items[0][_index(moved, 0, 7)].counters, 1, "Передача старой души тоже меняет контроль")
	t.equal(moved.zone_of(475), "soul:2", "Душа не скопирована при краже")
	t.equal(moved.g.souls[1], 0, "Прежний владелец больше не считает душу")
	# Обязательная Карма сама открывает ручную панель, даже когда новое применение карт закрыто.
	var karma := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(3).dlc().current(1).item(0, 8).item(1, 243).build()
	karma.g.tick(11.0)
	t.check(karma.g.off_turn_open(0), "Окна 10 с больше нет: свои карты в чужой ход открыты (06.11)")
	_manual(karma, 1, 243)
	karma.effect(1, "item_to_soul", {"target": 1, "item": _index(karma, 1, 243)})
	karma.close()
	t.equal(karma.g.resolving.card, 8, "Получение чужой души само открыло Карму")
	t.equal(karma.g.actor(), 0, "Выбор принадлежит владельцу Кармы, не активному игроку")
	karma.no(1, "effect", {"op": "take_shop", "target": 1, "item": 0}, "Активный не выбирает за владельца Кармы")
	var first: int = karma.g.shop[0]
	var second: int = karma.g.shop[1]
	var coins: Array = karma.g.coins.duplicate()
	karma.effect(0, "take_shop", {"target": 1, "item": 0})
	karma.effect(0, "loot", {"target": 1, "amount": 1})
	karma.effect(0, "take_shop", {"target": 2, "item": 1})
	karma.effect(0, "loot", {"target": 2, "amount": 1})
	t.check(karma.g.items[1].any(func(item): return item.id == first), "Первый выбранный игрок получил предмет")
	t.check(karma.g.items[2].any(func(item): return item.id == second), "Второй выбранный игрок получил другой предмет")
	t.equal(karma.g.coins, coins, "Оба предмета получены без оплаты")
	karma.ok(0, "effect_done", null)
	t.equal(karma.g.resolving.card, 243, "После Кармы вернулся прежний эффект Сундука")
	karma.ok(1, "effect_done", null)
	karma.close()
	t.equal(karma.zone_of(243), "soul:1", "Вложенная Карма не потеряла исходную душу")
	karma.inv("После вложенной Кармы")
	# Та же вложенность поверх награды: признак kept_as_soul обязан пережить ручную Карму.
	var reward := Scenario.new(t).players(3).dlc().current(1).item(0, 8) \
		.monster(0, 345, {"hp": 1, "dc": 1}).monster(1, 344).room(-1).build()
	reward.roll(6)
	reward.ok(1, "attack", {"slot": 0})
	reward.ok(1, "roll", null)
	reward.close()
	t.equal(reward.g.resolving.card, 8, "Награда монстра вызывает вложенную Карму")
	reward.choose(0, "karma_first20", {"target": 1})
	reward.choose(0, "karma_second20", {"target": 2})
	reward.close()
	reward.choose(1, "take_shop", {"item": 0})
	reward.close()
	reward.choose(2, "take_shop", {"item": 1})
	reward.close()
	t.equal(reward.zone_of(345), "soul:1", "Награда не положила ту же карту ещё и в сброс")
	reward.inv("Награда после Кармы")
	for automatic: bool in [false, true]:
		var bonus := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(1).item(0, 7).coins(1, 25).build()
		if not bonus.g.bonuses.has(689):
			bonus.g.bonuses.append(689)
		bonus.ok(1, "end" if automatic else "claim", null if automatic else {"card": 689})
		bonus.close()
		t.equal(bonus.g.items[0][_index(bonus, 0, 7)].counters, 1, "Бонусная душа вызывает Друга: автоматическая=%s" % automatic)
		t.equal(bonus.zone_of(689), "soul:1", "Бонусная карта получена физически")
	var removed := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(1).item(0, 7, {"counters": 2}).hand(1, [475]).build()
	removed.ok(1, "loot", {"card": 475})
	# Между постановкой пассива и разрешением источник может покинуть стол.
	removed.g._destroy_item(0, _index(removed, 0, 7))
	removed.close()
	t.equal(removed.zone_of(7), "discard:treasure", "Ушедший источник не превратился задним числом")
	t.equal(removed.g.souls[0], 0, "Отложенный триггер не создал вторую копию уничтоженного Друга")
	# Проверка выигрыша должна выполняться и при тихом разрешении, без нового клика.
	var win := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(2).dlc().current(1).item(0, 7, {"counters": 2}) \
		.soul(0, 344).soul(0, 345).soul(0, 346).hand(1, [475]).build()
	win.ok(1, "loot", {"card": 475})
	for i in 5:
		win.g.tick(5.1)
	t.equal(win.g.winner, 0, "Друг дал четвёртую душу без нового действия")
	t.equal(win.g.phase, "game_over", "Тихий таймер показал окончание партии")
	# Extended RulebookP4: одна физическая карта ценностью2 учитывается как две души для триггеров.
	# На полном изображении312 напечатано+2души; переносится всё равно одна карта.
	for trigger: int in [7, 8]:
		var double := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(3).dlc().current(2).item(0, trigger).item(2, 13).soul(1, 312).build()
		double.g.soul_cards[1][0].value = 2
		double.g.souls[1] = 2
		_manual(double, 2, 13)
		double.effect(2, "steal_soul", {"target": 1, "item": 0})
		double.close()
		if trigger == 7:
			t.equal(double.g.items[0][_index(double, 0, 7)].counters, 2, "Карта ценностью2 даёт Другу два жетона")
		else:
			for repeat in 2:
				t.equal(double.g.resolving.get("card"), 8, "Карма срабатывает на каждую единицу души: %d" % repeat)
				double.ok(0, "effect_done", null)
				double.close()
			t.equal(double.g.resolving.get("card"), 13, "Оба срабатывания Кармы вернули внешний эффект")
		t.equal(double.g.soul_cards[2].size(), 1, "Несколько триггеров не копируют физическую карту")
		t.equal(double.g.souls[2], 2, "Получатель считает полную душевую ценность")
		double.inv("Карта с двойной душевой ценностью")
	# Контроль источника может смениться после постановки обязательного триггера.
	var transferred := Scenario.new(t).rules_type(preload("res://tests/fs/fs_legacy_manual_reward_rules.gd")).players(3).dlc().current(1).item(0, 7, {"counters": 2}).build()
	var source: Dictionary = transferred.g.items[0][_index(transferred, 0, 7)]
	transferred.g._queue_passive(0, 7, source, [{"op": "counter_soul", "amount": 1}])
	transferred.g.items[2].append(transferred.g._remove_item(0, _index(transferred, 0, 7)))
	transferred.close()
	t.equal(transferred.zone_of(7), "soul:2", "Переданный источник превращается у своего текущего контроллера")
	t.equal(transferred.g.souls[0], 0, "Прежний контроллер не получает чужую физическую карту")
	transferred.inv("Передача источника перед третьим жетоном")
