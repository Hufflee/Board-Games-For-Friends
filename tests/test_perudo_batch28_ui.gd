extends SceneTree
## UI настоящей мышью и штатный Net.dispatch с транспортом-mock без сокетов.
## --headless --audio-driver Dummy --path . --script res://tests/test_perudo_batch28_ui.gd
var checks := 0
var errors := 0
var net: Node
var app: Control
var table: Control
var model: PerudoRules

func _init() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(text)

func frames(count: int = 5) -> void:
	for i in count:
		await process_frame

func make() -> PerudoRules:
	var r := PerudoRules.new()
	r.new_game([{"name": "А"}, {"name": "Б"}, {"name": "В"}], 5, true, 28)
	r.begin()
	for seat in 3:
		r.shake(seat)
	r.turn = 0
	return r

func click(control: Control) -> void:
	if control == null:
		check(false, "Цель клика существует")
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func apply_view(seat: int = 0, spectator: bool = false, paused: bool = false) -> void:
	var view := model.get_view(seat)
	view["game_id"] = "ui-fixture"
	view["game_paused"] = paused
	view["spectator"] = spectator
	view["auto_in"] = 0
	table._apply(view)
	await frames()

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/shots/batch28_perudo")
	root.get_texture().get_image().save_png("res://build/shots/batch28_perudo/%s.png" % name)

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	net = root.get_node("Net")
	net.host_offline("perudo")
	net.set_bots(2)
	net.start_game()
	net.set_process(false)
	net.send_action("seat_begin")
	for seat in 3:
		net.perudo.shake(seat)
	net.perudo.turn = 0
	net._push_state()
	app = load("res://games/perudo/ui/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(12)
	table = app.screen
	model = make()
	await apply_view()
	check(table._qty == 1 and table._face == 2, "Новый раунд начинаетколичество1, неединицы")
	var ones := table.find_child("BidFace1", true, false) as Button
	check(ones != null and ones.disabled, "Единицы первымходом невыбираются")
	table._face = 4
	table._qty = 9
	table._update_panel()
	model.round_no += 1
	await apply_view()
	check(table._qty == 1 and table._face == 4, "Новый раунд сбрасываеттолькоqty, сохраняетface4")
	table._qty = 4
	await apply_view()
	check(table._qty == 4, "Повторныйview того жераунда не сбрасываетвыбор")
	model.turn = 1
	model.place_bid(1, 5, 4)
	model.turn = 0
	await apply_view()
	table._face = 4
	table._qty = 8
	table._update_panel()
	table._layout()
	await frames()
	await click(table.find_child("BidFace1", true, false))
	check(table._face == 1 and table._qty == 3, "Выборединиц мышью сбрасывает8 доmin3, хотя8 тоже легально")
	await shot("ones-min")
	model.round_no += 1
	model.bid = {}
	model.bids = []
	await apply_view()
	check(table._qty == 1 and table._face == 2, "Послеединиц новыйраунд выбираетразрешённыйface2")
	model.maputo = true
	model.counts[0] = 1
	model.dice[0] = [1]
	model.round_no += 1
	await apply_view()
	check(table.find_child("BidFace1", true, false).disabled and not table.find_child("BidFace2", true, false).disabled, "Палифико с однойединицей оставляетпервыйход")
	model = make()
	model.place_bid(0, 3, 2)
	await apply_view(2)
	check(table.find_child("Calza", true, false) != null, "Calza видна внеочереди участнику2")
	check(table.find_child("BidFace2", true, false) == null, "Внеочереди нетпанели ставок")
	await shot("calza-out-of-turn")
	await apply_view(0)
	check(table.find_child("Calza", true, false) == null, "Авторставки невидитcalza")
	await apply_view(2, true)
	check(table.find_child("Calza", true, false) == null, "Зритель невидитcalza")
	await apply_view(2, false, true)
	check(table.find_child("Calza", true, false) == null, "Пауза невключаетcalza")
	model.counts[2] = 0
	await apply_view(2)
	check(table.find_child("Calza", true, false) == null, "Выбывший невидитcalza")
	# Реальный GUI-клик через Net.send_action: владелец peer1 занимаетместо2.
	model = make()
	model.dice = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6], [2, 3, 4, 5, 6]]
	model.place_bid(0, 3, 2)
	net.perudo = model
	net.seat_peers.assign([0, 0, 1])
	net._push_state()
	await frames()
	await click(table.find_child("Calza", true, false))
	check(model.phase == "reveal" and model.reveal.challenger == 2 and model.reveal.calza, "Настоящийклик внеочереди дошёл доNet")
	table.queue_free()
	app.queue_free()
	await frames()
	net.leave()
	# Штатный серверныйdispatcher и адресныеview, только _send_view заменён захватом.
	var server: Node = load("res://tests/fixtures/perudo_batch28_net.gd").new()
	root.add_child(server)
	server.mode = "enet"
	server.party_game = "perudo"
	server.game_id = "contract-fixture"
	server.in_game = true
	server.seat_peers.assign([11, 22, 33])
	server.perudo = make()
	server.perudo.dice = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6], [2, 3, 4, 5, 6]]
	server.perudo.place_bid(0, 3, 2)
	server._push_state()
	check(server.delivered.size() == 3 and server.delivered[2].value.can_calza, "Адресныйview доставляетправоcalza")
	check(server.delivered[2].value.dice[0].is_empty(), "Доcalza чужиекости скрыты")
	server._handle_action(44, "calza", {})
	check(server.perudo.phase == "bid", "Постороннийpeer неможетcalza")
	server._handle_action(11, "calza", {"seat": 2})
	check(server.perudo.phase == "bid", "Подменаseat не позволяет авторуcalza")
	server.paused = true
	server._handle_action(33, "calza", {})
	check(server.perudo.phase == "bid", "Net блокируетcalza напаузе")
	server.paused = false
	server._handle_action(33, "challenge", {})
	check(server.perudo.phase == "bid", "Дудо внеочереди отвергнутоNet/правилами")
	server._handle_action(33, "calza", {"seat": 0})
	check(server.perudo.phase == "reveal" and server.perudo.reveal.challenger == 2, "Отправитель определяетговорящего, неarg.seat")
	var history_count: int = server.perudo.history.size()
	server._handle_action(22, "calza", {})
	check(server.perudo.history.size() == history_count, "Повтор конкурентногоcalza недублируетвскрытие")
	server.queue_free()
	await frames()
	print("PERUDO28 UI/NET: %d проверок, %d ошибок" % [checks, errors])
	await root.get_node("Sfx").request_quit(1 if errors else 0)
