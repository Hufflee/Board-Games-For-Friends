extends RefCounted
## 20пилюль/рун: все грани, превращения без копий, чужой обязательный выбор и замещения.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_rune_cards.gd")
const ROLLED := [478, 479, 520, 521, 551, 579, 580, 581, 584, 672, 673, 674]

func _game(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 908) \
		.no_items(0).no_items(1).no_items(2).hand(0, [id, 549]).hand(1, [480, 481]).hand(2, [482]) \
		.item(0, 91).item(1, 40).item(2, 229).monster(0, 423).monster(1, 427) \
		.deck_top("treasure", [249, 174, 143]).coins(0, 5).build()
	s.g.bonuses.clear()
	return s

func _order(s: RefCounted, first: int = -1) -> Array:
	var cards: Array = s.g.peek.cards.duplicate()
	if first >= 0 and first in cards:
		cards.erase(first)
		cards.push_front(first)
	for id in cards:
		s.choose(0, "order_card", {"card": int(id)})
	return cards

func run(t: Check) -> void:
	t.equal(Cards.IDS.size(), 20, "Пакет06содержит20карт")
	for id in ROLLED:
		for face in range(1, 7):
			var s = _game(t, id)
			if id == 551:
				s.g.battle = 1
			if id == 579 and face <= 2:
				s._take(550)
				s.g._push({"kind": "loot", "card": 550, "owner": 1}, "turn")
			var initial_rolls: int = s.g.roll_no
			s.ok(0, "loot", {"card": id})
			s.close()
			for roll_index in (3 if id == 521 else 1):
				s.roll(face)
				s.ok(0, "effect_roll")
				s.close()
			if id == 520 and face <= 4:
				for i in (3 if face <= 2 else 1):
					s.choose(0, "hand_top")
			if id == 579:
				if face <= 2:
					s.choose(0, "cancel_selected")
					t.equal(s.g.coins[1], 3, "Пилюля579отменила выплату выбранной монеты")
				elif face <= 4:
					for seat in [1, 2]:
						s.close()
						t.equal(s.g.actor(), seat, "Другие игроки выбирают сброс последовательно")
						s.ok(seat, "forced_discard", {"item": 0})
						s.close()
					t.equal(s.g.hands[1].size(), 1, "579первыйсоперник сбросил1")
					t.equal(s.g.hands[2].size(), 0, "579второйсоперник сбросил1")
			if id == 580 and face <= 4:
				s.choose(0, "reroll_item", {"target": 0 if face <= 2 else 1, "item": 1, "shop": false})
			if id == 581:
				if face <= 2: s.choose(0, "damage", {"target": 2})
				elif face <= 4: s.choose(0, "monster_damage", {"item": 1})
			if id == 584 and face in [3, 4]:
				s.choose(0, "reroll_item", {"target": 1, "item": 1, "shop": false})
			if id == 674 and face >= 5:
				s.choose(0, "discard_loot")
			s.close()
			match id:
				478, 479:
					t.equal(s.zone_of(id), "item:0" if face >= 5 else "discard:loot", "Превращение%dприграни%d сохраняетоднукарту" % [id, face])
					if id == 479 and face >= 5:
						t.equal(s.g.attack[0], 2, "Золотая пилюля даёт постоянную1атаку")
					if id == 478 and face >= 5:
						s.g._damage_player(0, 1)
						t.equal(s.g.hp[0], 2, "Синий предмет предотвращает первый1урон")
						s.g._damage_player(0, 1)
						t.equal(s.g.hp[0], 1, "Второй урон того же хода проходит")
				520:
					t.equal(s.g.hands[0].size(), 0 if face <= 2 else 4, "520добор/возврат по напечатанной ветке")
				521:
					t.equal(s.g.roll_no - initial_rolls, 3, "521требует три отдельных броска")
					if face <= 2: t.equal(s.g.attack[0], 4, "Три бонуса атаки сложились")
					elif face <= 4: t.equal(s.g.max_hp[0], 5, "Три бонуса здоровья сложились")
					else: t.equal(s.g.hp[0], 0, "Три неблагоприятных исхода довели до смерти")
				551:
					if face in [3, 4]: t.equal(s.g._monster_evasion(s.g.monsters[1]), 2, "551уменьшаетзащиту атакуемого монстра")
					if face >= 5: t.equal(s.g._monster_attack(s.g.monsters[1]), 3, "551прибавляет2атаки атакуемому монстру")
					if face >= 3: t.equal(s.g._monster_attack(s.g.monsters[0]), 1, "Неатакуемый сейчас монстр не получает чужой бонус")
				580:
					t.equal(s.zone_of(91 if face <= 2 or face >= 5 else 40), "discard:treasure", "580уничтожил правильный старый предмет")
					if face <= 2 or face >= 5: t.equal(s.zone_of(143), "item:0", "Новый предмет получил исходный контроллер")
				581:
					if face <= 2: t.equal(s.g.hp[2], 2, "581нанёс1выбранномуигроку")
					elif face <= 4: t.equal(s.g.monsters[1].hp, 1, "581нанёс1выбранномумонстру")
					else: t.equal(s.g.hp[0], 1, "581нанёс1себе")
				584:
					if face >= 5: t.equal(s.g.hands[0].size(), 3, "Чёрная руна сбросила руку и взяла3")
				672:
					t.equal(s.g.coins[0], 9 if face <= 2 else 12 if face <= 4 else 1, "672монеты по грани")
				673:
					if face <= 2: t.equal(s.g._turn_roll_bonus[0], 1, "673модификаторпоследующихбросков")
					elif face <= 4: t.equal(s.g.max_hp[0], 3, "673временноез здоровье")
					else: t.equal(s.g.hp[0], 1, "673неблагоприятныйурон")
				674:
					t.equal(s.g.hands[0].size(), 2 if face <= 2 else 4 if face <= 4 else 0, "674добор/сброс по грани")
			s.inv("Пилюля/руна%d грань%d" % [id, face])
	var gift = _game(t, 477)
	for seed_value in range(1, 100):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if rng.randi_range(0, 2) == 1:
			gift.g._rng.seed = seed_value
			break
	gift.ok(0, "loot", {"card": 477})
	gift.close()
	t.equal(gift.g.actor(), 1, "Случайный отдающий игрок сам выбирает свой предмет")
	t.check(gift.g.get_view(0).card_choices.is_empty(), "Автор не выбирает чужой обязательный предмет")
	gift.choose(1, "gift_item")
	t.equal(gift.zone_of(40), "item:0", "Выбранная физическая карта передана автору пилюли")
	var eternal = _game(t, 495)
	eternal.ok(0, "loot", {"card": 495})
	eternal.close()
	eternal.choose(0, "grant_eternal", {"target": 1})
	t.check(eternal.g.items[1].all(func(item): return bool(item.eternal)), "Альгиз дал вечность всем предметам цели")
	eternal.ok(0, "end")
	eternal.close()
	t.check(not eternal.g.items[1][1].eternal and eternal.g.items[1][0].eternal, "Истекла только временная вечность")
	var berkano = _game(t, 496)
	var shop_card: int = int(berkano.g.shop[0])
	berkano.ok(0, "loot", {"card": 496})
	berkano.close()
	berkano.choose(0, "berkano_destroy", {"target": 1, "item": 1, "shop": false})
	t.equal(berkano.g.actor(), 1, "После уничтожения карту магазина выбирает прежний контроллер")
	berkano.choose(1, "berkano_take", {"item": 0})
	t.equal(berkano.zone_of(shop_card), "item:1", "Беркано дал физический предмет правильному игроку")
	for id in [565, 530]:
		var s = _game(t, id)
		if id == 530:
			s._take(352)
			s.g.decks.monster.append(352)
		s.ok(0, "loot", {"card": id})
		s.close()
		s.choose(0, "peek_deck", {"deck": "monster"})
		t.equal(s.g.peek.cards.size(), 4 if id == 565 else 5, "Точное количество просмотренных карт")
		t.check(s.g.get_view(1).peek.is_empty(), "Просмотр руны приватен")
		_order(s, 352 if id == 530 else -1)
		if id == 530:
			s.choose(0, "discard_monster", {"item": 1})
			s.close()
			t.equal(s.zone_of(427), "discard:monster", "Хагалаз сбросил выбранного неатакуемого сейчас монстра")
	var reroll = _game(t, 578)
	reroll.ok(0, "loot", {"card": 578})
	reroll.close()
	reroll.choose(0, "reroll_item", {"target": 1, "item": 1, "shop": false})
	reroll.close()
	t.equal(reroll.zone_of(40), "discard:treasure", "Пертро уничтожил выбранный предмет")
	t.equal(reroll.zone_of(143), "item:1", "Пертро заменил предмет его владельцу")
	var dagaz = _game(t, 648)
	dagaz._take(709)
	dagaz.g.curses[1].append(709)
	dagaz.ok(0, "loot", {"card": 648})
	dagaz.close()
	dagaz.choose(0, "dagaz_curse")
	dagaz.choose(0, "destroy_curse", {"target": 1, "card": 709})
	t.equal(dagaz.zone_of(709), "discard:monster", "Дагаз уничтожает выбранное проклятие")
	var ace = _game(t, 529)
	ace.ok(0, "loot", {"card": 529})
	ace.close()
	t.equal(ace.g.coins[0], 8, "Туз учитывает2монстра и1оставшуюсякарту руки")
