extends RefCounted
## Ручное условие предмета не является активацией: окно10с, поворот, бонус237 и физический магазин.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	for id: int in [70, 222]:
		var s := Scenario.new(t).players(2).dlc().current(1).item(0, id).item(0, 237).shop(0, 243).build()
		var index := -1
		for i in s.g.items[0].size():
			if int(s.g.items[0][i].id) == id:
				index = i
		s.g.items[0][index].tapped = true
		s.g.tick(11)
		t.check(not s.g.off_turn_open(0), "Чужое окно действительно закрыто")
		s.no(0, "activate", {"item": index, "tap": false}, "Новая активация после10с по-прежнему запрещена")
		var coins: int = s.g.coins[0]
		s.ok(0, "item_trigger", {"item": index, "card": 91, "target": 1}, "Условие своей карты после10с")
		s.close()
		t.equal(s.g.phase, "effect", "Открыт ручной текст условия")
		t.equal(int(s.g.resolving.card), id, "Хост берёт карту из своего инвентаря, а не из запроса")
		t.equal(int(s.g.resolving.owner), 0, "Владелец условия определяется отправителем")
		t.equal(s.g.coins[0], coins, "Условие не вызывает бонус237 за активацию")
		t.check(s.g.items[0][index].tapped, "Пассивный текст не перезарядил повёрнутую карту")
		s.no(1, "effect", {"op": "discard_shop", "item": 0}, "Чужое место не выполняет условие владельца")
		s.effect(0, "discard_shop", {"item": 0})
		t.equal(s.zone_of(243), "discard:treasure", "Сундук сброшен из магазина без уничтожения")
		s.ok(0, "effect_done")
		s.close()
		t.equal(s.g.phase, "turn", "Условие вернуло исходный чужой ход")
		s.no(0, "item_trigger", {"item": -1}, "Отрицательный индекс")
		s.no(0, "item_trigger", {"item": 999}, "Индекс вне своего инвентаря")
		if id == 70:
			s.g.current = 0
			s.g.items[0][index].tapped = false
			s.ok(0, "activate", {"item": index}, "Поворотная часть70 остаётся активацией")
			s.close()
			t.equal(s.g.coins[0], coins + 1, "Настоящая активация вызывает237 ровно один раз")
			t.check(s.g.items[0][index].tapped, "Настоящая активация поворачивает карту")
	var automatic := Scenario.new(t).players(2).dlc().item(0, 518).item(0, 69).build()
	for index in automatic.g.items[0].size():
		var id: int = automatic.g.items[0][index].id
		if id in [518, 69]:
			automatic.no(0, "item_trigger", {"item": index}, "Автоматический518 и платный69 не вызываются как ручной пассив")
	automatic.g.phase = "discard"
	automatic.no(0, "item_trigger", {"item": 0}, "Закрытая фаза не принимает условие")
	# Протокол ручного условия: фактическое наступление текста подтверждает человек.
	# Здесь проверяется сохранение уже объявленной смерти под ручным стеком.
	var dying := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.item(1, 222).monster(0, 344, {"hp": 5, "dc": 6, "at": 9}).build()
	dying.roll(1)
	dying.ok(0, "attack", {"slot": 0})
	dying.ok(0, "roll", null)
	dying.close()
	t.equal(dying.g.phase, "death", "Штраф смерти уже объявлен")
	dying.g.tick(11)
	dying.ok(1, "item_trigger", {"item": 0}, "Ручное условие поверх объявленной смерти")
	dying.close()
	t.equal(dying.g.actor(), 1, "Выбор временно принадлежит владельцу ручного условия")
	dying.ok(1, "effect_done")
	dying.close()
	t.equal(dying.g.phase, "death", "После условия сохранена фаза штрафа")
	t.equal(dying.g.actor(), 0, "Штраф остался у того же погибшего игрока")
	var lost_loot: int = int(dying.g.hands[0][0]) if not dying.g.hands[0].is_empty() else -1
	dying.ok(0, "death", {"loot": lost_loot, "item": -1})
	dying.close()
	t.equal(dying.g.current, 1, "После штрафа очередь продолжилась")
