extends RefCounted
## Пакет 20 карт: реальные активации/лут, все ветки событий, цели и защита протокола.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_card_automation.gd")

func _game(t: Check) -> RefCounted:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [478, 479, 480]).hand(1, [481]) \
		.monster(0, 423).monster(1, 427).coins(0, 5).coins(1, 9).build()
	s.g.bonuses.clear()
	return s

func _choice(s: RefCounted, t: Check, op: String, target: int = -1) -> void:
	var choices: Array = s.g._card_choices()
	for i in choices.size():
		var arg: Dictionary = choices[i].arg
		if str(arg.op) == op and (target < 0 or int(arg.get("target", -1)) == target):
			s.ok(0, "card_choice", {"index": i, "revision": s.g.revision})
			s.close()
			return
	t.check(false, "Нет ожидаемого выбора " + op)

func _start(s: RefCounted, id: int, kind: String) -> void:
	if kind == "item":
		s._take(id)
		s.g._gain_item(0, id)
		s.g.items[0].back().tapped = false
		s.ok(0, "activate", {"item": s.g.items[0].size() - 1})
	elif kind == "loot":
		s._take(id)
		s.g.hands[0].append(id)
		s.ok(0, "loot", {"card": id})
	else:
		s._take(id)
		s.g._push({"kind": kind, "card": id, "owner": 0}, "turn")
	s.close()

