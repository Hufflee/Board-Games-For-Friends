extends "res://tests/fs/core/core_automation_batch19.gd"
## Границы очереди Four Souls от 9 ноября: добор, защита, сброс и настройки партии.

func run(t: Check) -> void:
	_pill_and_keeper(t)
	_clock_and_responses(t)
	_start_and_remove(t)
	_coop_cancel_keeps_monster(t)
	_lobby_options_and_gifts(t)
	_bomb_during_refill(t)
	var boosted := Scenario.new(t).dlc().current(0).monster(0, 423, {"dc": 6, "hp": 3}).monster(1, 400).build()
	t.check(boosted.g._monster_evasion(boosted.g.monsters[0]) > 6, "Аура повышает исходное уклонение")
	t.equal(int(boosted.g.get_view(0).monsters[0].dc), 6, "Эффективное уклонение не выше шести")
	_attack_roll17(boosted, 6)
	t.equal(int(boosted.g.monsters[0].hp), 2, "Шестёрка попадает после усиления уклонения")


func _lobby_options_and_gifts(t: Check) -> void:
	var g := FSRules.new()
	g.character_offer_count = 4
	g.random_bonus_souls = true
	var members: Array = []
	for seat in 8:
		members.append({"name": str(seat)})
	g.new_game(members, false, 21)
	var seen := {}
	for seat in 8:
		var offers: Array = g.get_view(seat).character_offers
		t.equal(offers.size(), 4, "Четыре личных варианта в партии на восемь мест")
		for offer: Dictionary in offers:
			t.check(not seen.has(offer.card), "Персонаж предлагается только одному месту")
			seen[offer.card] = true
	t.equal(g.bonuses.size(), 3, "Случайный набор содержит три души")
	t.check(g.bonuses.any(func(id): return id >= 692), "Случайный набор берёт души DLC при выключенных комнатах")
	g.random_bonus_souls = false
	g.new_game(members, true, 21)
	t.equal(g.bonuses, [689, 690, 691], "Стандартные души доступны при включённом DLC")
	var s := Scenario.new(t).players(3).current(0).build()
	var before: Array = s.g.coins.duplicate()
	s.ok(0, "trade", {"target": 1, "amount": 1})
	var offer: Dictionary = s.g.get_view(1).coin_offers[0]
	t.check(s.g.get_view(2).coin_offers.is_empty(), "Чужое предложение скрыто")
	s.no(2, "answer_trade", {"sender": 0, "id": int(offer.id), "accept": true})
	s.ok(1, "answer_trade", {"sender": 0, "id": int(offer.id), "accept": false})
	t.equal(s.g.coins, before, "Отказ сохраняет балансы")
	s.no(1, "answer_trade", {"sender": 0, "id": int(offer.id), "accept": true})
	s.g._spider_tokens15[1] = 2
	t.equal(s.g.get_view(2).players[1].spider_tokens15, 2, "Пауки Вдовы видны другим игрокам")


func _bomb_during_refill(t: Check) -> void:
	var s := Scenario.new(t).dlc().current(0).hand(0, [588]).item(0, 824).deck_top("monster", [423, 712, 422, 421, 420]).build()
	var g := s.g
	g.strict_responses28 = true
	g.monster_slots = g.monsters.size() + 4
	s.ok(0, "loot", {"card": 588})
	g._after_stack = "refill"
	g.tick(0.0)
	g.tick(g.RESPONSE_WINDOW + 0.01)
	t.check(not g.stack.is_empty() and int(g.stack.back().card) == 712, "Новая Мегатролль-бомба ждёт отдельное окно ответов")
	var before: int = g.hp[0]
	s.ok(0, "activate", {"item": g.items[0].size() - 1})
	s.close()
	s.choose(0, "shield_event21", {"zone": "player", "target": 0})
	s.close()
	t.equal(g.hp[0], before, "Ням-сердце предотвращает урон Мегатролль-бомбы")


func _pill_and_keeper(t: Check) -> void:
	var pill := Scenario.new(t).current(0).hand(0, [520]).item(0, 168).build()
	pill.ok(0, "activate", {"item": pill.g.items[0].size() - 1})
	pill.close()
	pill.choose(0, "double_draw13", {"target": 0})
	pill.ok(0, "loot", {"card": 520})
	pill.close()
	pill.roll(5)
	pill.ok(0, "effect_roll")
	pill.close()
	t.equal(pill.g.hands[0].size(), 6, "Двойка треф удваивает добор пилюли с трёх до шести")

	var keeper = _monster(t, 435)
	var before: int = keeper.g.hp[0]
	_attack_roll17(keeper, 4)
	t.equal(keeper.g.hp[0], before, "Четвёрка попадает в Проклятую Голову Хранителя без модификаторов")
	t.equal(int(keeper.g.monsters[0].hp), 1, "Четвёрка наносит боевой урон Проклятой Голове Хранителя")


