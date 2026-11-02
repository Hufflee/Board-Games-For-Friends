extends RefCounted
## Сундук243: замещение обычного уничтожения, штраф смерти и событие чужой души.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _index(s, seat: int, id: int) -> int:
	for i in s.g.items[seat].size():
		if int(s.g.items[seat][i].id) == id:
			return i
	return -1

func run(t: Check) -> void:
	var s := Scenario.new(t).players(2).dlc().current(0).no_items(0).item(0, 243).item(1, 7).build()
	s.g._begin_resolving({"kind": "item", "card": 13, "owner": 0})
	s.effect(0, "destroy", {"target": 0, "item": _index(s, 0, 243)})
	s.close()
	t.equal(s.zone_of(243), "soul:0", "Уничтожение превращает Сундук в душу владельца")
	t.equal(s.g.souls[0], 1, "Сундук даёт одну душу")
	t.equal(_index(s, 0, 243), -1, "Сундук перестал быть предметом")
	t.equal(s.g.items[1][_index(s, 1, 7)].counters, 1, "Превращение вызывает чужого Друга")
	s.inv("Сундук после уничтожения")
	var death := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.item(0, 243).item(0, 91).item(1, 7).hand(0, [497]).monster(0, 344, {"hp": 5, "dc": 6, "at": 9}).build()
	death.roll(1)
	death.ok(0, "attack", {"slot": 0})
	death.ok(0, "roll", null)
	death.close()
	t.equal(death.g.phase, "death", "Смерть дошла до выбора штрафа")
	death.ok(0, "death", {"loot": 497, "item": _index(death, 0, 243)})
	death.close()
	t.equal(death.zone_of(243), "soul:0", "Штраф смерти тоже превращает Сундук")
	t.check(_index(death, 0, 91) >= 0, "Штраф не требует уничтожить второй предмет")
	t.equal(death.zone_of(497), "discard:loot", "Остальной штраф смерти выполнен")
	t.equal(death.g.items[1][_index(death, 1, 7)].counters, 1, "Смерть не теряет вызванный Сундуком пассив")
	death.inv("Сундук после штрафа смерти")
	# Тот же перенос во время штрафа может открыть чужую обязательную ручную Карму.
	var karma := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.item(0, 243).item(1, 8).hand(0, [497]).shop(0, 91).shop(1, 229) \
		.monster(0, 344, {"hp": 5, "dc": 6, "at": 9}).build()
	karma.roll(1)
	karma.ok(0, "attack", {"slot": 0})
	karma.ok(0, "roll", null)
	karma.close()
	karma.ok(0, "death", {"loot": 497, "item": _index(karma, 0, 243)})
	karma.close()
	t.equal(karma.g.resolving.get("card"), 8, "Сундук из штрафа открывает Карму перед окончанием хода")
	t.equal(karma.g.actor(), 1, "Выбор принадлежит владельцу Кармы")
	karma.effect(1, "take_shop", {"target": 0, "item": 0})
	karma.effect(1, "loot", {"target": 0, "amount": 1})
	karma.effect(1, "take_shop", {"target": 1, "item": 1})
	karma.effect(1, "loot", {"target": 1, "amount": 1})
	karma.ok(1, "effect_done", null)
	karma.close()
	t.equal(karma.g.current, 1, "После Кармы очередь продолжилась ходом следующего игрока")
	t.equal(karma.zone_of(243), "soul:0", "Карма не потеряла Сундук погибшего")
	karma.inv("Карма после штрафа смерти")
