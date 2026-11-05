extends RefCounted
## Второй пакет: 20 комнат, сверенных с изображениями; положительные и соседние условия.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const ROOMS := [764, 766, 769, 770, 771, 772, 777, 781, 782, 796, 797, 798, 799, 800, 802, 806, 808, 809, 812, 818]

func _room(t: Check, id: int) -> RefCounted:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [478, 479]).hand(1, [480, 481]) \
		.coins(0, 5).coins(1, 5).monster(0, 423).monster(1, 427).room(id).build()
	s.g.bonuses.clear()
	return s

func run(t: Check) -> void:
	t.equal(ROOMS.size(), 20, "Пакет содержит20комнат")
	for id in ROOMS:
		var s = _room(t, id)
		match id:
			764:
				s.ok(0, "end")
				s.close()
				t.equal(s.g.coins[0], 3, "764 списывает2монеты в конце")
				t.equal(s.g.coins[1], 5, "764 не затрагивает соседа")
			766:
				s.g._begin_turn()
				s.close()
				t.equal(s.g.coins[0], 8, "766 автоматически даёт3в начале")
			769, 770:
				t.equal(s.g.max_hp[0], 3 if id == 769 else 2, "769 источник пределаHP")
				t.equal(s.g.attack[0], 2 if id == 770 else 1, "770 источник атаки")
				s.g.discards.room.append(id)
				s.g.room = -1
				s.g._refresh_passive_stats()
				t.equal(s.g.max_hp[0], 2, "ПределHP не залипает после ухода комнаты")
				t.equal(s.g.attack[0], 1, "Атака не залипает после ухода комнаты")
			771:
				t.equal(s.g._purchase_cost(0, 0), 5, "771 скидка активному в магазине")
				t.equal(s.g._purchase_cost(1, 0), 10, "771 не скидка сопернику")
				t.equal(s.g._purchase_cost(0, -1), 10, "771 не скидка вслепую")
			772:
				s.g._begin_turn()
				t.equal(s.g.hands[0].size(), 4, "772 даёт2карты в шаге добычи")
				t.equal(s.g.hands[1].size(), 2, "772 добирает только активный")
			777:
				s.g.dead[1] = true
				s.g._emit_passives("death", {"seat": 0})
				s.close()
				t.equal(s.g.hands[1].size(), 3, "777 добыча каждому другому, включая умершего")
				t.equal(s.g.hands[0].size(), 2, "777 умерший не получает свою награду")
			781:
				t.equal(s.g.attack_left, 2, "781 разрешает дополнительную атаку")
				s.no(0, "end", null, "781 нельзя пропустить доступную атаку")
			782:
				t.equal(s.g._purchase_cost(0, 0), 0, "782 равные минимальные души: бесплатно")
				t.equal(s.g._purchase_cost(1, 0), 10, "782 вне своего хода льготы нет")
				s.g._gain_soul_card(0, {"id": 689, "value": 1})
				t.equal(s.g._purchase_cost(0, 0), 10, "782 лидер платит обычную цену")
			796:
				s.g._emit_passives("turn_end")
				s.close()
				t.equal(s.g.hp[0], 1, "796 равенство минимума руки тоже даёт1урон")
				t.equal(s.g.hp[1], 2, "796 не наносит урон сопернику")
			797:
				t.equal(s.g._monster_hp(423), 2, "797 новый монстр получает+1HP")
				s.g.discards.room.append(id)
				s.g.room = -1
				t.equal(s.g._monster_hp(423), 1, "797 после ухода предел обычный")
			798:
				s.g._emit_passives("death", {"seat": 0})
				s.close()
				t.equal(s.g.coins[1], 9, "798 другой игрок получает4монеты")
				t.equal(s.g.coins[0], 5, "798 умерший не получает свои монеты")
			799:
				s.g._draw_loot(0, 1)
				s.close()
				t.equal(s.g.hands[0].size(), 3, "799 добыча действительно выдана")
				t.equal(s.g.hp[0], 1, "799 за фактически взятую карту1урон")
				s.g._emit_passives("activate", {"seat": 1})
				s.close()
				t.equal(s.g.hp[1], 2, "799 не реагирует на чужое событие активации")
			800:
				s.ok(0, "end")
				s.close()
				t.equal(s.g.phase, "forced_discard", "800 требует выбрать карту, не произвольную операцию")
				s.ok(0, "forced_discard", {"item": 1})
				s.close()
				t.equal(s.g.hands[0], [478], "800 сбрасывает именно выбранную карту")
			802:
				s.g._emit_passives("turn_end")
				s.close()
				t.check(not s.g.character_ready[0], "802 автоматически деактивирует персонажа")
			806:
				s._take(689)
				s.g._gain_soul_card(0, {"id": 689, "value": 1})
				s.close()
				t.equal(s.g.skipped_turns[0], 1, "806 получение души назначает пропуск")
				s._take(690)
				s.g._gain_soul_card(1, {"id": 690, "value": 1}, false)
				s.close()
				t.equal(s.g.skipped_turns[1], 0, "806 передача контроля не подменяет получение")
			808:
				t.equal(s.g.attack[0], 2, "808 бонус атаки при минимуме душ")
				t.equal(s.g.attack_left, 2, "808 дополнительный бой")
				s.g._gain_soul_card(0, {"id": 689, "value": 1})
				s.g._refresh_passive_stats()
				t.equal(s.g.attack[0], 1, "808 бонус снимается у нового лидера")
				t.equal(s.g.attack_left, 1, "808 дополнительный бой снимается у лидера")
				s.g.souls[0] = 0
				s.g.soul_cards[0].clear()
				s.g._refresh_passive_stats()
				t.equal(s.g.attack_left, 2, "808 бонус восстанавливается без накопления")
			809:
				s.g._begin_turn()
				s.no(0, "end", null, "809 нельзя закончить без обязательной атаки")
				s.no(0, "attack", {"slot": 0}, "809 открытая цель не заменяет колоду")
			812:
				s.ok(0, "activate", {"item": 0})
				s.close()
				t.equal(s.g.hp[0], 1, "812 активация наносит1урон")
				t.equal(s.g.hp[1], 2, "812 страдает только активировавший")
			818:
				t.equal(s.g._monster_attack(s.g.monsters[0]), 2, "818 монстр имеет+1атаку")
				s.g.discards.room.append(id)
				s.g.room = -1
				t.equal(s.g._monster_attack(s.g.monsters[0]), 1, "818 бонус снимается после ухода")
		s.inv("Комната%d" % id)