func _clock_and_responses(t: Check) -> void:
	var s := Scenario.new(t).current(0).hand(0, []).hand(1, []).build()
	var g := s.g
	g.set_turn_clock(20.0)
	g.tick(0.0)
	g.tick(19.0)
	t.equal(g.current, 0, "До двадцатой секунды ход остаётся у игрока")
	s.ok(0, "trade", {"target": 1, "amount": 1})
	t.equal(g.turn_time_left(), 20.0, "Принятое действие сбрасывает часы")
	g.tick(20.0)
	t.equal(g.current, 1, "Бездействие завершает ход")
	g.strict_responses28 = true
	g.character_ready.fill(false)
	for inventory: Array in g.items:
		for item: Dictionary in inventory:
			item.tapped = true
	for seat in 2:
		g.decks.loot.append_array(g.hands[seat])
		g.hands[seat].clear()
	s._take(549)
	g._push({"kind": "loot", "owner": 1, "card": 549}, "turn")
	g.revision += 1
	var view := g.get_view(1)
	t.equal(view.response_left28, -1.0, "Часы ответа скрыты, когда никто не может ответить")
	t.check(not view.live_discards.any(func(entry): return int(entry.card) == 549), "Добычи из стека нет в сбросе")
	g.tick(0.0)
	t.check(g.get_view(1).live_discards.any(func(entry): return int(entry.card) == 549), "Без ответов добыча разрешается и попадает в сброс")
	t.check(549 in g.get_view(1).log_cards, "Запись о сбросе хранит ID для предпросмотра")


func _start_and_remove(t: Check) -> void:
	var g := FSRules.new()
	g.choose_character_at_start = true
	g.new_game([{"name": "Первый", "steam_id": 111}, {"name": "Второй", "steam_id": 222}], false, 24)
	var first: Array = g.get_view(0).character_offers
	var second: Array = g.get_view(1).character_offers
	t.equal(first.size(), 2, "Хост предлагает двух персонажей")
	t.equal(second.size(), 2, "Второй видит свои варианты одновременно с первым")
	t.check(first.all(func(offer): return not second.has(offer)), "Две раздачи не пересекаются")
	t.check(g.get_view(-1).character_offers.is_empty(), "Зритель не получает закрытые варианты")
	t.check(not g.action(1, "choose_character", {"card": int(first[0].card)}), "Чужой вариант отклонён")
	t.check(g.action(1, "choose_character", {"card": int(second[0].card)}), "Второй может выбрать раньше первого")
	t.equal(g.get_view(1).character_offers.size(), 0, "Подтвердивший игрок ждёт остальных")
	t.equal(g.get_view(0).character_remaining, 1, "Хост сообщает число оставшихся выборов")
	t.check(not g.action(1, "choose_character", {"card": int(second[1].card)}), "Повторный выбор отклонён")
	t.equal(g.chars, [-1, -1], "Раздача ждёт последнего игрока")
	t.check(g.action(0, "choose_character", {"card": int(first[0].card)}), "Последний выбор завершает раздачу")
	t.equal(g.chars, [int(first[0].card), int(second[0].card)], "В партии только выбранные персонажи")
	t.equal(g.get_view(1).players[0].steam_id, 111, "Клиент получает Steam ID для аватарки")

	var s := Scenario.new(t).players(3).current(0).hand(0, [549]).item(0, 168).build()
	t.check(s.g.remove_player(0), "Хост исключает ходящего в свободной фазе")
	t.equal(s.g.current, 1, "Ход исключённого переходит следующему")
	t.check(s.g.is_out(0) and int(s.g.chars[0]) == -1, "Место потеряло персонажа и выбыло")
	t.check(549 in s.g.discards.loot and 168 in s.g.discards.treasure, "Карты исключённого сохраняются в сбросах")
	s.inv("Исключение игрока сохраняет монеты и физические карты")


func _coop_cancel_keeps_monster(t: Check) -> void:
	var s = _monster(t, 419)
	_item(s, 0, 910)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.choose(0, "squid_buff27")
	s.choose(0, "squid_invite27", {"target": 1})
	s.choose(1, "squid_join27", {"mode": "accept"})
	s.close()
	s.roll(4)
	s.ok(0, "roll")
	s.close()
	t.equal(s.g.actor(), 1, "После атакующего бросает напарник")
	s.roll(6)
	s.ok(1, "roll")
	s.close()
	if s.g.phase == "priority":
		s.close("разрешить оставшиеся срабатывания конца хода")
	t.equal(s.g.current, 1, "Шестёрка напарника завершает ход после способности Маминой руки")
	t.check(s.g.monsters.any(func(monster): return int(monster.id) == 419), "Мамина рука остаётся в своём слоте")
	s.inv("Отмена всех эффектов совместной атаки сохраняет физические карты")
