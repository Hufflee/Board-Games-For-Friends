extends SceneTree
## Разовая проверка (07.11): «Рак» 552 — 3 на кубике против защиты 4+ должно быть попаданием.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	s._take(552)
	g._gain_item(0, 552)
	g.monsters[0].dc = 4
	if OS.get_environment("HAUNT") == "1":
		s._take(328)
		g.monsters[1] = {"id": 328, "hp": 2, "dc": 3, "at": 1}
	var hp0: int = int(g.monsters[0].hp)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3, [2])
	s.ok(0, "roll")
	if g.phase == "effect":
		print("выбор: ", g.get_view(g.actor()).card_choices, " выбирает ", g.actor())
		if g.phase == "effect" and not g._card_choices().is_empty():
			s.ok(g.actor(), "effect_roll")
			s.close()
		print("выбор после броска: ", g._card_choices().map(func(c): return c.label))
		g.action(g.actor(), "card_choice", {"index": 0, "revision": g.revision})
	print("стек после броска: ", g.stack.map(func(e): return [e.kind, e.get("value", ""), e.get("hit", ""), e.get("final_value", "")]))
	s.close()
	print("стек после окна: ", g.stack.map(func(e): return [e.kind, e.get("value", ""), e.get("hit", "")]), " фаза ", g.phase)
	for i in 4:
		if g.phase == "priority": s.close()
	print("hp монстра ", hp0, " -> ", g.monsters[0].hp, " игрок hp ", g.hp[0], " журнал ", g.log.slice(-6))
	quit()
