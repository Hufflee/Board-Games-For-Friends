extends SceneTree
## Разовая проверка (09.11): «Повелитель ямы» 836 — отмена атаки в разные моменты.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _report(name: String, s, g) -> void:
	for i in 6:
		if g.phase == "priority": s.close()
	print(name, ": напарники ", g._coop_partners20, " бросает ", g._battle_roller15(), " фаза ", g.phase, " бой ", g.battle, " стек ", g.stack.map(func(e): return e.kind), " resolving ", g.resolving.get("card", -1), " атак ", g.attack_left, " проблемы ", Inv.check(g, true), " может атаковать ", g.clone().action(0, "attack", {"slot": 1}))

func _init() -> void:
	for moment in ["declared", "battle", "roll", "offturn", "coop"]:
		var t := Check.new()
		var s = Batch.new()._game(t, 836)
		var g = s.g
		g.strict_responses28 = true
		if moment == "coop":
			s._take(754)
			g.room = 754
			g._refresh_passive_stats()
		var actor := 0
		if moment == "offturn":
			s._take(16)
			g.items[1].append(g.items[0].pop_back())
			actor = 1
		var slot: int = g.items[actor].size() - 1
		s.ok(0, "attack", {"slot": 0})
		if moment in ["battle", "roll", "offturn", "coop"]:
			s.close()
		if moment in ["roll", "offturn", "coop"]:
			s.roll(2)
			s.ok(0, "roll")
		var ok = g.action(actor, "activate", {"item": slot})
		print(moment, ": активация ", ok, " фаза ", g.phase)
		_report(moment, s, g)
	quit()
