extends Control
## Служебная сцена: новые мини-игры в окне «Общение» (4 в ряд, шарики, звёздочки, сапёр) — снимки в build/shots/mg_*.png.
## Без пати: комнаты считаются здесь же, соседи по комнате добавлены вручную.
## Проверяет, что нажатие по звёздочке засчитано и не нажимает кнопку под ней.
## Запуск: APPDATA=<пустая папка> godot --audio-driver Dummy --resolution 1280x720 --path . res://tools/_mg_probe/mg_probe.tscn

const Balls := preload("res://hub/minigames/logic/mg_balls.gd")
const Stars := preload("res://hub/minigames/logic/mg_stars.gd")

var _out := ""
var _fails := 0


func _ready() -> void:
	_out = ProjectSettings.globalize_path("res://build/shots/")
	DirAccess.make_dir_recursive_absolute(_out)
	var bg := ColorRect.new()
	bg.color = Color("3f4a5c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + name + ".png")
	print("SHOT ", name)


func _click(at: Vector2, pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	button.global_position = at
	Input.parse_input_event(button)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	Net.host_offline("")
	Net.my_name = "Я"
	var panel: Control = Net.chat.panel()
	await _wait(0.6)
	await _key(KEY_X)
	await _wait(0.3)
	var mg: Node = Net.minigames
	await _shot("mg_lobby")
	# 4 в ряд за обоих
	mg.start_local("connect4")
	var id: String = mg.current
	for col: int in [3, 3, 4, 4, 5, 5]:
		mg.move(id, {"col": col})
	await _wait(0.6)
	await _shot("mg_connect4")
	for col: int in [6]:
		mg.move(id, {"col": col})
	await _wait(0.6)
	var state: Dictionary = mg.sessions[id].state
	_check(bool(state.over) and int(state.winner) == 0, "4 в ряд: красные собрали четвёрку")
	await _shot("mg_connect4_win")
	# шарики: я и двое соседей
	mg.join_room("balls")
	var rng := RandomNumberGenerator.new()
	var balls_state: Dictionary = mg._rooms.balls.state
	Balls.join(balls_state, 2, "Костя", 3, rng)
	Balls.join(balls_state, 3, "Юля", 5, rng)
	Balls.steer(balls_state, 2, Vector2(-0.3, 0.2), true)
	Balls.steer(balls_state, 3, Vector2(0.4, -0.3), true)
	balls_state.balls[2].score = 3
	balls_state.balls[3].score = 1
	balls_state.feed = ["Костя вытолкнул(а) Юля"]
	balls_state.seq = int(balls_state.seq) + 1
	await _wait(1.5)
	var list: Array = mg.sessions[mg.room_id("balls")].state.get("list", [])
	_check(list.size() == 3, "Шарики: в комнате трое")
	await _shot("mg_balls")
	# «мой ход» в основной игре: заслонка «Ваш ход» поверх мини-игр
	mg.probe_blocked = true
	await _wait(0.3)
	_check(panel.get("_turn_lock").visible, "Ваш ход: заслонка видна")
	await _shot("mg_turn_lock")
	mg.probe_blocked = false
	await _wait(0.2)
	# звёздочки: кнопка-приманка под звездой не должна нажаться
	var bait := Button.new()
	bait.text = "Не нажимать"
	bait.size = Vector2(160, 60)
	bait.position = Vector2(560, 300)
	var bait_presses := [0]
	bait.pressed.connect(func(): bait_presses[0] += 1)
	add_child(bait)
	mg.join_room("stars")
	var stars_state: Dictionary = mg._rooms.stars.state
	Stars.join(stars_state, 2, "Костя", 3)
	Stars.join(stars_state, 3, "Юля", 5)
	stars_state.players[2].score = 4
	stars_state.players[3].score = 2
	stars_state.next = 0.0
	await _wait(0.3)
	var star: Dictionary = stars_state.star
	_check(not star.is_empty(), "Звёздочки: звезда появилась")
	var view := get_viewport().get_visible_rect().size
	var target := bait.get_global_rect().get_center()
	star.x = target.x / view.x
	star.y = target.y / view.y
	star.until = float(stars_state.time) + 30.0
	mg._room_push("stars")
	await _wait(0.4)
	await _shot("mg_stars")
	# щелчок у края звезды (за рисунком, но в хитбоксе)
	var edge: float = mg._overlay.RADIUS * mg._overlay.call("_scale") * 1.2
	await _click(target + Vector2(edge, 0), true)
	await _click(target + Vector2(edge, 0), false)
	await _wait(0.2)
	var mine_score := int(stars_state.players[1].score) if stars_state.players.has(1) else -1
	_check(mine_score == 1, "Звёздочки: звезда поймана щелчком чуть за рисунком (очков %d)" % mine_score)
	_check(bait_presses[0] == 0, "Звёздочки: кнопка под звездой не нажалась")
	await _click(target, true)
	await _click(target, false)
	_check(bait_presses[0] == 1, "Звёздочки: без звезды кнопка нажимается")
	bait.queue_free()
	await _wait(0.2)
	await _shot("mg_stars_after")
	# сапёр: бесконечный, несколько открытий
	mg.start_local("mines", {"mode": "deep"})
	id = mg.current
	var mines_rules: GDScript = mg.RULES.mines
	mg.move(id, {"open": 8 * 16 + 8})
	var deep_state: Dictionary = mg.sessions[id].state
	for i in 40:
		if bool(deep_state.over):
			break
		# открываем видимые безопасные клетки нижних слоёв, чтобы появились разные цвета
		for sq in 256:
			var d: int = mines_rules.depth_at(deep_state, sq)
			var lay: Dictionary = mines_rules.layer(deep_state, d)
			if d >= 1 and int(lay.open[sq]) == 0 and (not bool(lay.ready) or int(lay.mine[sq]) == 0) and int(lay.flag[sq]) == 0:
				mg.move(id, {"open": sq})
				break
	var seen_deeper := false
	for sq in 256:
		seen_deeper = seen_deeper or mines_rules.depth_at(deep_state, sq) >= 1
	_check(seen_deeper and int(deep_state.depth) == 1, "Сапёр∞: виден второй слой, но глубина 1 — первый слой не пройден")
	await _wait(0.3)
	await _shot("mg_mines_deep")
	mg.start_local("mines", {"mode": "classic"})
	id = mg.current
	mg.move(id, {"open": 0})
	mg.move(id, {"flag": 255})
	await _wait(0.3)
	await _shot("mg_mines")
	# секундомер: идёт с первого хода, в мой ход — пауза и «Ваш ход», после — «Продолжить?» до нажатия
	var mines_state: Dictionary = mg.sessions[id].state
	await _wait(1.2)
	_check(float(mines_state.elapsed) > 1.0, "Сапёр: секундомер идёт (%.1f с)" % float(mines_state.elapsed))
	mg.probe_blocked = true
	await _wait(0.2)
	var frozen := float(mines_state.elapsed)
	await _wait(0.6)
	var lock: Control = panel.get("_turn_lock")
	var big := lock.find_child("Big", true, false) as Label
	_check(is_equal_approx(float(mines_state.elapsed), frozen) and lock.visible and big.text == "Ваш ход", "Сапёр: мой ход — секундомер стоит, надпись «Ваш ход»")
	await _shot("mg_mines_turn")
	mg.probe_blocked = false
	await _wait(0.6)
	_check(is_equal_approx(float(mines_state.elapsed), frozen) and lock.visible and big.text == "Продолжить?", "Сапёр: ход закончился — «Продолжить?», секундомер ещё стоит")
	await _shot("mg_mines_continue")
	var spot := lock.get_global_rect().get_center()
	await _click(spot, true)
	await _click(spot, false)
	await _wait(0.6)
	_check(not lock.visible and float(mines_state.elapsed) > frozen + 0.3, "Сапёр: нажатие по панели — сапёр продолжился")
	# победа — рекорд
	var classic_lay: Dictionary = mg.RULES.mines.layer(mines_state, 0)
	if int(classic_lay.flag[255]) == 1:
		mg.move(id, {"flag": 255})
	for sq in 256:
		if int(classic_lay.mine[sq]) == 0 and int(classic_lay.open[sq]) == 0 and not bool(mines_state.over):
			mg.move(id, {"open": sq})
	_check(int(mines_state.winner) == 0 and bool(mines_state.get("record", false)) and mg.best_time(mg.BEST_TIME_KEY) > 0.0, "Сапёр: победа — первый результат стал рекордом и сохранён")
	await _wait(0.3)
	await _shot("mg_mines_win")
	print("ПРОБА: ошибок %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
