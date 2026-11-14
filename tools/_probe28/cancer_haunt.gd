extends SceneTree
## Разовая проверка (07.11): «Рак» 552 при живом 328 (два кубика, выбирает сосед) и при 140 (четыре кубика).
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	s._take(552)
	g._gain_item(0, 552)
	s._take(328)
	g.discards.monster.append(int(g.monsters[1].id))
	g.monsters[1] = {"id": 328, "hp": 2, "dc": 3, "at": 1}
	g.monsters[0].dc = 4
	var hp0: int = int(g.monsters[0].hp)
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3)
	s.ok(0, "roll")
	s.close()
	print("фаза ", g.phase, " resolving ", g.resolving.get("card", -1), " бросает ", g.actor())
	s.roll(1)
	s.ok(g.actor(), "effect_roll")
	s.close()
	print("варианты: ", g._card_choices().map(func(c): return c.label), " выбирает ", g.actor())
	var choices: Array = g._card_choices()
	for i in choices.size():
		if str(choices[i].label).ends_with("3"):
			g.action(g.actor(), "card_choice", {"index": i, "revision": g.revision})
	print("стек: ", g.stack.map(func(e): return [e.kind, e.get("value", "")]))
	for i in 5:
		if g.phase == "priority": s.close()
	print("hp монстра ", hp0, " -> ", g.monsters[0].hp, " журнал ", g.log.slice(-4))
	quit()
