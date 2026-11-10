extends RefCounted
## Лента содержит публичный результат действия, сохраняя тайну колоды и руки.
const Check := preload("res://tests/fs/fs_check.gd")
const Scenario := preload("res://tests/fs/fs_scenario.gd")


func run(t: Check) -> void:
	var s := Scenario.new(t).dlc().current(0).hand(0, [497]).coins(0, 15)
	s.monster(0, 435).shop(0, 174).deck_top("treasure", [57]).build()
	s.ok(0, "loot", {"card": 497})
	s.close()
	s.choose(0, "monster_damage", {"item": 0})
	s.close()
	var bomb: Dictionary = _entry(s.g, "loot", 497)
	t.check(not bomb.is_empty() and bomb.results.any(func(result):
		return result.kind == "damage" and int(result.card) == 435 and int(result.amount) == 1),
		"Лента связывает Бомбу с целью и фактическим уроном")
	s.ok(0, "buy", {"slot": 0})
	s.close()
	var purchase: Dictionary = _entry(s.g, "purchase", 174)
	t.check(not purchase.is_empty() and purchase.results.any(func(result):
		return result.kind == "gain_item" and int(result.card) == 174 and result.target.name == s.g.name_of(0)),
		"В записи о покупке видны полученный предмет и покупатель")
	t.equal(int(s.g.shop[0]), 57, "Преследователь занимает освободившийся слот по FAQ")
	var before := s.g._action_sequence
	s.g._draw_loot(0, 1)
	var feed: Array = s.g.get_view(1).action_history
	var draw: Dictionary = feed.back()
	t.check(int(draw.seq) > before and int(draw.card) == -1 and draw.results.all(func(result):
		return not result.has("card")), "Соперник видит количество добранных карт без их ID")
	_coin_and_roll(t)


func _coin_and_roll(t: Check) -> void:
	var early := Scenario.new(t).current(0).hand(0, [549]).build()
	early.g.strict_responses28 = true
	early.ok(0, "attack", {"slot": 0})
	early.close()
	early.ok(0, "loot", {"card": 549})
	early.no(0, "roll", null, "Новый бросок ждёт ранее разыгранную монетку")
	early.close()
	t.equal(early.g.roll_no, 0, "До разрешения монетки кубик не бросался")

	var s := Scenario.new(t).current(0).hand(0, [549]).coins(0, 0).item(0, 228) \
		.monster(0, 435).build()
	s.g.strict_responses28 = true
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3)
	s.ok(0, "roll")
	s.ok(0, "loot", {"card": 549})
	s.no(0, "roll", null, "Окно ответов нельзя закрыть повторным жестом кубика")
	s.close()
	t.equal(int(s.g.monsters[0].hp), 2, "Монетка над броском убирает бонус Пустого сосуда до проверки попадания")
	t.check(int(s.g.coins[0]) > 0, "Монетка применилась до разрешения броска")

	var effect := Scenario.new(t).current(0).hand(0, [520]).build()
	effect.g.strict_responses28 = true
	effect.ok(0, "loot", {"card": 520})
	effect.close()
	effect.roll(5)
	effect.ok(0, "effect_roll")
	effect.no(0, "effect_roll", null, "Повторный жест не закрывает окно броска по эффекту")
	effect.close()
	t.equal(effect.g.roll_no, 1, "Один бросок по эффекту расходует одну грань")


func _entry(game: FSRules, kind: String, card: int) -> Dictionary:
	for entry: Dictionary in game.action_history:
		if entry.kind == kind and int(entry.card) == card:
			return entry
	return {}
