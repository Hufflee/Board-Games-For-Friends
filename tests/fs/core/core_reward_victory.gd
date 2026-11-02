extends RefCounted
## Четвёртая душа завершает игру до ручной Кармы; физический монстр не остаётся второй копией души.
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")

func run(t: Check) -> void:
	var s := Scenario.new(t).players(3).dlc().current(0).character(0, 821).no_items(0).no_items(1).no_items(2) \
		.item(1, 8).soul(0, 345).soul(0, 421).soul(0, 428) \
		.monster(0, 420, {"hp": 1, "dc": 1}).monster(1, 344).deck_top("treasure", [91]).build()
	s.g.bonuses.clear()
	s.roll(5)
	s.ok(0, "attack", {"slot": 0})
	s.ok(0, "roll", null)
	for i in 4:
		if s.g.phase == "game_over":
			break
		s.g.tick(5.1)
	t.equal(s.g.phase, "game_over", "Четыре души завершают игру без ручного выбора Кармы")
	t.equal(s.g.winner, 0, "Побеждает получатель четвёртой души")
	t.equal(s.g.soul_cards[0].filter(func(card): return card.id == 420).size(), 1, "Одна физическая Маска в душах")
	t.check(not s.g.monsters.any(func(monster): return monster.id == 420), "На финальном столе нет второй копии карты души")
	s.inv("Победа во время вложенного обязательного триггера")
