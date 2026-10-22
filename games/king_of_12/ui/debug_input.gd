extends Node
## Отладка (--input-test): имитирует мышь — бросок кубика и перетаскивание карт — и проверяет результат.

var app: Node
var shots_dir := ""
var _last := Vector2.ZERO
var _ok := 0
var _fail := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Net.host_offline()
	Net.bot_delay = 2.5  # бот ходит не сразу — успеем забрать карту обратно
	Net.set_bots(1)
	Net.start_game()
	await _wait(1.0)
	var t: Node = app.screen
	var die: Control = t._dice[t._me]
	var c := die.get_global_rect().get_center()
	await _drag(c, c + Vector2(-260, -200), 6, 0.012)
	await _wait(0.2)
	_check(Net.rules.rolled[0], "кубик брошен перетаскиванием")
	await _shot("1_throw")
	for i in 40:
		if Net.rules.phase == "select":
			break
		await _wait(0.25)
	await _wait(0.3)
	_check(Net.rules.phase == "select", "после бросков — выбор карт (фаза %s)" % Net.rules.phase)
	await _shot("2_select")

	var card: Control = t._hand.values()[2]
	var cc := card.get_global_rect().get_center()
	await _drag(cc, cc + Vector2(30, -330), 12, 0.02)
	await _wait(0.6)
	_check(Net.rules.selected[0] != "", "карта сыграна перетаскиванием (%s)" % Net.rules.selected[0])
	await _shot("3_played")

	if Net.rules.phase == "select":
		var slot: Control = t._slots[t._me]
		var sc := slot.get_global_rect().get_center()
		await _drag(sc, Vector2(sc.x, t.size.y - 60), 12, 0.02)
		await _wait(0.6)
		_check(Net.rules.selected[0] == "", "карта утащена обратно в руку")
		_check(t._hand.size() == Net.rules.hands[0].size(), "в руке снова %d карт" % t._hand.size())
		await _shot("4_back")
		var card2: Control = t._hand.values()[0]
		var c2 := card2.get_global_rect().get_center()
		_mouse(c2, true, false)
		_mouse(c2, false)
		await _wait(0.05)
		_mouse(c2, true, true)
		_mouse(c2, false)
		await _wait(0.6)
		_check(Net.rules.selected[0] != "" or Net.rules.phase != "select", "двойной клик играет карту")
		await _shot("4b_dblclick")
	Net.bot_delay = 0.3
	await _wait(2.5)
	_check(Net.rules.phase in ["trick_result", "sorcerer"], "розыгрыш вскрыт (фаза %s)" % Net.rules.phase)
	await _shot("5_reveal")
	print("SOUNDS: %s (driver %s)" % [Sfx.played, AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?"])
	print("INPUT TEST: ok=%d fail=%d" % [_ok, _fail])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
	print(("OK   " if cond else "FAIL ") + msg)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if shots_dir != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func _drag(from: Vector2, to: Vector2, steps: int, dt: float) -> void:
	_mouse(from, null)
	_mouse(from, true)
	await _wait(dt)
	for i in steps:
		_mouse(from.lerp(to, float(i + 1) / steps), null)
		await _wait(dt)
	_mouse(to, false)


func _mouse(pos: Vector2, pressed, dbl: bool = false) -> void:
	var ev: InputEventMouse
	if pressed == null:
		var m := InputEventMouseMotion.new()
		m.relative = pos - _last
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		ev = m
	else:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.double_click = dbl
		ev = b
	ev.position = pos
	ev.global_position = pos
	_last = pos
	Input.parse_input_event(ev)
