extends SceneTree
## Cheat Poker: проверка ввода через игровой стол и кадры при 1280×720.
## Запуск: godot --audio-driver Dummy --path . --script res://tests/test_poker_cheat_ui.gd

const Cards := preload("res://games/poker/logic/pk_cheat_cards.gd")

var errors := 0
var checks := 0
var net: Node
var table: Control


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		print("ОШИБКА: ", message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	net = root.get_node("Net")
	net.host_offline("poker")
	net.set_bots(3)
	net.set_setting("pk_mode", "cheat")
	var app: Control = load("res://games/poker/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await process_frame
	check(app.screen.find_child("TargetAuto", true, false) != null, "цель спортрежима доступна в лобби")
	var issue: String = net.start_game()
	check(issue.is_empty(), "запуск из лобби: %s" % issue)
	await process_frame
	table = app.screen
	var game: RefCounted = net.pkr
	for player: Dictionary in game.players:
		player.bot = false
	game.cheat.hands[0] = [0, 3, 5, 7, 11, 10, 27]
	while game.phase == "hand" and game.to_act != 0:
		game.check_call(game.to_act)
	net._push_state()
	await process_frame
	var last := table._cheat_hand.find_child("CheatCard27", true, false) as Control
	check(last.get_global_rect().end.x <= table._action.get_global_rect().position.x, "рука не перекрывает панель ставки")
	while game.phase == "hand":
		game.check_call(game.to_act)
	net._push_state()
	await process_frame
	await process_frame
	var hand: Control = table._cheat_hand
	var card := hand.find_child("CheatCard0", true, false) as Control
	check(card != null and absf((table.size.y - card.position.y) / card.size.y - 0.7) < 0.02, "карта выглядывает на 70%")
	check(card.rotation < 0.0 and hand._hand_cards[-1].rotation > 0.0, "крайние карты наклонены в разные стороны")
	check(hand._hand_cards[1].position.x - card.position.x < card.size.x, "карты лежат внахлёст")
	var rest_y := card.position.y
	var start := card.get_global_rect().position + Vector2(10, 22)
	await _shot("pick")
	_motion(start)
	await create_timer(0.25).timeout
	check(hand._preview.get_child_count() == 0, "быстрое наведение не открывает просмотр")
	check(card.position.y < rest_y and card.z_index > hand._hand_cards[-1].z_index, "при наведении карта поднимается над веером")
	await create_timer(0.35).timeout
	check(hand._preview.get_child_count() == 1, "после 0,5 с карточка открылась в центре")
	await _shot("preview")
	_button(start, true)
	_motion(hand._center)
	await process_frame
	await process_frame
	check(hand._drag.get_child_count() == 1, "зажатая карточка едет за курсором")
	_button(hand._center, false)
	await process_frame
	check(game.cheat.pending.get(0, {}).get("id", -1) == 0, "отпускание в зелёной зоне отправляет закрытую заявку")
	game.cheat.hands[1] = [0]
	game.action(1, "cheat_play", {"id": 0, "args": [-1, -1, -1, -1], "window": game.cheat.window})
	game.tick(10.0)
	net._push_state()
	await process_frame
	check(hand._stage.get_child_count() == 2 and game.cheat.revealed[0].status == "cancelled", "показаны обе отменённые карты")
	await create_timer(0.5).timeout
	await _shot("cancel")
	game.tick(2.0)
	while game.phase == "hand":
		game.check_call(game.to_act)
	net._push_state()
	await process_frame
	var targeted := hand.find_child("CheatCard7", true, false) as Control
	var target_start := targeted.get_global_rect().position + Vector2(10, 22)
	_motion(target_start)
	_button(target_start, true)
	_motion(hand._center)
	await process_frame
	_button(hand._center, false)
	await process_frame
	check(is_instance_valid(hand._target), "после перетаскивания карты с целью появляется выбор")
	if is_instance_valid(hand._target):
		var choice: Array[Node] = hand._target.find_children("*", "OptionButton", true, false)
		check(choice.size() == 1 and choice[0].item_count == 2, "можно выбрать одну из двух своих карт")
		await _shot("target")
		if choice.size() == 1:
			choice[0].select(1)
			var play: Button = hand._target.find_children("*", "Button", true, false).filter(func(item: Button) -> bool: return item.text == "Разыграть")[0]
			var pos := play.get_global_rect().get_center()
			_motion(pos)
			_button(pos, true)
			_button(pos, false)
			await process_frame
			check(game.cheat.pending.get(0, {}).get("args", [-1])[0] == 1, "хост получил выбранную вторую карту")
	game.cheat._effect(game, 0, Cards.GAPPED_STRAIGHT, [-1, -1, -1, -1])
	game.cheat._effect(game, 0, Cards.COLOR_FLUSH, [-1, -1, -1, -1])
	net._push_state()
	await process_frame
	var side_labels: Array = table._side.find_children("*", "Label", true, false)
	check(side_labels.any(func(label: Label) -> bool: return label.text == "Через ступеньку"), "в панели виден активный стрит с пропусками")
	check(side_labels.any(func(label: Label) -> bool: return label.text == "В один цвет"), "в панели виден активный флеш по цвету")
	await _shot("hand_effects")
	net._finish_session()
	app.queue_free()
	await process_frame
	await process_frame
	print("ИТОГ UI: проверок %d, ошибок %d" % [checks, errors])
	quit(1 if errors > 0 else 0)


func _motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(event)


func _button(pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://build/shots/cheat_%s.png" % label)
	check(result == OK, "сохранён кадр %s" % label)
