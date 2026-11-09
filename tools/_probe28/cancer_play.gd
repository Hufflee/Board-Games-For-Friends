extends SceneTree
## Разовая проверка (07.11): «Рак» 552 разыгран из руки как брелок, затем атака 3 против 4+.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	s._take(552)
	g.hands[0].append(552)
	s.ok(0, "loot", {"card": 552})
	for i in 4:
		if g.phase == "priority": s.close()
	print("предметы ", g.items[0].map(func(e): return [int(e.id), e.get("physical_id13", "")]), " счёт Рака ", g._item_count(0, 552), " фаза ", g.phase)
	g.monsters[0].dc = 4
	var hp0: int = int(g.monsters[0].hp)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3)
	s.ok(0, "roll")
	for i in 5:
		if g.phase == "priority": s.close()
	print("hp монстра ", hp0, " -> ", g.monsters[0].hp, " журнал ", g.log.slice(-5))
	quit()
