extends SceneTree
## Four Souls, регресс 06.11: «потерянная» смерть. Игрок с 0 здоровья в очереди смерти, а партия ушла в бой/ход —
## штраф не применялся, панель была видна только 5 с окна ответов. Теперь tick снова объявляет смерть,
## а одно нажатие «Принять штраф» доводит до штрафа.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_fs_death_watchdog.gd

var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ПРОВАЛ: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _lost_death(scenario: GDScript, phase: String):
	var s = scenario.new().players(3).current(0).hand(1, [478]).build()
	var g = s.g
	g.hp[1] = 0
	g._death_queue = [1]
	g._death_resume = "effect"
	g._after_stack = phase
	g.phase = phase
	g.stack.clear()
	return g


func _run() -> void:
	var Scenario: GDScript = load("res://tests/fs/fs_scenario.gd")
	var Legal: GDScript = load("res://games/four_souls/logic/fs_legal.gd")

	# 1. Смерть потерялась в обычном ходе: tick объявляет её заново, после окна — фаза штрафа без таймера.
	var g = _lost_death(Scenario, "turn")
	check(g.tick(0.1), "tick заметил потерянную смерть")
	check(g.phase == "priority" and g.stack.any(func(e): return e.kind == "death"), "смерть снова в стеке (%s)" % g.phase)
	for i in 30:
		g.tick(0.25)
	check(g.phase == "death" and g.actor() == 1, "после окна ответов — фаза штрафа у погибшего (%s)" % g.phase)
	for i in 80:
		g.tick(0.25)
	check(g.phase == "death", "фаза штрафа не закрывается по 5-секундному окну (%s)" % g.phase)
	check(g.action(1, "death", Legal._death_choice(g, 1)), "штраф принят")
	check(bool(g.dead[1]) and g._death_queue.is_empty(), "игрок мёртв, очередь пуста")
	check(g.phase == "turn", "ход продолжается (%s)" % g.phase)

	# 2. Потерялась посреди боя, погибший не ходит: одно нажатие в окне ответов доводит до штрафа.
	g = _lost_death(Scenario, "battle_roll")
	g.tick(0.1)
	check(g.phase == "priority", "смерть объявлена в бою (%s)" % g.phase)
	check(g.action(1, "death", Legal._death_choice(g, 1)), "одно нажатие «Принять штраф»")
	check(bool(g.dead[1]), "штраф применён с первого нажатия")
	check(g.phase == "battle_roll", "бой продолжается (%s)" % g.phase)

	# 3. Здоровье уже вернули — смерть из очереди просто убирается.
	g = _lost_death(Scenario, "turn")
	g.hp[1] = 2
	g.tick(0.1)
	check(g._death_queue.is_empty() and not bool(g.dead[1]) and g.phase == "turn", "спасённый игрок не получает штраф")

	print("FS потерянная смерть: %d проверок, провалов %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
