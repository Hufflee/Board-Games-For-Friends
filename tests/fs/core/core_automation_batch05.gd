extends RefCounted
## 20 карт Таро621–640: выборы, обязательные броски, приватный просмотр, срок характеристик и стоимость.
const Check := preload("res://tests/fs/fs_check.gd")
const Fixture := preload("res://tests/fs/core/core_automation_batch03.gd")
const Tarot := preload("res://games/four_souls/logic/fs_tarot_cards.gd")

func run(t: Check) -> void:
	t.equal(Tarot.IDS.size(), 20, "Пакет Таро содержит20карт")
	var fixture := Fixture.new()
	for id in Tarot.IDS:
		var s = fixture._game(t, id)
		if id == 621:
			s.g._push({"kind": "roll", "value": 2, "owner": 1}, "turn")
		if id == 626:
			s._take(549)
			s.g._push({"kind": "loot", "card": 549, "owner": 1}, "turn")
		if id == 637:
			s._take(91)
			s.g._gain_item(0, 91)
			s._take(229)
			if int(s.g.shop[0]) >= 0:
				s.g.decks.treasure.push_front(int(s.g.shop[0]))
			s.g.shop[0] = 229
		if id == 639:
			s._take(91)
			s.g.decks.treasure.append(91)
		s.ok(0, "loot", {"card": id})
		s.close()
		match id:
			621:
				s.choose(0, "set_selected_roll", {"face": 6})
				s.close()
				t.equal(s.g.last_roll, 6, "Маг устанавливает точный выбранный результат")
			622:
				s.choose(0, "priestess_target", {"zone": "player", "target": 2})
				s.no(0, "effect_done", null, "Жрица не пропускает бросок после выбора цели")
				s.roll(2)
				s.ok(0, "effect_roll")
				s.close()
				t.equal(s.g.hp[2], 1, "Жрица нанесла2урона выбранному игроку")
			623, 628, 629, 632:
				var opcode: String = {623: "empress", 628: "lovers", 629: "chariot", 632: "strength"}[id]
				s.choose(0, opcode, {"target": 0})
				t.equal(s.g.attack[0], 1 if id == 628 else 2, "Точный бонус атаки Таро%d" % id)
				t.equal(s.g.max_hp[0], 4 if id == 628 else 3 if id == 629 else 2, "Точный предел здоровья Таро%d" % id)
				t.equal(s.g.hp[0], s.g.max_hp[0], "При росте здоровья сохраняется количество отмеченного урона")
				t.equal(s.g._turn_roll_bonus[0], 1 if id == 623 else 0, "Бонус бросков только Императрицы")
				if id == 632: t.equal(s.g.attack_left, 2, "Сила даёт дополнительную атаку активному")
				s.ok(0, "end")
				s.close()
				t.equal(s.g.attack[0], 1, "Временная атака Таро%d истекла" % id)
				t.equal(s.g.max_hp[0], 2, "Временное здоровье Таро%d истекло" % id)
				t.equal(s.g._turn_roll_bonus[0], 0, "Бонус броска истёк")
			624, 625, 640:
				var selected: int = int(s.g.peek.cards[0])
				var deck: String = str(s.g.peek.deck)
				var rest: Array = s.g.peek.cards.duplicate()
				rest.erase(selected)
				t.check(s.g.get_view(1).peek.is_empty() and s.g.get_view(1).card_choices.is_empty(), "Чужой просмотр Таро%d не раскрывается" % id)
				s.choose(0, "peek_keep_top", {"card": selected})
				t.equal(s.g.decks[deck].back(), selected, "Выбранная карта наверху колоды")
				t.equal(s.g.decks[deck].slice(0, rest.size()), rest, "Остальные просмотренные карты под низом")
			626:
				s.close() # Обычное окно перезарядки822 в конце хода сохраняется.
				t.equal(s.g.current, 1, "Дурак завершил текущий ход")
				t.equal(s.zone_of(549), "discard:loot", "Дурак отменил неразрешившуюся монету")
				t.equal(s.g.coins[1], 6, "Отменённая монета не выдала ресурс")
			627:
				s.choose(0, "next_hit_shield", {"zone": "player", "target": 1, "amount": 2})
				s.g._damage_player(1, 1)
				t.equal(s.g.hp[1], 2, "Иерофант предотвратил первое событие1урона")
				s.g._damage_player(1, 1)
				t.equal(s.g.hp[1], 1, "Остаток Иерофанта не перенёсся на второе событие")
			630:
				s.choose(0, "justice", {"target": 1})
				t.equal(s.g.coins[0], 6, "Справедливость довела монеты до выбранного игрока")
				t.equal(s.g.hands[0].size(), 2, "Справедливость довела руку до выбранного игрока")
			631:
				s.roll(5)
				s.ok(0, "effect_roll")
				s.close()
				t.equal(s.g.coins[0], 8, "Колесо фортуны5даёт5монет")
			633:
				var group: Dictionary = s.g.peek.groups[0].duplicate()
				t.check(s.g.get_view(1).peek.is_empty(), "Повешенный смотрит колоды приватно")
				s.choose(0, "peek_bottom", {"deck": str(group.deck)})
				t.equal(s.g.decks[str(group.deck)].front(), int(group.card), "Повешенный отправляет выбранную карту вниз")
				s.choose(0, "close_peek")
				t.equal(s.g.hands[0].size(), 2, "Повешенный после просмотра берёт2карты")
			634:
				s.choose(0, "kill_player", {"target": 1})
				t.equal(s.g.hp[1], 0, "Смерть убивает выбранного игрока")
			635:
				s.choose(0, "temperance", {"damage": 1})
				t.equal(s.g.hp[0], 1, "Умеренность нанесла выбранный1урон")
				t.equal(s.g.coins[0], 7, "Умеренность дала соответствующие4монеты")
			636:
				t.equal(s.g.decks.loot.front(), 636, "Солнце ушло под низ вместо сброса")
				t.equal(s.g.extra_turns, [0], "Солнце назначило дополнительный ход владельцу")
			637:
				s.choose(0, "devil_destroy")
				s.choose(0, "take_shop", {"item": 0})
				t.equal(s.zone_of(91), "discard:treasure", "Дьявол уничтожил свою карту как условие")
				t.equal(s.zone_of(229), "item:0", "Дьявол автоматически украл выбранную карту магазина")
				t.equal(s.g.coins[0], 3, "Кража Дьявола не стала покупкой")
			638:
				s.roll(1)
				s.ok(0, "effect_roll")
				s.close()
				t.equal(s.g.hp, [1, 1, 2], "Башня1наносит1урон каждому игроку")
			639:
				t.equal(s.zone_of(91), "item:0", "Звёзды автоматически дали верхнее сокровище")
		s.close()
		t.check(not s.g._card_automation_active(), "Таро%d завершилось без произвольной панели" % id)
		s.inv("Таро%d" % id)
	# Все напечатанные ветки двух таблиц, не только счастливый исход.
	for id in [631, 638]:
		for face in range(1, 7):
			var s = fixture._game(t, id)
			s._take(91)
			s.g.decks.treasure.append(91)
			s._take(352)
			s.g.decks.monster.append(352)
			s.ok(0, "loot", {"card": id})
			s.close()
			s.roll(face)
			s.ok(0, "effect_roll")
			s.close()
			if id == 631:
				t.equal(s.g.coins[0], {1: 4, 2: 3, 3: 3, 4: 0, 5: 8, 6: 3}[face], "Колесо: монеты исхода%d" % face)
				if face == 2: t.equal(s.g.hp[0], 0, "Колесо2: смертельный урон сохраняет штатный штраф")
				if face == 3: t.equal(s.g.hands[0].size(), 3, "Колесо3: три карты")
				if face == 6: t.equal(s.zone_of(91), "item:0", "Колесо6: сокровище")
			else:
				if face in [3, 4]:
					s.close() # Смерть монстра имеет своё штатное окно ответов после урона Башни.
					t.equal(s.zone_of(423), "discard:monster", "Башня3–4: первый монстр убит")
					t.equal(s.g.monsters.filter(func(m): return int(m.id) == 427)[0].hp, 1, "Башня3–4: второй монстр получил1урон")
					t.equal(s.g.hp, [2, 2, 3], "Ветка монстров не ранит игроков")
				else:
					t.equal(s.g.hp, [1, 1, 2] if face <= 2 else [0, 0, 1], "Башня: точный урон всем игрокам")
			s.inv("Таро%d исход%d" % [id, face])
	var shield = fixture._game(t, 627)
	shield.ok(0, "loot", {"card": 627})
	shield.close()
	shield.choose(0, "next_hit_shield", {"zone": "monster", "monster_id": 427, "amount": 2})
	shield.operation_panel()
	shield.effect(0, "monster_damage", {"item": 1, "amount": 1})
	t.equal(shield.g.monsters[1].hp, 2, "Иерофант предотвращает урон монстру")
	shield.effect(0, "monster_damage", {"item": 1, "amount": 1})
	t.equal(shield.g.monsters[1].hp, 1, "Неиспользованная часть щита монстра не переносится")
	shield.ok(0, "effect_done")
	for item_id in [518, 243]:
		var devil = fixture._game(t, 637)
		devil._take(item_id)
		devil.g._gain_item(0, item_id)
		var index: int = devil.g.items[0].size() - 1
		devil.ok(0, "loot", {"card": 637})
		devil.close()
		devil.choose(0, "devil_destroy", {"item": index})
		t.check(not devil.g._card_automation_active(), "Замещение уничтожения%d не оплатило кражу" % item_id)
		devil.inv("Условие Дьявола%d" % item_id)
