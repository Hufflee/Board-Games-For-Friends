extends SceneTree
## Замер генерации слоёв сапёра без угадывания: сколько мс и удаётся ли (по слоям 0–10).
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tools/_mg_probe/mines_gen_bench.gd

const Mines := preload("res://hub/minigames/logic/mg_mines.gd")


func _init() -> void:
	for index in [0, 2, 4, 6, 8, 10]:
		var ok := 0
		var worst := 0
		for seed_value in 5:
			var state := Mines.new_state({"mode": "deep", "seed": seed_value})
			var started := Time.get_ticks_msec()
			Mines._generate(state, index, 120)
			worst = maxi(worst, Time.get_ticks_msec() - started)
			if Mines.solvable(Mines.layer(state, index).mine, 120):
				ok += 1
		print("слой %d (мин %d): решаемых %d/5, худшее %d мс" % [index, Mines.mines_for(index, "deep"), ok, worst])
	quit()
