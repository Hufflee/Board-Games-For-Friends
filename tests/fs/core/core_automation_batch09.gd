extends RefCounted
## Пакет09:20сокровищ. Полные тексты, границы броска/атаки, оплаты и входа в игру.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_treasure_cards.gd")

func _game(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 821) \
		.no_items(0).no_items(1).no_items(2).hand(0, [549]).hand(1, [480]).hand(2, [482]) \
		.item(0, id).monster(0, 423).monster(1, 427).room(-1).shop(0, 249).shop(1, 174).coins(0, 5).build()
	s.g.bonuses.clear()
	return s

func _attack_roll(s: RefCounted, face: int) -> void:
	s.roll(face)
	s.ok(0, "roll")
	s.close()

func run(t: Check) -> void:
	t.equal(Cards.IDS.size(), 20, "Пакет09содержит20сокровищ")
	var ring = _game(t, 16)
	t.equal(ring.g.attack[0], 2, "Мамино кольцо даёт1атаку")
	var ring_hand: int = ring.g.hands[0].size()
	ring.g._destroy_item(0, 1)
	ring._take(16)
	ring.g._gain_item(0, 16)
	ring.close()
	t.equal(ring.g.hands[0].size(), ring_hand + 1, "Кольцо при получении берёт1добычу")
	var coal = _game(t, 18)
	coal.g._turn_attack_rolls[0] = 3
	coal.g._emit_passives("attack_roll", {"seat": 0, "count": 3})
	coal.close()
	t.equal(coal.g.attack[0], 2, "Уголь после третьего броска дал1атаку")
	coal.g._emit_passives("attack_roll", {"seat": 0, "count": 4})
	coal.close()
	t.equal(coal.g.attack[0], 2, "Уголь не повторяет бонус на четвёртом броске")
	for id in [24, 25, 26]:
		var s = _game(t, id)
		t.equal(s.g.attack_left, 2, "Каждая мамина вещь добавляет одну атаку в свой ход")
		if id == 24:
			s.g.monsters[1].hp = 8
			s.g.battle = 1
			s.g.phase = "battle_roll"
			_attack_roll(s, 2)
			t.equal(s.g.last_roll, 3, "Помада повышает первый бросок атаки")
			_attack_roll(s, 2)
			t.equal(s.g.last_roll, 2, "Помада не повышает второй бросок")
		elif id == 25:
			s.g.monsters[1].hp = 10
			s.g._turn_attacks_started = 2
			s.g.battle = 1
			s.g.phase = "battle_roll"
			for expected in [7, 4]:
				_attack_roll(s, 6)
				t.equal(s.g.monsters[1].hp, expected, "Бельё даёт2атаки каждому броску именно второй атаки")
			s.g._turn_attacks_started = 3
			_attack_roll(s, 6)
			t.equal(s.g.monsters[1].hp, 3, "Третья атака без бонуса Белья")
		else:
			s.g._damage_player(0, 1)
			t.equal(s.g.hp[0], 1, "Небоевой урон не предотвращается Туфлями")
			s.g._damage_player(0, 4, {"combat": true})
			t.equal(s.g.hp[0], 1, "Туфли предотвращают целиком первое событие боевого урона")
			s.g._damage_player(0, 1, {"combat": true})
			t.equal(s.g.hp[0], 0, "Следующий боевой урон проходит")
	for id in [33, 41]:
		var s = _game(t, id)
		s.g._roll_passives(2 if id == 33 else 6, 1 if id == 33 else 0)
		s.close()
		s.choose(0, "damage", {"target": 1})
		t.equal(s.g.hp[1], 1, "Пассив числа даёт серверный выбор и наносит1выбраннойцели")
		if id == 41:
			t.equal(s.g.attack[0], 2, "Сера также даёт постоянную1атаку")
	var seraph = _game(t, 36)
	seraph.g.monsters[1].hp = 20
	seraph.g.hp[0] = 20
	seraph.g.max_hp[0] = 20
	seraph.g.battle = 1
	seraph.g.phase = "battle_roll"
	for expected in [3, 2, 3, 2, 3, 2]:
		_attack_roll(seraph, 2)
		t.equal(seraph.g.last_roll, expected, "Серафим повышает только1/3/5броскиатаки")
	var quarter = _game(t, 38)
	quarter.ok(0, "activate", {"item": 1, "tap": false})
	quarter.close()
	t.equal(quarter.g.coins[0], 30, "Четвертак уничтожен в обмен на25монет")
	t.equal(quarter.zone_of(38), "discard:treasure", "Четвертак физически уничтожен один раз")
	var fuel = _game(t, 39)
	fuel.g.character_ready[0] = false
	fuel.g._emit_passives("turn_end")
	fuel.close()
	t.check(fuel.g.character_ready[0], "G Fuel39заряжаетперсонажавконцесвоегохода")
	var box = _game(t, 45)
	for count in range(1, 7):
		box.g._emit_passives("turn_start")
		box.close()
		t.equal(box.g.items[0][1].counters, count, "Шкатулка накапливает по одному жетону")
	t.equal(box.g.coins[0], 15, "Второй жетон Шкатулки даёт10монет")
	t.equal(box.g.hands[0].size(), 5, "Четвёртый жетон Шкатулки даёт4карты")
	t.equal(box.g.items[0].size(), 4, "Шестой жетон Шкатулки даёт2сокровища")
	var bottom = _game(t, 58)
	bottom.g._destroy_item(0, 1)
	bottom._take(58)
	bottom.g._gain_item(0, 58)
	t.equal(bottom.g.items[0][1].counters, 1, "Каменное дно запоминает размер руки при получении")
	bottom.g.discards.loot.append_array(bottom.g.hands[0])
	bottom.g.hands[0].clear()
	bottom.g._emit_passives("turn_end")
	bottom.close()
	t.equal(bottom.g.hands[0].size(), 2, "Каменное дно берёт2приуменьшившейсяруке")
	var keeper = _game(t, 62)
	keeper.g._destroy_item(0, 1)
	keeper._take(62)
	var old_slots: int = keeper.g.shop.size()
	keeper.g._gain_item(0, 62)
	keeper.close()
	t.equal(keeper.g.shop.size(), old_slots + 2, "Коробок расширяет магазин при входе")
	keeper.g.current = 1
	keeper.g._turn_allowances()
	keeper.g._gain_coins(1, 10)
	keeper.ok(1, "buy", {"slot": 0})
	keeper.close()
	t.equal(keeper.g.coins[0], 7, "Чужая покупка магазина даёт владельцу Коробка2монеты")
	t.equal(keeper.g.hands[0].size(), 2, "Чужая покупка магазина даёт владельцу Коробка1карту")
	var sack = _game(t, 69)
	var sack_coins: int = int(sack.g.coins[0])
	sack.ok(0, "activate", {"item": 1, "tap": false})
	sack.close()
	t.equal(sack.g.coins[0], sack_coins - 4, "Передача Мошны оплачивается4монетами")
	sack.choose(0, "give_source", {"target": 1})
	t.equal(sack.zone_of(69), "item:1", "Мошна передана без повторного входного14монет")
	t.equal(sack.g.coins[1], 3, "Передача контроля не повторяет награду получения")
	var hungry = _game(t, 69)
	hungry.g._emit_passives("turn_end")
	hungry.close()
	hungry.choose(0, "discard_loot")
	t.equal(hungry.g.hands[0].size(), 0, "Мошна требует сбросить свою карту в конце хода")
	hungry.g._emit_passives("turn_end")
	hungry.close()
	t.equal(hungry.g.hp[0], 0, "Без карты Мошна наносит2урона")
	var trick = _game(t, 76)
	t.equal(trick.g._purchase_cost(0, 0), 0, "Первая покупка с Пенни на нитке бесплатна")
	trick.ok(0, "buy", {"slot": 0})
	trick.close()
	t.equal(trick.g.coins[0], 6, "Покупка с Пенни на нитке возвращает1монету")
	t.equal(trick.g._purchase_cost(0, 1), 9, "Следующая покупка имеет только скидку1")
	trick.g._emit_passives("turn_end")
	trick.close()
	t.equal(trick.g.coins[0], 7, "В конце своего хода Пенни даётещё1монету")
	var penny = _game(t, 77)
	var penny_coins: int = int(penny.g.coins[0])
	penny.ok(0, "activate", {"item": 1})
	penny.close()
	penny.choose(0, "give_source", {"target": 1})
	t.equal(penny.g.coins[0], penny_coins + 1, "Пенни Хранителя выдаёт монеты по новому числу жетонов")
	t.equal(penny.g.items[1].back().counters, 1, "Пенни передаётся с накопленным жетоном")
	for id in [39, 79, 112, 174, 249]:
		var s = _game(t, 16)
		s._take(id)
		s.g.hp[0] = 1
		s.g._gain_item(0, id)
		t.equal(s.g.max_hp[0], 3, "Карта здоровья%dувеличиваетмаксимумна1" % id)
		t.equal(s.g.hp[0], 2, "Карта здоровья%dсохраняетотмеченныйурон" % id)
		if id == 112:
			s.g._damage_player(0, 4, {"combat": true, "value": 4})
			t.equal(s.g.hp[0], 2, "Плацента предотвращает боевой урон на4")
