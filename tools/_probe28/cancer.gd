extends SceneTree
## Разовая проверка (07.11): «Рак» 552 — +1 к первому броску за ход.
const Batch := preload("res://tests/fs/core/core_automation_batch12.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	var t := Check.new()
	var s = Batch.new()._game(t, 40)
	var g = s.g
	s._take(552)
	g._gain_item(0, 552)
	print("перед: бросков за ход ", g._turn_die_throws.get(0, 0))
	s.ok(0, "attack", {"slot": 0})
	s.close()
	s.roll(3)
	s.ok(0, "roll")
	var rolls: Array = g.stack.filter(func(e): return str(e.kind) == "roll")
	print("атака: выпало 3, в стеке ", rolls.map(func(e): return e.value), " last_roll ", g.last_roll, " raw ", g._last_raw_die20, " fx ", g.fx28.slice(-2))
	s.close()
	print("второй бросок того же хода:")
	s.roll(3)
	if g.phase == "battle_roll":
		s.ok(0, "roll")
		print("  в стеке ", g.stack.filter(func(e): return str(e.kind) == "roll").map(func(e): return e.value))
	# следующий ход: снова +1?
	g._complete_turn_start()
	print("новый ход: бросков ", g._turn_die_throws.get(0, 0))
	quit()
