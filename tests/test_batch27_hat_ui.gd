extends SceneTree
## Узкая релизная проверка NH hardmode и общего 2D-flip. Dummy, отдельный APPDATA.
var checks := 0
var failures := 0
var net: Node
var shown := true
var commits := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ПРОВАЛ: ", message)

func frames() -> void:
	for i: int in 3:
		await process_frame

func snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/shots/batch27-hat/" + name + ".png") == OK, "Сохранён кадр " + name)

func mouse(at: Vector2, pressed: int = -1) -> void:
	Input.warp_mouse(at)
	if pressed < 0:
		var event := InputEventMouseMotion.new()
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	await frames()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots/batch27-hat"))
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.set_process(false)
	var helper: Script = load("res://hub/card_flip.gd")
	var card := ColorRect.new()
	card.position = Vector2(40, 80)
	card.size = Vector2(120, 150)
	card.color = Color("ae4c80")
	root.add_child(card)
	var flip: Node = helper.attach(card, func(up: bool): shown = up, true, true)
	flip.flipped.connect(func(_up: bool): commits += 1)
	flip.flip_to(false, 0.12)
	await create_timer(0.2).timeout
	check(not shown and not flip.busy and commits == 1, "Автозакрытие завершилось без жеста")
	check(card.position == Vector2(40, 80) and card.scale == Vector2.ONE, "После переворота восстановлены позиция и масштаб")
	flip.flip_to(false)
	check(not flip.busy and commits == 1, "Повтор той же стороны не запускает вторую анимацию")
	flip.flip_to(true, 0.12)
	await create_timer(0.2).timeout
	check(shown and commits == 2, "Автооткрытие завершилось")
	await mouse(Vector2(158, 120))
	await mouse(Vector2(158, 120), 1)
	check(flip.dragging, "Настоящим вводом схвачен край карты")
	await mouse(Vector2(70, 120))
	await mouse(Vector2(70, 120), 0)
	await create_timer(0.35).timeout
	check(not shown and not flip.busy and commits == 3, "Достаточное вытягивание края завершает переворот")
	flip.flip_to(true, 1.0)
	flip.cancel()
	check(not shown and not flip.busy and card.scale == Vector2.ONE, "Отмена восстанавливает текущую сторону и геометрию")
	card.queue_free()
	await frames()
	var public_card: Control = load("res://games/not_a_hat/ui/nh_card.gd").new(0, 1)
	root.add_child(public_card)
	public_card.set_card(1, 1, true)
	check(public_card.gift == 1, "Другое уже открытое лицо обновляется без лишнего переворота")
	public_card.set_card(-1, 1, true)
	await create_timer(0.6).timeout
	check(public_card.gift == -1, "Открытая карта затем автоматически закрывается")
	public_card.queue_free()
	await frames()
	for count: int in [4, 8]:
		var rules: RefCounted = load("res://games/not_a_hat/logic/nh_rules.gd").new()
		var players: Array = []
		for i: int in count:
			players.append({"name": "Игрок" + str(i), "bot": false, "color": i})
		rules.new_game(players, 2, 271027)
		net.mode = "offline"
		net.party_game = "not_a_hat"
		net.in_game = true
		net.game_id = "hat-ui-" + str(count)
		net.view = rules.get_view(0, false)
		var app: Control = load("res://games/not_a_hat/ui/main.tscn").instantiate()
		root.add_child(app)
		current_scene = app
		await frames()
		var table: Node = app.screen
		var cards: Array = table._hand_cards[0]
		check(cards.size() == 2 and cards[1].global_position.x > cards[0].global_position.x + cards[0].size.x * cards[0].scale.x, "Две карты рядом без перекрытия: " + str(count))
		await snap("memorize-" + str(count))
		rules.start_play()
		net.view = rules.get_view(0, false)
		net.state_changed.emit(net.view)
		await create_timer(0.6).timeout
		for seat: int in table._hand_cards:
			for item: Control in table._hand_cards[seat]:
				check(item.gift == -1, "После запоминания карта закрылась автоматически")
		rules.give(rules.giver, 0)
		net.view = rules.get_view(0, false)
		net.state_changed.emit(net.view)
		await create_timer(0.5).timeout
		var receiver: int = rules.receiver
		check(table._hand_cards[receiver][0].glow > 0, "Получателю выделен передариваемый левый подарок")
		await snap("respond-" + str(count))
		rules.respond(receiver, true)
		net.view = rules.get_view(0, false)
		net.state_changed.emit(net.view)
		await frames()
		check(table._exchange_cards.size() == 3, "При принятии автоматически двигаются входящая, исходящая и оставшаяся карты")
		var epoch: int = table._exchange_epoch
		net.state_changed.emit(net.view.duplicate(true))
		check(table._exchange_epoch == epoch, "Повторный view не запускает обмен заново")
		await snap("exchange-" + str(count))
		await create_timer(0.65).timeout
		check(table._exchange_cards.is_empty() and table._moving.visible, "Обмен завершился и оставил новый исходящий подарок")
		for item: Control in table._hand_cards[receiver]:
			check(item.visible and item.gift == -1, "Итоговый слот виден и не раскрывает скрытое лицо")
		await snap("after-" + str(count))
		rules.give(rules.giver, 0)
		net.view = rules.get_view(0, false)
		net.state_changed.emit(net.view)
		rules.respond(rules.receiver, false)
		net.view = rules.get_view(0, false)
		net.state_changed.emit(net.view)
		await create_timer(0.6).timeout
		check(table._moving.gift == rules.card.g, "Отказ автоматически открыл только публично вскрытый подарок")
		app.queue_free()
		current_scene = null
		await frames()
	net.mode = ""
	net.in_game = false
	net.view = {}
	print("NH И FLIP: проверок=", checks, " ошибок=", failures)
	await root.get_node("Sfx").request_quit(1 if failures else 0)
