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
	g.roll_source = func() -> int: return rng.randi_range(1, 6)
	var history: Array = []
	for step in 400:
		var choice: Dictionary = Fuzz._pick(g, rng)
		if choice.is_empty():
			print("ЗАВИСАНИЕ"); break
		var before := "phase %s res %s/%s ctx %s stack %s" % [g.phase, str(g.resolving.get("kind", "")), str(g.resolving.get("card", -1)), str(g.resolving.get("automation_context", "")), str(g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]))]
		var ok: bool = Fuzz.perform(g, int(choice.seat), str(choice.kind), choice.get("arg"))
		if not ok:
			continue
		history.append("%s %s %s | до: %s" % [choice.seat, choice.kind, str(choice.get("arg")), before])
		var found: Array = Inv.check(g, false)
		if not found.is_empty():
			for line in history.slice(-16): print("  ", line)
			print("ПРОБЛЕМА: ", found)
			print("после: phase ", g.phase, " res ", g.resolving, " stack ", g.stack.map(func(e): return [e.kind, e.get("card", e.get("value", ""))]), " after ", g._after_stack, " paused ", g.paused_effects.size())
			print("журнал: ", g.log.slice(-12))
			break
	quit()
