extends RefCounted
## Напечатанные награды выдаёт реальная цепочка смерти: ресурсы, карта души, ручная часть и вложенные пассивы.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Data := preload("res://games/four_souls/logic/fs_reward_data.gd")

func run(t: Check) -> void:
	for id: int in Data.DATA:
		var printed: Dictionary = Data.DATA[id]
		var s := Scenario.new(t).rules_type(preload("res://tests/fs/fs_reward_catalog_rules.gd")).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
			.hand(0, []).monster(0, id, {"hp": 1, "dc": 1, "at": 1}).monster(1, 352 if id == 344 else 344) \
			.deck_top("treasure", [91, 229]).deck_top("monster", [427 if id == 423 else 423]).build()
		s.g.bonuses.clear() # Каталог награды отдельно от бонусных душ; интеграция ниже.
		if id in [279, 284, 286]:
			s.g.monsters[0]["counters"] = 2
		if id == 299:
			s.g.monsters[0]["counters"] = 5
		if id == 362:
			s.g.monsters[0]["death_saved_turn"] = s.g.turn_serial
		var initial_coins: int = int(s.g.coins[0])
		var initial_hand: int = s.g.hands[0].size()
		var initial_items: int = s.g.items[0].size()
		if id not in [264, 344, 352, 428]:
			# Контракт награды после подтверждённой смерти; боевые способности проверяются другими кейсами.
			s.g.monsters[0].hp = 0
			s.g._continue_stack()
		else:
			s.roll(6 if id == 264 else 5)
			s.ok(0, "attack", {"slot": 0})
			s.ok(0, "roll", null)
		s.close()
		if id == 417:
			var choices: Array = s.g._card_choices()
			s.ok(0, "card_choice", {"index": choices.size() - 1, "revision": s.g.revision}, "Отказ от необязательного просмотра417")
			s.close()
		if bool(printed.get("manual_death", false)) and id not in [369, 395, 414, 417, 424] and id not in preload("res://games/four_souls/logic/fs_monster19_cards.gd").IDS and id not in preload("res://games/four_souls/logic/fs_monster20_cards.gd").IDS:
			t.equal(s.g.phase, "effect", "Ручная часть смерти сохраняется у %d" % id)
			t.equal(s.g.hands[0].size(), initial_hand, "Награда ждёт окончания текста смерти%d" % id)
			s.no(0, "effect", {"op": "loot", "amount": 9}, "Ручной повтор награды не допускается")
			if s.g.resolving.has("spawn_card"):
				s.ok(0, "place_bloat", {"slot": 1})
				# Размещение перемешало колоду: изолируем награду от случайного события добора.
				t.check(s.g.decks.monster.has(423), "Карта контрольного добора осталась в колоде")
				s.g.decks.monster.erase(423)
				s.g.decks.monster.append(423)
			s.ok(0, "effect_done", null, "Подтверждение только ручного текста смерти")
			s.close()
		if printed.has("roll") or printed.get("return_roll", false):
			s.no(0, "effect_done", null, "Награда требует настоящий бросок")
			s.roll(4)
			s.ok(0, "effect_roll")
			s.close()
		if bool(printed.get("manual_post", false)):
			t.check(bool(s.g.resolving.get("post_reward_wait", false)), "Текст после наград ждёт после ресурсов%d" % id)
			s.ok(0, "effect_done", null, "Подтверждение только текста после ресурсов")
			s.close()
		if printed.has("damage_choice"):
			s.ok(0, "reward_damage", {"zone": "monster", "target": 1})
			s.close()
		if bool(printed.get("soul_other", false)):
			s.no(0, "reward_soul_target", {"target": 0}, "Душу надо передать другому игроку")
			s.ok(0, "reward_soul_target", {"target": 1})
			s.close()
		var expected_coins: int = 4 if printed.get("roll", "") == "coins" else int(printed.get("coins", 0)) + int(printed.get("coins_per_counter", 0)) * 2
		var expected_loot: int = 4 if printed.get("roll", "") == "loot" else int(printed.get("loot", 0)) + int(printed.get("loot_per_counter", 0)) * 2
		var soul_owner: int = 1 if bool(printed.get("soul_other", false)) else 0
		t.equal(int(s.g.coins[0]), initial_coins + expected_coins, "Монеты напечатанной награды%d" % id)
		t.equal(s.g.hands[0].size(), initial_hand + expected_loot, "Добыча награды%d" % id)
		t.equal(s.g.items[0].size(), initial_items + int(printed.get("treasure", 0)) + (1 if bool(printed.get("self_item", false)) else 0), "Сокровища и предметы награды%d" % id)
		t.equal(int(s.g.souls[soul_owner]), int(printed.get("souls", 0)), "Душевая ценность получателя%d" % id)
		t.equal(s.g.soul_cards[soul_owner].count({"id": id, "value": int(printed.get("souls", 0))}), 1 if int(printed.get("souls", 0)) > 0 else 0, "Не более одной физической карты души%d" % id)
		t.check(not s.g.monsters.any(func(monster): return monster.id == id), "Монстр снят после награды%d" % id)
		s.no(0, "effect_done", null, "Повторное завершение не выдаёт награду%d" % id)
		s.inv("Автоматическая награда%d" % id)
	var blocked := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.monster(0, 428, {"hp": 1, "dc": 1}).room(779).build()
	# Пин не получает боевой урон от6: смертельная пятёрка.
	blocked.roll(5)
	blocked.ok(0, "attack", {"slot": 0})
	blocked.ok(0, "roll", null)
	blocked.close()
	t.equal(blocked.g.souls[0], 0, "Комната запрещает душу автоматической награды")
	t.equal(blocked.zone_of(428), "discard:monster", "Без полученной души физическая карта в сбросе")
	var heart := Scenario.new(t).players(2).dlc().current(0).character(0, 821).no_items(0).no_items(1) \
		.soul(1, 345).soul(1, 421).monster(0, 381, {"hp": 0}).build()
	heart.g._continue_stack()
	heart.close()
	t.equal(heart.g.resolving.get("reward_winners"), [0, 1], "При равенстве максимумов Сердце Мамы требует выбор")
	heart.no(1, "reward_winner", {"target": 1}, "Чужой игрок не выбирает победителя")
	heart.no(0, "reward_winner", {"target": 99}, "Нет победителя вне списка")
	heart.ok(0, "reward_winner", {"target": 1})
	t.equal(heart.g.winner, 1, "При равенстве выбран другой игрок")
	t.equal(heart.zone_of(381), "soul:0", "Сердце осталось у получателя души, не у выбранного победителя")
	heart.inv("После альтернативной победы")
