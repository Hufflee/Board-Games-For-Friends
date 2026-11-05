extends RefCounted
## Пакет10:20сокровищ, все грани таблиц и приватные/платные обязательные решения.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_active_cards.gd")

func _game(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 821) \
		.no_items(0).no_items(1).no_items(2).hand(0, [549]).hand(1, [480]).hand(2, [482]) \
		.item(0, id).monster(0, 423).monster(1, 427).room(-1).shop(0, 143).shop(1, 229) \
		.deck_top("treasure", [16, 24, 25, 26, 79, 174, 249]).coins(0, 5).build()
	s.g.bonuses.clear()
	return s

func _activate(s: RefCounted) -> void:
	s.ok(0, "activate", {"item": 1, "tap": false})
	s.close()

func run(t: Check) -> void:
	t.equal(Cards.IDS.size(), 20, "Пакет10содержит20сокровищ")
	for id in [6, 15, 86, 94, 95]:
		for face in {6: [1, 3], 15: [4, 5], 86: [1, 3, 5], 94: [1, 2, 3, 4, 5, 6], 95: [1, 6]}[id]:
			var s = _game(t, id)
			if id == 15:
				s.ok(0, "attack", {"slot": 1})
				s.close()
			elif id == 86:
				s.g.items[0][0].tapped = true
				s.g._emit_passives("monster_death", {"seat": 0, "card": 423})
				s.close()
			else:
				_activate(s)
			s.roll(face)
			s.ok(0, "effect_roll")
			s.close()
			if id == 6 and face >= 3:
				s.choose(0, "damage", {"target": 1})
			if id == 86 and face in [3, 4]:
				s.choose(0, "hand_top")
			if s.g.phase == "priority":
				s.close()
			match id:
				6:
					t.equal(s.g.hp[0] if face <= 2 else s.g.hp[1], 1, "Динамит наносит1по соответствующей ветке")
					s.g.items[0][1].tapped = true
					s.g._gain_coins(0, 3)
					s.close()
					t.check(not s.g.items[0][1].tapped, "Динамит перезарядился от разовой выплаты3")
				15:
					t.equal(s.g._monster_evasion(s.g.monsters[1]), 2 if face >= 5 else 3, "Папино кольцо меняет защиту именно объявленной цели на5–6")
				86:
					if face <= 2: t.equal(s.g.coins[0], 7, "Сундучок на1–2даётименно2монеты")
					elif face <= 4: t.equal(s.g.hands[0].size(), 2, "Сундучок взял2иобязательновернул1карту")
					else: t.check(not s.g.items[0][0].tapped, "Сундучок зарядил все свои предметы")
				94:
					if face == 1: t.equal(s.g.hp[0], 0, "Лечение на1убиваетавтора")
					elif face == 2: t.equal(s.g.hands[0].size(), 4, "Лечение на2даёт3карты")
					elif face == 3: t.equal(s.g.coins[0], 14, "Лечение на3даёт9монет")
					elif face <= 5: t.equal(s.g.items[0].size(), 1 + face - 3, "Лечение даёт1/2сокровища после уничтожения источника")
					else:
						t.equal(s.g.souls[0], 1, "Лечение на6сталооднойдушой")
						t.equal(s.zone_of(94), "soul:0", "Лечение не осталось одновременно в сбросе и душах")
				95:
					t.equal(s.g.coins[0], 5 + face * 4, "Эффектный мальчик начисляет грань×4")
					t.equal(s.zone_of(95), "discard:treasure", "Мальчик уничтожается до броска")
	var gift = _game(t, 0)
	_activate(gift)
	for target in [1, 2]: gift.choose(0, "gift_player", {"target": target})
	gift.choose(0, "skip_choice")
	t.equal(gift.g.peek.cards.size(), 2, "Подарок смотрит число выбранных игроков")
	t.check(gift.g.get_view(1).peek.is_empty(), "Просмотр Подарка приватен")
	gift.choose(0, "gift_arrange", {"card": 249, "destination": "top"})
	gift.choose(0, "gift_arrange", {"card": 174, "destination": "bottom"})
	gift.close()
	t.equal(gift.zone_of(249), "item:0", "Свой подарок берётся после полного упорядочивания")
	t.equal(gift.g.items[1].size(), 2, "Первый выбранный игрок получил сокровище")
	t.equal(gift.g.items[2].size(), 2, "Второй выбранный игрок получил сокровище")
	t.equal(gift.g.decks.treasure.front(), 174, "Выбранная карта сохранилась под низом")
	var pumpkin = _game(t, 92)
	pumpkin._take(14)
	pumpkin.g._gain_item(0, 14)
	pumpkin.close()
	t.equal(pumpkin.zone_of(14), "discard:treasure", "Маска уничтожилась прежде просмотра")
	t.equal(pumpkin.g.peek.cards.size(), 10, "Маска смотрит ровно10карт")
	pumpkin.choose(0, "pumpkin_pick", {"card": 249})
	t.equal(pumpkin.zone_of(249), "item:0", "Маска дала выбранное сокровище")
	var dollar = _game(t, 21)
	var shop: Array = dollar.g.shop.duplicate()
	_activate(dollar)
	for id in shop: t.equal(dollar.zone_of(int(id)), "item:0", "Доллар украл каждый исходный предмет магазина")
	t.equal(dollar.g.shop.size(), shop.size(), "Доллар не крадёт бесконечно новые добираемые карты")
	var xray = _game(t, 84)
	_activate(xray)
	xray.choose(0, "peek_hand", {"target": 1})
	t.equal(xray.g.get_view(0).peek.hands[0].cards, [480], "Рентген показывает выбранную руку")
	xray.choose(0, "close_peek")
	xray.choose(0, "peek_deck", {"deck": "treasure"})
	xray.choose(0, "xray_discard", {"card": 249})
	t.equal(xray.zone_of(249), "discard:treasure", "Рентген сбросил выбранный верх колоды")
	var hallowed = _game(t, 85)
	hallowed.no(0, "activate", {"item": 1, "tap": false})
	for i in 3:
		hallowed.g._roll_passives(2, 1)
		hallowed.close()
	hallowed._take(550)
	hallowed.g.discards.loot.append(550)
	_activate(hallowed)
	t.equal(hallowed.zone_of(550), "hand:0", "Священная земля вернула верхний лут сброса")
	t.equal(hallowed.g.items[0][1].counters, 0, "Священная земля оплатила ровно3жетона")
	var shadow = _game(t, 87)
	shadow.g._emit_passives("death", {"seat": 0})
	shadow.close()
	t.equal(shadow.g.items[0][1].counters, 2, "Тень до штрафа накапливает2жетона")
	shadow.g._destroy_item(0, 1)
	shadow.close()
	t.equal(shadow.g.coins[0], 7, "Тень выдала2монеты после уничтожения")
	t.equal(shadow.g.hands[0].size(), 3, "Тень выдала2карты после уничтожения")
	var ultra = _game(t, 89)
	for i in 12:
		ultra.g._emit_passives("monster_death", {"seat": 1, "card": 423})
	ultra.close()
	ultra.g._emit_passives("turn_end")
	ultra.close()
	t.equal(ultra.zone_of(89), "soul:0", "Ультрамясной на12жетонах стал физической душой")
	t.equal(ultra.g.souls[0], 1, "Ультрамясной даёт ровно1душу")
	var prize = _game(t, 90)
	prize._take(348)
	prize.g._gain_soul_card(1, {"id": 348, "value": 2})
	prize.g._emit_passives("turn_start")
	prize.close()
	t.equal(prize.g.hands[0].size(), 3, "Утешительный приз берётразницу2душ")
	var member = _game(t, 91)
	t.equal(member.g._purchase_cost(0, 0), 6, "Членская карта сохраняет скидку4")
	_activate(member)
	for id in [249, 79, 174]: member.choose(0, "order_card", {"card": id})
	t.equal(member.g.decks.treasure.back(), 249, "Членская карта упорядочила верх3до сброса магазина")
	member.choose(0, "discard_shop", {"item": 0})
	t.equal(member.zone_of(143), "discard:treasure", "Членская карта сбросила именно выбранный магазин")
	var bandage = _game(t, 92)
	bandage.g._damage_player(0, 4, {"combat": true, "value": 3})
	t.equal(bandage.g.hp[0], 2, "Шар из пластырей полностью предотвращает боевой урон на3")
	var milk = _game(t, 93)
	for i in 3:
		milk.g._emit_passives("turn_start")
		milk.close()
		if i == 1: t.equal(milk.g.attack[0], 2, "Молоко при двух жетонах даёт1атаку")
	milk.choose(0, "damage", {"target": 1})
	t.equal(milk.g.attack[0], 1, "После третьего жетона бонус Молока исчез")
	t.equal(milk.g.hp[1], 1, "Молоко нанесло1выбранномуигроку")
	var gish = _game(t, 96)
	gish.g.items[1][0].tapped = true
	_activate(gish)
	gish.choose(0, "gish_lock", {"target": 1, "item": 0})
	gish.ok(0, "end")
	gish.close()
	t.equal(gish.g.current, 1, "Ход дошёл до контролирующего выбранный предмет")
	t.check(gish.g.items[1][0].tapped and not gish.g.items[1][0].has("skip_recharge_once"), "Гиш пропустил именно ближайшую зарядку и снял отметку")
	var eye = _game(t, 97)
	eye.operation_panel()
	eye.effect(0, "monster_damage", {"item": 1, "amount": 1})
	eye.close()
	t.equal(eye.g.attack[0], 2, "Мёртвый глаз получает1атаку от нанесённого монстру урона")
	var marked = _game(t, 98)
	marked._take(24)
	marked.g._gain_item(0, 24)
	marked.g.monsters[1].hp = 8
	marked.g.battle = 1
	marked.g.phase = "battle_roll"
	marked.roll(2)
	marked.ok(0, "roll")
	marked.close()
	marked.choose(0, "marked_set")
	marked.close()
	t.equal(marked.g.last_roll, 5, "Отмеченный задаёт итог5дажесПомадой")
	var fetus = _game(t, 99)
	_activate(fetus)
	fetus.choose(0, "monster_damage", {"item": 1})
	fetus.choose(0, "damage", {"target": 1})
	t.equal(fetus.g.monsters[1].hp, 1, "Зародыш нанёс1монстру")
	t.equal(fetus.g.hp[1], 1, "Зародыш нанёс1выбранномуигроку")
	t.equal(fetus.g.hp[0], 1, "Зародыш также нанёс1автору")
