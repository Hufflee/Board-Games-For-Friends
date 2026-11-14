extends SceneTree
## Разовая проверка (07.11): растёт ли ревизия хоста без действий игроков (с проклятием 729 и без).
const Scenario := preload("res://tests/fs/fs_scenario.gd")
const Check := preload("res://tests/fs/fs_check.gd")
func _init() -> void:
	for curse in [false, true]:
		var s := Scenario.new(Check.new()).players(3).dlc().current(0).build()
		var g = s.g
		if curse:
			s._take(729)
			g.curses[1].append(729)
			g.hands[1].append_array([480, 481, 482])
		var bumps := 0
		for i in 200:
			var before: int = g.revision
			g.tick(0.05)
			if g.revision != before:
				bumps += 1
		print("ПРОКЛЯТИЕ ", curse, ": ревизия менялась ", bumps, " раз из 200, фаза ", g.phase, " стек ", g.stack.map(func(e): return e.kind))
		# то же в чужой ход
		g.current = 1
		g.phase = "turn"
		bumps = 0
		for i in 200:
			var before: int = g.revision
			g.tick(0.05)
			if g.revision != before:
				bumps += 1
		print("   ход места 1: ", bumps, " раз, фаза ", g.phase)
	quit()
