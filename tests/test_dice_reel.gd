extends SceneTree
## Сравнение общего кубомёта с обычным кубиком на одном результате хоста.
## Запуск: Godot --headless --audio-driver Dummy --script res://tests/test_dice_reel.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var prefs := root.get_node("Prefs")
	var die_script: GDScript = load("res://hub/toss_die.gd")
	var classic: Control = die_script.new()
	classic.use_player_style = false
	root.add_child(classic)
	classic.max_face = 8
	classic.set_process(false)
	prefs.dice_style = "reel"
	var die: Control = die_script.new()
	root.add_child(die)
	die.max_face = 8
	die.set_process(false)
	die.home = Vector2(240, 200)
	die.wait_for_roll()
	die.draggable = true
	var reel: Control = die._reel
	reel.set_process(false)
	var requests := [0]
	die.thrown.connect(func(_velocity: Vector2): requests[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(24, 30)
	_check(reel.active, "Рычаг подсвечен в ожидании собственного броска")
	reel._gui_input(click)
	_check(requests[0] == 0, "Окошко барабана не отправляет бросок")
	die.set_reel_prompt(true)
	reel._present(1.0)
	var art_center := Vector2(33, 46)
	var screen_center := root.get_visible_rect().get_center()
	_check(reel.scale.is_equal_approx(Vector2(3, 3)), "Обязательный бросок увеличивает кубомёт втрое")
	_check((reel.get_global_transform() * art_center).distance_to(screen_center) < 1.0, "Обязательный бросок выводит кубомёт в центр")
	click.position = Vector2(56, 35)
	reel._gui_input(click)
	reel._gui_input(click)
	_check(requests[0] == 1 and die.awaits_result() and not reel.active, "Рычаг отправляет ровно один запрос")
	for frame in 90:
		die._process(1.0 / 60.0)
	_check(die.awaits_result(), "При задержке хоста барабан продолжает прокрутку")
	die.set_result(8)
	classic.throw(Vector2(300, 0), 8)
	for frame in 160:
		die._process(1.0 / 60.0)
		classic._process(1.0 / 60.0)
	_check(die.state == "settled" and reel._face == 8, "Кубомёт останавливается на восьмёрке")
	_check(reel._face == classic._die.value, "Два оформления показывают одну грань хоста")
	die.set_reel_prompt(false)
	reel._present(1.0)
	_check(reel._focus > 0.99, "После изменения фазы результат остаётся в центре")
	die.set_reel_prompt(true)
	die._stop_anim()
	die._back_home()
	die.wait_for_roll()
	reel._present(1.0)
	_check(reel._focus > 0.99 and reel.active == die.draggable, "Следующий обязательный бросок начинается без возврата")
	die.set_reel_prompt(false)
	reel._present(1.0)
	_check(reel._focus == 0.0 and not reel.is_set_as_top_level(), "Когда серия завершилась, кубомёт возвращается домой")

	die.throw(Vector2.ZERO, 3)
	for frame in 175:
		die._process(1.0 / 60.0)
	_check(die.state == "flying", "Удалённый бросок ещё крутится перед трёхсекундной отметкой")
	for frame in 10:
		die._process(1.0 / 60.0)
	_check(die.state == "settled" and reel._face == 3, "Удалённый бросок заканчивается примерно через три секунды")
	die.throw(Vector2.ZERO)
	var stalls := [0]
	die.stalled.connect(func(): stalls[0] += 1)
	for frame in 370:
		die._process(1.0 / 60.0)
	_check(stalls[0] == 1 and die.state == "returning", "Без ответа можно снова запросить бросок")

	var king_script: GDScript = load("res://games/king_of_12/ui/die3d.gd")
	var king: Control = king_script.new()
	root.add_child(king)
	king.set_process(false)
	king.throw(Vector2.ZERO, 12)
	for frame in 185:
		king._process(1.0 / 60.0)
	_check(king.face == 12 and king._reel._face == 12, "Дюжина короля показывает двузначную грань")
	for node in [classic, die, king]:
		node.queue_free()
	# Dummy не выводит звук, но проигрыватели завершают короткие дорожки по времени.
	await create_timer(1.0).timeout
	print("Кубомёт: %d проверок, ошибок %d" % [_checks, _failures])
	quit(int(_failures > 0))
