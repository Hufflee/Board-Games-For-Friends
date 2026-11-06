extends RefCounted
## Начало хода70 открывает выбор магазина без ручного вызова и без повторной активации.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var s := Scenario.new(t).players(2).dlc().current(1).item(0, 70).item(0, 237).shop(0, 243).build()
	var index := -1
	for i in s.g.items[0].size():
		if int(s.g.items[0][i].id) == 70:
			index = i
	s.g.items[0][index].tapped = true
	s.g.tick(11)
	s.no(0, "activate", {"item": index}, "Активация после окна ответов запрещена")
	s.no(0, "item_trigger", {"item": index}, "Автоматический пассив нельзя вызвать вручную")
	var coins: int = int(s.g.coins[0])
	s.g.current = 0
	s.g._emit_passives("turn_start", {"seat": 0})
	s.close()
	t.equal(int(s.g.resolving.get("card", -1)), 70, "Само начало хода вызвало способность70")
	s.choose(0, "discard_shop", {"item": 0})
	t.equal(s.zone_of(243), "discard:treasure", "Сундук сброшен без уничтожения")
	t.equal(s.g.coins[0], coins, "Пассив не вызвал бонус237 за активацию")
	t.check(bool(s.g.items[0][index].tapped), "Пассив не поворачивает и не перезаряжает источник")
	s.no(0, "item_trigger", {"item": -1}, "Отрицательный индекс")
	s.no(0, "item_trigger", {"item": 999}, "Индекс вне инвентаря")
	var dying := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.item(1, 70).monster(0, 344, {"hp": 5, "dc": 6, "at": 9}).build()
	dying.roll(1)
	dying.ok(0, "attack", {"slot": 0})
	dying.ok(0, "roll")
	dying.close()
	t.equal(dying.g.phase, "death", "Штраф смерти объявлен")
	dying.no(1, "item_trigger", {"item": dying.g.items[1].size() - 1}, "Чужой ручной вызов не прерывает оплату штрафа")
	t.equal(dying.g.actor(), 0, "Штраф остался у погибшего игрока")
