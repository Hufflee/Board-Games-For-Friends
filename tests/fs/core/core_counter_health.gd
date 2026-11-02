extends RefCounted
## Пакет518 и Гиперкоагуляция867: жетоны, замещение штрафа смерти и незалипающий предел здоровья.
## Полные изображения518/867 сверены02.11; проверяется предел HP, не общий вопрос добавления текущего HP.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var bag := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1).item(0, 518).build()
	bag.g._begin_resolving({"kind": "item", "card": 13, "owner": 0})
	bag.effect(0, "destroy", {"target": 0, "item": 1})
	t.equal(bag.zone_of(518), "item:0", "Первое уничтожение оставляет Пакет на столе")
	t.equal(bag.g.items[0][1].counters, 1, "Замещение кладёт ровно один жетон")
	t.equal(bag.g.max_hp[0], 3, "Жетон добавляет один к пределу здоровья")
	bag.effect(0, "destroy", {"target": 0, "item": 1})
	t.equal(bag.zone_of(518), "discard:loot", "Второе уничтожение сбрасывает брелок в лут")
	t.equal(bag.g.max_hp[0], 2, "Уход источника снимает бонус здоровья")
	bag.inv("Два уничтожения Пакета")
	var death := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.item(0, 518).hand(0, [497]).monster(0, 344, {"hp": 9, "dc": 6, "at": 9}).build()
	death.roll(1)
	death.ok(0, "attack", {"slot": 0})
	death.ok(0, "roll", null)
	death.close()
	death.ok(0, "death", {"loot": 497, "item": 1})
	death.close()
	t.equal(death.zone_of(518), "item:0", "Штраф смерти тоже заменён без выбора второго предмета")
	t.equal(death.g.items[0][1].counters, 1, "После штрафа на Пакете один жетон")
	death.inv("Пакет после смерти")
	var coag := Scenario.new(t).players(2).dlc().current(1).character(0, 866).character(1, 821) \
		.no_items(0).no_items(1).item(0, 867, {"counters": 2}).hand(0, []).build()
	# item(...) заменил стартовую867 той же физической картой с двумя подготовленными жетонами.
	var source: Dictionary = coag.g.items[0].back()
	coag.ok(1, "end", null)
	coag.close()
	t.equal(source.counters, 3, "В начале своего хода добавлен третий жетон")
	t.equal(coag.g.max_hp[0], 4, "Предел здоровья связан с тремя жетонами")
	var hand_size: int = coag.g.hands[0].size()
	coag.ok(0, "end", null)
	coag.close()
	t.equal(source.counters, 0, "В конце хода сброшены все жетоны")
	t.equal(coag.g.hands[0].size(), hand_size + 3, "За три жетона получены ровно три карты")
	t.equal(coag.g.max_hp[0], 1, "Сброс жетонов снимает весь бонус, он не залипает")
	coag.inv("Цикл Гиперкоагуляции")
