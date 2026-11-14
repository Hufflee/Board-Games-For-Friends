extends SceneTree
## Разовая проверка (09.11): Бомба в чужой ход убивает монстра — появляется ли новый.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _init() -> void:
	for moment in ["turn", "battle", "roll"]:
		var t := Check.new()
		var s = Batch.new()._game(t, 40)
		var g = s.g
		s._take(497)
		g.hands[1].append(497)
		g.character_ready[1] = true
		g.monsters[0].hp = 1
		var dead_id: int = int(g.monsters[0].id)
		if moment in ["battle", "roll"]:
			s.ok(0, "attack", {"slot": 0})
			s.close()
		if moment == "roll":
			s.roll(1)
			s.ok(0, "roll")
		print(moment, ": бомба ", g.action(1, "loot", {"card": 497}), " фаза ", g.phase)
		for i in 10:
			if g.phase == "priority":
				s.close()
			elif g.phase == "effect" and not g._card_choices().is_empty():
				var choices: Array = g._card_choices()
				var pick := 0
				for k in choices.size():
					if str(choices[k].arg.get("op", "")) == "monster_damage" and int(choices[k].arg.get("item", -1)) == 0: pick = k
				g.action(g.actor(), "card_choice", {"index": pick, "revision": g.revision})
			else:
				break
		print("   монстры ", g.monsters.map(func(m): return [m.id, m.hp]), " (был ", dead_id, ") слотов ", g.monster_slots, " фаза ", g.phase, " бой ", g.battle, " проблемы ", Inv.check(g, true), " журнал ", g.log.slice(-4))
	quit()
