extends SceneTree
## Разовая проверка (09.11): 836 отменяет атаку, пока способность монстра 372 ждёт своего броска.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 836)
	var g = s.g
	g.strict_responses28 = true
	s._take(372)
	g.discards.monster.append(int(g.monsters[0].id))
	g.monsters[0] = {"id": 372, "hp": 5, "dc": 6, "at": 1}
	g.hp[0] = 4
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(1)
	s.ok(0, "roll")
	for i in 3:
		if g.phase == "priority" and not g.stack.any(func(e): return e.kind == "effect_roll"):
			s.close()
	print("до отмены: фаза ", g.phase, " res ", g.resolving.get("card", -1), "/", g.resolving.get("automation_context", ""), " стек ", g.stack.map(func(e): return e.kind), " пауз ", g.paused_effects.size())
	if g.phase == "effect":
		s.roll(3)
		s.ok(g.actor(), "effect_roll")
		print("после броска эффекта: фаза ", g.phase, " стек ", g.stack.map(func(e): return e.kind), " пауз ", g.paused_effects.size())
	var ok = g.action(0, "activate", {"item": g.items[0].size() - 1})
	print("активация ", ok)
	for i in 6:
		if g.phase == "priority": s.close()
	print("итог: фаза ", g.phase, " бой ", g.battle, " стек ", g.stack.map(func(e): return e.kind), " res ", g.resolving.get("card", -1), " пауз ", g.paused_effects.size(), " проблемы ", Inv.check(g, true), " действия ", g.clone().action(0, "end"))
	quit()
