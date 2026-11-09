extends SceneTree
## Разовая отладка фазза (06.11): повторить партию run() с тем же сидом и показать состояние в момент сбоя.
const Fuzz := preload("res://tests/fs/fs_fuzz.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _init() -> void:
	var game_seed := int(OS.get_environment("SEED"))
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed * 7919 + 13
	var config := {"players": [2, 2, 3, 4, 4, 6, 8][rng.randi_range(0, 6)], "dlc": rng.randf() < 0.5, "seed": game_seed}
	var s = Fuzz._start(config)
	var g = s.g
	if OS.get_environment("NOREFILL") == "1":
		g.refill_calm28 = false
	g.roll_source = func() -> int: return rng.randi_range(1, 6)
	var history: Array = []
	for step in 400:
		var choice: Dictionary = Fuzz._pick(g, rng)
		if choice.is_empty():
			for line in history.slice(-8): print("  ", line)
			print("ЗАВИСАНИЕ фаза ", g.phase, " res ", g.resolving.get("card", -1), "/", g.resolving.get("automation_context", ""), " стек ", g.stack.map(func(e): return [e.kind, e.get("card", "")]), " ходит ", g.current, " actor ", g.actor(), " монстры ", g.monsters.map(func(m): return [m.id, m.hp]), " слотов ", g.monster_slots, " после ", g._after_stack, " выборы ", g._card_choices().size(), " журнал ", g.log.slice(-6))
			break
		var before := "phase %s res %s/%s ctx %s stack %s" % [g.phase, str(g.resolving.get("kind", "")), str(g.resolving.get("card", -1)), str(g.resolving.get("automation_context", "")), str(g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]))] + " мон " + str(g.monsters.map(func(m): return [m.id, m.hp, m.get("death_pending", false)])) + " пауз " + str(g.paused_effects.map(func(p): return [p.effect.get("kind", ""), p.effect.get("card", -1)]))
		var ok: bool = Fuzz.perform(g, int(choice.seat), str(choice.kind), choice.get("arg"))
		if not ok:
			continue
		history.append("%s %s %s | до: %s" % [choice.seat, choice.kind, str(choice.get("arg")), before])
		var found: Array = Inv.check(g, false)
		if not found.is_empty():
			for line in history.slice(-16): print("  ", line)
			print("ПРОБЛЕМА: ", found)
			print("монстры после: ", g.monsters.map(func(m): return [m.id, m.hp]), " сброс монстров ", g.discards.monster.slice(-4), " души ", g.soul_cards.map(func(r): return r.map(func(c): return c.id)))
			print("после: phase ", g.phase, " res ", g.resolving, " stack ", g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]), " after ", g._after_stack, " paused ", g.paused_effects.size())
			print("журнал: ", "
".join(g.log.slice(-16)))
			break
	quit()
