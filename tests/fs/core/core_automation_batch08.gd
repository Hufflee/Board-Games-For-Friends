extends RefCounted
## Пакет08:20брелоков. Проверяются события, чужой выбор, отмена и замена до изменения ресурсов.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Cards := preload("res://games/four_souls/logic/fs_trinket_cards.gd")

func _game(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).character(1, 821).character(2, 821) \
		.no_items(0).no_items(1).no_items(2).hand(0, [549]).hand(1, [480, 481]).hand(2, [482]) \
		.item(0, id).monster(0, 423).monster(1, 427).deck_top("monster", [352, 348, 357]).room(-1).coins(0, 5).build()
	s.g.bonuses.clear()
	return s

func run(t: Check) -> void:
	t.equal(Cards.IDS.size(), 20, "Пакет08содержит20брелоков")
	var found = _game(t, 471)
	t.equal(found.g.attack[0], 2, "Найденная душа даёт1атаку")
	found._take(475)
	found.g._gain_soul_card(0, {"id": 475, "value": 1})
	found.close()
	found.choose(0, "found_soul_give", {"target": 1})
	t.equal(found.zone_of(471), "item:1", "Получение души заставляет отдать сам брелок")
	t.equal(found.g.attack[0], 1, "Бонус ушёл у старого владельца")
	t.equal(found.g.attack[1], 2, "Бонус появился у нового владельца")
	var sticker = _game(t, 473)
	t.equal(sticker.g._purchase_cost(0, 0), 9, "Стикер снижает стоимость магазина на1")
	t.equal(sticker.g._purchase_cost(0, -1), 10, "Стикер не снижает стоимость скрытого верха")
	sticker._take(40)
	sticker.g.discards.treasure.append(40)
	sticker.g._gain_coins(0, 4)
	sticker.ok(0, "buy", {"slot": -2})
	sticker.close()
	t.equal(sticker.zone_of(40), "item:0", "Стикер разрешает купить верх сброса")
	var fuse = _game(t, 474)
	fuse.g._destroy_item(0, 1)
	fuse.close()
	fuse.choose(0, "damage", {"target": 1, "amount": 2})
	t.equal(fuse.g.hp[1], 0, "Уничтоженный запал автоматически наносит2выбраннойцели")
	t.equal(fuse.zone_of(474), "discard:loot", "Запал не возвращается в предметы после триггера")
	var wish = _game(t, 505)
	var old_count: int = wish.g.items[0].size()
	wish.g._destroy_item(0, 1)
	wish.close()
	t.equal(wish.g.items[0].size(), old_count, "Кость желаний заменилась одним новым сокровищем")
	t.equal(wish.zone_of(505), "discard:loot", "Уничтоженная кость в сбросе добычи")
	var rib = _game(t, 523)
	rib.g._gain_coins(0, -4)
	t.equal(rib.g.coins[0], 5, "Ребро предотвращает потерю монет от способности")
	rib.g._push({"kind": "forced_discard", "owner": 1, "target": 0, "card": 579, "amount": 1}, "turn")
	rib.close()
	t.equal(rib.g.hands[0], [549], "Ребро предотвращает принудительный сброс от способности")
	var remote = _game(t, 526)
	remote._take(40)
	remote.g._gain_item(0, 40)
	remote.ok(0, "activate", {"item": 2})
	remote.close()
	remote.choose(0, "discard_monster", {"item": 1})
	remote.close()
	t.equal(remote.zone_of(427), "discard:monster", "Активация предмета открывает выбор сброса Пульта")
	var toe = _game(t, 527)
	toe.g._draw_loot(0, 2)
	t.equal(toe.g.hands[0].size(), 4, "Палец даёт2+1добычи от эффекта")
	toe.g._draw_loot(0, 1, "step")
	t.equal(toe.g.hands[0].size(), 5, "Палец не увеличивает обычную фазу добора")
	var pink = _game(t, 546)
	pink.g._damage_player(0, 1, {"combat": true, "value": 1, "monster": 427})
	pink.close()
	t.equal(pink.g.monsters[1].hp, 1, "Конъюнктивит наносит1именноисточникубоевогоурона")
	pink.g._damage_player(0, 1, {"combat": false, "value": 1, "monster": 427})
	pink.close()
	t.equal(pink.g.monsters[1].hp, 1, "Небоевой урон не активирует Конъюнктивит")
	for id in [566, 687, 653, 582]:
		for face in range(1, 7):
			var s = _game(t, id)
			match id:
				566:
					s.g.character_ready[0] = false
					s.ok(0, "end")
				687:
					s.g.hp[0] = 0
					s.g._check_deaths()
				653:
					s.g._damage_player(0, 2)
					t.equal(s.g.hp[0], 2, "Комок шерсти откладывает урон до настоящего броска")
				582:
					s.g._gain_coins(0, 4)
					t.equal(s.g.coins[0], 5, "Покерная фишка откладывает заменяемое начисление до броска")
			s.close()
			s.roll(face)
			s.ok(0, "effect_roll")
			s.close()
			if s.g.phase == "priority":
				s.close()
			match id:
				566:
					if face >= 4:
						s.choose(0, "recharge", {"target": 1, "item": 0})
						s.close()
						if s.g.phase == "priority":
							s.close()
					t.equal(s.g.current, 1, "ААА завершает свой обязательный бросок и ход")
				687:
					if face == 6:
						t.equal(s.g.current, 1, "Анх на6предотвращаетсмертьизавершаетсвойход")
						t.equal(s.g.coins[0], 5, "Предотвращённая Анхом смерть без штрафа")
					else:
						t.equal(s.g.phase, "death", "Неудачный Анх возвращает оплату смерти")
				653:
					t.equal(s.g.hp[0], 1 if face == 6 else 0, "Комок предотвращает ровно1тольконагранях6")
				582:
					t.equal(s.g.coins[0], 6 if face <= 3 else 13, "Покерная фишка заменяет первую выплату1илиудвоением")
					s.g._gain_coins(0, 2)
					t.equal(s.g.coins[0], 8 if face <= 3 else 15, "Вторая выплата собственного хода без нового броска")
	var left = _game(t, 570)
	left.g._emit_passives("death", {"seat": 1})
	left.close()
	left.choose(0, "recharge", {"target": 1, "item": 0})
	left.close()
	t.check(not left.g.items[1][0].tapped, "Левая рука перезарядила выбранный предмет при чужой смерти")
	var worm = _game(t, 571)
	worm.g.battle = 1
	worm.g.phase = "battle_roll"
	worm.roll(1)
	worm.ok(0, "roll")
	worm.close()
	worm.choose(0, "damage", {"target": 1})
	worm.close()
	t.equal(worm.g.hp[1], 1, "Червь при промахе наносит1другомуигроку")
	for id in [647, 651, 678]:
		var s = _game(t, id)
		var deck: String = "loot" if id == 647 else "treasure" if id == 651 else "monster"
		var top: int = int(s.g.decks[deck].back())
		s.g._emit_passives("turn_start")
		s.close()
		t.equal(s.g.get_view(0).peek.cards, [top], "Брелок показывает ровно верхнюю карту своей колоды")
		t.check(s.g.get_view(1).peek.is_empty(), "Просмотр начала хода приватен")
		s.choose(0, "trinket_bottom")
		t.equal(s.g.decks[deck].front(), top, "Брелок положил выбранный верх под низ")
	var horn = _game(t, 652)
	t.equal(horn.g.attack[0], 1, "Рог не даёт постояннуюатакунавесьход")
	horn.g.monsters[1].hp = 8
	horn.g.battle = 1
	horn.g.phase = "battle_roll"
	for expected in [6, 5]:
		horn.roll(6)
		horn.ok(0, "roll")
		horn.close()
		t.equal(horn.g.monsters[1].hp, expected, "Рог добавляет1урон только первого броска атаки")
	var bloody = _game(t, 654)
	bloody.g._emit_passives("death", {"seat": 1})
	bloody.close()
	t.equal(bloody.g.hands[0].size(), 2, "Кровавый пенни берёт1карту до чужого штрафа")
	var swallowed = _game(t, 677)
	swallowed.g._damage_player(0, 1)
	swallowed.close()
	t.equal(swallowed.g.coins[0], 6, "Проглоченный пенни даёт1монету от полученного урона")
