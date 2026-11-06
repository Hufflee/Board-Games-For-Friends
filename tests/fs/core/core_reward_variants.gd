extends RefCounted
## Особые награды: предотвращения284/299/362, ресурсы убийце отдельно от души и жетоны монстров.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _game(t: Check, id: int, health: int = 0) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 821) \
		.no_items(0).no_items(1).no_items(2).hand(0, []).hand(1, []).hand(2, []) \
		.monster(0, id, {"hp": health}).monster(1, 344).deck_top("monster", [423]) \
		.deck_top("treasure", [91, 229, 180]).room(-1).build()
	s.g.bonuses.clear()
	return s

func run(t: Check) -> void:
	var duke := _game(t, 284)
	# Новый обязательный урон284 проверяется отдельно; здесь изолируется контракт награды.
	duke.g.max_hp = [8, 8, 8]
	duke.g.hp = [8, 8, 8]
	var initial_items: int = duke.g.items[0].size()
	for count in 2:
		duke.g.monsters[0].hp = 0
		duke.g._continue_stack()
		duke.close()
		duke.close() # После отдельного обязательного текста284 закрывается очередь сокровища.
		t.equal(duke.g.monsters[0].id, 284, "Герцог остаётся монстром после предотвращения")
		t.equal(duke.g.monsters[0].counters, count + 1, "Предотвращение добавляет ровно один жетон")
		t.equal(duke.g.monsters[0].hp, 4, "Предотвращение полностью лечит Герцога")
		t.equal(duke.g.items[0].size(), initial_items + count + 1, "Сокровище за каждое предотвращение")
		t.equal(duke.g.souls[0], 0, "Предотвращение не создаёт душу")
		t.equal(duke.g.bonus_progress.monsters, 0, "Предотвращение не считается убийством")
	duke.g.monsters[0].hp = 0
	duke.g._continue_stack()
	duke.close()
	t.equal(duke.zone_of(284), "soul:0", "Третья смерть даёт физическую душу")
	t.equal(duke.g.items[0].size(), initial_items + 3, "Настоящая смерть тоже даёт сокровище")
	duke.inv("Герцог после трёх смертельных состояний")
	var rush := _game(t, 299)
	var initial_coins: int = rush.g.coins[0]
	for count in 6:
		rush.g.monsters[0].hp = 0
		rush.g._continue_stack()
		rush.close()
		t.equal(rush.g.coins[0], initial_coins + 6 * (count + 1), "Каждое предотвращение Нашествия даёт6монет")
		if count < 5:
			t.equal(rush.g.monsters[0].counters, count + 1, "Жетоны Нашествия сохраняются")
	t.equal(rush.zone_of(299), "discard:monster", "Шестой жетон сбрасывает Нашествие")
	t.equal(rush.g.bonus_progress.monsters, 0, "Сброс после предотвращения не является убийством")
	rush.inv("Нашествие после шестого предотвращения")
	var horse := _game(t, 362)
	horse.g._continue_stack()
	horse.close()
	t.equal(horse.g.monsters[0].hp, 2, "Первое спасение Всадника оставляет2HP")
	t.equal(horse.g.monsters[0].dc, 4, "Всадник получает+1защиты по оригиналу")
	t.equal(horse.g.monsters[0].at, 1, "Всадник теряет одну атаку")
	t.equal(horse.g.souls[0], 0, "Спасение обычного Всадника не даёт душу")
	horse.ok(0, "end")
	horse.close()
	t.equal(horse.g.monsters[0].dc, 3, "Временная защита восстановилась на новом ходу")
	t.equal(horse.g.monsters[0].at, 2, "Временная атака восстановилась на новом ходу")
	horse.g.monsters[0].hp = 0
	horse.g._continue_stack()
	horse.close()
	t.equal(horse.g.monsters[0].hp, 2, "На новом ходу Всадник снова спасается один раз")
	t.equal(horse.g.current, 1, "Автоматическое событие нового хода не завершает его повторно")
	horse.g.monsters[0].hp = 0
	horse.g._continue_stack()
	horse.close()
	t.equal(horse.zone_of(362), "soul:1", "Вторая смерть того же хода даёт душу активному игроку")
	horse.inv("Обычный Всадник после смены хода")
	var greed := _game(t, 339)
	greed.g.monsters[0]["slayer"] = 1
	greed.g.bonuses = [689]
	greed.g.claimed.clear()
	greed.g._continue_stack()
	greed.close()
	t.equal(greed.g.coins[0], 3, "Активный игрок не получает чужие40монет")
	t.equal(greed.g.coins[1], 43, "Убийца получает40монет")
	t.equal(greed.zone_of(339), "soul:0", "Душу Ультра жадности получает активный игрок")
	t.equal(greed.zone_of(689), "soul:1", "Бонус25монет достаётся получателю монет")
	greed.inv("Разные получатели ресурсов и души")
	var final_blow := _game(t, 339, 1)
	final_blow.g.monsters[0].dc = 1
	final_blow.g.monsters[0]["slayer"] = 1
	final_blow.roll(5)
	final_blow.ok(0, "attack", {"slot": 0})
	final_blow.ok(0, "roll", null)
	final_blow.close()
	t.equal(final_blow.g.coins[0], 43, "Смертельный боевой удар обновляет прежнего владельца бомбы")
	t.equal(final_blow.g.coins[1], 3, "Несмертельная чужая бомба не крадёт награду последнего удара")
	final_blow.inv("Последний удар после чужой бомбы")
	var counters := _game(t, 279, 5)
	counters.g._host_manual = true # Аварийная операция хоста, не способность случайной карты.
	counters.g._begin_resolving({"kind": "item", "card": int(counters.g.items[0][0].id), "owner": 0})
	counters.effect(0, "monster_counter", {"item": 0, "amount": 3})
	counters.no(1, "effect", {"op": "monster_counter", "item": 0, "amount": 1}, "Чужой игрок не управляет жетонами эффекта")
	counters.no(0, "effect", {"op": "monster_counter", "item": -1, "amount": 1}, "Отрицательный индекс монстра")
	counters.ok(0, "effect_done")
	counters.g._host_manual = false
	counters.g.monsters[0].hp = 0
	counters.g._continue_stack()
	counters.close()
	t.equal(counters.g.coins[0], 6, "Награда Святой жадности читает3жетона с монстра")
	t.equal(counters.zone_of(279), "soul:0", "Жетоны не заменяют физическую душу")
	counters.inv("Награда по жетонам")
