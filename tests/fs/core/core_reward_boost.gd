extends RefCounted
## Счастливая монета: множитель награды, независимые души, конечный добор и бонус по тихому таймеру.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func _game(t: Check, monster: int) -> RefCounted:
	var s := Scenario.new(t).players(2).dlc().current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [528]).hand(1, []).coins(0, 0) \
		.monster(0, monster, {"hp": 1}).monster(1, 423).deck_top("monster", [427]).build()
	s.g.bonuses.clear()
	return s

func run(t: Check) -> void:
	for id in [352, 345, 259, 310]:
		var s = _game(t, id)
		s.ok(0, "loot", {"card": 528})
		s.close()
		t.equal(s.g.reward_boost, 2, "Множитель включён после розыгрыша528")
		t.equal(s.g.coins[0], 1, "Сама монета даёт ровно1")
		var hand: int = s.g.hands[0].size()
		var items: int = s.g.items[0].size()
		s.g.monsters[0].hp = 0
		s.g._continue_stack()
		s.close()
		if id == 310:
			s.roll(3)
			s.ok(0, "effect_roll")
			s.close()
		if id == 352:
			t.equal(s.g.coins[0], 7, "3 монеты награды удвоены, исходная монета отдельно")
		if id == 345:
			t.equal(s.g.hands[0].size(), hand + 4, "2карты добычи удвоены")
		if id == 259:
			t.equal(s.g.items[0].size(), items + 2, "Сокровище удвоено один раз")
		if id == 310:
			t.equal(s.g.hands[0].size(), hand + 6, "Бросок 3 даёт 6 карт добычи")
		if id in [345, 259]:
			t.equal(s.g.souls[0], 1, "Душа не удваивается")
		s.inv("Удвоенная награда")
	var expiry = _game(t, 352)
	expiry.g.reward_boost = 8
	expiry.ok(0, "end")
	expiry.close()
	t.equal(expiry.g.reward_boost, 1, "Новый ход сбрасывает множитель")
	var bonus := Scenario.new(t).players(2).current(0).character(0, 821).character(1, 821) \
		.no_items(0).no_items(1).hand(0, [549]).coins(0, 24).build()
	bonus.ok(0, "loot", {"card": 549})
	for i in 14:
		bonus.g.tick(0.5)
	t.check(bonus.g.claimed.has(689), "Бонус25монет выдаётся по тихому таймеру без следующего жеста")
	bonus.inv("Бонус от автоматического лута")