func run(t: Check) -> void:
	t.equal(Cards.BATCH_01.size(), 20, "Пакет содержит 20 карт")
	var fuel = _game(t)
	fuel.g.character_ready[0] = false
	_start(fuel, 40, "item")
	t.check(fuel.g.character_ready[0], "40 автоматически заряжает персонажа")
	t.equal(fuel.g.phase, "turn", "40 не требует ручного завершения")
	fuel.ok(0, "end")
	fuel.close()
	t.check(fuel.g._card_choices().any(func(c): return c.arg.op == "skip_choice"), "40 предлагает необязательную перезарядку в конце хода")
	_choice(fuel, t, "skip_choice")
	t.equal(fuel.g.current, 1, "Отказ от40 продолжает конец хода")
	for id in [476, 506, 544]:
		for face in ([2, 5] if id == 506 else [4]):
			var s = _game(t)
			_start(s, id, "loot")
			if id != 544:
				s.no(0, "effect_done", null, "Нельзя пропустить обязательный бросок")
				s.roll(face)
				s.ok(0, "effect_roll")
				s.close()
			else:
				_choice(s, t, "recharge", 0)
			t.equal(s.g.coins[0], 10 if id == 506 and face == 5 else 5 if id == 506 else 6, "Монеты карты%d" % id)
			if id == 506:
				t.equal(s.zone_of(506), "hand:1" if face == 2 else "discard:loot", "Липкий пятак сохраняет физическую карту")
			s.inv("Лут%d" % id)
	for id in [700, 703, 719, 727, 730, 120]:
		for face in range(1, 7):
			var s = _game(t)
			# Смертельные исходы проверяются отдельно; здесь проверяем точный численный эффект.
			s.g.max_hp[0] = 10
			s.g.hp[0] = 10
			_start(s, id, "item" if id == 120 else "event")
			s.roll(face)
			s.ok(0, "effect_roll")
			s.close()
			if id == 703 and face in [2, 3]:
				_choice(s, t, "discard_loot")
				_choice(s, t, "discard_loot")
				t.equal(s.g.hands[0].size(), 1, "703 требует ровно 2 выбранных сброса")
			if id == 120 and face >= 4:
				_choice(s, t, "peek_deck")
				t.check(s.g.get_view(1).peek.is_empty(), "Просмотр120 закрыт для соперника")
				_choice(s, t, "close_peek")
			if id == 730 and face <= 3:
				var ids: Array = s.g.peek.cards.duplicate()
				for selected in ids:
					var choices: Array = s.g._card_choices()
					for i in choices.size():
						if int(choices[i].arg.get("card", -1)) == int(selected):
							s.ok(0, "card_choice", {"index": i, "revision": s.g.revision})
							break
				var reversed: Array = ids.duplicate()
				reversed.reverse()
				t.equal(s.g.decks.monster.slice(-ids.size()), reversed, "730 возвращает карты в выбранном порядке сверху")
			if id == 700:
				t.equal(s.g.coins[0], 8 if face in [3, 4] else 5, "700 монеты по грани")
				t.equal(s.g.hands[0].size(), 4 if face <= 2 else 3, "700 добыча по грани")
			if id == 719:
				t.equal(s.g.hp[0], s.g.max_hp[0] - 1, "719 каждый исход наносит ровно1урон")
			if id == 727 and face <= 2:
				t.check(s.g.required_deck_attacks > s.g.deck_attacks, "727 обязательная атака колоды")
			t.check(not s.g._card_automation_active(), "Карта%d грань%d завершилась автоматически" % [id, face])
	var greed = _game(t)
	_start(greed, 716, "event")
	t.equal(greed.g._card_choices().size(), 1, "716 допустим только богатейший игрок")
	greed.no(1, "card_choice", {"index": 0, "revision": greed.g.revision}, "Чужой выбор отклонён")
	greed.no(0, "card_choice", {"index": 0, "revision": greed.g.revision - 1}, "Устаревший выбор отклонён")
	_choice(greed, t, "lose_all_coins", 1)
	t.equal(greed.g.coins[1], 0, "716 списала все монеты цели")
	var shovel = _game(t)
	shovel._take(689)
	shovel.g.soul_cards[1].append({"id": 689, "value": 1})
	shovel.g.souls[1] += 1
	_start(shovel, 199, "item")
	_choice(shovel, t, "steal_soul", 1)
	t.equal(shovel.g.souls[0], 1, "199 крадёт выбранную душу")
	t.equal(shovel.zone_of(199), "discard:treasure", "199 уничтожает саму лопату")
	for id in [395, 414, 417, 424, 369]:
		var s = _game(t)
		s._take(id)
		s.g.decks.monster.push_front(int(s.g.monsters[0].id))
		s.g.monsters[0] = {"id": id, "hp": 0, "dc": 3, "at": 1, "slayer": 1}
		var hand_before: int = s.g.hands[0].size()
		var slots_before: int = s.g.monster_slots
		s.g._continue_stack()
		s.close()
		if id == 417:
			_choice(s, t, "peek_hand", 1)
			t.check(s.g.get_view(1).peek.is_empty(), "417 просмотр чужой руки приватен")
			_choice(s, t, "close_peek")
		if id == 395: t.equal(s.g.skipped_turns[0], 1, "395 назначил пропуск")
		if id == 414: t.equal(s.g.hands[1].size(), 0, "414 сбрасывает руку убийцы, а не активного")
		if id == 424: t.equal(s.g.monster_slots, slots_before + 1, "424 расширил ряд")
		if id == 369:
			t.equal(s.g.hp[0], s.g.max_hp[0] - 1, "369 урон активному")
			t.equal(s.g.hp[1], s.g.max_hp[1] - 1, "369 урон сопернику")
		if id != 417: t.check(not s.g._card_automation_active(), "Текст смерти%d завершён" % id)
		s.inv("Смерть монстра%d" % id)
	for id in [822, 828]:
		var s = _game(t)
		s.g.stack.append({"kind": "roll", "owner": 0, "value": 3})
		_start(s, id, "item")
		_choice(s, t, "reroll" if id == 822 else "roll")
		if id == 822:
			t.check(s.g.resolving.has("reroll_request"), "822 ждёт жест исходного владельца кубика")
			s.roll(6)
			s.ok(0, "effect_roll")
			s.close()
		t.check(not s.g._card_automation_active(), "Модификатор%d завершён" % id)
	var blood = _game(t)
	_start(blood, 834, "item")
	var before: int = blood.g.monsters[0].at
	_choice(blood, t, "monster_temporary_attack")
	t.equal(blood.g.monsters[0].at, before + 1, "834 усиливает выбранного монстра")
	t.equal(blood.g.monsters[0].temporary_at, 1, "834 фиксирует истекающий бонус")
