extends SceneTree
## Разовая проверка (09.11): на место убитого монстра выходит событие-сундук — заполняется ли слот потом.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
const Inv := preload("res://games/four_souls/logic/fs_invariants.gd")
func _settle(s, g) -> void:
	for i in 14:
		if g.phase == "priority":
			s.close()
		elif g.phase == "effect" and g.get_view(g.actor()).get("card_roll_wait", false):
			s.roll(3)
			g.action(g.actor(), "effect_roll")
		elif g.phase == "effect" and not g._card_choices().is_empty():
			g.action(g.actor(), "card_choice", {"index": 0, "revision": g.revision})
		elif g.phase == "effect" and g.resolving.get("requires_reward_roll", false):
			s.roll(3)
			g.action(g.actor(), "effect_roll")
		else:
			break

func _init() -> void:
	for chest in [701, 702, 699, 713, 719]:
		for strict in [false, true]:
			var t := Check.new()
			var s = Batch.new()._game(t, 40)
			var g = s.g
			g.strict_responses28 = strict
			s._take(chest)
			g.decks.monster.append(chest)
			g.monsters[0].hp = 1
			s.ok(0, "attack", {"slot": 0})
			s.close()
			s.roll(6)
			s.ok(0, "roll")
			_settle(s, g)
			print(chest, " строго ", strict, ": монстры ", g.monsters.map(func(m): return m.id), " фаза ", g.phase, " res ", g.resolving.get("card", -1), " сброс событий ", chest in g.discards.monster, " проблемы ", Inv.check(g, true))
	quit()
