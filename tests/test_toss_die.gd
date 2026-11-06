extends SceneTree
## Регресс TossDie (06.11): новый бросок посреди показа прошлого, результат до броска, бросок без ответа хоста.
## Запуск: godot --headless --audio-driver Dummy --path . --script res://tests/test_toss_die.gd

var fails := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("ПРОВАЛ: ", msg)


func _initialize() -> void:
	_run.call_deferred()


## Прогоняем кадры вручную: _process кубика + твины дерева.
func _frames(die: Control, seconds: float) -> void:
	var step := 1.0 / 60.0
	var t := 0.0
	while t < seconds:
		die._process(step)
		await process_frame
		t += step


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	# Скрипт кубика тянет Sfx — грузим после регистрации autoload'ов.
	var Die: GDScript = load("res://hub/toss_die.gd")
	var die: Control = Die.new()
	root.add_child(die)
	die.home = Vector2(400, 300)
	die.area = Rect2(0, 0, 800, 600)
	var finished := [0]
	var stalled := [0]
	die.finished.connect(func(): finished[0] += 1)
	die.stalled.connect(func(): stalled[0] += 1)

	# 1. Обычный чужой бросок: лёг на нужную грань и вернулся.
	die.throw(Vector2(900, 0), 4)
	while die.state == "flying":
		await _frames(die, 0.2)
	check(die.state == "settled", "кубик остановился (%s)" % die.state)
	check(int(die._die.value) == 4, "выпало 4")

	# 2. Новый бросок во время показа прошлого: старый твин не должен вернуть кубик домой посреди полёта.
	die.throw(Vector2(-900, 200), 2)
	await _wait(1.3)  # старый твин успел бы выставить returning
	check(die.state in ["flying", "settled"], "новый бросок не перебит старым показом (%s)" % die.state)
	while die.state == "flying":
		await _frames(die, 0.2)
	check(int(die._die.value) == 2, "второй бросок показал свою грань 2 (%d)" % int(die._die.value))
	await _wait(2.0)
	check(die.state == "idle" and finished[0] >= 1, "вернулся на место (%s)" % die.state)

	# 3. wait_for_roll посреди показа: кубик остаётся «ждущим», а не idle.
	die.throw(Vector2(500, 0), 5)
	while die.state == "flying":
		await _frames(die, 0.2)
	die.wait_for_roll()
	await _wait(1.8)
	check(die.state == "waiting", "после wait_for_roll кубик ждёт броска (%s)" % die.state)

	# 4. Результат пришёл до броска: throw(vel, 0) его не затирает.
	die.set_result(3)
	die.throw(Vector2(700, 100), 0)
	var guard := 0
	while die.state == "flying" and guard < 60:
		await _frames(die, 0.2)
		guard += 1
	check(die.state == "settled" and int(die._die.value) == 3, "ранний результат 3 показан (%s, %d)" % [die.state, int(die._die.value)])
	await _wait(2.0)

	# 5. Хост не ответил: кубик не крутится вечно, а возвращается и сообщает stalled.
	die.throw(Vector2(600, 0), 0)
	guard = 0
	while die.state == "flying" and guard < 100:
		await _frames(die, 0.2)
		guard += 1
	check(stalled[0] == 1, "без результата — сигнал stalled")
	check(die.state in ["returning", "idle"], "без результата кубик возвращается (%s)" % die.state)
	await _wait(1.0)
	check(die.state == "idle", "и становится свободным (%s)" % die.state)

	print("TossDie: %d проверок, провалов %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
